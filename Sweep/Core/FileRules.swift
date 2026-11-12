import Foundation

public enum FileRules {
    public static func isDescendant(_ file: URL, of root: URL) -> Bool {
        // File scanning only accepts existing entries. Foundation may leave an entire
        // URL unresolved when its final component is missing; fail closed in that case.
        guard FileManager.default.fileExists(atPath: file.path),
              FileManager.default.fileExists(atPath: root.path) else { return false }
        let rootParts = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let parts = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return parts.count > rootParts.count && Array(parts.prefix(rootParts.count)) == rootParts
    }
}

public enum SweepFormat {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
