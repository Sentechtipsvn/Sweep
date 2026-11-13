import SwiftUI

private enum AppRelease {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Công cụ ảnh và tệp").font(.title3.bold())
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
                Text("BẢN THỬ NGHIỆM \(AppRelease.version) · © Sentechtipsvn")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Text("Sweep").font(.title2.bold()).accessibilityAddTraits(.isHeader) }
            ToolbarItem(placement: .topBarTrailing) { Image(systemName: "sparkles").foregroundStyle(.green).accessibilityHidden(true) }
        }
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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoStore
    @AppStorage("photoLimit") private var photoLimit = 500
    @AppStorage("allowCloudScan") private var allowCloud = false
    var body: some View {
        Form {
            Section("Trợ lý giao hàng") {
                NavigationLink("Công đơn và QR công ty") { DeliverySettingsView() }
                NavigationLink("Sao lưu và khôi phục sổ / ảnh") { DeliveryBackupView() }
                Text("Sổ lưu trên thiết bị. Xóa app có thể xóa sổ; xuất bản sao ra Tệp trước khi đổi máy hoặc cài lại.").font(.footnote).foregroundStyle(.secondary)
            }
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
                LabeledContent("Phiên bản", value: "\(AppRelease.version) (\(AppRelease.build)) · thử nghiệm")
                LabeledContent("Phát triển", value: "© Sentechtipsvn")
                Text("Sổ giao hàng hoạt động offline sau khi nhập đủ ảnh. Chia sẻ báo cáo do Sếp chọn ứng dụng và xác nhận gửi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cài đặt")
        .onChange(of: photoLimit) { _, _ in if library.canRead { library.reload() } }
    }
}
