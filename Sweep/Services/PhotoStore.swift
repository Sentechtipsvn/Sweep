import SwiftUI
import Photos

@MainActor
final class PhotoStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var photos: [PhotoRecord] = []
    @Published private(set) var visibleCount = 0
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var scanResult: ExactScanResult?
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = "Chọn Quét ảnh để bắt đầu."
    @Published var message: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var mutating = false

    var canRead: Bool { authorization == .authorized || authorization == .limited }
    var screenshots: [PhotoRecord] { photos.filter(\.screenshot) }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self); task?.cancel() }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self, !self.mutating else { return }
            self.reload()
        }
    }

    func authorizeAndLoad() {
        guard !busy else { return }
        busy = true
        task = Task {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if canRead { reload() } else { busy = false }
        }
    }

    func reload() {
        task?.cancel()
        generation = UUID()
        let token = generation
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        groups = []; scanResult = nil
        guard canRead else { photos = []; visibleCount = 0; busy = false; return }
        busy = true; status = "Đang đọc danh sách ảnh…"
        let limit = min(max(UserDefaults.standard.integer(forKey: "photoLimit").nonzero(or: 500), 100), 5000)
        task = Task {
            let snapshot = await PhotoLibraryService.snapshot(limit: limit)
            guard !Task.isCancelled, token == generation else { return }
            photos = snapshot.records; visibleCount = snapshot.visibleCount
            busy = false; status = "Đã tải \(photos.count) ảnh gần nhất được cấp quyền."
        }
    }

    func startScan(allowNetwork: Bool) {
        guard canRead, !busy else { return }
        groups = []; scanResult = nil; busy = true; progress = 0
        status = "Đang đối chiếu dữ liệu ảnh gốc…"
        generation = UUID()
        let token = generation
        let snapshot = photos
        task = Task {
            do {
                let result = try await PhotoLibraryService.scan(snapshot, allowNetwork: allowNetwork) { [weak self] done, total in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.busy, self.scanResult == nil else { return }
                        self.progress = total == 0 ? 1 : Double(done) / Double(total)
                        self.status = "Đối chiếu \(done)/\(total) ảnh có cùng kích thước…"
                    }
                }
                guard !Task.isCancelled, token == generation else { return }
                groups = result.groups; scanResult = result; progress = 1
                status = "Tìm thấy \(groups.count) nhóm trùng dữ liệu."
            } catch {
                guard token == generation else { return }
                status = Task.isCancelled ? "Đã dừng quét." : error.localizedDescription
            }
            if token == generation { busy = false }
        }
    }

    func cancel() {
        task?.cancel(); generation = UUID(); busy = false; status = "Đã dừng. Kết quả chưa hoàn tất không được dùng để chọn xóa."
        groups = []; scanResult = nil
    }

    func delete(_ ids: Set<String>, protectGroups: Bool) async -> Bool {
        guard !busy, !ids.isEmpty else { return false }
        guard !protectGroups || DuplicateRules.keepsAtLeastOne(in: groups, deleting: ids) else {
            message = "Mỗi nhóm cần giữ lại ít nhất một ảnh."; return false
        }
        mutating = true; busy = true
        do {
            try await PhotoLibraryService.delete(ids: ids)
            mutating = false; busy = false; reload()
            message = "Đã gửi \(ids.count) ảnh vào Đã xóa gần đây. Nếu dùng iCloud Photos, thao tác được đồng bộ sang các thiết bị khác."
            return true
        } catch {
            mutating = false; busy = false; message = error.localizedDescription
            return false
        }
    }
}

private extension Int {
    func nonzero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
