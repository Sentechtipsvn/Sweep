import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keep supported original bytes. Normalize only alternate still-image representations.
enum IncomingInvoiceImage {
    static let maximumDimension = 3072

    static func copy(from source: URL, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        do {
            let file = try EvidenceFiles.importImage(source, role: .invoice, directory: directory)
            return directory.appendingPathComponent(file.filename)
        } catch {
            // A provider may advertise JPEG but vend a TIFF/other decoded-image representation.
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            _ = try EvidenceFiles.hash(source)
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(imageSource) == 1,
                  let type = CGImageSourceGetType(imageSource) as String?, UTType(type)?.conforms(to: .image) == true else { throw error }
            let index = CGImageSourceGetPrimaryImageIndex(imageSource)
            guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any],
                  let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
                  let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
                  width > 0, height > 0, width <= 120_000_000 / height else { throw error }
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw error }
            let target = directory.appendingPathComponent(UUID().uuidString + ".png")
            do {
                guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw error }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw error }
                _ = try EvidenceFiles.hash(target); _ = try EvidenceFiles.imageExtension(target)
                return target
            } catch { try? FileManager.default.removeItem(at: target); throw error }
        }
    }

    static func copy(data: Data, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !data.isEmpty, data.count <= EvidenceFiles.maximumBytes else { throw DeliveryError.invalid("Ảnh chia sẻ trống hoặc vượt 80 MB.") }
        let source = directory.appendingPathComponent(UUID().uuidString + ".incoming")
        defer { try? FileManager.default.removeItem(at: source) }
        try data.write(to: source, options: .atomic)
        return try copy(from: source, directory: directory)
    }
}
