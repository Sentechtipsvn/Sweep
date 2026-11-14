import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var library = PhotoStore()
    @StateObject private var delivery = DeliveryStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                OrdersView().tabItem { Label("Đơn hàng", systemImage: "shippingbox") }
                NavigationStack { ReconciliationView() }
                    .tabItem { Label("Lịch sử", systemImage: "clock.arrow.circlepath") }
                NavigationStack { HomeView() }
                    .tabItem { Label("Công cụ", systemImage: "sparkles") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Cài đặt", systemImage: "gearshape") }
            }
            .tint(SweepStyle.blue)
            .environmentObject(library)
            .environmentObject(delivery)
            .background(DeliveryFeedback(store: delivery).frame(width: 0, height: 0))
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--seed-delivery") { delivery.installUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--qr-ui-testing") { delivery.installQRUITestFixture() }
                if ProcessInfo.processInfo.arguments.contains("--monthly-ui-testing") { delivery.installMonthlyUITestFixture() }
                #endif
                if library.canRead { library.reload() }
            }
        }
    }
}
