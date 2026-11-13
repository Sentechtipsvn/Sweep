import Foundation

/// Stored separately from the legacy free-form account note. Optional in old ledgers/backups.
struct VietQRAccount: Codable, Equatable {
    var bankID: String
    var accountNumber: String
    var accountName: String

    func validate() throws {
        guard bankID.range(of: #"^[A-Za-z0-9]{2,32}$"#, options: .regularExpression) != nil,
              accountNumber.range(of: #"^[A-Za-z0-9]{1,19}$"#, options: .regularExpression) != nil,
              !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              accountName.count <= 100, !accountName.contains(where: { $0.isNewline }) else {
            throw DeliveryError.invalid("Điền mã ngân hàng/BIN, số tài khoản (tối đa 19 chữ hoặc số) và tên chủ tài khoản.")
        }
    }
}

enum VietQR {
    static func suggestedAmount(for order: DeliveryOrder) -> Int64 {
        if order.remaining > 0 { return order.remaining }
        let awaitingBankCheck = order.bank - order.verifiedBank
        return awaitingBankCheck > 0 ? awaitingBankCheck : order.total
    }
    static func transferNote(code: String) -> String {
        let folded = code.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D").uppercased()
        let safe = folded.map { character -> Character in
            character.unicodeScalars.allSatisfy { (65...90).contains($0.value) || (48...57).contains($0.value) } ? character : " "
        }
        let words = String(safe).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(("TT DON " + words).prefix(50)).trimmingCharacters(in: .whitespaces)
    }

    static func url(account: VietQRAccount, order: DeliveryOrder, amount: Int64) throws -> URL {
        try account.validate(); try VND.check(amount)
        guard order.voidReason == nil, amount > 0, amount <= order.total else {
            throw DeliveryError.invalid("Số tiền QR phải lớn hơn 0 và không vượt tổng đơn đang hoạt động. Tạo lại QR không sửa khoản thu đã ghi nhận.")
        }
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = "img.vietqr.io"
        parts.path = "/image/\(account.bankID)-\(account.accountNumber)-qr_only.svg"
        parts.queryItems = [URLQueryItem(name: "amount", value: String(amount)),
                            URLQueryItem(name: "addInfo", value: transferNote(code: order.code)),
                            URLQueryItem(name: "accountName", value: account.accountName)]
        guard let url = parts.url else { throw DeliveryError.invalid("Chưa tạo được yêu cầu VietQR.") }
        return url
    }
}
