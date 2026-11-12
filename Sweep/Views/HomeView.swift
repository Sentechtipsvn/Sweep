import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 38, weight: .medium))
                    Text("Ảnh gọn.\nBộ nhớ thoáng.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Xem rõ trước khi dọn. Mọi lựa chọn nằm trong tay Sếp.")
                        .font(.subheadline).opacity(0.9)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(26)
                .background(LinearGradient(colors: [Color(red: 0.04, green: 0.43, blue: 0.29),
                                                   Color(red: 0.12, green: 0.67, blue: 0.42)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 30))

                Text("Công cụ của Sếp").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    NavigationLink { LibraryView(mode: .duplicates) } label: {
                        ToolCard(title: "Ảnh trùng", subtitle: "Đối chiếu dữ liệu gốc", icon: "square.on.square", color: .green)
                    }.accessibilityIdentifier("tool.duplicates")
                    NavigationLink { LibraryView(mode: .screenshots) } label: {
                        ToolCard(title: "Ảnh màn hình", subtitle: "Rà soát ảnh đã lưu", icon: "viewfinder", color: .teal)
                    }
                    NavigationLink { CompressionView() } label: {
                        ToolCard(title: "Nén ảnh", subtitle: "Nhẹ hơn, dễ chia sẻ", icon: "arrow.down.right.and.arrow.up.left", color: .blue)
                    }.accessibilityIdentifier("tool.compress")
                    NavigationLink { FilesView() } label: {
                        ToolCard(title: "File lớn", subtitle: "Xem thư mục được chọn", icon: "folder", color: .orange)
                    }
                }
                .buttonStyle(.plain)

                Label("Xử lý trên thiết bị", systemImage: "lock.shield")
                    .font(.headline)
                Text("Sweep không có máy chủ tải ảnh lên, không cần tài khoản hay VPN. Ảnh chỉ tải từ iCloud khi Sếp cho phép hoặc chọn nhập ảnh đó.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("BẢN THỬ NGHIỆM 0.1.0 · © Sentechtipsvn")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Sweep")
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
                .frame(width: 44, height: 44).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .padding(17)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoStore
    @AppStorage("photoLimit") private var photoLimit = 500
    @AppStorage("allowCloudScan") private var allowCloud = false
    var body: some View {
        Form {
            Section("Quét thư viện ảnh") {
                Stepper("\(photoLimit) ảnh gần nhất", value: $photoLimit, in: 100...5000, step: 100)
                    .disabled(library.busy)
                Toggle("Cho tải ảnh gốc từ iCloud khi quét", isOn: $allowCloud)
                    .disabled(library.busy)
                Text("Tắt để ưu tiên dữ liệu đang có trên máy. Ảnh gốc chưa tải sẽ được bỏ qua khi đối chiếu. Bật có thể dùng mạng và tăng dung lượng tạm.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Quyền truy cập") {
                Button("Mở cài đặt quyền của Sweep") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("Quyền ảnh giới hạn chỉ cho Sweep xem các ảnh Sếp đã chọn. App không thể dọn cache của các ứng dụng khác hoặc toàn bộ Dữ liệu hệ thống.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Cách Sweep bảo vệ dữ liệu") {
                Label("Chỉ xóa ảnh sau khi Sếp xác nhận", systemImage: "checkmark.shield")
                Label("Nén thành bản mới, giữ ảnh đầu vào", systemImage: "doc.on.doc")
                Label("Không gửi ảnh lên máy chủ của Sweep", systemImage: "iphone")
                Text("Xóa ảnh trong iCloud Photos được đồng bộ sang thiết bị khác. Ảnh vào Đã xóa gần đây; dung lượng trống không nhất thiết tăng ngay.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Phiên bản", value: "0.1.0 (1) · thử nghiệm")
                LabeledContent("Phát triển", value: "© Sentechtipsvn")
                Text("Giai đoạn sau: ảnh gần giống, nén video và tiện ích ảnh chứng từ. Chưa tích hợp công cụ dọn qua pairing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cài đặt")
        .onChange(of: photoLimit) { _, _ in if library.canRead { library.reload() } }
    }
}
