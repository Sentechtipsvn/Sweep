import SwiftUI

private enum AppRelease {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var store: DeliveryStore
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
                NavigationLink { PayrollView() } label: {
                    TimelineView(.periodic(from: .now, by: 60)) { clock in
                        ToolIcon(title: "Chấm công", asset: "tool-payroll", badge: AttendanceReminderPolicy.showDot(store.ledger, now: clock.date))
                    }
                }.accessibilityIdentifier("tool.payroll")
            }.buttonStyle(.plain).padding(20)
        }.background(Color(uiColor: .systemGroupedBackground)).sendeliNavigationTitle("Công cụ")
    }
}
private struct ToolIcon: View {
    let title: String
    let asset: String
    var badge = false
    var body: some View {
        VStack(spacing: 8) {
            Image(asset).resizable().scaledToFit().frame(maxWidth: 66).aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) { if badge { Circle().fill(SweepStyle.green).frame(width: 10, height: 10).offset(x: 3, y: -3).accessibilityLabel("Chưa chấm công hôm nay") } }
            Text(title).font(.caption).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2).frame(minHeight: 32, alignment: .top)
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
    }
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoStore
    @EnvironmentObject private var delivery: DeliveryStore
    @EnvironmentObject private var attendance: AttendanceReminderManager
    @AppStorage(OriginalPhotoPolicy.key) private var originalPhotoPolicy = OriginalPhotoPolicy.ask.rawValue
    @AppStorage("photoLimit") private var photoLimit = 500
    @AppStorage("allowCloudScan") private var allowCloud = false
    var body: some View {
        Form {
            Section("Trợ lý giao hàng") {
                NavigationLink("Công đơn và QR công ty") { DeliverySettingsView() }
                NavigationLink("Gia hạn Sendeli") { RenewalView() }
                NavigationLink("Nhận ảnh bằng Phím tắt") { SweepShortcutGuide() }
                NavigationLink("Sao lưu và khôi phục sổ / ảnh") { DeliveryBackupView() }
                Text("Sổ lưu trên thiết bị. Xóa app có thể xóa sổ; xuất bản sao ra Tệp trước khi đổi máy hoặc cài lại.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Nhắc chấm công") {
                Toggle("Nhắc lúc 08:00", isOn: Binding(get: { attendance.enabled }, set: { value in Task { await attendance.setEnabled(value, ledger: delivery.ledger) } }))
                NavigationLink("Lịch nghỉ lễ của công ty") { WorkHolidaySettings() }
                Text(attendance.status).font(.footnote).foregroundStyle(.secondary)
                Button("Mở cài đặt thông báo") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("Ảnh gốc sau khi gửi Zalo") {
                Picker("Xoá khỏi thư viện Ảnh", selection: $originalPhotoPolicy) {
                    ForEach(OriginalPhotoPolicy.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
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
                Button("Mở cài đặt quyền của Sendeli") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("Quyền ảnh giới hạn chỉ cho Sendeli xem các ảnh Sếp đã chọn. App không thể dọn cache của các ứng dụng khác hoặc toàn bộ Dữ liệu hệ thống.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Cách Sendeli bảo vệ dữ liệu") {
                Label("Chỉ xóa ảnh sau khi Sếp xác nhận", systemImage: "checkmark.shield")
                Label("Nén thành bản mới, giữ ảnh đầu vào", systemImage: "doc.on.doc")
                Label("Không gửi ảnh lên máy chủ của Sendeli", systemImage: "iphone")
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
        .sendeliNavigationTitle("Cài đặt")
        .onChange(of: photoLimit) { _, _ in if library.canRead { library.reload() } }
    }
}

private struct WorkHolidaySettings: View {
    @EnvironmentObject private var store: DeliveryStore
    private func binding<T>(_ path: WritableKeyPath<WorkHolidayOptions, T>) -> Binding<T> {
        Binding(get: { (store.ledger.settings.holidays ?? WorkHolidayOptions())[keyPath: path] }, set: { newValue in
            store.change { ledger in
                var options = ledger.settings.holidays ?? WorkHolidayOptions()
                options[keyPath: path] = newValue
                ledger.settings.holidays = options
            }
        })
    }
    var body: some View {
        Form {
            Section("Lịch nhắc 08:00") {
                Text("Bỏ qua Chủ nhật, 1/1, 30/4, 1/5, 2/9, Giỗ Tổ 10/3 âm lịch và 5 ngày Tết.")
                Picker("Năm ngày Tết", selection: binding(\.beforeTet)) {
                    ForEach(1...3, id: \.self) { n in Text("\(n) ngày trước, \(5-n) ngày từ mùng 1").tag(n) }
                }
                Picker("Quốc khánh", selection: binding(\.nationalDayOffset)) {
                    Text("Chỉ 2/9").tag(0)
                    Text("1/9 và 2/9").tag(-1)
                    Text("2/9 và 3/9").tag(1)
                }
                Toggle("Nghỉ bù khi lễ trùng Chủ nhật", isOn: binding(\.compensateSunday))
            }
        }.sendeliNavigationTitle("Lịch nghỉ lễ")
    }
}
