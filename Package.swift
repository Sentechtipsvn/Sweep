// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SweepCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "SweepCore", targets: ["SweepCore"])],
    targets: [
        .target(name: "SweepCore", path: "Sweep",
                exclude: ["App", "Services", "Views", "Info.plist", "PrivacyInfo.xcprivacy", "Assets.xcassets", "Sweep.entitlements"],
                sources: ["Core", "Imaging"]),
        .testTarget(name: "SweepCoreTests", dependencies: ["SweepCore"], path: "Tests")
    ]
)
