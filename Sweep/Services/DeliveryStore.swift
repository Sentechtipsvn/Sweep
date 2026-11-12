import SwiftUI

@MainActor
final class DeliveryStore: ObservableObject {
    @Published private(set) var ledger = DeliveryLedger()
    @Published private(set) var busy = false
    @Published private(set) var blocked = false
    @Published var message: String?
    let root: URL
    let evidenceDirectory: URL
    private var database: DeliveryDatabase?

    init(root: URL? = nil) {
        var base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Delivery", isDirectory: true)
        #if DEBUG
        if root == nil, ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-Delivery-UITests", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-delivery") { try? FileManager.default.removeItem(at: base) }
        }
        #endif
        self.root = base; evidenceDirectory = base.appendingPathComponent("Evidence", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
            database = try DeliveryDatabase(url: base.appendingPathComponent("Sweep.sqlite"))
            ledger = try database!.load()
        } catch { blocked = true; message = "Sổ chưa mở được. Dữ liệu được giữ nguyên. " + error.localizedDescription }
    }
    func order(_ id: UUID) -> DeliveryOrder? { ledger.orders.first { $0.id == id } }
    func url(_ evidence: DeliveryEvidence) -> URL { evidenceDirectory.appendingPathComponent(evidence.filename) }
    @discardableResult func change(_ operation: (inout DeliveryLedger) throws -> Void) -> Bool {
        guard !blocked, let database else { return false }
        guard !busy else { message = "Sổ đang xử lý ảnh hoặc sao lưu. Chờ hoàn tất rồi lưu thay đổi."; return false }
        do {
            var next = ledger; try operation(&next)
            try database.save(next); ledger = next; return true
        } catch { message = error.localizedDescription; return false }
    }
    func create(_ draft: DeliveryOrder, image: URL?, signedAt: Date?, allowRepeatedImage: Bool = false) async -> UUID? {
        guard !busy, !blocked else { return nil }
        if let old = ledger.orders.first(where: { ($0.sourceID != nil && $0.sourceID == draft.sourceID) || DeliveryOrder.normalizedCode($0.code) == DeliveryOrder.normalizedCode(draft.code) }) { return old.id }
        busy = true; defer { busy = false }
        var file: DeliveryEvidence?
        do {
            if let image {
                let directory = evidenceDirectory
                file = try await Task.detached(priority: .userInitiated) { try EvidenceFiles.importImage(image, role: .invoice, directory: directory) }.value
                if !allowRepeatedImage, let file, let duplicate = ledger.orders.first(where: { $0.evidence.contains { $0.role == .invoice && $0.sha256 == file.sha256 } }) {
                    try? FileManager.default.removeItem(at: url(file))
                    message = "Ảnh này đã có trong phiếu \(duplicate.code). Mở hồ sơ cũ để kiểm tra; nếu là một phiếu khác hợp lệ, bật xác nhận dùng lại ảnh."
                    return nil
                }
            }
            var result = draft
            if let file { result.evidence.append(file) }
            var next = ledger
            let id = try next.insert(result)
            if let signedAt { try next.sign(id, at: signedAt) }
            try database!.save(next); ledger = next; return id
        } catch {
            if let file { try? FileManager.default.removeItem(at: url(file)) }
            message = error.localizedDescription; return nil
        }
    }
    func attach(_ image: URL, role: EvidenceRole, to id: UUID?) async {
        guard !busy, !blocked else { return }
        busy = true; defer { busy = false }
        var file: DeliveryEvidence?
        do {
            let directory = evidenceDirectory
            let imported = try await Task.detached(priority: .userInitiated) { try EvidenceFiles.importImage(image, role: role, directory: directory) }.value
            file = imported
            var next = ledger
            if let id {
                guard let i = next.orders.firstIndex(where: { $0.id == id }), next.orders[i].voidReason == nil else { throw DeliveryError.invalid("Hồ sơ không hợp lệ.") }
                if next.orders[i].activeEvidence.contains(where: { $0.role == role && $0.sha256 == imported.sha256 }) {
                    try? FileManager.default.removeItem(at: url(imported)); return
                }
                next.orders[i].evidence.append(imported); next.orders[i].revision += 1
                next.record("Thêm chứng từ", orderID: id, "\(role.rawValue) · \(imported.sha256)")
            } else { next.settings.qr = imported; next.record("Cập nhật QR công ty", imported.sha256) }
            try database!.save(next); ledger = next
        } catch {
            if let file { try? FileManager.default.removeItem(at: url(file)) }; message = error.localizedDescription
        }
    }
    func prepareReport(_ id: UUID, text: String) async -> DeliveryReport? {
        guard !busy, let order = order(id) else { return nil }
        busy = true; defer { busy = false }
        do {
            let directory = evidenceDirectory
            try await Task.detached(priority: .userInitiated) { for file in order.activeEvidence { try EvidenceFiles.verify(file, directory: directory) } }.value
            var next = ledger; let report = try next.prepareReport(id, text: text)
            try database!.save(next); ledger = next; return report
        } catch { message = error.localizedDescription; return nil }
    }
    func exportBackup() async -> URL? {
        guard !busy, !blocked else { return nil }
        busy = true; defer { busy = false }
        let snapshot = ledger, directory = evidenceDirectory
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-\(UUID().uuidString.prefix(8)).sweepbackup")
        do {
            try await Task.detached(priority: .utility) { try DeliveryBackup.write(snapshot, evidence: directory, to: destination) }.value
            return destination
        } catch { message = error.localizedDescription; return nil }
    }
    func restore(_ prepared: DeliveryBackup.Prepared) async -> Bool {
        guard !busy, !blocked else { return false }
        busy = true; defer { busy = false }
        do {
            let previous = ledger, directory = evidenceDirectory
            let recovery = root.appendingPathComponent("Before-restore-\(UUID().uuidString).sweepbackup")
            try await Task.detached(priority: .utility) {
                try DeliveryBackup.write(previous, evidence: directory, to: recovery)
                for file in prepared.ledger.allEvidence {
                    let target = directory.appendingPathComponent(file.filename)
                    if FileManager.default.fileExists(atPath: target.path) { try EvidenceFiles.verify(file, directory: directory) }
                    else { try FileManager.default.copyItem(at: prepared.staging.appendingPathComponent(file.filename), to: target) }
                }
            }.value
            var next = prepared.ledger
            next.record("Khôi phục sổ", "Bản trước khi khôi phục: \(recovery.lastPathComponent)")
            try database!.save(next, replacing: true); ledger = next
            return true
        } catch { message = error.localizedDescription; return false }
    }
}
