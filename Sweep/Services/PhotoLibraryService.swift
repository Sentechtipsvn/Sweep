import Foundation
import Photos
import CryptoKit
import UniformTypeIdentifiers

struct PhotoSnapshot {
    let records: [PhotoRecord]
    let visibleCount: Int
}

struct ExactScanResult {
    let groups: [DuplicateGroup]
    let checked: Int
    let unavailable: Int
    let unsupported: Int
}

private final class ResourceTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHAssetResourceDataRequestID?
    private var cancelled = false
    func set(_ value: PHAssetResourceDataRequestID) {
        lock.lock(); id = value; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let value = id; lock.unlock()
        if let value { PHAssetResourceManager.default().cancelDataRequest(value) }
    }
}

private final class ResourceHash: @unchecked Sendable {
    private var hash = SHA256()
    private var bytes: Int64 = 0
    // PhotoKit delivers a resource's data and completion serially.
    func append(_ data: Data) { hash.update(data: data); bytes += Int64(data.count) }
    func finish() -> (String, Int64) {
        (hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
    }
}

enum PhotoLibraryService {
    static func snapshot(limit: Int) async -> PhotoSnapshot {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let all = PHAsset.fetchAssets(with: .image, options: options)
        var records: [PhotoRecord] = []
        for index in 0..<min(all.count, max(1, limit)) {
            let asset = all.object(at: index)
            let resources = PHAssetResource.assetResources(for: asset)
            let supportedTypes = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, "public.heif"]
            let singleOriginal = resources.count == 1 && resources[0].type == .photo &&
                supportedTypes.contains(resources[0].uniformTypeIdentifier)
            records.append(PhotoRecord(id: asset.localIdentifier, date: asset.creationDate,
                width: asset.pixelWidth, height: asset.pixelHeight, favorite: asset.isFavorite,
                screenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                eligibleForExactMatch: singleOriginal && !asset.mediaSubtypes.contains(.photoLive)))
        }
        return PhotoSnapshot(records: records, visibleCount: all.count)
    }

    static func scan(_ records: [PhotoRecord], allowNetwork: Bool,
                     progress: @escaping @Sendable (Int, Int) -> Void) async throws -> ExactScanResult {
        let candidates = DuplicateRules.candidateIDs(in: records)
        var digests: [PhotoDigest] = []
        var unavailable = 0
        var checked = 0
        for record in records where candidates.contains(record.id) {
            try Task.checkCancellation()
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.id], options: nil)
            if let asset = assets.firstObject {
                let resources = PHAssetResource.assetResources(for: asset)
                if resources.count == 1, let resource = resources.first, resource.type == .photo {
                    do {
                        let (hash, bytes) = try await digest(resource, allowNetwork: allowNetwork)
                        try Task.checkCancellation()
                        digests.append(PhotoDigest(photo: record, hash: hash, bytes: bytes))
                    } catch {
                        try Task.checkCancellation()
                        unavailable += 1
                    }
                } else { unavailable += 1 }
            } else { unavailable += 1 }
            checked += 1
            progress(checked, candidates.count)
        }
        try Task.checkCancellation()
        return ExactScanResult(groups: DuplicateRules.groups(from: digests), checked: checked,
            unavailable: unavailable, unsupported: records.filter { !$0.eligibleForExactMatch }.count)
    }

    private static func digest(_ resource: PHAssetResource, allowNetwork: Bool) async throws -> (String, Int64) {
        let ticket = ResourceTicket()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = allowNetwork
                let accumulator = ResourceHash()
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options,
                    dataReceivedHandler: { accumulator.append($0) }, completionHandler: { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: accumulator.finish()) }
                    })
                ticket.set(id)
            }
        }, onCancel: { ticket.cancel() })
    }

    static func delete(ids: Set<String>) async throws {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        guard fetched.count == ids.count else {
            throw NSError(domain: "Sweep", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Thư viện đã thay đổi. Sếp tải lại danh sách rồi chọn ảnh giúp em nhé."])
        }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(fetched) }
    }
}
