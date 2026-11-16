import Foundation

/// Presentation only: never changes settlement, payroll, or report acknowledgement.
struct DeliverySuccessNotice: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var completedOrderIDs: [UUID] = []
}

enum DeliveryFeedbackPolicy {
    static func notice(before: DeliveryLedger, after: DeliveryLedger, text: String? = nil) -> DeliverySuccessNotice? {
        guard before != after else { return nil }
        let previous = Dictionary(uniqueKeysWithValues: before.orders.map { ($0.id, $0) })
        let completed = after.orders.filter { order in
            guard let old = previous[order.id] else { return false } // Imports/restores are not new deliveries.
            return order.voidReason == nil && order.taskComplete && !old.taskComplete
        }
        if !completed.isEmpty {
            let caption = completed.count == 1 ? "Hoàn tất giao hàng · " + completed[0].code : "Đã hoàn tất \(completed.count) đơn giao hàng"
            return DeliverySuccessNotice(text: caption, completedOrderIDs: completed.map(\.id))
        }
        if let text { return DeliverySuccessNotice(text: text) }
        let action = after.audit.count > before.audit.count ? after.audit.last?.action : nil
        let caption: String
        switch action {
        case "Chuẩn bị báo cáo", "Lưu nội dung báo cáo nháp": return nil // Background draft saves stay quiet.
        case "Nhận hồ sơ": caption = "Đã nhận đơn hàng"
        case "Ký nhận đi giao": caption = "Đã lưu ký nhận và công đơn"
        case "Chốt giao / tiền": caption = "Đã lưu giao hàng và khoản thực nhận"
        case "Đối soát CK": caption = "Đã lưu đối soát chuyển khoản"
        case "Khách đã chuyển khoản": caption = "Đã xác nhận khách chuyển khoản · xong nhắc tiền"
        case "Sếp xác nhận đã gửi": caption = "Đã lưu xác nhận gửi chứng từ"
        case "Thêm chứng từ": caption = "Đã thêm ảnh chứng từ"
        case "Cập nhật QR công ty": caption = "Đã cập nhật ảnh QR công ty"
        case "Lưu liên hệ": caption = "Đã lưu liên hệ"
        case "Lưu vị trí": caption = "Đã lưu vị trí giao hàng"
        case "Sửa hồ sơ": caption = "Đã cập nhật đơn hàng"
        case "Nộp tiền mặt": caption = "Đã ghi nhận nộp tiền mặt"
        case "Hủy và điều chỉnh công": caption = "Đã hủy hồ sơ và lưu điều chỉnh"
        case "Loại ảnh khỏi báo cáo, giữ bản gốc": caption = "Đã loại ảnh khỏi báo cáo"
        case .some(let value) where value.hasPrefix("Sửa công "): caption = "Đã lưu chấm công"
        case .some(let value) where value.hasPrefix("Cấu hình lương "): caption = "Đã lưu cấu hình lương"
        case .some(let value) where value.hasPrefix("Chốt lương "): caption = "Đã chốt bảng lương"
        case .some(let value) where value.hasPrefix("Mở khóa lương"): caption = "Đã mở khóa bảng lương"
        case .some: caption = "Đã lưu thay đổi"
        case nil:
            if before.contacts != after.contacts { caption = "Đã cập nhật liên hệ" }
            else if before.places != after.places { caption = "Đã cập nhật vị trí" }
            else if before.settings != after.settings { caption = "Đã lưu cài đặt giao hàng" }
            else { return nil } // Internal prompts do not generate success banners.
        }
        return DeliverySuccessNotice(text: caption)
    }
}

/// Separate presentation history, so the business database and backup format stay unchanged.
final class DeliveryCelebrationHistory {
    private let file: URL
    private var seen: Set<UUID>
    init(file: URL) {
        self.file = file
        seen = (try? JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: file))) ?? []
    }
    func seed(_ ledger: DeliveryLedger) {
        let complete = Set(ledger.orders.filter { $0.voidReason == nil && $0.taskComplete }.map(\.id))
        guard !complete.isSubset(of: seen) else { return }
        seen.formUnion(complete)
        try? persist()
    }
    func claim(_ ids: [UUID]) -> [UUID] {
        let fresh = ids.filter { !seen.contains($0) }
        guard !fresh.isEmpty else { return [] }
        seen.formUnion(fresh)
        do { try persist(); return fresh } catch { return [] } // Conservative: no replay if history cannot be saved.
    }
    private func persist() throws { try JSONEncoder().encode(seen).write(to: file, options: .atomic) }
}
