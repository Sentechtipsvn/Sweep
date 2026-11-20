import SwiftUI
import UserNotifications

@MainActor
final class AttendanceReminderManager: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = ""
    private var generation = 0
    private var refreshing = false
    private var queued: DeliveryLedger?
    private var permissionQueued = false
    private let center = UNUserNotificationCenter.current()
    init() {
        UserDefaults.standard.register(defaults: ["attendance.reminders.enabled": true])
        enabled = UserDefaults.standard.bool(forKey: "attendance.reminders.enabled")
    }
    func setEnabled(_ value: Bool, ledger: DeliveryLedger) async {
        enabled = value; UserDefaults.standard.set(value, forKey: "attendance.reminders.enabled")
        await refresh(ledger, requestPermission: value)
    }
    func refresh(_ ledger: DeliveryLedger, requestPermission: Bool = false) async {
        generation += 1; queued = ledger; permissionQueued = permissionQueued || requestPermission
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        while let snapshot = queued {
            queued = nil; let ask = permissionQueued; permissionQueued = false
            await updateSchedule(snapshot, requestPermission: ask)
        }
    }
    private func updateSchedule(_ ledger: DeliveryLedger, requestPermission: Bool) async {
        let token = generation
        var settings = await center.notificationSettings()
        if enabled && requestPermission && settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard token == generation else { return }
        let pending = await center.pendingNotificationRequests()
        guard token == generation else { return }
        let prefix = "sendeli.attendance."
        let existing = Set(pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let dates = enabled && authorized ? AttendanceReminderPolicy.dates(ledger, now: Date()) : []
        func identifier(_ date: Date) -> String { prefix + String(Int(date.timeIntervalSince1970)) }
        let obsolete = existing.subtracting(dates.map(identifier))
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(obsolete)) }
        guard enabled else { status = "Nhắc chấm công đang tắt."; return }
        guard authorized else {
            status = "Chưa có quyền thông báo. Dấu nhắc trong app vẫn hoạt động."; return
        }
        do {
            for date in dates where !existing.contains(identifier(date)) {
                guard token == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = "Sendeli · Nhớ chấm công hôm nay"
                content.body = "Sếp ghi nhận đi làm hoặc nghỉ theo thực tế nhé."
                content.sound = .default; content.userInfo = ["route": "attendance"]
                var components = DeliveryMonth.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                components.timeZone = DeliveryMonth.calendar.timeZone
                try await center.add(UNNotificationRequest(identifier: identifier(date), content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
            if token == generation { status = "Nhắc lúc 08:00 giờ Việt Nam, thứ Hai–thứ Bảy nếu chưa chấm, trừ ngày nghỉ lễ. Lịch 30 ngày được cập nhật khi mở app hoặc sửa công." }
        } catch { if token == generation { status = "Chưa đặt đủ nhắc chấm công: " + error.localizedDescription } }
    }
}
