import XCTest
@testable import SweepCore

final class ApprovedWorkflowTests: XCTestCase {
    func testSixRoutesEnforceEvidenceAndKeepMoneySeparate() throws {
        for (route, cash, bank, roles) in [
            (DeliveryRoute.cashFull, Int64(1000), Int64(0), [EvidenceRole]()),
            (.transferNow, 300, 700, [.invoice, .transfer]),
            (.transferLater, 300, 0, [.signature]),
            (.transferNow, 0, 1000, [.invoice, .transfer]),
            (.transferLater, 0, 0, [.signature]),
            (.freight, 0, 0, [.freightSignature, .goods])
        ] {
            var ledger = DeliveryLedger(); let id = try ledger.insert(order())
            try ledger.sign(id, at: Date()); try ledger.sign(id, at: Date())
            let mode: PaymentMode = cash > 0 && bank > 0 ? .mixed : bank > 0 ? .bank : cash > 0 ? .cash : .deferred
            try ledger.settle(id, value: Settlement(outcome: .delivered, mode: mode, cash: cash, bank: bank, note: "", at: Date(), route: route))
            XCTAssertEqual(ledger.orders[0].requiredReportRoles, roles)
            XCTAssertEqual(ledger.orders[0].activeAssignments.count, 1)
            if route == .cashFull {
                XCTAssertTrue(ledger.orders[0].taskComplete); XCTAssertFalse(ledger.orders[0].reportNeeded)
                XCTAssertThrowsError(try ledger.prepareReport(id, text: "cash"))
            } else {
                XCTAssertThrowsError(try ledger.prepareReport(id, text: "test", evidenceIDs: []))
                for role in roles where role != .invoice { ledger.orders[0].evidence.append(file(role)) }
                let wanted = ledger.orders[0].defaultShareEvidenceIDs
                let report = try ledger.prepareReport(id, text: ledger.orders[0].shareText(), evidenceIDs: wanted)
                XCTAssertFalse(ledger.orders[0].taskComplete)
                try ledger.acknowledgeReport(id, reportID: report.id)
                XCTAssertTrue(ledger.orders[0].taskComplete)
                if route == .transferLater || route == .freight { XCTAssertFalse(wanted.contains(ledger.orders[0].evidence[0].id)) }
            }
            XCTAssertEqual(ledger.cashHeld, cash); try ledger.validate()
        }
    }
    func testReportStatusSurvivesUnrelatedEditsButNotMoneyChanges() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(order()); try ledger.sign(id, at: Date())
        ledger.orders[0].evidence.append(file(.transfer))
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 1000, note: "", at: Date(), route: .transferNow))
        let report = try ledger.prepareReport(id, text: ledger.orders[0].shareText())
        try ledger.acknowledgeReport(id, reportID: report.id)
        try ledger.verifyBank(id, note: "Legacy accountant check")
        ledger.orders[0].address = "Updated address"; ledger.orders[0].revision += 1
        ledger.orders[0].evidence.append(file(.signature)); ledger.orders[0].revision += 1
        XCTAssertTrue(ledger.orders[0].reportSent)
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 900, note: "Correction", at: Date(), route: .transferNow))
        XCTAssertFalse(ledger.orders[0].reportSent)
    }
    func testNewFieldsDecodeOldBackupAndDirectoryRoundTrips() throws {
        var ledger = DeliveryLedger(); _ = try ledger.insert(order())
        let data = try DeliveryCoding.encode(ledger)
        let decoded = try DeliveryCoding.decode(DeliveryLedger.self, from: data)
        XCTAssertNil(decoded.places); XCTAssertNil(decoded.contacts); XCTAssertNil(decoded.orders[0].settlement?.route)
        try ledger.saveContact(DeliveryContact(name: "Ngọc", phone: "0900000000", zalo: "https://zalo.me/0900000000", aliases: "TEL, N", role: "Bán hàng"))
        XCTAssertTrue(ledger.contacts![0].matches("tel")); XCTAssertFalse(ledger.contacts![0].matches(""))
        let p = DeliveryPlace(customer: "Bánh A", phone: "", address: "12A", kind: "Khách hàng", latitude: 10.7, longitude: 106.7)
        try ledger.savePlace(p); try ledger.savePlace(p)
        var branch = p; branch.id = UUID(); branch.address = "12B"; try ledger.savePlace(branch)
        XCTAssertEqual(ledger.places?.count, 2)
        var invalid = p; invalid.latitude = 91; XCTAssertThrowsError(try ledger.savePlace(invalid))
        XCTAssertEqual(try DeliveryCoding.decode(DeliveryLedger.self, from: DeliveryCoding.encode(ledger)), ledger)
    }
    func testTransferNextMonthDoesNotMoveLastMonthCashReceipt() throws {
        let october = ISO8601DateFormatter().date(from: "2026-10-31T10:00:00Z")!
        let november = ISO8601DateFormatter().date(from: "2026-11-01T10:00:00Z")!
        var ledger = DeliveryLedger(); let id = try ledger.insert(order()); try ledger.sign(id, at: october)
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .cash, cash: 300, bank: 0, note: "", at: october, route: .transferLater))
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .mixed, cash: 300, bank: 700, note: "", at: november, route: .transferNow))
        XCTAssertEqual(MonthlyReconciliation(ledger: ledger, month: october).cashCollected, 300)
        XCTAssertEqual(MonthlyReconciliation(ledger: ledger, month: november).cashCollected, 0)
        XCTAssertEqual(ledger.cashHeld, 300)
    }
    private func order() -> DeliveryOrder { var o = DeliveryOrder(code: UUID().uuidString, customer: "Khách", total: 1000); o.evidence = [file(.invoice)]; return o }
    private func file(_ role: EvidenceRole) -> DeliveryEvidence { DeliveryEvidence(role: role, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 100) }
}
