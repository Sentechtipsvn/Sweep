import Foundation

enum AppGroupConfiguration {
    /// AltStore rewrites provisioning groups and publishes the new IDs in each bundle's Info.plist.
    /// A custom build setting is not rewritten by AltStore and must only be the fallback.
    static func identifiers(in info: [String: Any]) -> [String] {
        let values: [String]
        if let injected = info["ALTAppGroups"] {
            values = injected as? [String] ?? []
        } else {
            values = (info["SweepAppGroupIdentifier"] as? String).map { [$0] } ?? []
        }
        return Array(Set(values.filter {
            $0.count <= 255 && $0.range(of: #"^group\.[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
        })).sorted()
    }
}
