import Foundation

/// Label-based suggestions only. Never infer a total from item prices or a customer phone from a salesperson.
struct InvoiceFields: Equatable {
    var code = ""
    var customer = ""
    var address = ""
    var phone = ""
    var deliveryNote = ""
    var invoiceDate: Date?
    var total: Int64?
}

enum InvoiceParser {
    private static let labels = #"(?:don\s+vi|nguoi\s+mua\s+hang|dia\s+chi\s+giao\s+hang|dia\s+chi|dien\s+thoai|sdt|nv\s+ban\s+hang|so)\s*[:：]"#
    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
    }
    /// Maps the folded label boundary back to the untouched Vietnamese value.
    private static func value(_ line: String, pattern: String) -> String? {
        var ascii = "", boundaries: [String.Index] = []
        for index in line.indices {
            let piece = folded(String(line[index]))
            boundaries += Array(repeating: index, count: piece.utf16.count)
            ascii += piece
        }
        boundaries.append(line.endIndex)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ascii, range: NSRange(ascii.startIndex..., in: ascii)) else { return nil }
        let start = match.range.location + match.range.length
        guard start < boundaries.count else { return nil }
        var end = ascii.utf16.count
        if let regex = try? NSRegularExpression(pattern: #"\s+(?:"# + labels + ")"),
           let next = regex.firstMatch(in: ascii, range: NSRange(location: start, length: end - start)) { end = next.range.location }
        return String(line[boundaries[start]..<boundaries[end]]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func parse(_ text: String) -> InvoiceFields {
        let lines = text.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result = InvoiceFields()
        var totalPriority = 0
        for (i, line) in lines.enumerated() {
            func field(_ label: String) -> String? {
                let found = value(line, pattern: #"(?:^|\s)(?:"# + label + #")\s*[:：]\s*"#)
                // OCR may put a value on the next line. Do not consume another labelled field.
                if found == "", i + 1 < lines.count, value(lines[i + 1], pattern: labels) == nil { return lines[i + 1] }
                return found
            }
            if result.customer.isEmpty, let v = field(#"don\s+vi"#) { result.customer = v }
            if result.address.isEmpty, let v = field(#"dia\s+chi"#) { result.address = v }
            if result.deliveryNote.isEmpty, let v = field(#"dia\s+chi\s+giao\s+hang"#) { result.deliveryNote = v }
            if result.code.isEmpty, let v = field("so"), let token = v.split(whereSeparator: { $0.isWhitespace }).first,
               token.range(of: #"^[A-Za-z0-9][A-Za-z0-9./_-]{0,47}$"#, options: .regularExpression) != nil { result.code = String(token) }
            if result.phone.isEmpty, let v = field(#"dien\s+thoai|sdt"#) {
                let digits = v.filter { $0.isNumber || $0 == "+" }
                if digits.range(of: #"^(?:0[0-9]{9,10}|\+84[0-9]{9,10})$"#, options: .regularExpression) != nil { result.phone = digits }
            }
            // Keep to the labelled total cell (or its next line), never the whole footer/item table.
            for (priority, label) in [(4, #"tong\s+thanh\s+toan"#), (3, #"tong\s+cong"#), (2, #"tong\s+tien(?:\s+hang)?"#), (1, #"tien\s+hang"#)] where priority > totalPriority {
                if let v = value(line, pattern: #"(?:^|\s)(?:"# + label + #")\s*[:：]?\s*"#) {
                    let candidate = v.isEmpty && i + 1 < lines.count ? lines[i + 1] : v
                    let money = candidate.replacingOccurrences(of: "₫", with: "").replacingOccurrences(of: "đ", with: "").trimmingCharacters(in: .whitespaces)
                    if let amount = try? VND.parse(money) { result.total = amount; totalPriority = priority }
                }
            }
            if result.invoiceDate == nil {
                let ascii = folded(line)
                if let regex = try? NSRegularExpression(pattern: #"\bngay\s+(\d{1,2})\s+thang\s+(\d{1,2})\s+nam\s+(\d{4})\b"#),
                   let match = regex.firstMatch(in: ascii, range: NSRange(ascii.startIndex..., in: ascii)) {
                    let ns = ascii as NSString
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
                    let d = Int(ns.substring(with: match.range(at: 1)))!, m = Int(ns.substring(with: match.range(at: 2)))!, y = Int(ns.substring(with: match.range(at: 3)))!
                    if let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)),
                       calendar.component(.day, from: date) == d, calendar.component(.month, from: date) == m { result.invoiceDate = date }
                }
            }
        }
        return result
    }
}
