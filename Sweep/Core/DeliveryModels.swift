import Foundation

enum DeliveryError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum VND {
    static let maximum: Int64 = 1_000_000_000_000
    static func parse(_ text: String) throws -> Int64 {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only digits or unambiguous Vietnamese thousands groups. Never strip a minus or decimal.
        guard value.range(of: #"^(?:0|[1-9][0-9]*|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)$"#, options: .regularExpression) != nil,
              let number = Int64(value.replacingOccurrences(of: ".", with: "")), number <= maximum else {
            throw DeliveryError.invalid("Nhập số tiền nguyên từ 0 đến 1.000.000.000.000₫, ví dụ 2165000 hoặc 2.165.000.")
        }
        return number
    }
    static func format(_ value: Int64) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "vi_VN"); f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: value)) ?? String(value)) + "₫"
    }
    static func check(_ value: Int64) throws {
        guard (0...maximum).contains(value) else { throw DeliveryError.invalid("Số tiền vượt giới hạn hoặc âm.") }
    }
}

enum DeliveryOutcome: String, Codable, CaseIterable {
    case pending = "Chưa giao", delivered = "Đã giao", postponed = "Hoãn giao", failed = "Giao thất bại"
}
enum PaymentMode: String, Codable, CaseIterable {
    case none = "Chưa thu", cash = "Tiền mặt", bank = "Chuyển khoản ngay", deferred = "Chuyển khoản sau", mixed = "CK + tiền mặt"
}
enum EvidenceRole: String, Codable, CaseIterable {
    case invoice = "Phiếu nội bộ", signature = "Phiếu khách ký", transfer = "Ảnh giao dịch", companyQR = "QR công ty"
}
struct DeliveryEvidence: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: EvidenceRole
    var filename: String
    var sha256: String
    var bytes: Int64
    var addedAt = Date()
}
struct SignedAssignment: Codable, Identifiable, Equatable {
    var id = UUID()
    var signedAt: Date
    var fee: Int64
}
struct CommissionReversal: Codable, Identifiable, Equatable {
    var id = UUID()
    var assignmentID: UUID
    var reason: String
    var at = Date()
}
struct Settlement: Codable, Identifiable, Equatable {
    var id = UUID()
    var outcome: DeliveryOutcome
    var mode: PaymentMode
    var cash: Int64
    var bank: Int64
    var note: String
    var at: Date
    func validate(total: Int64) throws {
        try VND.check(total); try VND.check(cash); try VND.check(bank)
        guard cash + bank <= total else { throw DeliveryError.invalid("Tiền ghi nhận vượt tổng đơn. Kiểm tra khoản thừa trước khi lưu.") }
        switch mode {
        case .none, .deferred:
            guard cash == 0 && bank == 0 else { throw DeliveryError.invalid("Chưa thu / CK sau phải có hai khoản bằng 0. Chọn đúng hình thức nếu đã nhận tiền.") }
        case .cash:
            guard bank == 0 else { throw DeliveryError.invalid("Có chuyển khoản: chọn CK + tiền mặt hoặc chuyển khoản ngay.") }
        case .bank:
            guard cash == 0 else { throw DeliveryError.invalid("Có tiền mặt: chọn CK + tiền mặt.") }
        case .mixed: break
        }
        if outcome == .failed || outcome == .postponed {
            guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DeliveryError.invalid("Ghi lý do giao thất bại / hoãn giao.")
            }
        }
    }
}
struct BankVerification: Codable, Identifiable, Equatable {
    var id = UUID()
    var settlementID: UUID
    var amount: Int64
    var note: String
    var at = Date()
}
struct DeliveryReport: Codable, Identifiable, Equatable {
    var id = UUID()
    var revision: Int
    var text: String
    var evidenceIDs: [UUID]
    var preparedAt = Date()
}
struct ReportAcknowledgement: Codable, Identifiable, Equatable {
    var id = UUID()
    var reportID: UUID
    var at = Date()
}
struct DeliveryOrder: Codable, Identifiable, Equatable {
    var id = UUID()
    var code: String
    var customer: String
    var total: Int64
    var phone = ""
    var address = ""
    var invoiceAt: Date?
    var importedAt = Date()
    var sourceID: String?
    var reviewNote = ""
    var note = ""
    var revision = 1
    var evidence: [DeliveryEvidence] = []
    var assignments: [SignedAssignment] = []
    var reversals: [CommissionReversal] = []
    var settlements: [Settlement] = []
    var bankChecks: [BankVerification] = []
    var reports: [DeliveryReport] = []
    var reportAcks: [ReportAcknowledgement] = []
    var voidReason: String?
    var settlement: Settlement? { settlements.last }
    var outcome: DeliveryOutcome { settlement?.outcome ?? .pending }
    var cash: Int64 { settlement?.cash ?? 0 }
    var bank: Int64 { settlement?.bank ?? 0 }
    var remaining: Int64 { total - cash - bank }
    var verifiedBank: Int64 { bankChecks.last(where: { $0.settlementID == settlement?.id })?.amount ?? 0 }
    var activeAssignments: [SignedAssignment] { assignments.filter { a in !reversals.contains { $0.assignmentID == a.id } } }
    var reportSent: Bool {
        guard let report = reports.last, report.revision == revision else { return false }
        return reportAcks.contains { $0.reportID == report.id }
    }
    var reportNeeded: Bool { settlement != nil && !reportSent && voidReason == nil }
    static func normalizedCode(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().filter { !$0.isWhitespace }
    }
    func missingEvidence() -> [EvidenceRole] {
        var needed: [EvidenceRole] = [.invoice]
        if settlement?.mode == .deferred || settlement?.mode == .mixed { needed.append(.signature) }
        if bank > 0 { needed.append(.transfer) }
        return needed.filter { role in !evidence.contains { $0.role == role } }
    }
    func reportText() -> String {
        var rows = [customer, "Mã phiếu: \(code)", "Kết quả: \(outcome.rawValue)", "Tổng đơn: \(VND.format(total))",
                    "Tiền mặt đã thu: \(VND.format(cash))", "CK khách báo: \(VND.format(bank))",
                    "Còn lại theo ghi nhận: \(VND.format(remaining))"]
        if bank > 0 { rows.append("CK đã đối soát công ty: \(VND.format(verifiedBank))") }
        if settlement?.mode == .deferred { rows.append("Khách hẹn chuyển khoản sau, chưa ghi nhận tiền chuyển.") }
        if let text = settlement?.note, !text.isEmpty { rows.append("Ghi chú: \(text)") }
        let roles = [EvidenceRole.invoice, .signature, .transfer].filter { role in evidence.contains { $0.role == role } }
        if !roles.isEmpty { rows.append("Đính kèm: " + roles.map(\.rawValue).joined(separator: ", ") + ".") }
        return rows.joined(separator: "\n")
    }
}
struct CashHandover: Codable, Identifiable, Equatable {
    var id = UUID()
    var amount: Int64
    var at: Date
    var note: String
}
struct DeliverySettings: Codable, Equatable {
    var fee: Int64 = 5_000
    var company = ""
    var account = ""
    var qr: DeliveryEvidence?
}
struct DeliveryAudit: Codable, Identifiable, Equatable {
    var id = UUID()
    var at = Date()
    var orderID: UUID?
    var action: String
    var detail: String
}
struct DeliveryLedger: Codable, Equatable {
    var schema = 1
    var orders: [DeliveryOrder] = []
    var handovers: [CashHandover] = []
    var settings = DeliverySettings()
    var audit: [DeliveryAudit] = []
    var cashCollected: Int64 { orders.reduce(0) { $0 + $1.cash } }
    var cashHanded: Int64 { handovers.reduce(0) { $0 + $1.amount } }
    var cashHeld: Int64 { cashCollected - cashHanded }
    var bankPending: Int64 { orders.reduce(0) { $0 + $1.bank - $1.verifiedBank } }
    var allEvidence: [DeliveryEvidence] { orders.flatMap(\.evidence) + (settings.qr.map { [$0] } ?? []) }
    mutating func record(_ action: String, orderID: UUID? = nil, _ detail: String) {
        audit.append(DeliveryAudit(orderID: orderID, action: action, detail: detail))
    }
    mutating func insert(_ order: DeliveryOrder) throws -> UUID {
        if let old = orders.first(where: {
            ($0.sourceID != nil && $0.sourceID == order.sourceID) ||
            DeliveryOrder.normalizedCode($0.code) == DeliveryOrder.normalizedCode(order.code)
        }) { return old.id }
        guard !order.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !order.customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeliveryError.invalid("Nhập tên khách và mã phiếu duy nhất để chống tính công trùng.")
        }
        try VND.check(order.total)
        orders.append(order); record("Nhận hồ sơ", orderID: order.id, "\(order.code) · \(order.customer) · \(order.total)")
        return order.id
    }
    mutating func sign(_ id: UUID, at date: Date) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].voidReason == nil else { throw DeliveryError.invalid("Không tìm thấy hồ sơ hợp lệ.") }
        guard orders[i].assignments.isEmpty else { return } // A reversed assignment cannot be silently recreated.
        guard orders[i].evidence.contains(where: { $0.role == .invoice }) else { throw DeliveryError.invalid("Lưu phiếu nội bộ trước khi xác nhận ký nhận.") }
        guard date <= Date().addingTimeInterval(60) else { throw DeliveryError.invalid("Ngày ký nhận không được ở tương lai.") }
        orders[i].assignments.append(SignedAssignment(signedAt: date, fee: settings.fee))
        record("Ký nhận đi giao", orderID: id, "Ngày \(date.ISO8601Format()) · công \(settings.fee)")
    }
    mutating func settle(_ id: UUID, value: Settlement) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].voidReason == nil else { throw DeliveryError.invalid("Không tìm thấy hồ sơ hợp lệ.") }
        try value.validate(total: orders[i].total)
        if let previous = orders[i].settlement, previous.cash == value.cash, previous.bank == value.bank,
           previous.mode == value.mode, previous.outcome == value.outcome, previous.note == value.note, previous.at == value.at { return }
        guard cashCollected - orders[i].cash + value.cash >= cashHanded else {
            throw DeliveryError.invalid("Điều chỉnh làm tiền đã thu thấp hơn số đã nộp. Kiểm tra sổ nộp tiền trước.")
        }
        let before = "TM \(orders[i].cash), CK \(orders[i].bank)"
        orders[i].settlements.append(value); orders[i].revision += 1
        record("Chốt giao / tiền", orderID: id, "\(before) → TM \(value.cash), CK \(value.bank) · \(value.outcome.rawValue) · \(value.note)")
    }
    mutating func verifyBank(_ id: UUID, note: String) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), let payment = orders[i].settlement, payment.bank > 0,
              !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Ghi nguồn xác nhận công ty đã nhận chuyển khoản.") }
        guard orders[i].verifiedBank != payment.bank else { return }
        orders[i].bankChecks.append(BankVerification(settlementID: payment.id, amount: payment.bank, note: note))
        orders[i].revision += 1
        record("Đối soát CK", orderID: id, "\(payment.bank) · \(note)")
    }
    mutating func prepareReport(_ id: UUID, text: String) throws -> DeliveryReport {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].settlement != nil, orders[i].voidReason == nil else {
            throw DeliveryError.invalid("Chốt giao / tiền trước khi chuẩn bị báo cáo.")
        }
        guard orders[i].missingEvidence().isEmpty else { throw DeliveryError.invalid("Thiếu: " + orders[i].missingEvidence().map(\.rawValue).joined(separator: ", ")) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nội dung báo cáo đang trống.") }
        let evidence = [EvidenceRole.invoice, .signature, .transfer].flatMap { role in orders[i].evidence.filter { $0.role == role }.map(\.id) }
        if let previous = orders[i].reports.last, previous.revision == orders[i].revision, previous.text == text, previous.evidenceIDs == evidence { return previous }
        let report = DeliveryReport(revision: orders[i].revision, text: text, evidenceIDs: evidence)
        orders[i].reports.append(report); record("Chuẩn bị báo cáo", orderID: id, report.id.uuidString)
        return report
    }
    mutating func acknowledgeReport(_ id: UUID, reportID: UUID) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), let report = orders[i].reports.last,
              report.id == reportID, report.revision == orders[i].revision else { throw DeliveryError.invalid("Hồ sơ đã đổi. Chuẩn bị lại báo cáo trước khi xác nhận gửi.") }
        guard !orders[i].reportAcks.contains(where: { $0.reportID == reportID }) else { return }
        orders[i].reportAcks.append(ReportAcknowledgement(reportID: reportID))
        record("Sếp xác nhận đã gửi", orderID: id, reportID.uuidString)
    }
    mutating func handover(_ amount: Int64, at: Date, note: String) throws {
        try VND.check(amount)
        guard amount > 0, amount <= cashHeld, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeliveryError.invalid("Nhập khoản nộp lớn hơn 0, không vượt tiền còn giữ, và người nhận / ghi chú xác nhận.")
        }
        handovers.append(CashHandover(amount: amount, at: at, note: note)); record("Nộp tiền mặt", "\(amount) · \(note)")
    }
    mutating func void(_ id: UUID, reason: String) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nhập lý do hủy hồ sơ.") }
        guard orders[i].cash == 0 && orders[i].bank == 0 else { throw DeliveryError.invalid("Hồ sơ còn khoản thu. Rà soát, điều chỉnh tiền trước khi hủy.") }
        guard orders[i].voidReason == nil else { return }
        for assignment in orders[i].activeAssignments { orders[i].reversals.append(CommissionReversal(assignmentID: assignment.id, reason: reason)) }
        orders[i].voidReason = reason; orders[i].revision += 1; record("Hủy và điều chỉnh công", orderID: id, reason)
    }
    func commissions(in month: Date, calendar: Calendar = .current) -> [(DeliveryOrder, SignedAssignment)] {
        orders.flatMap { order in order.activeAssignments.filter { calendar.isDate($0.signedAt, equalTo: month, toGranularity: .month) }.map { (order, $0) } }
    }
    func csv(in month: Date, calendar: Calendar = .current) -> String {
        func escape(_ text: String) -> String {
            // Prevent spreadsheet formula execution from customer-controlled names and codes.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(String(text.first ?? " ")) ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = ["Mã phiếu", "Khách", "Ngày ký", "Kết quả", "Tiền mặt", "CK khách báo", "CK đối soát", "Còn lại", "Công VND", "ID lượt ký"]
        let rows = commissions(in: month, calendar: calendar).map { order, assignment in
            [order.code, order.customer, assignment.signedAt.ISO8601Format(), order.outcome.rawValue,
             String(order.cash), String(order.bank), String(order.verifiedBank), String(order.remaining), String(assignment.fee), assignment.id.uuidString]
        }
        return "\u{FEFF}" + ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
    }
    func validate() throws {
        guard schema == 1, orders.count <= 50_000, handovers.count <= 100_000, Set(orders.map(\.id)).count == orders.count else { throw DeliveryError.invalid("Sổ không đúng phiên bản hoặc trùng ID.") }
        try VND.check(settings.fee)
        guard Set(orders.map { DeliveryOrder.normalizedCode($0.code) }).count == orders.count else { throw DeliveryError.invalid("Sổ có mã phiếu trùng.") }
        let sources = orders.compactMap(\.sourceID)
        guard Set(sources).count == sources.count else { throw DeliveryError.invalid("Sổ có gói nhập trùng.") }
        for order in orders {
            guard !order.code.isEmpty, !order.customer.isEmpty, order.revision > 0, order.assignments.count <= 1 else { throw DeliveryError.invalid("Hồ sơ không hợp lệ.") }
            try VND.check(order.total)
            for value in order.settlements { try value.validate(total: order.total) }
            for value in order.assignments { try VND.check(value.fee) }
            for reversal in order.reversals where !order.assignments.contains(where: { $0.id == reversal.assignmentID }) { throw DeliveryError.invalid("Điều chỉnh công thiếu lượt ký gốc.") }
            for check in order.bankChecks {
                guard order.settlements.contains(where: { $0.id == check.settlementID && $0.bank == check.amount }), check.amount > 0 else { throw DeliveryError.invalid("Đối soát CK không khớp khoản thu.") }
            }
            for report in order.reports where !Set(report.evidenceIDs).isSubset(of: Set(order.evidence.map(\.id))) { throw DeliveryError.invalid("Báo cáo thiếu ảnh nguồn.") }
            for ack in order.reportAcks where !order.reports.contains(where: { $0.id == ack.reportID }) { throw DeliveryError.invalid("Xác nhận gửi thiếu báo cáo gốc.") }
        }
        for value in handovers { try VND.check(value.amount); guard value.amount > 0 else { throw DeliveryError.invalid("Lần nộp tiền không hợp lệ.") } }
        guard cashHeld >= 0, Set(allEvidence.map(\.id)).count == allEvidence.count,
              Set(allEvidence.map(\.filename)).count == allEvidence.count else { throw DeliveryError.invalid("Sổ tiền mặt hoặc danh sách ảnh không hợp lệ.") }
        for file in allEvidence {
            guard file.filename == URL(fileURLWithPath: file.filename).lastPathComponent,
                  UUID(uuidString: String(file.filename.prefix(36))) != nil,
                  file.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  file.bytes > 0, file.bytes <= 80 * 1024 * 1024 else { throw DeliveryError.invalid("Đường dẫn hoặc thông tin ảnh không hợp lệ.") }
        }
    }
}
