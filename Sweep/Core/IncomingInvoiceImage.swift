import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalize incoming images to a small, metadata-free JPEG. Source is never modified.
enum IncomingInvoiceImage {
    static let maximumDimension = 3072

    static func copy(from source: URL, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try InvoiceImageEncoder.compact(source, directory: directory)
    }

    static func copy(data: Data, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !data.isEmpty, data.count <= EvidenceFiles.maximumBytes else { throw DeliveryError.invalid("Ảnh chia sẻ trống hoặc vượt 80 MB.") }
        let source = directory.appendingPathComponent(UUID().uuidString + ".incoming")
        defer { try? FileManager.default.removeItem(at: source) }
        try data.write(to: source, options: .atomic)
        return try copy(from: source, directory: directory)
    }
}
