import XCTest
@testable import SweepCore

final class SendeliWorkTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDeliveredPeriodUsesFirstDeliveryNotLaterMoneyCorrection() {
        var order = DeliveryOrder(code: "PERIOD", customer: "Khách thử", total: 1000)
        order.settlements = [Settlement(outcome: .delivered, mode: .cash, cash: 300, bank: 0, note: "", at: date("2026-11-15T03:00:00Z"), route: .transferLater),
            Settlement(outcome: .delivered, mode: .cash, cash: 500, bank: 0, note: "", at: date("2026-11-16T03:00:00Z"), route: .transferLater)]
        let monday = date("2026-11-16T03:00:00Z")
        XCTAssertFalse(DeliveryPeriod.day.contains(order, now: monday))
        XCTAssertFalse(DeliveryPeriod.week.contains(order, now: monday))
        XCTAssertTrue(DeliveryPeriod.month.contains(order, now: monday))
    }
    func testDotWindowAndSundayAndAllAttendanceStates() throws {
        var ledger = DeliveryLedger()
        XCTAssertFalse(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-16T00:59:00Z")))
        XCTAssertTrue(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-16T01:00:00Z")))
        XCTAssertTrue(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-16T09:59:00Z")))
        XCTAssertFalse(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-16T10:00:00Z")))
        XCTAssertFalse(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-15T03:00:00Z")))
        for state in AttendanceState.allCases {
            try ledger.markAttendance(date("2026-11-16T03:00:00Z"), state: state, now: date("2026-11-16T12:00:00Z"))
            XCTAssertFalse(AttendanceReminderPolicy.showDot(ledger, now: date("2026-11-16T03:00:00Z")))
        }
    }
    func testReminderDatesAreFutureAt1730AndExcludeSundayAndRecordedDays() throws {
        var ledger = DeliveryLedger(); let now = date("2026-11-16T03:00:00Z")
        try ledger.markAttendance(now, state: .leave, now: now)
        let dates = AttendanceReminderPolicy.dates(ledger, now: now)
        XCTAssertFalse(dates.isEmpty); XCTAssertLessThan(dates.count, 30)
        for value in dates {
            let c = DeliveryMonth.calendar
            XCTAssertGreaterThan(value, now); XCTAssertEqual(c.component(.hour, from: value), 17)
            XCTAssertEqual(c.component(.minute, from: value), 30); XCTAssertNotEqual(c.component(.weekday, from: value), 1)
            XCTAssertFalse(c.isDate(value, inSameDayAs: now))
        }
    }
    func testWorklistSeparatesFreightResponsibilityAndNeverMutatesMoney() {
        var ledger = DeliveryLedger()
        var freight = DeliveryOrder(code: "FREIGHT", customer: "Chành thử", total: 1000)
        freight.settlements = [Settlement(outcome: .delivered, mode: .deferred, cash: 0, bank: 0, note: "", at: Date(), route: .freight)]
        var cash = DeliveryOrder(code: "CASH", customer: "Khách thử", total: 1000)
        cash.settlements = [Settlement(outcome: .delivered, mode: .cash, cash: 1000, bank: 0, note: "", at: Date(), route: .cashFull)]
        ledger.orders = [freight, cash]; let before = ledger
        let items = DeliveryWorkItem.items(ledger, now: date("2026-11-15T03:00:00Z"))
        XCTAssertTrue(items.contains { $0.kind == .sales && !$0.actionable })
        XCTAssertFalse(items.contains { $0.kind == .payment && $0.orderID == freight.id })
        XCTAssertEqual(items.filter { $0.kind == .cash }.count, 1)
        XCTAssertFalse(items.contains { $0.kind == .attendance }); XCTAssertEqual(ledger, before)
    }
}
