import SwiftUI
import Photos

struct PhotoThumbnail: View {
    let photo: PhotoRecord
    var large = false
    var allowNetwork = false
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            if let image {
                if large { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: photo.id) {
            image = nil
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.id], options: nil).firstObject else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork
            options.deliveryMode = .opportunistic
            let edge: CGFloat = large ? 1600 : 400
            requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: edge, height: edge),
                contentMode: large ? .aspectFit : .aspectFill, options: options) { value, _ in
                    if let value { DispatchQueue.main.async { image = value } }
                }
        }
        .onDisappear {
            if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
            requestID = nil
        }
    }
}

private struct PhotoPreview: View {
    let photo: PhotoRecord
    @Environment(\.dismiss) private var dismiss
    @AppStorage("allowCloudScan") private var allowCloud = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PhotoThumbnail(photo: photo, large: true, allowNetwork: allowCloud)
                Text("\(photo.width) × \(photo.height)").font(.caption.monospacedDigit())
                if let date = photo.date { Text(date, format: .dateTime.day().month().year().hour().minute()).font(.caption) }
                if !allowCloud {
                    Text("Nếu ảnh không hiện, ảnh gốc có thể đang ở iCloud. Sếp có thể cho phép tải trong Cài đặt.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            .padding(.bottom)
            .navigationTitle("Xem ảnh").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
    }
}

struct LibraryView: View {
    enum Mode { case duplicates, screenshots }
    let mode: Mode
    @EnvironmentObject private var library: PhotoStore
    @AppStorage("allowCloudScan") private var allowCloud = false
    @State private var selected = Set<String>()
    @State private var preview: PhotoRecord?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if !library.canRead {
                Section {
                    ContentUnavailableView("Cho Sweep xem ảnh", systemImage: "photo.on.rectangle",
                        description: Text("Sếp có thể cấp một phần thư viện hoặc toàn bộ ảnh. Chỉ những ảnh được cấp quyền mới được quét."))
                    Button("Cho phép truy cập ảnh") { library.authorizeAndLoad() }.disabled(library.busy)
                    Button("Mở Cài đặt") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } else {
                Section {
                    Text("Phạm vi: \(library.photos.count)/\(library.visibleCount) ảnh được cấp quyền, lấy ảnh mới nhất trước.")
                        .font(.footnote)
                    if library.authorization == .limited {
                        Label("Đang dùng quyền ảnh giới hạn", systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
                    }
                    if library.busy {
                        ProgressView(value: library.progress)
                        Text(library.status).font(.caption).foregroundStyle(.secondary)
                        Button("Dừng") { library.cancel() }
                    } else if mode == .duplicates {
                        Button { selected = []; library.startScan(allowNetwork: allowCloud) } label: {
                            Label("Quét ảnh trùng", systemImage: "magnifyingglass")
                        }.disabled(library.photos.isEmpty)
                        Text(library.status).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if mode == .duplicates {
                    if let result = library.scanResult {
                        Section {
                            Text("Đã đối chiếu \(result.checked) ảnh có cùng kích thước. \(result.unavailable) ảnh không đọc được hoặc cần tải; \(result.unsupported) ảnh Live Photo/đã chỉnh sửa/nhiều tài nguyên chưa hỗ trợ.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if result.groups.isEmpty { Text("Chưa tìm thấy bản trùng trong phần dữ liệu đã đọc.") }
                        }
                    }
                    ForEach(library.groups) { group in
                        Section {
                            ForEach(group.members) { photo in
                                photoRow(photo, suggestedKeep: photo.id == group.suggestedKeepID)
                            }
                        } header: {
                            Text("\(group.members.count) bản · \(SweepFormat.bytes(group.bytesPerPhoto))/ảnh")
                        } footer: {
                            Text("Cùng dữ liệu ảnh gốc. Album, chú thích và thông tin quản lý của từng bản có thể khác. Giữ ít nhất một ảnh.")
                        }
                    }
                    Section {
                        Text("Chỉ tìm trùng dữ liệu trong ảnh tĩnh chưa chỉnh sửa. Ảnh gần giống hoặc khác định dạng chưa được gom trong bản đầu.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("\(library.screenshots.count) ảnh màn hình trong phạm vi hiện tại") {
                        if library.screenshots.isEmpty { Text("Chưa có ảnh chụp màn hình trong phạm vi này.").foregroundStyle(.secondary) }
                        ForEach(library.screenshots) { photo in photoRow(photo) }
                    }
                }
            }
        }
        .navigationTitle(mode == .duplicates ? "Ảnh trùng" : "Ảnh màn hình")
        .toolbar {
            if library.canRead {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selected = []; library.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(library.busy).accessibilityLabel("Tải lại ảnh")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                HStack {
                    Button("Bỏ chọn") { selected = [] }
                    Spacer()
                    Button("Xóa \(selected.count) ảnh", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.borderedProminent).tint(.red).disabled(library.busy)
                }
                .padding().background(.regularMaterial)
            }
        }
        .confirmationDialog("Xóa \(selected.count) ảnh đã chọn?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa ảnh đã chọn", role: .destructive) {
                let ids = selected
                Task { if await library.delete(ids, protectGroups: mode == .duplicates) { selected = [] } }
            }
        } message: {
            Text("Ảnh sẽ vào Đã xóa gần đây. Nếu bật iCloud Photos, ảnh cũng bị xóa trên những thiết bị đồng bộ. Dung lượng không nhất thiết được giải phóng ngay.")
        }
        .sheet(item: $preview) { PhotoPreview(photo: $0) }
        .alert("Sweep", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("Đã hiểu") { library.message = nil }
        } message: { Text(library.message ?? "") }
        .onChange(of: library.photos) { _, _ in selected = [] }
        .onChange(of: library.groups.map(\.id)) { _, _ in selected = [] }
    }

    private func photoRow(_ photo: PhotoRecord, suggestedKeep: Bool = false) -> some View {
        HStack(spacing: 14) {
            Button { preview = photo } label: {
                PhotoThumbnail(photo: photo).frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel("Xem ảnh")
            VStack(alignment: .leading, spacing: 5) {
                if let date = photo.date { Text(date, format: .dateTime.day().month().year().hour().minute()).font(.subheadline) }
                Text("\(photo.width) × \(photo.height)").font(.caption).foregroundStyle(.secondary)
                if photo.favorite { Label("Yêu thích", systemImage: "heart.fill").font(.caption).foregroundStyle(.pink) }
                if suggestedKeep { Text("Gợi ý giữ").font(.caption.weight(.semibold)).foregroundStyle(.green) }
            }
            Spacer(minLength: 0)
            Button {
                if selected.contains(photo.id) { selected.remove(photo.id) } else { selected.insert(photo.id) }
            } label: {
                Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected.contains(photo.id) ? Color.red : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).disabled(library.busy)
            .accessibilityLabel(selected.contains(photo.id) ? "Bỏ chọn xóa ảnh" : "Chọn xóa ảnh")
        }
    }
}
