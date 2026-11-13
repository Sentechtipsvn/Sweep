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
