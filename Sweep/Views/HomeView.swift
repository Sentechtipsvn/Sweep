import SwiftUI

private enum AppRelease {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 2 : 4) }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                NavigationLink { LibraryView(mode: .duplicates) } label: { ToolIcon(title: "Ảnh trùng", asset: "tool-duplicates") }.accessibilityIdentifier("tool.duplicates")
                NavigationLink { LibraryView(mode: .screenshots) } label: { ToolIcon(title: "Ảnh màn hình", asset: "tool-screenshots") }
                NavigationLink { CompressionView() } label: { ToolIcon(title: "Nén ảnh", asset: "tool-compress") }.accessibilityIdentifier("tool.compress")
                NavigationLink { FilesView() } label: { ToolIcon(title: "Tệp lớn", asset: "tool-files") }
                NavigationLink { PlacesView() } label: { ToolIcon(title: "Vị trí", asset: "tool-places") }
                NavigationLink { ContactsView() } label: { ToolIcon(title: "Liên hệ", asset: "tool-contacts") }
                NavigationLink { MaintenanceView() } label: { ToolIcon(title: "Dọn dẹp", asset: "tool-cleanup") }
            }.buttonStyle(.plain).padding(20)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Công cụ")
    }
}
private struct ToolIcon: View {
    let title: String
    let asset: String
    var body: some View {
        VStack(spacing: 8) {
            Image(asset).resizable().scaledToFit().frame(maxWidth: 66).aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title).font(.caption).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2).frame(minHeight: 32, alignment: .top)
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoStore
    @AppStorage("photoLimit") private var photoLimit = 500
    @AppStorage("allowCloudScan") private var allowCloud = false
    var body: some View {
        Form {
            Section("Trợ lý giao hàng") {
                NavigationLink("Liên hệ bán hàng / tài xế") { ContactsView(editable: true) }
                NavigationLink("Dọn dẹp / đặt lại dữ liệu") { MaintenanceView() }
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
