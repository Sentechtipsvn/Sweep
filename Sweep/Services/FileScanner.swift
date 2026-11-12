import Foundation
import Combine

struct ScannedFile: Identifiable {
    let url: URL
    let relativePath: String
    let bytes: Int64
    var id: String { url.path }
}

private final class FolderLease: @unchecked Sendable {
    let url: URL
    private let accessed: Bool
    init(_ url: URL) { self.url = url; accessed = url.startAccessingSecurityScopedResource() }
    deinit { if accessed { url.stopAccessingSecurityScopedResource() } }
}

struct FileScanResult {
    let files: [ScannedFile]
    let scanned: Int
    let skipped: Int
    let reachedLimit: Bool
}

@MainActor
final class FileScanner: ObservableObject {
    @Published private(set) var files: [ScannedFile] = []
    @Published private(set) var busy = false
    @Published private(set) var result: FileScanResult?
    @Published var message: String?
    @Published private(set) var folderName = "Chưa chọn thư mục"
    private var lease: FolderLease?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func scan(_ url: URL) {
        task?.cancel(); generation = UUID()
        let token = generation
        let access = FolderLease(url)
        lease = access; files = []; result = nil; busy = true; folderName = url.lastPathComponent
        task = Task {
            let worker = Task.detached(priority: .utility) { try Self.read(access) }
            do {
                let output = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, token == generation else { return }
                files = output.files; result = output
            } catch {
                guard token == generation else { return }
                if !Task.isCancelled { message = error.localizedDescription }
            }
            if token == generation { busy = false }
        }
    }

    func cancel() { task?.cancel(); generation = UUID(); busy = false }

    nonisolated private static func read(_ access: FolderLease) throws -> FileScanResult {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey,
                                      .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var coordinationError: NSError?
        var scanError: Error?
        var result: FileScanResult?
        NSFileCoordinator().coordinate(readingItemAt: access.url, options: [], error: &coordinationError) { root in
            do {
                let manager = FileManager.default
                var skipped = 0
                guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else {
                    throw CocoaError(.fileReadNoPermission)
                }
                var files: [ScannedFile] = []
                var visited = 0
                var reachedLimit = false
                for case let url as URL in iterator {
                    try Task.checkCancellation()
                    visited += 1
                    if visited > 20_000 { reachedLimit = true; break }
                    guard let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isSymbolicLink != true, FileRules.isDescendant(url, of: root) else {
                        iterator.skipDescendants(); skipped += 1; continue
                    }
                    guard values.isRegularFile == true else { continue }
                    guard values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus == .current ||
                            values.ubiquitousItemDownloadingStatus == .downloaded else { skipped += 1; continue }
                    let size = Int64(values.fileSize ?? 0)
                    guard size > 0 else { continue }
                    let path = url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
                    files.append(ScannedFile(url: url, relativePath: path, bytes: size))
                }
                files.sort { $0.bytes == $1.bytes ? $0.relativePath < $1.relativePath : $0.bytes > $1.bytes }
                result = FileScanResult(files: Array(files.prefix(200)), scanned: files.count,
                                        skipped: skipped, reachedLimit: reachedLimit)
            } catch { scanError = error }
        }
        if let coordinationError { throw coordinationError }
        if let scanError { throw scanError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return result
    }
}
