import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageEncodingError: LocalizedError {
    case unreadable, unsupported, tooLarge, encodeFailed
    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Không đọc được ảnh đầu vào."
        case .unsupported: return "Bản đầu hỗ trợ ảnh tĩnh JPEG, PNG và HEIC; chưa xử lý ảnh động hoặc RAW."
        case .tooLarge: return "Ảnh quá lớn để xử lý an toàn trong bản thử nghiệm."
        case .encodeFailed: return "Không tạo được ảnh nén."
        }
    }
}

public struct EncodedImage: Sendable {
    public let url: URL
    public let sourceBytes: Int64
    public let outputBytes: Int64
    public let width: Int
    public let height: Int
    public var savedBytes: Int64 { max(0, sourceBytes - outputBytes) }
}

public enum ImageEncoder {
    public static func encode(source: URL, destination: URL, maxDimension: Int, quality: Double) throws -> EncodedImage {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let sourceType = CGImageSourceGetType(input) else { throw ImageEncodingError.unreadable }
        let type = sourceType as String
        guard [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, "public.heif"].contains(type),
              CGImageSourceGetCount(input) == 1 else { throw ImageEncodingError.unsupported }
        let props = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any] ?? [:]
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0, width <= 120_000_000 / height else { throw ImageEncodingError.tooLarge }
        let edge = min(max(maxDimension, 320), 4096)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary) else {
            throw ImageEncodingError.unreadable
        }
        // JPEG cannot preserve alpha. Flatten transparency onto white intentionally.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageEncodingError.encodeFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageEncodingError.encodeFailed
        }
        // Only encode new pixels and explicit orientation; GPS/EXIF are not copied.
        CGImageDestinationAddImage(output, image, [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.3), 0.95),
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw ImageEncodingError.encodeFailed }
        let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let outputSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard outputSize > 0 else { throw ImageEncodingError.encodeFailed }
        return EncodedImage(url: destination, sourceBytes: Int64(sourceSize), outputBytes: Int64(outputSize),
                            width: image.width, height: image.height)
    }
}
