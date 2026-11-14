import XCTest
@testable import SweepCore

final class PayrollTests: XCTestCase {
    func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 1) -> Date {
        PayrollDates.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func ready(_ month: Date) -> PayrollMonth {
        var p = PayrollMonth(month: DeliveryMonth.start(month))
        p.policy.weekdays = [2, 3, 4, 5, 6, 7]; p.policy.confirmed = true
        p.policy.fuelType = "RON95"; p.policy.fuelRegion = "Vùng 1"
        p.fuel = PayrollFuel(price: 27_008, effectiveDay: PayrollDates.fuelDay(month), source: "Mẫu công ty")
        p.entries = PayrollDates.days(month).map { AttendanceEntry(day: $0, state: .off) }
        return p
    }
    func testSalarySampleMatchesAndCustomerMoneyNeverBecomesSalary() throws {
        var ledger = DeliveryLedger(), p = ready(date())
        for i in 0..<24 { p.entries[i].state = .work }
        for i in 0..<92 {
            var order = DeliveryOrder(code: "PAY-\(i)", customer: "Khách", total: 1_000_000)
            order.evidence = [DeliveryEvidence(role: .invoice, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 100)]
            let id = try ledger.insert(order); try ledger.sign(id, at: date())
        }
        p.advances = [SalaryAdvance(day: date(), amount: 3_000_000, note: "Tạm ứng")]
        let result = PayrollCalculation(ledger: ledger, period: p)
        XCTAssertEqual(result.plannedUnits, 48); XCTAssertEqual(result.workUnits, 48)
        XCTAssertEqual(result.commissions, 92); XCTAssertEqual(result.fee, 460_000)
        XCTAssertEqual(result.fuel, 1_944_576); XCTAssertEqual(result.net, 6_636_576)
    }
    func testExactlyThreeDaysRetainsAttendanceAndMoreThanThreeLosesIt() {
        var p = ready(date())
        p.entries[0].state = .leave; p.entries[1].state = .leave; p.entries[2].state = .leave
        XCTAssertEqual(PayrollCalculation(ledger: DeliveryLedger(), period: p).attendance, 500_000)
        p.entries[3].state = .half
        XCTAssertEqual(PayrollCalculation(ledger: DeliveryLedger(), period: p).attendance, 0)
    }
    func testLeaveHasNoDailyAllowancesAndHalfDayIsExact() {
        var p = ready(date())
        p.entries[0].state = .work; p.entries[1].state = .leave; p.entries[2].state = .half
        let r = PayrollCalculation(ledger: DeliveryLedger(), period: p)
        XCTAssertEqual(r.workUnits, 3); XCTAssertEqual(r.leaveUnits, 3)
        XCTAssertEqual(r.meal, 45_000); XCTAssertEqual(r.maintenance, 37_500); XCTAssertEqual(r.fuel, 121_536)
    }
    func testMonthEndAndFuelDatesHandle31AndLeapFebruary() {
        XCTAssertEqual(PayrollDates.calendar.component(.day, from: PayrollDates.closeDay(date(2026, 1))), 31)
        XCTAssertEqual(PayrollDates.calendar.component(.day, from: PayrollDates.fuelDay(date(2026, 1))), 30)
        XCTAssertEqual(PayrollDates.calendar.component(.day, from: PayrollDates.closeDay(date(2028, 2))), 29)
        XCTAssertEqual(PayrollDates.calendar.component(.day, from: PayrollDates.fuelDay(date(2026, 2))), 28)
    }
    func testClosingOn30FailsFor31DayMonthAndSnapshotCannotBeOverwritten() throws {
        let month = date(2026, 1); var ledger = DeliveryLedger(); var p = ready(month)
        p.entries[0].state = .work
        try ledger.changePayroll("Cấu hình") { try $0.put(p) }
        XCTAssertThrowsError(try ledger.closePayroll(month, now: date(2026, 1, 30)))
        try ledger.closePayroll(month, now: date(2026, 1, 31))
        let frozen = try XCTUnwrap(ledger.payroll?.closed(month))
        XCTAssertThrowsError(try ledger.markAttendance(date(2026, 1, 10), state: .work))
        XCTAssertThrowsError(try ledger.reopenPayroll(month, reason: " "))
        let before = ledger
        try ledger.reopenPayroll(month, reason: "Bổ sung ngày công")
        try ledger.markAttendance(date(2026, 1, 10), state: .work)
        try ledger.validateAppendOnly(from: before)
        XCTAssertEqual(ledger.payroll?.snapshots.first, frozen)
        var invalid = ledger; invalid.payroll?.snapshots[0].calculation.base += 1
        XCTAssertThrowsError(try invalid.validateAppendOnly(from: ledger))
    }
    func testAttendanceIsIdempotentNoFutureAndNoAutomaticAbsence() throws {
        var ledger = DeliveryLedger()
        try ledger.markAttendance(date(), state: .work)
        try ledger.markAttendance(date(), state: .half)
        XCTAssertEqual(ledger.payroll?.period(date()).entries.count, 1)
        XCTAssertThrowsError(try ledger.markAttendance(date(2099), state: .work))
        var p = PayrollMonth(month: DeliveryMonth.start(date())); p.policy.weekdays = [1, 2, 3, 4, 5, 6, 7]
        let r = PayrollCalculation(ledger: ledger, period: p)
        XCTAssertEqual(r.leaveUnits, 0); XCTAssertEqual(r.missingDays, 30)
    }
    func testAnnual12DayLimitDoesNotDiscardRealLeaveAndDoesNotRollIntoNextYear() throws {
        var ledger = DeliveryLedger()
        try ledger.changePayroll("Số đầu kỳ") { $0.openingLeaveUnits["2026"] = 22 }
        try ledger.markAttendance(date(), state: .leave)
        XCTAssertEqual(ledger.payroll?.annualLeaveUnits(year: 2026), 24)
        try ledger.markAttendance(date(2026, 9, 2), state: .half)
        XCTAssertEqual(ledger.payroll?.annualLeaveUnits(year: 2026), 25)
        XCTAssertEqual(ledger.payroll?.annualLeaveUnits(year: 2027), 0)
        try ledger.validate()
    }
    func testPayrollBackupAndLegacyLedgerRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var ledger = DeliveryLedger(); try ledger.markAttendance(date(), state: .work)
        let file = root.appendingPathComponent("test.sweepbackup")
        try DeliveryBackup.write(ledger, evidence: root, to: file)
        let restored = try DeliveryBackup.prepare(file, staging: root.appendingPathComponent("check"))
        XCTAssertEqual(restored.ledger, ledger)
        var object = try JSONSerialization.jsonObject(with: DeliveryCoding.encode(DeliveryLedger())) as! [String: Any]
        object["schema"] = 2; object.removeValue(forKey: "payroll")
        let legacy = try DeliveryCoding.decode(DeliveryLedger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.payroll); try legacy.validate()
    }
    func testWrongFuelDayOrMissingWorkSchedulePreventsClose() throws {
        var p = ready(date()); p.fuel?.effectiveDay = date(2026, 9, 29)
        var b = PayrollBook(); b.months = [p]
        XCTAssertThrowsError(try b.validate())
        p = ready(date()); p.policy.confirmed = false
        var ledger = DeliveryLedger(); try ledger.changePayroll("Cấu hình") { try $0.put(p) }
        XCTAssertThrowsError(try ledger.closePayroll(date(), now: date(2026, 9, 30)))
    }
    func testRemindersAreEveryThreeHoursAndRenewalChangesTheWholeSchedule() {
        let expiry = date(), now = expiry.addingTimeInterval(-30 * 3600)
        let times = SigningExpiry.reminders(expiry: expiry, now: now)
        XCTAssertEqual(times.count, 48); XCTAssertEqual(times.first, expiry.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(times[1].timeIntervalSince(times[0]), 3 * 3600)
        XCTAssertTrue(SigningExpiry.reminders(expiry: expiry, now: expiry.addingTimeInterval(3600)).allSatisfy { $0 > expiry })
        XCTAssertNotEqual(times, SigningExpiry.reminders(expiry: expiry.addingTimeInterval(7 * 86400), now: now))
    }
    func testEmbeddedProfileReadAndUnsupportedProfilesFallBack() throws {
        let expiration = date()
        let xml = try PropertyListSerialization.data(fromPropertyList: ["CreationDate": expiration.addingTimeInterval(-86400), "ExpirationDate": expiration], format: .xml, options: 0)
        XCTAssertEqual(SigningExpiry.expiration(in: Data([0x30, 0x82]) + xml + Data([0])), expiration)
        XCTAssertNil(SigningExpiry.expiration(in: Data("broken".utf8)))
        XCTAssertNil(SigningExpiry.expiration(in: try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": "bad"], format: .xml, options: 0)))
    }
    func testContactsNormalizePhonesAndOnlyOpenZaloHosts() {
        XCTAssertEqual(ContactLinks.phoneKey("+84 903 123 456"), ContactLinks.phoneKey("0903123456"))
        XCTAssertNotNil(ContactLinks.zalo("https://zalo.me/0903123456"))
        XCTAssertNil(ContactLinks.zalo("https://zalo.me.example.com/fake"))
        XCTAssertNil(ContactLinks.zalo("https://zalo.me@evil.com/fake"))
        XCTAssertNil(ContactLinks.zalo("file:///tmp/image.png"))
    }
}
