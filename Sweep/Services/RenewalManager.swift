import SwiftUI
import UserNotifications

@MainActor
final class RenewalManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var expiry: Date?
    @Published private(set) var source = "Chưa có ngày hết hạn"
    @Published private(set) var status = ""
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "renewal.enabled")
    private var generation = 0
    private var refreshing = false
    private var refreshRequested = false
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func setEnabled(_ value: Bool) async {
        if value {
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
                    status = "Thông báo chưa được cho phép. Bật quyền trong Cài đặt iPhone."; return
                }
            } catch { status = error.localizedDescription; return }
        }
        enabled = value; UserDefaults.standard.set(value, forKey: "renewal.enabled")
        await refresh()
    }
    func saveManual(_ date: Date) async {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "renewal.manualExpiry")
        await refresh()
    }
    func refresh() async {
        guard !refreshing else { refreshRequested = true; return }
        refreshing = true; defer { refreshing = false }
        repeat {
            refreshRequested = false
            await updateSchedule()
        } while refreshRequested
    }
    private func updateSchedule() async {
        generation += 1; let request = generation
        var candidates: [Date] = []
        var bundles = [Bundle.main.bundleURL]
        let plugins = Bundle.main.bundleURL.appendingPathComponent("PlugIns")
        if let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            bundles += items.filter { $0.pathExtension == "appex" }
        }
        for bundle in bundles {
            let profile = bundle.appendingPathComponent("embedded.mobileprovision")
            if let size = try? profile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
               let data = try? Data(contentsOf: profile, options: .mappedIfSafe), let value = SigningExpiry.expiration(in: data) {
                candidates.append(value)
            }
        }
        if let value = candidates.min() { expiry = value; source = "Hồ sơ ký của bản đang cài" }
        else {
            let value = UserDefaults.standard.double(forKey: "renewal.manualExpiry")
            expiry = value > 0 ? Date(timeIntervalSince1970: value) : nil
            source = expiry == nil ? "Chưa có ngày hết hạn" : "Sếp nhập từ công cụ ký"
        }
        let pending = await center.pendingNotificationRequests()
        guard request == generation else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("sweep.renewal.") }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        guard request == generation else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("sweep.renewal.") }.map { $0.request.identifier })
        guard enabled, let expiry else { status = enabled ? "Nhập hạn nhìn thấy trong AltStore nếu hồ sơ không đọc được." : "Nhắc gia hạn đang tắt."; return }
        let permission = await center.notificationSettings()
        guard request == generation else { return }
        guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else {
            status = "iOS chưa cho phép thông báo. Kiểm tra quyền trong Cài đặt."; return
        }
        let now = Date(), dates = SigningExpiry.reminders(expiry: expiry, now: now)
        do {
            for date in dates {
                guard request == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = date < expiry ? "Sendeli sắp hết hạn ký" : "Kiểm tra gia hạn Sendeli"
                content.body = "Hạn ký: \(expiry.formatted(date: .numeric, time: .shortened)). Gia hạn bằng công cụ ký, sau đó mở Sendeli để cập nhật hạn."
                content.sound = .default
                content.userInfo = ["route": "renewal"]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                let id = "sweep.renewal.\(Int(expiry.timeIntervalSince1970)).\(Int(date.timeIntervalSince1970))"
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
            if request == generation { status = "Đã đặt lịch từ 24 giờ trước hạn, mỗi 3 giờ. Mở lại Sendeli sau khi gia hạn để hủy lịch cũ." }
        } catch { if request == generation { status = "Chưa đặt đủ thông báo: " + error.localizedDescription } }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["route"] as? String == "renewal" {
            Task { @MainActor in NotificationCenter.default.post(name: .sweepRenewalSelected, object: nil) }
        }
        if response.notification.request.content.userInfo["route"] as? String == "attendance" {
            Task { @MainActor in NotificationCenter.default.post(name: .sendeliAttendanceSelected, object: nil) }
        }
        completionHandler()
    }
}
struct RenewalView: View {
    @EnvironmentObject private var renewal: RenewalManager
    @State private var manual = Date().addingTimeInterval(24 * 3600)
    var body: some View {
        Form {
            Section("Hạn bản Sendeli đang cài") {
                if let expiry = renewal.expiry {
                    Text(expiry.formatted(date: .complete, time: .shortened)).font(.headline)
                    Text(expiry > Date() ? "Còn \(max(0, Int(expiry.timeIntervalSinceNow / 3600))) giờ" : "Hạn đã qua; kiểm tra công cụ ký.").foregroundStyle(expiry > Date() ? Color.secondary : Color.red)
                }
                Text(renewal.source).font(.footnote).foregroundStyle(.secondary)
                Button("Kiểm tra lại hạn ký") { Task { await renewal.refresh() } }
            }
            Section {
                Toggle("Nhắc gia hạn Sendeli", isOn: Binding(get: { renewal.enabled }, set: { value in Task { await renewal.setEnabled(value) } }))
                Text(renewal.status).font(.footnote).foregroundStyle(.secondary)
            }
            if renewal.source != "Hồ sơ ký của bản đang cài" {
                Section("Nhập hạn từ AltStore / công cụ ký") {
                    DatePicker("Hết hạn lúc", selection: $manual, displayedComponents: [.date, .hourAndMinute])
                    Button("Lưu ngày hết hạn đã kiểm tra") { Task { await renewal.saveManual(manual) } }
                    Text("Nhập đúng hạn hiển thị trong công cụ ký. Không tự cộng 7 ngày hoặc coi đây là thao tác gia hạn.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Mở cài đặt thông báo") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("Sau khi refresh/ký lại, mở Sendeli để nhận hạn mới và hủy nhắc cũ. Thông báo phụ thuộc quyền iOS/Focus; không bảo đảm phát khi app đã hết hạn. Lịch đặt theo từng lô, bổ sung khi mở app.").font(.footnote).foregroundStyle(.secondary)
            }
        }.sendeliNavigationTitle("Gia hạn Sendeli").navigationBarTitleDisplayMode(.inline)
            .task { await renewal.refresh(); if let value = renewal.expiry { manual = value } }
    }
}
