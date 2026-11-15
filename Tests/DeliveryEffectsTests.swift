import XCTest
@testable import SweepCore

final class DeliveryEffectsTests: XCTestCase {
    func testAllDeliveryRoutesCelebrateOnlyTheirActualCompletion() throws {
        for route in [DeliveryRoute.cashFull, .transferNow, .transferLater, .freight] {
            var ledger = DeliveryLedger()
            var order = DeliveryOrder(code: "EFFECTS", customer: "Khách kiểm thử", total: 1000)
            order.evidence = [file(.invoice)]
            let id = try ledger.insert(order); try ledger.sign(id, at: Date())
            let before = ledger
            try ledger.settle(id, value: Settlement(outcome: .delivered, mode: route == .cashFull ? .cash : route == .transferNow ? .bank : .deferred,
                cash: route == .cashFull ? 1000 : 0, bank: route == .transferNow ? 1000 : 0, note: "", at: Date(), route: route))
            let saved = try XCTUnwrap(DeliveryFeedbackPolicy.notice(before: before, after: ledger))
            if route == .cashFull { XCTAssertEqual(saved.completedOrderIDs, [id]); continue }
            XCTAssertTrue(saved.completedOrderIDs.isEmpty)
            for role in ledger.orders[0].requiredReportRoles where role != .invoice { ledger.orders[0].evidence.append(file(role)) }
            let beforePreparation = ledger
            let report = try ledger.prepareReport(id, text: ledger.orders[0].shareText())
            XCTAssertNil(DeliveryFeedbackPolicy.notice(before: beforePreparation, after: ledger))
            let beforeAcknowledgement = ledger
            try ledger.acknowledgeReport(id, reportID: report.id)
            let completed = try XCTUnwrap(DeliveryFeedbackPolicy.notice(before: beforeAcknowledgement, after: ledger))
            XCTAssertEqual(completed.completedOrderIDs, [id])
            XCTAssertTrue(completed.text.hasPrefix("Hoàn tất giao hàng"))
            XCTAssertEqual(ledger.cashCollected, 0)
            if route == .transferLater || route == .freight { XCTAssertEqual(ledger.orders[0].remaining, 1000) }
        }
    }
    func testNoOpLoadingAndBackgroundDraftNeverProduceFalseSuccess() throws {
        var ledger = DeliveryLedger()
        XCTAssertNil(DeliveryFeedbackPolicy.notice(before: ledger, after: ledger, text: "Đã lưu"))
        let before = ledger; ledger.record("Lưu nội dung báo cáo nháp", "Bản nháp nền")
        XCTAssertNil(DeliveryFeedbackPolicy.notice(before: before, after: ledger))
        XCTAssertEqual(DeliveryFeedbackPolicy.notice(before: before, after: ledger, text: "Đã lưu bản nháp")?.text, "Đã lưu bản nháp")
    }
    func testAttendanceAndContactsHaveSpecificSuccessWithoutCelebrating() throws {
        var ledger = DeliveryLedger(); var before = ledger
        try ledger.markAttendance(Date(), state: .work)
        XCTAssertEqual(DeliveryFeedbackPolicy.notice(before: before, after: ledger)?.text, "Đã lưu chấm công")
        before = ledger
        try ledger.saveContact(DeliveryContact(name: "Liên hệ thử", phone: "0900000000", zalo: "", aliases: "", role: "Khác"))
        let notice = try XCTUnwrap(DeliveryFeedbackPolicy.notice(before: before, after: ledger))
        XCTAssertEqual(notice.text, "Đã lưu liên hệ"); XCTAssertTrue(notice.completedOrderIDs.isEmpty)
    }
    func testCelebrationHistorySurvivesRelaunchAndNeverChangesBusinessLedger() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("effects.json"), id = UUID()
        XCTAssertEqual(DeliveryCelebrationHistory(file: url).claim([id]), [id])
        XCTAssertTrue(DeliveryCelebrationHistory(file: url).claim([id]).isEmpty)
        var ledger = DeliveryLedger(); var order = DeliveryOrder(code: "OLD", customer: "Đơn cũ", total: 1000)
        order.settlements = [Settlement(outcome: .delivered, mode: .cash, cash: 1000, bank: 0, note: "", at: Date(), route: .cashFull)]
        ledger.orders = [order]
        let original = ledger
        let history = DeliveryCelebrationHistory(file: url); history.seed(ledger)
        XCTAssertTrue(DeliveryCelebrationHistory(file: url).claim([order.id]).isEmpty)
        XCTAssertEqual(ledger, original)
    }
    func testHistoryWriteFailureSuppressesConfetti() {
        let unavailable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("no-parent/effects.json")
        XCTAssertTrue(DeliveryCelebrationHistory(file: unavailable).claim([UUID()]).isEmpty)
    }
    private func file(_ role: EvidenceRole) -> DeliveryEvidence {
        DeliveryEvidence(role: role, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 100)
    }
}
