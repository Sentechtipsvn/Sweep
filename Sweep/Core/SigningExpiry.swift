import Foundation

enum SigningExpiry {
    /// Reads the embedded plist, not a certificate validation API. Missing/unsupported profiles use manual entry.
    static func expiration(in data: Data) -> Date? {
        guard data.count <= 4 * 1024 * 1024,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let value = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], options: [], format: nil) as? [String: Any],
              let expiry = value["ExpirationDate"] as? Date, expiry.timeIntervalSince1970.isFinite else { return nil }
        if let created = value["CreationDate"] as? Date, created >= expiry { return nil }
        return expiry
    }
    static func reminders(expiry: Date, now: Date, limit: Int = 48) -> [Date] {
        guard expiry.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { return [] }
        let start = expiry.addingTimeInterval(-24 * 3600), step: TimeInterval = 3 * 3600
        let offset = max(0, floor(now.timeIntervalSince(start) / step) + 1)
        let first = start > now ? start : start.addingTimeInterval(offset * step)
        return (0..<min(48, max(0, limit))).map { first.addingTimeInterval(Double($0) * step) }
    }
}

enum ContactLinks {
    static func phoneKey(_ value: String) -> String {
        var n = value.filter(\.isNumber)
        if n.hasPrefix("84"), n.count == 11 { n = "0" + n.dropFirst(2) }
        return n
    }
    static func zalo(_ text: String) -> URL? {
        guard let u = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.lowercased() == "https",
              let host = u.host?.lowercased(), ["zalo.me", "www.zalo.me", "qr.zalo.me"].contains(host),
              u.user == nil, u.password == nil, u.port == nil, u.path.count > 1 else { return nil }
        return u
    }
}
