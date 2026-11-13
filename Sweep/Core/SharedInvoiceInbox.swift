import Foundation

/// The extension publishes immutable images, never writes the live ledger.
/// Staging + rename keeps an interrupted share from becoming a visible half-file.
struct SharedInvoiceInbox {
    struct Item: Identifiable {
        let id: UUID
        let receivedAt: Date
        let evidence: DeliveryEvidence
        let directory: URL
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
    }
    let directory: URL

    static func live() throws -> SharedInvoiceInbox {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") {
            return SharedInvoiceInbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-Delivery-UITests/Inbox", isDirectory: true))
        }
        #endif
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SweepAppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw DeliveryError.invalid("Bản cài chưa truy cập được hộp thư chia sẻ. Cần ký cả Sweep và SweepShare với cùng quyền App Groups; ảnh chưa được nhận vào Sweep.")
        }
        return SharedInvoiceInbox(directory: container.appendingPathComponent("SharedInvoices", isDirectory: true))
    }

    @discardableResult func add(_ source: URL) throws -> Item {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), date = Date()
        let staging = directory.appendingPathComponent(".staging-" + id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let image = try EvidenceFiles.importImage(source, role: .invoice, directory: staging)
        let manifest = Manifest(id: id, receivedAt: date, evidence: image)
        try DeliveryCoding.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        return Item(id: id, receivedAt: date, evidence: image, directory: destination)
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
                result.items.append(Item(id: manifest.id, receivedAt: manifest.receivedAt, evidence: file, directory: folder))
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
