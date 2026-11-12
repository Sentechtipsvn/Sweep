import SwiftUI
import Photos
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO

final class ImportedImage: Transferable, @unchecked Sendable {
    let url: URL
    private let directory: URL
    private init(url: URL, directory: URL) { self.url = url; self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in try copy(from: received.file) }
    }

    static func copy(from source: URL) throws -> ImportedImage {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("input").appendingPathExtension(source.pathExtension)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 80 * 1024 * 1024 else { throw ImageEncodingError.tooLarge }
                try FileManager.default.copyItem(at: url, to: target)
            } catch { copyError = error }
        }
        if let error = coordinationError as Error? ?? copyError {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return ImportedImage(url: target, directory: directory)
    }
}

@MainActor
final class CompressionStore: ObservableObject {
    @Published private(set) var source: ImportedImage?
    @Published private(set) var output: EncodedImage?
    @Published private(set) var busy = false
    @Published var message: String?

    func importFile(_ url: URL) {
        guard !busy else { return }
        busy = true; output = nil
        Task {
            do { source = try await Task.detached(priority: .userInitiated) { try ImportedImage.copy(from: url) }.value }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    func importPicker(_ operation: @escaping () async throws -> ImportedImage?) {
        guard !busy else { return }
        busy = true; output = nil
        Task {
            do {
                guard let imported = try await operation() else { throw ImageEncodingError.unreadable }
                source = imported
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    func compress(edge: Int, quality: Double) {
        guard !busy, let source else { return }
        busy = true
        let destination = source.url.deletingLastPathComponent().appendingPathComponent("Sweep-\(UUID().uuidString.prefix(8)).jpg")
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImageEncoder.encode(source: source.url, destination: destination, maxDimension: edge, quality: quality)
                }.value
                if let previous = output { try? FileManager.default.removeItem(at: previous.url) }
                output = result
            } catch {
                try? FileManager.default.removeItem(at: destination)
                message = error.localizedDescription
            }
            busy = false
        }
    }

    func save() {
        guard !busy, let output else { return }
        busy = true
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                message = "Sếp cần cho Sweep quyền thêm ảnh trong Cài đặt để lưu bản nén."; busy = false; return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: output.url)
                }
                message = "Đã lưu bản JPEG mới. Ảnh đầu vào vẫn được giữ nguyên."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    nonisolated static func preview(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
