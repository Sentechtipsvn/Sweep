import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

enum SharedInvoiceLoader {
    static func imageTypes(_ identifiers: [String]) -> [String] {
        let preferred = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, UTType.heif.identifier]
        let images = identifiers.filter { UTType($0)?.conforms(to: .image) == true }
        return images.enumerated().sorted {
            let a = preferred.firstIndex(of: $0.element) ?? preferred.count
            let b = preferred.firstIndex(of: $1.element) ?? preferred.count
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    static func load(from provider: NSItemProvider) async throws -> URL {
        var types = imageTypes(provider.registeredTypeIdentifiers)
        if types.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) { types = [UTType.data.identifier] }
        var failures: [String] = []
        for type in types {
            try Task.checkCancellation()
            do { return try await loadFile(provider, type: type) }
            catch { failures.append("tệp \(type): \(error.localizedDescription)") }
            try Task.checkCancellation()
            do { return try await loadData(provider, type: type) }
            catch { failures.append("dữ liệu \(type): \(error.localizedDescription)") }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        do {
                            if let error { throw error }
                            guard let source = item as? URL, source.isFileURL else { throw DeliveryError.invalid("Nguồn chưa cung cấp đường dẫn ảnh.") }
                            continuation.resume(returning: try IncomingInvoiceImage.copy(from: source))
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            } catch { failures.append("đường dẫn: \(error.localizedDescription)") }
        }
        #if canImport(UIKit)
        if provider.canLoadObject(ofClass: UIImage.self) {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    provider.loadObject(ofClass: UIImage.self) { item, error in
                        do {
                            if let error { throw error }
                            guard let image = item as? UIImage else { throw DeliveryError.invalid("Chưa nhận được đối tượng ảnh.") }
                            continuation.resume(returning: try copy(image))
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            } catch { failures.append("đối tượng ảnh: \(error.localizedDescription)") }
        }
        #endif
        try Task.checkCancellation()
        let source = provider.registeredTypeIdentifiers.prefix(6).joined(separator: ", ")
        let detail = failures.suffix(3).map { String($0.prefix(220)) }.joined(separator: "\n")
        throw DeliveryError.invalid("Chưa đọc được ảnh nguồn sau khi thử các cách nhận ảnh. Kiểu nguồn: \(source).\n\(detail)")
    }

    private static func loadFile(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { source, error in
                do {
                    if let error { throw error }
                    guard let source else { throw DeliveryError.invalid("Nguồn chưa cung cấp tệp ảnh.") }
                    // The provider's URL expires as soon as this callback returns.
                    continuation.resume(returning: try IncomingInvoiceImage.copy(from: source))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func loadData(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                do {
                    if let error { throw error }
                    guard let data else { throw DeliveryError.invalid("Nguồn chưa cung cấp dữ liệu ảnh.") }
                    continuation.resume(returning: try IncomingInvoiceImage.copy(data: data))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    #if canImport(UIKit)
    private static func copy(_ image: UIImage) throws -> URL {
        let width = image.size.width * image.scale, height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 120_000_000 / height else {
            throw DeliveryError.invalid("Kích thước ảnh nguồn không hợp lệ hoặc vượt 120 megapixel.")
        }
        let factor = min(1, CGFloat(IncomingInvoiceImage.maximumDimension) / max(width, height))
        let size = CGSize(width: max(1, floor(width * factor)), height: max(1, floor(height * factor)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.pngData() else { throw DeliveryError.invalid("Chưa mã hóa được ảnh nguồn.") }
        return try IncomingInvoiceImage.copy(data: data)
    }
    #endif
}
