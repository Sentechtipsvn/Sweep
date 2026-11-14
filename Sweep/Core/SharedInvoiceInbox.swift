import Foundation

/// The extension publishes immutable images, never writes the live ledger.
/// Staging + rename keeps an interrupted share from becoming a visible half-file.
struct SharedInvoiceInbox {
    struct Item: Identifiable {
        let id: UUID
        let receivedAt: Date
        let evidence: DeliveryEvidence
        let directory: URL
        var signedAt: Date? = nil
        var image: URL { directory.appendingPathComponent(evidence.filename) }
        var sourceID: String { "share:" + id.uuidString }
    }
    struct Scan {
        var items: [Item] = []
        var warnings: [String] = []
    }
    private struct Manifest: Codable {
        var version = 1
        let id: UUID
        let receivedAt: Date
        let evidence: DeliveryEvidence
        var signedAt: Date? = nil
    }
    let directory: URL

    static func live() throws -> SharedInvoiceInbox {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") {
            return SharedInvoiceInbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-Delivery-UITests/Inbox", isDirectory: true))
        }
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        let groups = AppGroupConfiguration.identifiers(in: info)
        for group in groups {
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return SharedInvoiceInbox(directory: container.appendingPathComponent("SharedInvoices", isDirectory: true))
            }
        }
        let source = info["ALTAppGroups"] == nil ? "cấu hình gốc" : "AltStore"
        let details = groups.isEmpty ? "Chưa có nhóm được cấp." : "Nhóm từ \(source): " + groups.joined(separator: ", ")
        throw DeliveryError.invalid("Tiện ích đã mở nhưng chưa truy cập được hộp thư chung. \(details) Dùng bản IPA dành cho AltStore, giữ tiện ích mở rộng khi cài. Nếu vẫn lỗi, gửi lại thông báo này để kiểm tra quyền nhóm; ảnh chưa được nhận vào Sweep.")
    }

    @discardableResult func add(_ source: URL, signedAt: Date? = nil) throws -> Item {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), date = Date()
        let staging = directory.appendingPathComponent(".staging-" + id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let image = try EvidenceFiles.importImage(source, role: .invoice, directory: staging)
        let manifest = Manifest(id: id, receivedAt: date, evidence: image, signedAt: signedAt)
        try DeliveryCoding.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        return Item(id: id, receivedAt: date, evidence: image, directory: destination, signedAt: signedAt)
    }

    func scan() throws -> Scan {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return Scan() }
        var result = Scan()
        for folder in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            do {
                guard let folderID = UUID(uuidString: folder.lastPathComponent),
                      try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                    throw DeliveryError.invalid("Thư mục phiếu không hợp lệ.")
                }
                let manifestURL = folder.appendingPathComponent("manifest.json")
                let metadata = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard metadata.isSymbolicLink != true, let size = metadata.fileSize, size <= 64 * 1024 else { throw DeliveryError.invalid("Dữ liệu phiếu không hợp lệ.") }
                let manifest = try DeliveryCoding.decode(Manifest.self, from: Data(contentsOf: manifestURL))
                let file = manifest.evidence
                guard manifest.version == 1, manifest.id == folderID, file.role == .invoice,
                      file.filename.range(of: #"^[A-Fa-f0-9-]{36}\.(jpg|jpeg|png|heic|heif)$"#, options: .regularExpression) != nil,
                      file.bytes > 0, file.bytes <= EvidenceFiles.maximumBytes else { throw DeliveryError.invalid("Thông tin ảnh không hợp lệ.") }
                let properties = try folder.appendingPathComponent(file.filename).resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard properties.isSymbolicLink != true, let bytes = properties.fileSize, Int64(bytes) == file.bytes else { throw DeliveryError.invalid("Ảnh chưa đủ dữ liệu.") }
                result.items.append(Item(id: manifest.id, receivedAt: manifest.receivedAt, evidence: file, directory: folder, signedAt: manifest.signedAt))
            } catch { result.warnings.append("Một ảnh chờ nhận chưa đọc được, vẫn được giữ lại: " + error.localizedDescription) }
        }
        result.items.sort { $0.receivedAt < $1.receivedAt }
        return result
    }

    func remove(_ item: Item) throws {
        // Only a known UUID child of this inbox can be removed.
        let expected = directory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        guard expected.standardizedFileURL == item.directory.standardizedFileURL else { throw DeliveryError.invalid("Không đúng ảnh chờ nhận.") }
        try FileManager.default.removeItem(at: expected)
    }
}
