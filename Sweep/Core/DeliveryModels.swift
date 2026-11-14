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
enum DeliveryRoute: String, Codable, CaseIterable {
    case cashFull = "Tiền mặt đủ", transferNow = "Chuyển khoản ngay", transferLater = "Chuyển khoản sau", freight = "Giao chành"
}
enum EvidenceRole: String, Codable, CaseIterable {
    case invoice = "Phiếu nội bộ", signature = "Phiếu khách ký", transfer = "Ảnh giao dịch", companyQR = "QR công ty", freightSignature = "Phiếu nhà xe ký", goods = "Ảnh hàng đã gửi"
}
struct DeliveryEvidence: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: EvidenceRole
    var filename: String
    var sha256: String
    var bytes: Int64
    var addedAt = Date()
}
struct EvidenceExclusion: Codable, Identifiable, Equatable {
    var id = UUID()
    var evidenceID: UUID
    var reason: String
    var at = Date()
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
    var route: DeliveryRoute? = nil
    func validate(total: Int64) throws {
        try VND.check(total); try VND.check(cash); try VND.check(bank)
        guard cash + bank <= total else { throw DeliveryError.invalid("Tiền ghi nhận vượt tổng đơn. Kiểm tra khoản thừa trước khi lưu.") }
        if let route {
            guard outcome == .delivered else { throw DeliveryError.invalid("Chỉ chốt nhánh giao khi đã giao hàng.") }
            switch route {
            case .cashFull: guard cash == total && bank == 0 && mode == .cash else { throw DeliveryError.invalid("Thu đủ tiền mặt phải khớp tổng đơn.") }
            case .transferNow: guard bank > 0 && cash + bank <= total else { throw DeliveryError.invalid("Nhập khoản chuyển thực nhận.") }
            case .transferLater: guard bank == 0 && cash < total else { throw DeliveryError.invalid("CK sau phải còn khoản chưa thu.") }
            case .freight: guard cash == 0 && bank == 0 else { throw DeliveryError.invalid("Giao chành bàn giao tiền cho bán hàng theo dõi.") }
            }
        }
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
    var contentKey: String? = nil
}
struct DeliveryReportDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var evidenceIDs: [UUID]? = nil
    var revision: Int
    var text: String
    var at = Date()
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
    var sourceCreatedAt: Date?
    var sourceSnapshot: String?
    var salesperson: String? = nil
    var locationPromptedAt: Date? = nil
    var reviewNote = ""
    var note = ""
    var revision = 1
    var evidence: [DeliveryEvidence] = []
    var exclusions: [EvidenceExclusion] = []
    var assignments: [SignedAssignment] = []
    var reversals: [CommissionReversal] = []
    var settlements: [Settlement] = []
    var bankChecks: [BankVerification] = []
    var reports: [DeliveryReport] = []
    var reportDrafts: [DeliveryReportDraft] = []
    var reportAcks: [ReportAcknowledgement] = []
    var voidReason: String?
    var activeEvidence: [DeliveryEvidence] {
        let excluded = Set(exclusions.map(\.evidenceID))
        return evidence.filter { !excluded.contains($0.id) }
    }
    var settlement: Settlement? { settlements.last }
    var outcome: DeliveryOutcome { settlement?.outcome ?? .pending }
    var cash: Int64 { settlement?.cash ?? 0 }
    var bank: Int64 { settlement?.bank ?? 0 }
    var remaining: Int64 { total - cash - bank }
    var verifiedBank: Int64 { bankChecks.last(where: { $0.settlementID == settlement?.id })?.amount ?? 0 }
    var activeAssignments: [SignedAssignment] { assignments.filter { a in !reversals.contains { $0.assignmentID == a.id } } }
    var reportContentKey: String {
        // Bank verification, contact/location edits and unselected photos do not invalidate a sent report.
        let fields = [code, customer, String(total), outcome.rawValue, settlement?.mode.rawValue ?? "",
                      String(cash), String(bank), settlement?.route?.rawValue ?? "", settlement?.note ?? ""]
        return (try? String(data: DeliveryCoding.encode(fields), encoding: .utf8)) ?? ""
    }
    var reportSent: Bool {
        guard let report = reports.last else { return false }
        if let draft = reportDrafts.last, draft.at > report.preparedAt,
           draft.text != report.text || (draft.evidenceIDs != nil && draft.evidenceIDs != report.evidenceIDs) { return false }
        let current = report.contentKey.map { $0 == reportContentKey } ?? (report.revision == revision)
        return current && Set(report.evidenceIDs).isSubset(of: Set(activeEvidence.map(\.id))) && reportAcks.contains { $0.reportID == report.id }
    }
    var requiresReport: Bool { settlement != nil && settlement?.route != .cashFull }
    var reportNeeded: Bool { requiresReport && !reportSent && voidReason == nil }
    var taskComplete: Bool { outcome == .delivered && (settlement?.route == .cashFull || reportSent) }
    var workflowStatus: String {
        if voidReason != nil { return "Đã hủy" }
        if outcome != .delivered { return outcome == .pending ? "Đang giao" : outcome.rawValue }
        if settlement?.route == .cashFull { return "Đã giao · Tiền mặt chờ nộp" }
        if reportNeeded { return "Đã giao · Chờ gửi ảnh" }
        return settlement?.route == .freight ? "Đã giao chành" : "Đã hoàn tất"
    }
    static func normalizedCode(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().filter { !$0.isWhitespace }
    }
    var requiredReportRoles: [EvidenceRole] {
        switch settlement?.route {
        case .cashFull: return []
        case .transferNow: return [.invoice, .transfer]
        case .transferLater: return [.signature]
        case .freight: return [.freightSignature, .goods]
        case nil:
            var roles: [EvidenceRole] = [.invoice]
            if settlement?.mode == .deferred || settlement?.mode == .mixed { roles.append(.signature) }
            if bank > 0 { roles.append(.transfer) }; return roles
        }
    }
    var allowedReportRoles: Set<EvidenceRole> {
        switch settlement?.route {
        case .cashFull: return []
        case .transferNow: return [.invoice, .transfer]
        case .transferLater: return [.signature]
        case .freight: return [.freightSignature, .goods]
        case nil: return [.invoice, .signature, .transfer]
        }
    }
    func missingEvidence() -> [EvidenceRole] { requiredReportRoles.filter { role in !activeEvidence.contains { $0.role == role } } }
    var deliveryNoteForDisplay: String { InvoiceParser.cleanStoredNote(note) }
    var orderedEvidence: [DeliveryEvidence] {
        [EvidenceRole.invoice, .signature, .transfer, .freightSignature, .goods].flatMap { role in activeEvidence.filter { $0.role == role } }
    }
    var shareableEvidence: [DeliveryEvidence] { orderedEvidence.filter { allowedReportRoles.contains($0.role) } }
    var defaultShareEvidenceIDs: [UUID] {
        let roles: Set<EvidenceRole> = settlement?.route != nil ? allowedReportRoles : (bank > 0 ? [.invoice, .transfer] : [.invoice, .signature])
        return orderedEvidence.filter { roles.contains($0.role) }.map(\.id)
    }
    func shareText() -> String {
        if settlement?.route == .freight { return "\(customer) · Đã giao chành · \(code)" }
        if bank > 0 {
            let mixed = cash > 0 ? " · Tiền mặt \(VND.format(cash))" : ""
            let deferred = remaining > 0 ? " · Còn chuyển sau \(VND.format(remaining))" : ""
            return "\(customer) đã chuyển khoản \(VND.format(bank))" + mixed + deferred
        }
        if settlement?.route == .transferLater {
            let mixed = cash > 0 ? " · Đã thu tiền mặt \(VND.format(cash))" : ""
            return "\(customer) · Chuyển khoản sau \(VND.format(remaining))" + mixed
        }
        if cash > 0 { return "\(customer) đã thanh toán tiền mặt \(VND.format(cash))" }
        if settlement?.mode == .deferred { return "\(customer) · Chuyển khoản sau · \(VND.format(total))" }
        return "\(customer) · \(VND.format(total))"
    }
    func reportText() -> String {
        var rows = [customer, "Mã phiếu: \(code)", "Kết quả: \(outcome.rawValue)", "Tổng đơn: \(VND.format(total))",
                    "Tiền mặt đã thu: \(VND.format(cash))", "CK khách báo: \(VND.format(bank))",
                    "Còn lại theo ghi nhận: \(VND.format(remaining))"]
        if bank > 0 { rows.append("CK đã đối soát công ty: \(VND.format(verifiedBank))") }
        if settlement?.mode == .deferred { rows.append("Khách hẹn chuyển khoản sau, chưa ghi nhận tiền chuyển.") }
        if let text = settlement?.note, !text.isEmpty { rows.append("Ghi chú: \(text)") }
        let roles = [EvidenceRole.invoice, .signature, .transfer].filter { role in activeEvidence.contains { $0.role == role } }
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
struct HandoverReversal: Codable, Identifiable, Equatable {
    var id = UUID()
    var handoverID: UUID
    var reason: String
    var at = Date()
}
struct DeliverySettings: Codable, Equatable {
    var fee: Int64 = 5_000
    var company = ""
    var account = ""
    var qr: DeliveryEvidence?
    var vietQR: VietQRAccount?
}
struct DeliveryAudit: Codable, Identifiable, Equatable {
    var id = UUID()
    var at = Date()
    var orderID: UUID?
    var action: String
    var detail: String
}
struct DeliveryLedger: Codable, Equatable {
    var schema = 2
    var contacts: [DeliveryContact]? = nil
    var places: [DeliveryPlace]? = nil
    var orders: [DeliveryOrder] = []
    var handovers: [CashHandover] = []
    var handoverReversals: [HandoverReversal] = []
    var settings = DeliverySettings()
    var audit: [DeliveryAudit] = []
    var cashCollected: Int64 { orders.reduce(0) { $0 + $1.cash } }
    var cashHanded: Int64 {
        let reversed = Set(handoverReversals.map(\.handoverID))
        return handovers.filter { !reversed.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }
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
        guard orders[i].activeEvidence.contains(where: { $0.role == .invoice }) else { throw DeliveryError.invalid("Lưu phiếu nội bộ trước khi xác nhận ký nhận.") }
        guard date <= Date().addingTimeInterval(60) else { throw DeliveryError.invalid("Ngày ký nhận không được ở tương lai.") }
        orders[i].assignments.append(SignedAssignment(signedAt: date, fee: settings.fee))
        record("Ký nhận đi giao", orderID: id, "Ngày \(date.ISO8601Format()) · công \(settings.fee)")
    }
    mutating func settle(_ id: UUID, value: Settlement) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].voidReason == nil else { throw DeliveryError.invalid("Không tìm thấy hồ sơ hợp lệ.") }
        try value.validate(total: orders[i].total)
        if value.route != nil, orders[i].activeAssignments.isEmpty { throw DeliveryError.invalid("Xác nhận đã ký nhận trước khi chốt giao.") }
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
    mutating func prepareReport(_ id: UUID, text: String, evidenceIDs: [UUID]? = nil) throws -> DeliveryReport {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].settlement != nil, orders[i].voidReason == nil else {
            throw DeliveryError.invalid("Chốt giao / tiền trước khi chuẩn bị báo cáo.")
        }
        if evidenceIDs == nil {
            guard orders[i].missingEvidence().isEmpty else { throw DeliveryError.invalid("Thiếu: " + orders[i].missingEvidence().map(\.rawValue).joined(separator: ", ")) }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nội dung báo cáo đang trống.") }
        if orders[i].settlement?.route == .cashFull { throw DeliveryError.invalid("Thu đủ tiền mặt không cần gửi ảnh báo cáo.") }
        let allowed = Set(orders[i].shareableEvidence.map(\.id))
        let evidence = evidenceIDs ?? orders[i].shareableEvidence.map(\.id)
        guard Set(evidence).count == evidence.count, Set(evidence).isSubset(of: allowed) else { throw DeliveryError.invalid("Ảnh chọn gửi không còn trong hồ sơ. Chọn lại ảnh.") }
        if orders[i].settlement?.route != nil {
            let selectedRoles = Set(orders[i].activeEvidence.filter { evidence.contains($0.id) }.map(\.role))
            guard Set(orders[i].requiredReportRoles).isSubset(of: selectedRoles) else { throw DeliveryError.invalid("Chọn đủ: " + orders[i].requiredReportRoles.map(\.rawValue).joined(separator: ", ")) }
        }
        if let previous = orders[i].reports.last, previous.revision == orders[i].revision, previous.text == text, previous.evidenceIDs == evidence { return previous }
        let report = DeliveryReport(revision: orders[i].revision, text: text, evidenceIDs: evidence, contentKey: orders[i].reportContentKey)
        orders[i].reports.append(report); record("Chuẩn bị báo cáo", orderID: id, report.id.uuidString)
        return report
    }
    mutating func saveReportDraft(_ id: UUID, text: String, evidenceIDs: [UUID]? = nil) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), orders[i].voidReason == nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Nội dung nháp đang trống hoặc hồ sơ không hợp lệ.") }
        if let draft = orders[i].reportDrafts.last, draft.text == text, draft.evidenceIDs == evidenceIDs, draft.revision == orders[i].revision { return }
        if let report = orders[i].reports.last, report.text != text, report.revision == orders[i].revision { orders[i].revision += 1 }
        orders[i].reportDrafts.append(DeliveryReportDraft(evidenceIDs: evidenceIDs, revision: orders[i].revision, text: text))
        record("Lưu nội dung báo cáo nháp", orderID: id, text)
    }
    mutating func acknowledgeReport(_ id: UUID, reportID: UUID) throws {
        guard let i = orders.firstIndex(where: { $0.id == id }), let report = orders[i].reports.last,
              report.id == reportID, (report.contentKey.map { $0 == orders[i].reportContentKey } ?? (report.revision == orders[i].revision)) else { throw DeliveryError.invalid("Hồ sơ đã đổi. Chuẩn bị lại báo cáo trước khi xác nhận gửi.") }
        guard !orders[i].reportAcks.contains(where: { $0.reportID == reportID }) else { return }
        orders[i].reportAcks.append(ReportAcknowledgement(reportID: reportID))
        record("Sếp xác nhận đã gửi", orderID: id, reportID.uuidString)
    }
    mutating func excludeEvidence(_ evidenceID: UUID, orderID: UUID, reason: String) throws {
        guard let i = orders.firstIndex(where: { $0.id == orderID }), orders[i].evidence.contains(where: { $0.id == evidenceID }),
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Chọn ảnh và ghi lý do loại khỏi bộ báo cáo.") }
        guard !orders[i].exclusions.contains(where: { $0.evidenceID == evidenceID }) else { return }
        orders[i].exclusions.append(EvidenceExclusion(evidenceID: evidenceID, reason: reason)); orders[i].revision += 1
        record("Loại ảnh khỏi báo cáo, giữ bản gốc", orderID: orderID, "\(evidenceID) · \(reason)")
    }
    mutating func handover(_ amount: Int64, at: Date, note: String) throws {
        try VND.check(amount)
        guard amount > 0, amount <= cashHeld, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeliveryError.invalid("Nhập khoản nộp lớn hơn 0, không vượt tiền còn giữ, và người nhận / ghi chú xác nhận.")
        }
        handovers.append(CashHandover(amount: amount, at: at, note: note)); record("Nộp tiền mặt", "\(amount) · \(note)")
    }
    mutating func reverseHandover(_ id: UUID, reason: String) throws {
        guard handovers.contains(where: { $0.id == id }), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Ghi lý do điều chỉnh lần nộp tiền nhập nhầm.") }
        guard !handoverReversals.contains(where: { $0.handoverID == id }) else { return }
        handoverReversals.append(HandoverReversal(handoverID: id, reason: reason))
        record("Hủy ghi nhầm lần nộp tiền", "\(id) · \(reason)")
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
            let leading = text.trimmingCharacters(in: .whitespacesAndNewlines).first ?? " "
            let safe = "=+-@".contains(leading) || text.hasPrefix("\t") || text.hasPrefix("\r") ? "'" + text : text
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
        guard (schema == 1 || schema == 2), orders.count <= 50_000, handovers.count <= 100_000, Set(orders.map(\.id)).count == orders.count else { throw DeliveryError.invalid("Sổ không đúng phiên bản hoặc trùng ID.") }
        guard (contacts?.count ?? 0) <= 10_000, (places?.count ?? 0) <= 50_000,
              Set((contacts ?? []).map(\.id)).count == (contacts?.count ?? 0),
              Set((places ?? []).map(\.id)).count == (places?.count ?? 0) else { throw DeliveryError.invalid("Danh bạ / vị trí trùng ID hoặc quá giới hạn.") }
        for place in places ?? [] {
            guard !place.customer.isEmpty, !place.address.isEmpty,
                  (place.latitude == nil) == (place.longitude == nil) else { throw DeliveryError.invalid("Vị trí thiếu dữ liệu.") }
            if let lat = place.latitude, let lon = place.longitude { guard lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) else { throw DeliveryError.invalid("Tọa độ không hợp lệ.") } }
        }
        for contact in contacts ?? [] {
            guard !contact.name.isEmpty else { throw DeliveryError.invalid("Liên hệ thiếu tên.") }
            if !contact.zalo.isEmpty { guard let url = URL(string: contact.zalo), url.scheme == "https", url.host != nil else { throw DeliveryError.invalid("Link Zalo không hợp lệ.") } }
        }
        try VND.check(settings.fee)
        try settings.vietQR?.validate()
        guard Set(orders.map { DeliveryOrder.normalizedCode($0.code) }).count == orders.count else { throw DeliveryError.invalid("Sổ có mã phiếu trùng.") }
        let sources = orders.compactMap(\.sourceID)
        guard Set(sources).count == sources.count else { throw DeliveryError.invalid("Sổ có gói nhập trùng.") }
        for order in orders {
            guard !order.code.isEmpty, !order.customer.isEmpty, order.revision > 0, order.assignments.count <= 1 else { throw DeliveryError.invalid("Hồ sơ không hợp lệ.") }
            try VND.check(order.total)
            for value in order.settlements { try value.validate(total: order.total) }
            for value in order.assignments { try VND.check(value.fee) }
            guard order.assignments.isEmpty || order.evidence.contains(where: { $0.role == .invoice }) else { throw DeliveryError.invalid("Lượt ký nhận thiếu phiếu nội bộ.") }
            for reversal in order.reversals where !order.assignments.contains(where: { $0.id == reversal.assignmentID }) { throw DeliveryError.invalid("Điều chỉnh công thiếu lượt ký gốc.") }
            for check in order.bankChecks {
                guard order.settlements.contains(where: { $0.id == check.settlementID && $0.bank == check.amount }), check.amount > 0 else { throw DeliveryError.invalid("Đối soát CK không khớp khoản thu.") }
            }
            for report in order.reports where !Set(report.evidenceIDs).isSubset(of: Set(order.evidence.map(\.id))) { throw DeliveryError.invalid("Báo cáo thiếu ảnh nguồn.") }
            guard Set(order.exclusions.map(\.evidenceID)).count == order.exclusions.count else { throw DeliveryError.invalid("Trùng sự kiện loại ảnh.") }
            for exclusion in order.exclusions where !order.evidence.contains(where: { $0.id == exclusion.evidenceID }) { throw DeliveryError.invalid("Loại ảnh thiếu bản gốc.") }
            for ack in order.reportAcks where !order.reports.contains(where: { $0.id == ack.reportID }) { throw DeliveryError.invalid("Xác nhận gửi thiếu báo cáo gốc.") }
        }
        for value in handovers { try VND.check(value.amount); guard value.amount > 0 else { throw DeliveryError.invalid("Lần nộp tiền không hợp lệ.") } }
        for value in handoverReversals where !handovers.contains(where: { $0.id == value.handoverID }) { throw DeliveryError.invalid("Điều chỉnh nộp tiền thiếu bản ghi gốc.") }
        guard Set(handoverReversals.map(\.handoverID)).count == handoverReversals.count else { throw DeliveryError.invalid("Trùng điều chỉnh nộp tiền.") }
        var ids = orders.map(\.id) + handovers.map(\.id) + handoverReversals.map(\.id) + audit.map(\.id) + allEvidence.map(\.id)
        for order in orders {
            ids += order.assignments.map(\.id) + order.reversals.map(\.id) + order.settlements.map(\.id)
            ids += order.bankChecks.map(\.id) + order.reports.map(\.id) + order.reportAcks.map(\.id)
            ids += order.exclusions.map(\.id)
            ids += order.reportDrafts.map(\.id)
        }
        guard Set(ids).count == ids.count else { throw DeliveryError.invalid("Trùng ID sự kiện trong sổ.") }
        guard cashHeld >= 0, Set(allEvidence.map(\.id)).count == allEvidence.count,
              Set(allEvidence.map(\.filename)).count == allEvidence.count else { throw DeliveryError.invalid("Sổ tiền mặt hoặc danh sách ảnh không hợp lệ.") }
        for file in allEvidence {
            guard file.filename == URL(fileURLWithPath: file.filename).lastPathComponent,
                  UUID(uuidString: String(file.filename.prefix(36))) != nil,
                  file.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  file.bytes > 0, file.bytes <= 80 * 1024 * 1024 else { throw DeliveryError.invalid("Đường dẫn hoặc thông tin ảnh không hợp lệ.") }
        }
    }
    func validateAppendOnly(from previous: DeliveryLedger) throws {
        func keeps<T: Equatable>(_ before: [T], _ after: [T]) -> Bool { after.starts(with: before) }
        guard keeps(previous.audit, audit), keeps(previous.handovers, handovers), keeps(previous.handoverReversals, handoverReversals) else { throw DeliveryError.invalid("Không được xóa hoặc sửa lịch sử tài chính.") }
        let indexed = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        for old in previous.orders {
            guard let new = indexed[old.id], old.sourceID == new.sourceID, old.sourceSnapshot == new.sourceSnapshot,
                  old.sourceCreatedAt == new.sourceCreatedAt, new.revision >= old.revision,
                  keeps(old.evidence, new.evidence), keeps(old.assignments, new.assignments), keeps(old.reversals, new.reversals),
                  keeps(old.exclusions, new.exclusions),
                  keeps(old.settlements, new.settlements), keeps(old.bankChecks, new.bankChecks), keeps(old.reports, new.reports), keeps(old.reportAcks, new.reportAcks),
                  keeps(old.reportDrafts, new.reportDrafts),
                  old.voidReason == nil || old.voidReason == new.voidReason else { throw DeliveryError.invalid("Lịch sử hồ sơ phải được giữ nguyên; dùng bản ghi điều chỉnh.") }
        }
    }
}
