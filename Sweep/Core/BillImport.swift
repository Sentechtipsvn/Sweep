import Foundation
import CryptoKit
import CoreFoundation

struct BillCandidate: Identifiable {
    var id: String
    var filename: String
    var customer: String
    var total: Int64
    var cash: Int64 = 0
    var bank: Int64 = 0
    var deliveredAt: Date?
    var createdAt: Date?
    var note = ""
    var isLegacy = false
    var sourceSnapshot: String?
    var image: URL
}
struct BillImportResult { var candidates: [BillCandidate]; var warnings: [String] }

enum BillImport {
    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)
    }
    static func decode(_ data: Data, images: URL, legacy: Bool = false) throws -> [BillCandidate] {
        guard data.count <= 16 * 1024 * 1024, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DeliveryError.invalid("JSON Bill không hợp lệ.") }
        func text(_ record: [String: Any], _ key: String) -> String {
            if let value = record[key] as? String { return value }
            if let value = record[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
            return ""
        }
        func candidate(_ record: [String: Any], key: String, isLegacy: Bool) throws -> BillCandidate {
            let id = text(record, "id"), filename = text(record, "filename"), customer = text(record, "name")
            guard id == key, id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  !filename.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent, !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DeliveryError.invalid("Gói Bill thiếu ID/tên hoặc có đường dẫn ảnh không hợp lệ.")
            }
            if !isLegacy {
                let imageKey = text(record, "imageKey")
                let expected = SHA256.hash(data: Data("sen-bill-v1:\(imageKey)".utf8)).map { String(format: "%02x", $0) }.joined()
                guard !imageKey.isEmpty, expected == id, filename.contains(" · \(imageKey).") else { throw DeliveryError.invalid("Mã gói Bill không khớp tên ảnh.") }
            }
            let total = try VND.parse(text(record, "total"))
            let cash = isLegacy ? try VND.parse(text(record, "cash")) : 0
            let bank = isLegacy ? try VND.parse(text(record, "bank")) : 0
            guard cash + bank <= total else { throw DeliveryError.invalid("Khoản thu cũ vượt tổng đơn. Giữ sổ cũ để kiểm tra.") }
            var note = text(record, "note")
            if isLegacy {
                note += "\nNhập từ sen-orders-v3. Chưa có ngày ký nhận; chưa tính công. CK cũ chưa được tự đối soát."
                for field in ["deleted", "destroyed", "cancelled"] where text(record, field) == "1" { note += "\nSổ cũ có cờ \(field)=1; cần rà soát." }
                if !text(record, "latestReport").isEmpty { note += "\nBáo cáo cũ: \(text(record, "latestReport")); chưa xác nhận gửi trong Sweep." }
            }
            return BillCandidate(id: "bill:\(id)", filename: filename, customer: customer, total: total, cash: cash, bank: bank,
                                 deliveredAt: date(text(record, "deliveredAt")), createdAt: date(text(record, "createdAt")),
                                 note: note.trimmingCharacters(in: .whitespacesAndNewlines), isLegacy: isLegacy,
                                 sourceSnapshot: String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8), image: images.appendingPathComponent(filename))
        }
        if legacy {
            guard root["_schema"] as? String == "sen-orders-v3" else { throw DeliveryError.invalid("Chỉ hỗ trợ sổ Bill/Ảnh đơn hàng sen-orders-v3.") }
            return try root.keys.filter { !$0.hasPrefix("_") }.sorted().map { key in
                let record: [String: Any]?
                if let string = root[key] as? String, let bytes = string.data(using: .utf8) { record = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] }
                else { record = root[key] as? [String: Any] }
                guard let record else { throw DeliveryError.invalid("Không đọc được hồ sơ cũ \(key.prefix(8)). Chưa thay đổi dữ liệu.") }
                return try candidate(record, key: key, isLegacy: true)
            }
        }
        guard root["schema"] as? String == "sen-bill-v1" else { throw DeliveryError.invalid("Gói không đúng schema sen-bill-v1.") }
        return [try candidate(root, key: text(root, "id"), isLegacy: false)]
    }
    static func scan(_ root: URL) throws -> BillImportResult {
        let images = root.appendingPathComponent("Ảnh Đơn Hàng", isDirectory: true)
        let manager = FileManager.default
        guard manager.fileExists(atPath: images.path), FileRules.isDescendant(images, of: root) else { throw DeliveryError.invalid("Chọn thư mục SenTechTips_AnhDonHang, bên trong có Ảnh Đơn Hàng và Đơn mới.") }
        var candidates: [String: BillCandidate] = [:]; var warnings: [String] = []
        let ledger = root.appendingPathComponent("orders.json")
        if manager.fileExists(atPath: ledger.path) {
            guard FileRules.isDescendant(ledger, of: root) else { throw DeliveryError.invalid("Sổ cũ nằm ngoài thư mục đã chọn.") }
            let data = try boundedRead(ledger)
            // One malformed legacy record stops this source rather than silently dropping financial history.
            for item in try decode(data, images: images, legacy: true) { candidates[item.id] = item }
        }
        let inbox = root.appendingPathComponent("Đơn mới", isDirectory: true)
        if manager.fileExists(atPath: inbox.path) {
            guard FileRules.isDescendant(inbox, of: root) else { throw DeliveryError.invalid("Thư mục Đơn mới không hợp lệ.") }
            let entries = try manager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).filter { $0.pathExtension.lowercased() == "json" }
            guard entries.count <= 5_000 else { throw DeliveryError.invalid("Hơn 5.000 gói trong một lượt. Tách thư mục để nhập.") }
            for url in entries {
                do {
                    guard FileRules.isDescendant(url, of: root) else { throw DeliveryError.invalid("Đường dẫn ngoài thư mục.") }
                    for item in try decode(boundedRead(url), images: images) where candidates[item.id] == nil { candidates[item.id] = item }
                } catch { warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        var ready: [BillCandidate] = []
        for item in candidates.values {
            if FileRules.isDescendant(item.image, of: root) { ready.append(item) }
            else { warnings.append("Chưa đọc được ảnh: \(item.filename). Tải ảnh trong Tệp hoặc kiểm tra thư mục.") }
        }
        ready.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return BillImportResult(candidates: ready, warnings: warnings)
    }
    private static func boundedRead(_ url: URL) throws -> Data {
        let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
        let data = try reader.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 16 * 1024 * 1024 else { throw DeliveryError.invalid("Tệp thông tin vượt 16 MB.") }
        return data
    }
}
