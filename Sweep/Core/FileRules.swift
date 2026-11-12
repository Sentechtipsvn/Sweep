import Foundation

public enum FileRules {
    public static func isDescendant(_ file: URL, of root: URL) -> Bool {
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
