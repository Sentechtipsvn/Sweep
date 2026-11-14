import XCTest
@testable import SweepCore

final class ReleaseReadinessTests: XCTestCase {
    func testImageOnlyDraftRestoresAfterUnrelatedEditAndRoundTrip() throws {
        var ledger = try transferredOrder()
        let order = ledger.orders[0], selected = [order.evidence[0].id]
        try ledger.saveReportDraft(order.id, text: order.shareText(), evidenceIDs: selected)
        ledger.orders[0].address = "Địa chỉ cập nhật"; ledger.orders[0].revision += 1
        let restored = try DeliveryCoding.decode(DeliveryLedger.self, from: DeliveryCoding.encode(ledger))
        XCTAssertEqual(restored.orders[0].reportComposition.text, order.shareText())
        XCTAssertEqual(restored.orders[0].reportComposition.evidenceIDs, selected)
        XCTAssertThrowsError(try ledger.prepareReport(order.id, text: order.shareText(), evidenceIDs: selected))
    }

    func testReopeningSentReportDoesNotCreateAnUnsentCopy() throws {
        var ledger = try transferredOrder(); let id = ledger.orders[0].id
        let composition = ledger.orders[0].reportComposition
        try ledger.saveReportDraft(id, text: composition.text, evidenceIDs: composition.evidenceIDs)
        let report = try ledger.prepareReport(id, text: composition.text, evidenceIDs: composition.evidenceIDs)
        try ledger.acknowledgeReport(id, reportID: report.id)
        ledger.orders[0].phone = "0901234567"; ledger.orders[0].revision += 1
        let reopened = ledger.orders[0].reportComposition
        try ledger.saveReportDraft(id, text: reopened.text, evidenceIDs: reopened.evidenceIDs)
        XCTAssertTrue(ledger.orders[0].reportSent)
        let repeated = try ledger.prepareReport(id, text: reopened.text, evidenceIDs: reopened.evidenceIDs)
        XCTAssertEqual(repeated.id, report.id); XCTAssertEqual(ledger.orders[0].reports.count, 1)
    }

    func testChangedDraftCannotAcknowledgeOldSharedContent() throws {
        var ledger = try transferredOrder(); let id = ledger.orders[0].id
        let original = ledger.orders[0].reportComposition
        let report = try ledger.prepareReport(id, text: original.text, evidenceIDs: original.evidenceIDs)
        try ledger.saveReportDraft(id, text: "Khách đã chuyển, gửi lại bằng chứng", evidenceIDs: original.evidenceIDs)
        XCTAssertThrowsError(try ledger.acknowledgeReport(id, reportID: report.id))
        XCTAssertFalse(ledger.orders[0].reportSent)
        let updated = try ledger.prepareReport(id, text: ledger.orders[0].reportComposition.text, evidenceIDs: original.evidenceIDs)
        try ledger.acknowledgeReport(id, reportID: updated.id)
        XCTAssertTrue(ledger.orders[0].reportSent)
    }

    func testFinancialChangeDoesNotResurrectAnOldCaption() throws {
        var ledger = try transferredOrder(); let id = ledger.orders[0].id
        try ledger.saveReportDraft(id, text: "Đã thu đủ", evidenceIDs: ledger.orders[0].defaultShareEvidenceIDs)
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 700, note: "Sửa khoản thực nhận", at: Date(), route: .transferNow))
        XCTAssertNil(ledger.orders[0].currentReportDraft)
        XCTAssertTrue(ledger.orders[0].reportComposition.text.contains("700"))
        XCTAssertTrue(ledger.orders[0].reportComposition.text.contains("300"))
    }

    func testDifferentCustomersAtSameAddressAreNotMergedAndPhoneFormatsMatch() throws {
        var ledger = DeliveryLedger()
        let first = DeliveryPlace(customer: "Tiệm Mẫu", phone: "0901234567", address: "12A", kind: "Khách hàng")
        var second = first; second.id = UUID(); second.phone = "0907654321"
        try ledger.savePlace(first); try ledger.savePlace(second)
        XCTAssertEqual(ledger.places?.count, 2)
        var equivalent = first; equivalent.id = UUID(); equivalent.phone = "+84 901 234 567"
        try ledger.savePlace(equivalent)
        XCTAssertEqual(ledger.places?.count, 2)
    }

    func testFreightLocationIsLinkedSeparatelyFromInvoiceCustomer() throws {
        var ledger = try transferredOrder(); let id = ledger.orders[0].id
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .deferred, cash: 0, bank: 0, note: "Giao chành", at: Date(), route: .freight))
        let carrier = DeliveryPlace(customer: "Nhà xe Mẫu", phone: "0901234567", address: "Bến xe", kind: "Chành xe", latitude: 10.7, longitude: 106.7)
        try ledger.savePlace(carrier)
        XCTAssertFalse(ledger.hasPlace(for: ledger.orders[0]))
        ledger.orders[0].freightPlaceID = carrier.id
        XCTAssertTrue(ledger.hasPlace(for: ledger.orders[0]))
        XCTAssertEqual(ledger.orders[0].customer, "Khách Mẫu")
        XCTAssertNotEqual(ledger.orders[0].address, carrier.address)
    }

    private func transferredOrder() throws -> DeliveryLedger {
        var ledger = DeliveryLedger()
        var order = DeliveryOrder(code: UUID().uuidString, customer: "Khách Mẫu", total: 1000)
        order.evidence = [file(.invoice), file(.transfer)]
        let id = try ledger.insert(order); try ledger.sign(id, at: Date())
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 1000, note: "", at: Date(), route: .transferNow))
        return ledger
    }
    private func file(_ role: EvidenceRole) -> DeliveryEvidence {
        DeliveryEvidence(role: role, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 100)
    }
}
