import Foundation

enum DeliveryDirections {
    static func googleMaps(address: String, native: Bool = true) -> URL? {
        let destination = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }
        var parts = URLComponents(string: native ? "comgooglemaps://" : "https://www.google.com/maps/dir/")!
        parts.queryItems = native
            ? [URLQueryItem(name: "daddr", value: destination), URLQueryItem(name: "directionsmode", value: "driving")]
            : [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: destination), URLQueryItem(name: "travelmode", value: "driving"), URLQueryItem(name: "dir_action", value: "navigate")]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}

/// Preserve place IDs and short links as shared. Saving a link works offline.
enum PlaceMapLink {
    static func url(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 8192,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let hasQuery = query.contains { $0.value?.isEmpty == false }
        switch host {
        case "maps.app.goo.gl":
            return path.count > 1 ? url : nil
        case "goo.gl":
            return path.hasPrefix("/maps/") && path.count > 6 ? url : nil
        case "maps.apple.com", "maps.google.com", "maps.google.com.vn":
            return path.count > 1 || hasQuery ? url : nil
        case "maps.app.apple":
            return path.count > 1 ? url : nil
        case "www.google.com", "google.com", "www.google.com.vn", "google.com.vn":
            return (path.hasPrefix("/maps/") && (path.count > 6 || hasQuery)) || (path == "/maps" && hasQuery) ? url : nil
        default:
            return nil
        }
    }

    static func gpsLink(latitude: Double, longitude: Double) -> String {
        "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)"
    }
}
