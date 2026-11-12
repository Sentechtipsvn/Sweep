import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CompressionView: View {
    @StateObject private var store = CompressionStore()
    @State private var picker: PhotosPickerItem?
    @State private var showFilePicker = false
    @State private var edge = 2048
    @State private var quality = 0.82
    @State private var showOriginal = false
    @State private var preview: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PhotosPicker(selection: $picker, matching: .images, preferredItemEncoding: .current) {
                        Label("Chọn từ Ảnh", systemImage: "photo")
                    }.buttonStyle(.borderedProminent)
                    Button { showFilePicker = true } label: { Label("Từ Tệp", systemImage: "folder") }
                        .buttonStyle(.bordered)
                }.disabled(store.busy)
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 340)
                        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Kích thước cạnh dài").font(.headline)
                    Picker("Kích thước", selection: $edge) {
                        Text("1280").tag(1280); Text("2048").tag(2048); Text("4096").tag(4096)
                    }.pickerStyle(.segmented)
                    HStack { Text("Chất lượng JPEG"); Spacer(); Text("\(Int(quality * 100))%").monospacedDigit() }
                    Slider(value: $quality, in: 0.5...0.95, step: 0.01)
                    Button { store.compress(edge: edge, quality: quality) } label: {
                        Label("Tạo bản nén", systemImage: "arrow.down.right.and.arrow.up.left").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(store.source == nil || store.busy)
                }.disabled(store.busy)
                if store.busy { ProgressView("Đang xử lý…").frame(maxWidth: .infinity) }
                if let output = store.output {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(SweepFormat.bytes(output.sourceBytes)) → \(SweepFormat.bytes(output.outputBytes))")
                            .font(.title3.bold()).monospacedDigit()
                        Text("JPEG · \(output.width) × \(output.height)").font(.caption).foregroundStyle(.secondary)
                        if output.savedBytes > 0 {
                            Text("Bản mới nhỏ hơn \(SweepFormat.bytes(output.savedBytes)). Đây chưa phải dung lượng đã giải phóng trên máy.")
                                .font(.footnote).foregroundStyle(.green)
                        } else {
                            Text("Bản mới không nhỏ hơn ảnh đầu vào. Sếp cân nhắc giảm kích thước/chất lượng hoặc giữ ảnh cũ.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        Toggle("Xem ảnh đầu vào để so sánh", isOn: $showOriginal)
                        HStack {
                            Button("Lưu ảnh mới") { store.save() }.buttonStyle(.borderedProminent)
                            ShareLink(item: output.url) { Label("Chia sẻ", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        }.disabled(store.busy)
                    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 20))
                }
                Text("Bản đầu xử lý từng ảnh tĩnh JPEG/PNG/HEIC, tối đa 80 MB và 120 megapixel. Kết quả là JPEG mới: xoay đúng chiều, bỏ GPS/EXIF; vùng trong suốt thành trắng. Không giữ Live Photo, HDR, RAW hay lịch sử chỉnh sửa. Chữ nhỏ có thể mất nét khi nén; Sếp xem thử trước khi dùng cho hóa đơn.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Chọn ảnh từ iCloud có thể tải bản gốc về máy. Sweep không tự xóa ảnh gốc sau khi nén.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Nén ảnh")
        .onChange(of: picker) { _, item in
            if let item { store.importPicker { try await item.loadTransferable(type: ImportedImage.self) } }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.jpeg, .png, .heic]) { result in
            switch result {
            case .success(let url): store.importFile(url)
            case .failure(let error): store.message = error.localizedDescription
            }
        }
        .task(id: previewKey) {
            guard let url = showOriginal ? store.source?.url : (store.output?.url ?? store.source?.url) else { preview = nil; return }
            let result = await Task.detached(priority: .utility) { CompressionStore.preview(url) }.value
            guard !Task.isCancelled else { return }
            preview = result
        }
        .onChange(of: store.source?.url) { _, _ in showOriginal = false }
        .alert("Sweep", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("Đã hiểu") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private var previewKey: String {
        "\(store.source?.url.path ?? "")|\(store.output?.url.path ?? "")|\(showOriginal)"
    }
}
