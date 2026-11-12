import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct FilesView: View {
    @StateObject private var scanner = FileScanner()
    @State private var chooseFolder = false
    @State private var preview: URL?
    var body: some View {
        List {
            Section {
                Button { chooseFolder = true } label: { Label("Chọn thư mục", systemImage: "folder.badge.plus") }
                Text(scanner.folderName).font(.headline)
                Text("Hiển thị tối đa 200 file lớn nhất đã tải về, trong tối đa 20.000 mục được duyệt. Bỏ qua file ẩn, liên kết và dữ liệu ngoài thư mục.")
                    .font(.footnote).foregroundStyle(.secondary)
                if scanner.busy {
                    ProgressView("Đang kiểm tra tệp…")
                    Button("Dừng kiểm tra") { scanner.cancel() }
                }
                if let result = scanner.result {
                    Text("Đọc được \(result.scanned) file · bỏ qua/không truy cập được \(result.skipped) mục.")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.reachedLimit { Text("Đã đạt giới hạn duyệt; danh sách chưa bao phủ toàn bộ thư mục.").font(.caption).foregroundStyle(.orange) }
                }
            }
            Section("Theo kích thước giảm dần") {
                ForEach(scanner.files) { file in
                    Button { preview = file.url } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(file.url.lastPathComponent).foregroundStyle(.primary).lineLimit(2)
                                Text(file.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Text(SweepFormat.bytes(file.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("Bản đầu hỗ trợ kiểm tra và xem trước. Sếp quản lý/xóa file bằng ứng dụng Tệp; Sweep chưa tự xóa tài liệu trong thư mục.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("File lớn")
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): scanner.scan(url)
            case .failure(let error): scanner.message = error.localizedDescription
            }
        }
        .quickLookPreview($preview)
        .alert("Sweep", isPresented: Binding(get: { scanner.message != nil }, set: { if !$0 { scanner.message = nil } })) {
            Button("Đã hiểu") { scanner.message = nil }
        } message: { Text(scanner.message ?? "") }
        .onDisappear { scanner.cancel() }
    }
}
