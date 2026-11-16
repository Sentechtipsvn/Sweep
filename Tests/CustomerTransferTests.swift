import XCTest
@testable import SweepCore

final class CustomerTransferTests: XCTestCase {
    func testConfirmationClearsOnlyMoneyWorkAndPreservesFreightAndDeferredReports() throws {
        for route in [DeliveryRoute.freight, .transferLater] {
            var ledger = try fixture(route: route)
            let before = ledger, old = ledger.orders[0], id = old.id
            try ledger.confirmCustomerTransfer(id, settlementID: old.settlement!.id, amount: old.remaining)
            let paid = ledger.orders[0]
            XCTAssertEqual(paid.remaining, 0)
            XCTAssertEqual(paid.bank, old.total - old.cash)
            XCTAssertEqual(paid.verifiedBank, 0) // Customer confirmation is not company reconciliation.
            XCTAssertEqual(paid.settlements, old.settlements)
            XCTAssertEqual(paid.firstDeliveredAt, old.firstDeliveredAt)
            XCTAssertEqual(paid.assignments, old.assignments)
            XCTAssertEqual(paid.evidence, old.evidence)
            XCTAssertEqual(paid.reports, old.reports)
            XCTAssertEqual(paid.reportAcks, old.reportAcks)
            XCTAssertEqual(paid.reportContentKey, old.reportContentKey)
            XCTAssertTrue(paid.reportSent)
            XCTAssertEqual(ledger.cashHeld, before.cashHeld)
            XCTAssertFalse(DeliveryWorkItem.items(ledger, now: sunday).contains { $0.orderID == id })
            try ledger.validate()
            try ledger.validateAppendOnly(from: before)
            XCTAssertEqual(try DeliveryCoding.decode(DeliveryLedger.self, from: DeliveryCoding.encode(ledger)), ledger)
            let count = ledger.audit.count
            try ledger.confirmCustomerTransfer(id, settlementID: old.settlement!.id, amount: old.remaining)
            XCTAssertEqual(ledger.audit.count, count)
            try ledger.verifyBank(id, note: "Kế toán xác nhận")
            XCTAssertEqual(ledger.orders[0].verifiedBank, paid.bank)
            try ledger.validate()
        }
    }

    func testMissingReportRemainsActionableAfterPaymentConfirmation() throws {
        var ledger = try fixture(route: .freight, sendReport: false)
        let order = ledger.orders[0]
        try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining)
        let items = DeliveryWorkItem.items(ledger, now: sunday).filter { $0.orderID == order.id }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].kind, .report)
        XCTAssertFalse(ledger.orders[0].reportSent)
    }

    func testLegacyRevisionBasedSentReportStaysSent() throws {
        var ledger = try fixture(route: .freight)
        ledger.orders[0].reports[0].contentKey = nil
        let order = ledger.orders[0]
        XCTAssertTrue(order.reportSent)
        try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining)
        XCTAssertTrue(ledger.orders[0].reportSent)
    }

    func testStaleConfirmationAndUnpaidOrVoidedOrdersCannotRecordMoney() throws {
        var ledger = try fixture(route: .transferLater)
        let order = ledger.orders[0], before = ledger
        XCTAssertThrowsError(try ledger.confirmCustomerTransfer(order.id, settlementID: UUID(), amount: order.remaining))
        XCTAssertThrowsError(try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining + 1))
        XCTAssertEqual(ledger, before)
        ledger.orders[0].voidReason = "Hủy thử"
        XCTAssertThrowsError(try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining))
    }

    func testDatabaseRetainsConfirmationAndRejectsDeletingFinancialHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try DeliveryDatabase(url: root.appendingPathComponent("test.sqlite"))
        var ledger = try fixture(route: .transferLater)
        let order = ledger.orders[0]
        try database.save(ledger)
        XCTAssertNil(try database.load().orders[0].customerTransfers)
        try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining)
        try database.save(ledger)
        XCTAssertEqual(try database.load(), ledger)
        var tampered = ledger; tampered.orders[0].customerTransfers = nil
        XCTAssertThrowsError(try database.save(tampered))
        XCTAssertEqual(try database.load(), ledger)
    }

    func testLaterCorrectionUsesLatestSettlementAndCanConfirmAnIncreasedTotal() throws {
        var ledger = try fixture(route: .transferLater)
        let order = ledger.orders[0]
        try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: order.remaining)
        ledger.orders[0].total += 200
        try ledger.confirmCustomerTransfer(order.id, settlementID: order.settlement!.id, amount: 200)
        XCTAssertEqual(ledger.orders[0].remaining, 0)
        try ledger.validate()
        try ledger.settle(order.id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 500, note: "Điều chỉnh thực tế", at: Date(), route: .transferNow))
        XCTAssertEqual(ledger.orders[0].bank, 500)
        XCTAssertEqual(ledger.orders[0].remaining, 700)
        XCTAssertEqual(ledger.orders[0].customerTransfers?.count, 2)
        try ledger.validate()
    }

    private var sunday: Date { ISO8601DateFormatter().date(from: "2026-11-15T03:00:00Z")! }
    private func fixture(route: DeliveryRoute, sendReport: Bool = true) throws -> DeliveryLedger {
        var ledger = DeliveryLedger()
        var order = DeliveryOrder(code: "PAID", customer: "Khách thử", total: 1000)
        for role in [EvidenceRole.invoice, .signature, .freightSignature, .goods] {
            order.evidence.append(DeliveryEvidence(role: role, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 100))
        }
        let id = try ledger.insert(order)
        try ledger.sign(id, at: sunday)
        let cash: Int64 = route == .transferLater ? 300 : 0
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: cash > 0 ? .cash : .deferred, cash: cash, bank: 0, note: "", at: sunday, route: route))
        if sendReport {
            let report = try ledger.prepareReport(id, text: ledger.orders[0].shareText(), evidenceIDs: ledger.orders[0].defaultShareEvidenceIDs)
            try ledger.acknowledgeReport(id, reportID: report.id)
        }
        return ledger
    }
}
