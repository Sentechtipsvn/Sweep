import Foundation

public struct PhotoRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date?
    public let width: Int
    public let height: Int
    public let favorite: Bool
    public let screenshot: Bool
    public let eligibleForExactMatch: Bool

    public init(id: String, date: Date? = nil, width: Int, height: Int,
                favorite: Bool = false, screenshot: Bool = false, eligibleForExactMatch: Bool = true) {
        self.id = id; self.date = date; self.width = width; self.height = height
        self.favorite = favorite; self.screenshot = screenshot
        self.eligibleForExactMatch = eligibleForExactMatch
    }

    public var dimensionKey: String { "\(width)x\(height)" }
}

public struct PhotoDigest: Sendable {
    public let photo: PhotoRecord
    public let hash: String
    public let bytes: Int64
    public init(photo: PhotoRecord, hash: String, bytes: Int64) {
        self.photo = photo; self.hash = hash; self.bytes = bytes
    }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let members: [PhotoRecord]
    public let bytesPerPhoto: Int64
    public var suggestedKeepID: String { members[0].id }
    public var removableBytes: Int64 { Int64(members.count - 1) * bytesPerPhoto }
}

public enum DuplicateRules {
    public static func candidateIDs(in photos: [PhotoRecord]) -> Set<String> {
        let eligible = photos.filter(\.eligibleForExactMatch)
        return Set(Dictionary(grouping: eligible, by: \.dimensionKey).values
            .filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    public static func groups(from digests: [PhotoDigest]) -> [DuplicateGroup] {
        // Incomplete/failed reads never become a digest. Include byte length as an extra guard.
        let valid = digests.filter { $0.photo.eligibleForExactMatch && !$0.hash.isEmpty && $0.bytes > 0 }
        let buckets = Dictionary(grouping: valid) { "\($0.hash):\($0.bytes)" }
        return buckets.compactMap { key, values -> DuplicateGroup? in
            let unique = Dictionary(values.map { ($0.photo.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard unique.count > 1 else { return nil }
            let members = unique.values.map(\.photo).sorted {
                if $0.favorite != $1.favorite { return $0.favorite }
                if $0.date != $1.date { return ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                return $0.id < $1.id
            }
            return DuplicateGroup(id: key, members: members, bytesPerPhoto: values[0].bytes)
        }.sorted {
            $0.removableBytes == $1.removableBytes ? $0.id < $1.id : $0.removableBytes > $1.removableBytes
        }
    }

    public static func keepsAtLeastOne(in groups: [DuplicateGroup], deleting ids: Set<String>) -> Bool {
        groups.allSatisfy { $0.members.contains { !ids.contains($0.id) } }
    }
}
