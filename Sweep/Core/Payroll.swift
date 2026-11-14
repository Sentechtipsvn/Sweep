import Foundation

enum PayrollDates {
    static var calendar: Calendar { DeliveryMonth.calendar }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    static func days(_ month: Date) -> [Date] {
        let start = DeliveryMonth.start(month)
        return calendar.range(of: .day, in: .month, for: start)!.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }
    static func closeDay(_ month: Date) -> Date { days(month).last! }
    static func fuelDay(_ month: Date) -> Date { days(month)[min(30, days(month).count) - 1] }
}

enum AttendanceState: String, Codable, CaseIterable {
    case work = "Đi làm", half = "Nửa công", leave = "Nghỉ phép không lương", off = "Nghỉ theo lịch"
    var workUnits: Int { self == .work ? 2 : self == .half ? 1 : 0 }
    var leaveUnits: Int { self == .leave ? 2 : self == .half ? 1 : 0 }
}
struct AttendanceEntry: Codable, Equatable, Identifiable {
    var day: Date
    var state: AttendanceState
    var note = ""
    var id: Date { day }
}
struct PayrollPolicy: Codable, Equatable {
    var base: Int64 = 5_600_000
    var phone: Int64 = 400_000
    var meal: Int64 = 30_000
    var maintenance: Int64 = 25_000
    var attendance: Int64 = 500_000
    var insurance: Int64 = 588_000
    var fuelLitres = 3
    var weekdays: [Int] = [] // Empty until the actual work schedule is configured.
    var confirmed = false
    var fuelType = ""
    var fuelRegion = ""
    func validate() throws {
        for n in [base, phone, meal, maintenance, attendance, insurance] {
            guard (0...1_000_000_000).contains(n) else { throw DeliveryError.invalid("Mức lương/trợ cấp vượt giới hạn.") }
        }
        guard (0...20).contains(fuelLitres), Set(weekdays).count == weekdays.count,
              weekdays.allSatisfy({ (1...7).contains($0) }), !confirmed || !weekdays.isEmpty else {
            throw DeliveryError.invalid("Chọn lịch làm việc và kiểm tra định mức xăng.")
        }
    }
}
struct PayrollFuel: Codable, Equatable {
    var price: Int64
    var effectiveDay: Date
    var source: String
    var recordedAt = Date()
}
struct SalaryAdvance: Codable, Equatable, Identifiable {
    var id = UUID()
    var day: Date
    var amount: Int64
    var note: String
}
struct PayrollMonth: Codable, Equatable, Identifiable {
    var month: Date
    var policy = PayrollPolicy()
    var entries: [AttendanceEntry] = []
    var fuel: PayrollFuel?
    var advances: [SalaryAdvance] = []
    var adjustment: Int64 = 0
    var adjustmentReason = ""
    var id: String { PayrollDates.key(month) }
    func entry(_ day: Date) -> AttendanceEntry? { entries.first { PayrollDates.calendar.isDate($0.day, inSameDayAs: day) } }
    func isPlanned(_ day: Date) -> Bool {
        if let state = entry(day)?.state { return state != .off }
        return policy.weekdays.contains(PayrollDates.calendar.component(.weekday, from: day))
    }
}
struct PayrollCalculation: Codable, Equatable {
    var plannedUnits: Int
    var workUnits: Int
    var leaveUnits: Int
    var missingDays: Int
    var commissions: Int
    var fee: Int64
    var base: Int64
    var phone: Int64
    var meal: Int64
    var maintenance: Int64
    var fuel: Int64
    var attendance: Int64
    var insurance: Int64
    var advances: Int64
    var adjustment: Int64
    var fuelConfirmed: Bool
    var net: Int64 { base + phone + meal + maintenance + fuel + attendance + fee - insurance - advances + adjustment }
    var rows: [(String, Int64)] {
        [("Lương theo công", base), ("Công đơn", fee), ("Điện thoại", phone), ("Xăng xe", fuel),
         ("Ăn", meal), ("Bảo trì xe", maintenance), ("Chuyên cần", attendance),
         ("Bảo hiểm", -insurance), ("Tạm ứng", -advances), ("Điều chỉnh", adjustment), ("Thực nhận", net)]
    }
    static func round(_ number: Decimal) -> Int64 {
        var source = number, result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return NSDecimalNumber(decimal: result).int64Value
    }
    init(ledger: DeliveryLedger, period: PayrollMonth) {
        let days = PayrollDates.days(period.month), entries = period.entries
        plannedUnits = days.filter { period.isPlanned($0) }.count * 2
        workUnits = entries.reduce(0) { $0 + $1.state.workUnits }
        leaveUnits = entries.reduce(0) { $0 + $1.state.leaveUnits }
        missingDays = days.filter { period.isPlanned($0) && period.entry($0) == nil }.count
        let assignments = ledger.commissions(in: period.month, calendar: PayrollDates.calendar)
        commissions = assignments.count; fee = assignments.reduce(0) { $0 + $1.1.fee }
        let p = period.policy, ratio = plannedUnits == 0 ? Decimal(0) : Decimal(workUnits) / Decimal(plannedUnits)
        base = Self.round(Decimal(p.base) * ratio)
        phone = Self.round(Decimal(p.phone) * ratio)
        meal = Self.round(Decimal(p.meal) * Decimal(workUnits) / 2)
        maintenance = Self.round(Decimal(p.maintenance) * Decimal(workUnits) / 2)
        fuelConfirmed = period.fuel != nil
        fuel = Self.round(Decimal(period.fuel?.price ?? 0) * Decimal(p.fuelLitres) * Decimal(workUnits) / 2)
        attendance = leaveUnits > 6 ? 0 : p.attendance
        insurance = p.insurance
        advances = period.advances.reduce(0) { $0 + $1.amount }
        adjustment = period.adjustment
    }
}
struct PayrollSnapshot: Codable, Equatable, Identifiable {
    var id = UUID()
    var period: PayrollMonth
    var calculation: PayrollCalculation
    var assignmentIDs: [UUID]
    var closedAt = Date()
}
struct PayrollBook: Codable, Equatable {
    var months: [PayrollMonth] = []
    var snapshots: [PayrollSnapshot] = []
    var reopenedIDs: [UUID] = []
    var openingLeaveUnits: [String: Int] = [:]
    func period(_ month: Date) -> PayrollMonth { months.first { $0.id == PayrollDates.key(month) } ?? PayrollMonth(month: DeliveryMonth.start(month)) }
    func closed(_ month: Date) -> PayrollSnapshot? {
        snapshots.last { $0.period.id == PayrollDates.key(month) && !reopenedIDs.contains($0.id) }
    }
    func annualLeaveUnits(year: Int) -> Int {
        (openingLeaveUnits[String(year)] ?? 0) + months.filter { PayrollDates.calendar.component(.year, from: $0.month) == year }
            .flatMap(\.entries).reduce(0) { $0 + $1.state.leaveUnits }
    }
    mutating func put(_ period: PayrollMonth) throws {
        guard closed(period.month) == nil else { throw DeliveryError.invalid("Tháng đã chốt. Mở khóa có lý do trước khi sửa.") }
        if let i = months.firstIndex(where: { $0.id == period.id }) { months[i] = period } else { months.append(period) }
    }
    func validate() throws {
        guard months.count <= 1200, snapshots.count <= 5000, Set(months.map(\.id)).count == months.count,
              Set(snapshots.map(\.id)).count == snapshots.count, Set(reopenedIDs).count == reopenedIDs.count,
              Set(reopenedIDs).isSubset(of: Set(snapshots.map(\.id))),
              openingLeaveUnits.values.allSatisfy({ (0...732).contains($0) }) else { throw DeliveryError.invalid("Sổ công/lương không hợp lệ.") }
        for p in months + snapshots.map(\.period) {
            guard p.month.timeIntervalSince1970.isFinite, (-2_208_988_800...10_413_792_000).contains(p.month.timeIntervalSince1970) else {
                throw DeliveryError.invalid("Ngày kỳ lương ngoài phạm vi hỗ trợ.")
            }
            try p.policy.validate()
            guard p.month == DeliveryMonth.start(p.month), Set(p.entries.map(\.day)).count == p.entries.count,
                  p.entries.count <= 31, p.entries.allSatisfy({ DeliveryMonth.contains($0.day, in: p.month) && $0.day == PayrollDates.calendar.startOfDay(for: $0.day) }),
                  p.advances.count <= 1000, (-1_000_000_000...1_000_000_000).contains(p.adjustment),
                  p.adjustment == 0 || !p.adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(p.advances.map(\.id)).count == p.advances.count else { throw DeliveryError.invalid("Dữ liệu công trong tháng chưa hợp lệ.") }
            for a in p.advances {
                guard a.amount > 0, a.amount <= 1_000_000_000, DeliveryMonth.contains(a.day, in: p.month) else { throw DeliveryError.invalid("Tạm ứng không hợp lệ.") }
            }
            if let fuel = p.fuel {
                guard (1...1_000_000).contains(fuel.price), PayrollDates.calendar.isDate(fuel.effectiveDay, inSameDayAs: PayrollDates.fuelDay(p.month)),
                      !fuel.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Giá xăng phải có nguồn và đúng ngày chốt.") }
            }
        }
        for snap in snapshots {
            let c = snap.calculation
            let amounts = [c.base, c.phone, c.meal, c.maintenance, c.fuel, c.attendance, c.insurance, c.advances, c.adjustment]
            guard amounts.allSatisfy({ (-100_000_000_000_000...100_000_000_000_000).contains($0) }),
                  (0...50_000_000_000_000_000).contains(c.fee), (0...62).contains(c.plannedUnits),
                  (0...62).contains(c.workUnits), (0...62).contains(c.leaveUnits), (0...31).contains(c.missingDays),
                  (0...50_000).contains(c.commissions), snap.assignmentIDs.count == c.commissions,
                  Set(snap.assignmentIDs).count == snap.assignmentIDs.count else { throw DeliveryError.invalid("Bản lương đã chốt có số liệu không hợp lệ.") }
        }
        for snap in snapshots where !reopenedIDs.contains(snap.id) {
            guard months.first(where: { $0.id == snap.period.id }) == snap.period else { throw DeliveryError.invalid("Tháng đã chốt bị thay đổi khi chưa mở khóa.") }
        }
    }
    func validateAppendOnly(from previous: PayrollBook) throws {
        guard snapshots.starts(with: previous.snapshots), reopenedIDs.starts(with: previous.reopenedIDs) else { throw DeliveryError.invalid("Không được xóa/sửa bản lương đã chốt.") }
        for snap in previous.snapshots where !previous.reopenedIDs.contains(snap.id) && !reopenedIDs.contains(snap.id) {
            guard period(snap.period.month) == snap.period else { throw DeliveryError.invalid("Tháng đã chốt phải được giữ nguyên.") }
        }
    }
}
extension DeliveryLedger {
    mutating func changePayroll(_ action: String, _ operation: (inout PayrollBook) throws -> Void) throws {
        var book = payroll ?? PayrollBook(); try operation(&book); try book.validate()
        payroll = book; record(action, "Công và lương")
    }
    mutating func markAttendance(_ day: Date, state: AttendanceState?, note: String = "", now: Date = Date()) throws {
        let normalized = PayrollDates.calendar.startOfDay(for: day)
        guard normalized <= PayrollDates.calendar.startOfDay(for: now) else { throw DeliveryError.invalid("Chưa thể chấm công cho ngày tương lai.") }
        try changePayroll("Sửa công " + normalized.ISO8601Format()) { book in
            var p = book.period(normalized)
            p.entries.removeAll { $0.day == normalized }
            if let state { p.entries.append(AttendanceEntry(day: normalized, state: state, note: note)) }
            try book.put(p)
        }
    }
    mutating func closePayroll(_ month: Date, now: Date = Date()) throws {
        let book = payroll ?? PayrollBook(), p = book.period(month), result = PayrollCalculation(ledger: self, period: p)
        guard PayrollDates.calendar.startOfDay(for: now) >= PayrollDates.closeDay(month) else { throw DeliveryError.invalid("Chốt lương vào ngày cuối tháng, không cố định ngày 30.") }
        guard result.plannedUnits > 0, p.policy.confirmed, !p.policy.fuelType.isEmpty, !p.policy.fuelRegion.isEmpty, result.missingDays == 0, result.fuelConfirmed else {
            throw DeliveryError.invalid("Xác nhận lịch/mức lương, loại/vùng xăng, đủ công và giá chốt trước khi khóa tháng.")
        }
        let assignments = commissions(in: month, calendar: PayrollDates.calendar).map { $0.1.id }
        try changePayroll("Chốt lương " + p.id) { book in
            guard book.closed(month) == nil else { throw DeliveryError.invalid("Tháng đã được chốt.") }
            try book.put(p)
            book.snapshots.append(PayrollSnapshot(period: p, calculation: result, assignmentIDs: assignments, closedAt: now))
        }
    }
    mutating func reopenPayroll(_ month: Date, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Ghi lý do mở khóa.") }
        try changePayroll("Mở khóa lương: " + reason) { book in
            guard let closed = book.closed(month) else { throw DeliveryError.invalid("Tháng chưa khóa.") }
            book.reopenedIDs.append(closed.id)
        }
    }
}
