import XCTest
import Foundation
@testable import SweepCore

final class DeliveryWorkflowRegressionTests: XCTestCase {
    func testEveryReconciliationFigureUsesTheSelectedMonth() throws {
        var ledger = DeliveryLedger()
        let october = date("2026-10-12T03:00:00Z"), november = date("2026-11-12T03:00:00Z")
        let old = try ledger.insert(order("OCT")), current = try ledger.insert(order("NOV"))
        try ledger.sign(old, at: october); try ledger.sign(current, at: november)
        try ledger.settle(old, value: settlement(.mixed, cash: 600_000, bank: 1_500_000, at: october))
        try ledger.settle(current, value: settlement(.mixed, cash: 665_000, bank: 1_500_000, at: november))
        try ledger.handover(400_000, at: october, note: "Nộp tháng 10")
        try ledger.handover(500_000, at: november, note: "Nộp tháng 11")
        try ledger.verifyBank(old, note: "Kế toán đã nhận")
        let before = ledger
        let oct = MonthlyReconciliation(ledger: ledger, month: october)
        XCTAssertEqual(oct.count, 1); XCTAssertEqual(oct.fee, 5_000)
        XCTAssertEqual(oct.cashCollected, 600_000); XCTAssertEqual(oct.cashHanded, 400_000)
        XCTAssertEqual(oct.cashDifference, 200_000); XCTAssertEqual(oct.bankPending, 0)
        let nov = MonthlyReconciliation(ledger: ledger, month: november)
        XCTAssertEqual(nov.count, 1); XCTAssertEqual(nov.fee, 5_000)
        XCTAssertEqual(nov.cashCollected, 665_000); XCTAssertEqual(nov.cashHanded, 500_000)
        XCTAssertEqual(nov.cashDifference, 165_000); XCTAssertEqual(nov.bankPending, 1_500_000)
        XCTAssertEqual(nov.pendingOrders.map(\.id), [current])
        let empty = MonthlyReconciliation(ledger: ledger, month: date("2026-09-12T03:00:00Z"))
        XCTAssertEqual(empty.count, 0); XCTAssertEqual(empty.fee, 0)
        XCTAssertEqual(empty.cashCollected, 0); XCTAssertEqual(empty.cashHanded, 0)
        XCTAssertEqual(empty.cashDifference, 0); XCTAssertEqual(empty.bankPending, 0)
        XCTAssertTrue(empty.orders.isEmpty); XCTAssertTrue(empty.handovers.isEmpty)
        XCTAssertEqual(ledger, before); XCTAssertEqual(ledger.cashHeld, 365_000)
    }

    func testCrossMonthRemittanceAndReversalKeepTheCashLedgerIntact() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(order("CASH"))
        try ledger.settle(id, value: settlement(.cash, cash: 2_165_000, bank: 0, at: date("2026-10-31T03:00:00Z")))
        let november = date("2026-11-01T03:00:00Z")
        try ledger.handover(1_000_000, at: november, note: "Nộp tiền đã thu tháng trước")
        XCTAssertEqual(MonthlyReconciliation(ledger: ledger, month: november).cashDifference, -1_000_000)
        XCTAssertEqual(ledger.cashHeld, 1_165_000)
        try ledger.reverseHandover(ledger.handovers[0].id, reason: "Ghi nhầm")
        let summary = MonthlyReconciliation(ledger: ledger, month: november)
        XCTAssertEqual(summary.cashHanded, 0); XCTAssertEqual(summary.handovers.count, 1)
        XCTAssertEqual(ledger.cashHeld, 2_165_000)
        XCTAssertThrowsError(try ledger.handover(2_166_000, at: november, note: "Vượt số đang giữ"))
        try ledger.validate()
    }

    func testVietnamMonthBoundaryAndAutomaticRolloverPreserveHistorySelection() {
        let before = date("2026-10-31T16:59:59Z"), after = date("2026-10-31T17:00:00Z")
        let historical = date("2026-09-12T03:00:00Z")
        XCTAssertTrue(DeliveryMonth.contains(before, in: before))
        XCTAssertFalse(DeliveryMonth.contains(after, in: before))
        XCTAssertEqual(DeliveryMonth.calendar.component(.month, from: DeliveryMonth.start(after)), 11)
        XCTAssertEqual(DeliveryMonth.rollover(selected: historical, observed: before, now: before), historical)
        XCTAssertEqual(DeliveryMonth.rollover(selected: historical, observed: before, now: after), DeliveryMonth.start(after))
        XCTAssertEqual(DeliveryMonth.rollover(selected: after, observed: after, now: after), after)
    }

    func testTwoChosenReportImagesDoNotRemoveTheThirdOriginalOrChangeMoney() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(order("SEND"))
        try ledger.sign(id, at: Date())
        try ledger.settle(id, value: settlement(.mixed, cash: 665_000, bank: 1_500_000, at: Date()))
        let saved = ledger.orders[0], chosen = saved.defaultShareEvidenceIDs
        XCTAssertEqual(chosen, saved.orderedEvidence.filter { $0.role != .signature }.map(\.id))
        let two = try ledger.prepareReport(id, text: saved.shareText(), evidenceIDs: chosen)
        XCTAssertEqual(two.evidenceIDs.count, 2); XCTAssertEqual(ledger.orders[0].evidence.count, 3)
        XCTAssertTrue(ledger.orders[0].exclusions.isEmpty)
        let one = try ledger.prepareReport(id, text: saved.shareText(), evidenceIDs: [chosen[0]])
        XCTAssertEqual(one.evidenceIDs.count, 1)
        let restored = try ledger.prepareReport(id, text: saved.shareText(), evidenceIDs: chosen)
        XCTAssertEqual(restored.evidenceIDs, two.evidenceIDs)
        XCTAssertEqual(ledger.orders[0].settlements, saved.settlements)
        XCTAssertEqual(ledger.orders[0].assignments, saved.assignments)
        XCTAssertFalse(ledger.orders[0].reportSent)
        XCTAssertThrowsError(try ledger.prepareReport(id, text: "Sai", evidenceIDs: [chosen[0], chosen[0]]))
        XCTAssertThrowsError(try ledger.prepareReport(id, text: "Sai", evidenceIDs: [UUID()]))
        try ledger.validate()
    }

    func testExplicitPhotoSelectionCanSendTransferWithoutSignedCustomerSlip() throws {
        var ledger = DeliveryLedger(); var invoice = order("NO-SIGNATURE")
        invoice.evidence.removeAll { $0.role == .signature }
        let id = try ledger.insert(invoice)
        try ledger.settle(id, value: settlement(.mixed, cash: 665_000, bank: 1_500_000, at: Date()))
        XCTAssertThrowsError(try ledger.prepareReport(id, text: "Legacy validation"))
        let report = try ledger.prepareReport(id, text: ledger.orders[0].shareText(), evidenceIDs: ledger.orders[0].defaultShareEvidenceIDs)
        XCTAssertEqual(report.evidenceIDs.count, 2)
        XCTAssertTrue(ledger.orders[0].exclusions.isEmpty)
    }

    func testCompactCaptionUsesActualTransferAmountAndDoesNotInventPayment() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(order("CAPTION"))
        try ledger.settle(id, value: settlement(.mixed, cash: 665_000, bank: 1_500_000, at: Date()))
        XCTAssertEqual(ledger.orders[0].shareText(), "Khách thử đã chuyển khoản 1.500.000₫")
        try ledger.settle(id, value: settlement(.cash, cash: 2_165_000, bank: 0, at: Date()))
        XCTAssertEqual(ledger.orders[0].shareText(), "Khách thử đã thanh toán tiền mặt 2.165.000₫")
        try ledger.settle(id, value: settlement(.deferred, cash: 0, bank: 0, at: Date()))
        XCTAssertEqual(ledger.orders[0].shareText(), "Khách thử · Chuyển khoản sau · 2.165.000₫")
    }

    func testBlankDeliveryNoteDoesNotConsumeTableHeadersOrItemPhoneNumbers() {
        let fields = InvoiceParser.parse("Số: 3876\nNV bán hàng: TEL\nĐơn vị: BÁNH THỬ\nĐiện thoại: 0900000000\nĐịa chỉ giao hàng:\nMã hàng Thành\nTên hàng hóa Số lượng Thành tiền\nĐiện thoại: 0999999999\nTiền hàng 2.573.000")
        XCTAssertEqual(fields.phone, "0900000000"); XCTAssertEqual(fields.customer, "BÁNH THỬ")
        XCTAssertEqual(fields.total, 2_573_000); XCTAssertTrue(fields.deliveryNote.isEmpty)
        XCTAssertEqual(InvoiceParser.cleanStoredNote("Giao hàng: Mã hàng Thành"), "")
        XCTAssertEqual(InvoiceParser.cleanStoredNote("Điện thoại trên phiếu cần xác minh người nhận: 0900000000\nGiao hàng: Trước 10h sáng"), "Trước 10h sáng")
        XCTAssertEqual(InvoiceParser.cleanStoredNote("Mã hàng ABC cần giao trước 10h"), "Mã hàng ABC cần giao trước 10h")
    }

    func testGoogleMapsDirectionsKeepTheDestinationAndUseDrivingNavigation() throws {
        let address = "  12 Đường Mẫu + Cổng B, TP.HCM  "
        let native = try XCTUnwrap(DeliveryDirections.googleMaps(address: address))
        XCTAssertEqual(native.scheme, "comgooglemaps")
        let items = try XCTUnwrap(URLComponents(url: native, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "daddr" }?.value, address.trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(items.first { $0.name == "directionsmode" }?.value, "driving")
        XCTAssertTrue(native.absoluteString.contains("%2B"))
        let web = try XCTUnwrap(DeliveryDirections.googleMaps(address: address, native: false))
        XCTAssertEqual(web.host, "www.google.com")
        XCTAssertTrue(web.absoluteString.hasPrefix("https://www.google.com/maps/dir/?"))
        XCTAssertEqual(URLComponents(url: web, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "destination" }?.value, address.trimmingCharacters(in: .whitespaces))
        XCTAssertNil(DeliveryDirections.googleMaps(address: " \n"))
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func order(_ code: String) -> DeliveryOrder {
        var value = DeliveryOrder(code: code, customer: "Khách thử", total: 2_165_000)
        value.evidence = [EvidenceRole.invoice, .signature, .transfer].map {
            DeliveryEvidence(role: $0, filename: UUID().uuidString + ".png", sha256: String(repeating: "a", count: 64), bytes: 100)
        }
        return value
    }
    private func settlement(_ mode: PaymentMode, cash: Int64, bank: Int64, at: Date) -> Settlement {
        Settlement(outcome: .delivered, mode: mode, cash: cash, bank: bank, note: "", at: at)
    }
}
