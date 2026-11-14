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
            if ledger.schema == 1 {
                let previous = base
                let recovery = previous.appendingPathComponent("Before-upgrade-0.5-" + UUID().uuidString + ".sweepbackup")
                try DeliveryBackup.write(ledger, evidence: evidenceDirectory, to: recovery, version: 1)
                var upgraded = ledger; upgraded.schema = 2
                for i in upgraded.orders.indices where upgraded.orders[i].settlement != nil && upgraded.orders[i].settlement?.route == nil {
                    let reminder = "Chọn lại nhánh giao phù hợp; các khoản tiền cũ được giữ nguyên."
                    if !upgraded.orders[i].reviewNote.contains(reminder) { upgraded.orders[i].reviewNote += (upgraded.orders[i].reviewNote.isEmpty ? "" : "\n") + reminder }
                }
                upgraded.record("Nâng sổ 0.5", "Giữ nguyên tiền và công; bản trước nâng cấp: " + recovery.lastPathComponent)
                try database!.save(upgraded); ledger = upgraded
            }
            for name in ["Backups", "Exports"] {
                try FileManager.default.createDirectory(at: documents.appendingPathComponent(name), withIntermediateDirectories: true)
            }
        } catch { blocked = true; message = "Sổ chưa mở được. Dữ liệu được giữ nguyên. " + error.localizedDescription }
    }
    nonisolated private static func importCompact(_ image: URL, role: EvidenceRole, directory: URL) throws -> DeliveryEvidence {
        let compact = try InvoiceImageEncoder.compact(image)
        defer { try? FileManager.default.removeItem(at: compact) }
        return try EvidenceFiles.importImage(compact, role: role, directory: directory)
    }
    var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var shareCache: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DeliveryShares", isDirectory: true) }
    func outgoing(_ report: DeliveryReport, order: DeliveryOrder) async -> [URL]? {
        guard !busy, !blocked else { return nil }; busy = true; defer { busy = false }
        let files = report.evidenceIDs.compactMap { id in order.evidence.first { $0.id == id } }, dir = evidenceDirectory, cache = shareCache
        do {
            return try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                return try files.map { file in
                    try EvidenceFiles.verify(file, directory: dir)
                    return try InvoiceImageEncoder.compact(dir.appendingPathComponent(file.filename), directory: cache)
                }
            }.value
        } catch { message = error.localizedDescription; return nil }
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
                file = try await Task.detached(priority: .userInitiated) { try Self.importCompact(image, role: .invoice, directory: directory) }.value
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
            let imported = try await Task.detached(priority: .userInitiated) { try Self.importCompact(image, role: role, directory: directory) }.value
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
    func prepareReport(_ id: UUID, text: String, evidenceIDs: [UUID]? = nil) async -> DeliveryReport? {
        guard !busy, let order = order(id) else { return nil }
        busy = true; defer { busy = false }
        do {
            var next = ledger
            let report = try next.prepareReport(id, text: text, evidenceIDs: evidenceIDs)
            let files = report.evidenceIDs.compactMap { wanted in order.activeEvidence.first { $0.id == wanted } }
            let directory = evidenceDirectory
            try await Task.detached(priority: .userInitiated) { for file in files { try EvidenceFiles.verify(file, directory: directory) } }.value
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

extension DeliveryStore {
    func maintain(backupFolder: URL, reset: Bool) async -> URL? {
        guard !busy, !blocked, let database else { return nil }
        busy = true; defer { busy = false }
        let access = backupFolder.startAccessingSecurityScopedResource()
        defer { if access { backupFolder.stopAccessingSecurityScopedResource() } }
        do {
            let folder = backupFolder.resolvingSymlinksInPath().standardizedFileURL.path
            let protected = documents.resolvingSymlinksInPath().standardizedFileURL.path
            guard folder != protected, !folder.hasPrefix(protected + "/"), !folder.hasPrefix(root.path) else { throw DeliveryError.invalid("Chọn iCloud Drive hoặc thư mục ngoài Sweep để giữ bản sao.") }
            let snapshot = ledger, dir = evidenceDirectory
            let pendingInbox = try? SharedInvoiceInbox.live()
            let pendingScan = try (reset ? pendingInbox?.scan() : nil)
            guard pendingScan?.warnings.isEmpty != false else { throw DeliveryError.invalid("Có ảnh chờ lỗi cần kiểm tra trước khi sao lưu và đặt lại.") }
            let pending = pendingScan?.items ?? []
            let destination = backupFolder.appendingPathComponent("Sweep-before-\(reset ? "reset" : "cleanup")-\(UUID().uuidString.prefix(8)).sweepbackup")
            let verified = try await Task.detached(priority: .utility) {
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Backup-check-" + UUID().uuidString)
                try DeliveryBackup.write(snapshot, evidence: dir, to: destination)
                let checked = try DeliveryBackup.prepare(destination, staging: staging)
                guard checked.ledger == snapshot else { throw DeliveryError.invalid("Bản sao chưa khớp sổ. Chưa xoá dữ liệu.") }
                if !pending.isEmpty {
                    let extra = destination.deletingPathExtension().appendingPathExtension("pending")
                    try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
                    for item in pending {
                        try EvidenceFiles.verify(item.evidence, directory: item.directory)
                        let target = extra.appendingPathComponent(item.id.uuidString)
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                        for source in [item.image, item.directory.appendingPathComponent("manifest.json")] {
                            try FileManager.default.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
                        }
                        try EvidenceFiles.verify(item.evidence, directory: target)
                    }
                    let scan = try SharedInvoiceInbox(directory: extra).scan()
                    guard scan.items.count == pending.count, scan.warnings.isEmpty else { throw DeliveryError.invalid("Ảnh chờ chưa sao lưu đủ. Chưa xoá.") }
                }
                return checked
            }.value
            // Never delete the live store if anything changed while the backup was checked.
            guard ledger == snapshot else { throw DeliveryError.invalid("Sổ đã đổi; tạo lại bản sao trước khi dọn.") }
            if reset {
                try database.reset(using: verified); ledger = DeliveryLedger()
                for file in try FileManager.default.contentsOfDirectory(at: evidenceDirectory, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
                for name in ["Backups", "Exports"] {
                    let path = documents.appendingPathComponent(name)
                    for file in try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
                }
                for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "sweepbackup" { try FileManager.default.removeItem(at: file) }
                if let inbox = pendingInbox {
                    // Shares published after backup began remain available; do not race an active extension.
                    for item in pending { try inbox.remove(item) }
                }
                for key in ["photoLimit", "allowCloudScan"] { UserDefaults.standard.removeObject(forKey: key) }
            }
            let fm = FileManager.default
            if fm.fileExists(atPath: shareCache.path) { try fm.removeItem(at: shareCache) }
            // Specific owned caches only. Do not remove system caches or live files from another tool.
            let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            for name in ["VietQR", "SweepCompression"] {
                let path = cache.appendingPathComponent(name)
                if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
            }
            return destination
        } catch { message = "Chưa hoàn tất: " + error.localizedDescription; return nil }
    }
}
