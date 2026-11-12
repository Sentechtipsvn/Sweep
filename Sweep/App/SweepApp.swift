import SwiftUI

@main
struct SweepApp: App {
    @StateObject private var library = PhotoStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { HomeView() }
                    .tabItem { Label("Sweep", systemImage: "sparkles") }
                NavigationStack { SettingsView() }
                    .tabItem { Label("Cài đặt", systemImage: "gearshape") }
            }
            .tint(.green)
            .environmentObject(library)
            .task { if library.canRead { library.reload() } }
        }
    }
}
