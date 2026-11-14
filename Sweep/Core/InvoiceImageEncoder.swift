import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Encode only pixels: no source EXIF, GPS, IPTC, XMP or filename metadata is copied.
/// Keep text legible at 2560 px; alternate/animated formats use their primary still frame.
enum InvoiceImageEncoder {
    static func compact(_ source: URL, directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        _ = try EvidenceFiles.hash(source)
        guard let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(input) > 0 else { throw DeliveryError.invalid("Chưa giải mã được ảnh. Chọn ảnh trong thư viện để thử lại.") }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let props = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value ?? 0
        guard w > 0, h > 0, w <= 120_000_000 / h else { throw DeliveryError.invalid("Ảnh vượt giới hạn 120 megapixel hoặc chưa đầy đủ.") }
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(input, index, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2560, kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: thumb.width, height: thumb.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DeliveryError.invalid("Không xử lý được ảnh.") }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: thumb.width, height: thumb.height))
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: thumb.width, height: thumb.height))
        guard let pixels = ctx.makeImage() else { throw DeliveryError.invalid("Không tạo được ảnh.") }
        let url = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw DeliveryError.invalid("Không tạo được bản ảnh nhẹ.") }
            CGImageDestinationAddImage(out, pixels, [kCGImageDestinationLossyCompressionQuality: 0.82, kCGImagePropertyOrientation: 1] as CFDictionary)
            guard CGImageDestinationFinalize(out) else { throw DeliveryError.invalid("Không ghi được ảnh nén.") }
            _ = try EvidenceFiles.imageExtension(url); return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}
