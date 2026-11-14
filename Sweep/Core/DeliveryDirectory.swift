import Foundation

struct DeliveryContact: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var phone: String
    var zalo: String
    var aliases: String
    var role: String
    func matches(_ seller: String) -> Bool {
        let key = seller.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        return ([name] + aliases.components(separatedBy: ",")).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) == key.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")) }
    }
}
struct DeliveryPlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var customer: String
    var phone: String
    var address: String
    var kind: String
    var latitude: Double?
    var longitude: Double?
    var destination: String {
        if let lat = latitude, let lon = longitude { return "\(lat),\(lon)" }
        return address
    }
    static func key(customer: String, address: String, kind: String, phone: String = "") -> String {
        var number = phone.filter(\.isNumber)
        if number.hasPrefix("84"), number.count == 11 { number = "0" + String(number.dropFirst(2)) }
        return [customer, address, kind, number].map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN")).split(whereSeparator: \.isWhitespace).joined(separator: " ") }.joined(separator: "|")
    }
    var key: String { Self.key(customer: customer, address: address, kind: kind, phone: phone) }
}
extension DeliveryLedger {
    mutating func saveContact(_ value: DeliveryContact) throws {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nhập tên liên hệ.") }
        if !value.zalo.isEmpty {
            guard let u = URL(string: value.zalo), u.scheme == "https", u.host != nil else { throw DeliveryError.invalid("Dán liên kết Zalo HTTPS của liên hệ.") }
        }
        var list = contacts ?? []
        if let i = list.firstIndex(where: { $0.id == value.id }) { list[i] = value } else { list.append(value) }
        contacts = list; record("Lưu liên hệ", value.name)
    }
    mutating func savePlace(_ value: DeliveryPlace) throws {
        guard !value.customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nhập tên và địa chỉ.") }
        if let lat = value.latitude { guard lat.isFinite && (-90...90).contains(lat) else { throw DeliveryError.invalid("Vĩ độ không hợp lệ.") } }
        if let lon = value.longitude { guard lon.isFinite && (-180...180).contains(lon) else { throw DeliveryError.invalid("Kinh độ không hợp lệ.") } }
        guard (value.latitude == nil) == (value.longitude == nil) else { throw DeliveryError.invalid("Nhập đủ tọa độ.") }
        var list = places ?? []
        if let i = list.firstIndex(where: { $0.id == value.id || $0.key == value.key }) { var copy = value; copy.id = list[i].id; list[i] = copy } else { list.append(value) }
        places = list; record("Lưu vị trí", value.customer)
    }
    func hasPlace(for order: DeliveryOrder) -> Bool {
        if order.settlement?.route == .freight {
            return (places ?? []).contains { $0.id == order.freightPlaceID && $0.kind == "Chành xe" }
        }
        return (places ?? []).contains { $0.key == DeliveryPlace.key(customer: order.customer, address: order.address, kind: "Khách hàng", phone: order.phone) }
    }
}
