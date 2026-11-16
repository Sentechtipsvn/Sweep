import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var library = PhotoStore()
    @StateObject private var delivery = DeliveryStore()
    @StateObject private var router = SweepRouter()
    @StateObject private var renewal = RenewalManager()
    @StateObject private var attendance = AttendanceReminderManager()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            TabView(selection: $router.tab) {
                OrdersView().tabItem { Label("Đơn hàng", systemImage: "shippingbox") }.tag(0)
                NavigationStack { ReconciliationView() }
                    .tabItem { Label("Lịch sử", systemImage: "clock.arrow.circlepath") }.tag(1)
                NavigationStack(path: $router.tools) { HomeView().navigationDestination(for: String.self) { _ in PayrollView() } }
                    .tabItem { Label("Công cụ", systemImage: "sparkles") }.tag(2)
                NavigationStack(path: $router.settings) { SettingsView().navigationDestination(for: String.self) { _ in RenewalView() } }
                    .tabItem { Label("Cài đặt", systemImage: "gearshape") }.tag(3)
            }
            .tint(SweepStyle.blue)
            .environmentObject(library)
            .environmentObject(delivery)
            .environmentObject(router)
            .environmentObject(renewal)
            .environmentObject(attendance)
            .onOpenURL { router.open($0) }
            .onReceive(NotificationCenter.default.publisher(for: .sweepInboxReceived)) { _ in router.tab = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .sweepRenewalSelected)) { _ in router.tab = 3; router.settings = ["renewal"] }
            .onReceive(NotificationCenter.default.publisher(for: .sendeliAttendanceSelected)) { _ in router.tab = 2; router.tools = ["payroll"] }
            .onChange(of: delivery.ledger.payroll) { _, _ in Task { await attendance.refresh(delivery.ledger) } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in Task { await attendance.refresh(delivery.ledger) } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await renewal.refresh(); await attendance.refresh(delivery.ledger) } } }
            .background(DeliveryFeedback(store: delivery).frame(width: 0, height: 0))
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--seed-delivery") { delivery.installUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--qr-ui-testing") { delivery.installQRUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--monthly-ui-testing") { delivery.installMonthlyUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--reminder-ui-testing") { delivery.installReminderUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--update02-ui-testing") { delivery.installUpdate02UITestFixture() }
                #endif
                if library.canRead { library.reload() }
                await renewal.refresh()
                var requestAttendancePermission = true
                #if DEBUG
                if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") { requestAttendancePermission = false }
                #endif
                await attendance.refresh(delivery.ledger, requestPermission: requestAttendancePermission)
            }
        }
    }
}
