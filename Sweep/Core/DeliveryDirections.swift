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

struct MapPin: Equatable {
    let latitude: Double
    let longitude: Double
    static func read(_ input: String) -> MapPin? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func pair(_ text: String) -> MapPin? {
            let fields = text.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2,
                  let a = Double(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let b = Double(fields[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  (-90...90).contains(a), (-180...180).contains(b) else { return nil }
            return MapPin(latitude: a, longitude: b)
        }
        if let point = pair(value) { return point }
        guard let url = URL(string: value), isMapLink(url),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for key in ["destination", "query", "q", "ll"] {
            if let v = parts.queryItems?.first(where: { $0.name == key })?.value, let point = pair(v) { return point }
        }
        let path = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        if let match = path.range(of: #"!3d-?[0-9]+(?:\.[0-9]+)?!4d-?[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) {
            return pair(String(path[match].dropFirst(3)).replacingOccurrences(of: "!4d", with: ","))
        }
        return nil // @lat,lng in a Maps URL can be only the camera, far from the actual place.
    }
    static func isMapLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { return false }
        return ["maps.app.goo.gl", "www.google.com", "maps.google.com", "google.com",
                "www.google.com.vn", "maps.google.com.vn", "google.com.vn"].contains(host)
            || (host == "goo.gl" && url.path.hasPrefix("/maps/"))
    }
    static func googleSearch(_ query: String) -> URL? {
        var parts = URLComponents(string: "https://www.google.com/maps/search/")
        parts?.queryItems = [.init(name: "api", value: "1"), .init(name: "query", value: query)]
        return parts?.url
    }
}
