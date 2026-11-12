import XCTest
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

final class DeliveryTests: XCTestCase {
    func testMoneyRejectsNegativeDecimalsCurrencyAndOverflow() throws {
        XCTAssertEqual(try VND.parse("2.165.000"), 2_165_000)
        XCTAssertEqual(try VND.parse("2165000"), 2_165_000)
        XCTAssertEqual(try VND.parse("0"), 0)
        for invalid in ["-5000", "1,5", "1.5", "5.000₫", "1e6", "999999999999999999999999", "1000000000001", "", "00", "2 165 000"] {
            XCTAssertThrowsError(try VND.parse(invalid), invalid)
        }
    }
    func testDuplicatePackageAndPhysicalCodeNeverCreateExtraAssignment() throws {
        var ledger = DeliveryLedger()
        var order = invoiceOrder(); order.sourceID = "bill:source"
        let id = try ledger.insert(order)
        try ledger.sign(id, at: Date()); try ledger.sign(id, at: Date())
        var repeated = invoiceOrder(code: "RENAMED"); repeated.sourceID = "bill:source"
        XCTAssertEqual(try ledger.insert(repeated), id)
        XCTAssertEqual(try ledger.insert(invoiceOrder(code: " test-001 ")), id)
        XCTAssertEqual(ledger.orders.count, 1); XCTAssertEqual(ledger.orders[0].assignments.count, 1)
        XCTAssertEqual(ledger.orders[0].activeAssignments.first?.fee, 5_000)
        _ = try ledger.insert(invoiceOrder(code: "TEST-002")) // Same customer is not a duplicate.
        XCTAssertEqual(ledger.orders.count, 2)
    }
    func testUnsignedDraftAndMissingInvoiceDoNotAccrueCommission() throws {
        var ledger = DeliveryLedger(); var draft = invoiceOrder(); draft.evidence = []
        let id = try ledger.insert(draft)
        XCTAssertThrowsError(try ledger.sign(id, at: Date()))
        XCTAssertTrue(ledger.commissions(in: Date()).isEmpty)
        XCTAssertThrowsError(try ledger.sign(id, at: Date().addingTimeInterval(86400)))
    }
    func testCommissionUsesSignedMonthAndKeepsRateAndFailure() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        let signed = try XCTUnwrap(BillImport.date("2026-10-31T23:50:00Z"))
        try ledger.sign(id, at: signed)
        ledger.settings.fee = 8_000
        try ledger.settle(id, value: payment(.deferred, cash: 0, bank: 0, outcome: .failed, note: "Khách hẹn lại"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let nextMonth = try XCTUnwrap(BillImport.date("2026-11-01T01:00:00Z"))
        XCTAssertEqual(ledger.commissions(in: signed, calendar: calendar).count, 1)
        XCTAssertTrue(ledger.commissions(in: nextMonth, calendar: calendar).isEmpty)
        XCTAssertEqual(ledger.orders[0].activeAssignments[0].fee, 5_000)
        XCTAssertEqual(ledger.orders[0].cash, 0)
    }
    func testMixedPaymentFullPartialOverpaymentAndIndependentBankVerification() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        try ledger.sign(id, at: Date())
        try ledger.settle(id, value: payment(.mixed, cash: 665_000, bank: 1_500_000))
        XCTAssertEqual(ledger.orders[0].remaining, 0); XCTAssertEqual(ledger.bankPending, 1_500_000)
        try ledger.verifyBank(id, note: "Kế toán xác nhận giao dịch")
        XCTAssertEqual(ledger.bankPending, 0)
        try ledger.settle(id, value: payment(.mixed, cash: 600_000, bank: 1_500_000))
        XCTAssertEqual(ledger.orders[0].remaining, 65_000)
        XCTAssertEqual(ledger.bankPending, 1_500_000) // A new settlement needs a fresh check.
        let before = ledger
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.mixed, cash: 700_000, bank: 1_500_000)))
        XCTAssertEqual(ledger, before)
        XCTAssertEqual(ledger.orders[0].assignments.count, 1)
    }
    func testModesDoNotEraseReceivedMoneyOrAcceptContradictions() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.deferred, cash: 10, bank: 0)))
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.cash, cash: 10, bank: 20)))
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.bank, cash: 10, bank: 20)))
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.none, cash: -1, bank: 0)))
        try ledger.settle(id, value: payment(.cash, cash: 100_000, bank: 0, outcome: .failed, note: "Đã thu một phần trước khi hẹn lại"))
        XCTAssertEqual(ledger.cashCollected, 100_000)
    }
    func testCashHandoverNeverDeductsCommissionAndBlocksImpossibleCorrection() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        try ledger.sign(id, at: Date())
        try ledger.settle(id, value: payment(.cash, cash: 2_165_000, bank: 0))
        XCTAssertEqual(ledger.cashHeld, 2_165_000)
        try ledger.handover(2_000_000, at: Date(), note: "Đã nộp chị kế toán")
        XCTAssertEqual(ledger.cashHeld, 165_000)
        XCTAssertThrowsError(try ledger.handover(170_000, at: Date(), note: "Sai số"))
        XCTAssertThrowsError(try ledger.settle(id, value: payment(.cash, cash: 1_000_000, bank: 0)))
        XCTAssertEqual(ledger.orders[0].activeAssignments[0].fee, 5_000)
        let handoverID = ledger.handovers[0].id
        try ledger.reverseHandover(handoverID, reason: "Ghi nhầm số tiền")
        try ledger.reverseHandover(handoverID, reason: "Bấm lại")
        XCTAssertEqual(ledger.cashHeld, 2_165_000); XCTAssertEqual(ledger.handovers.count, 1)
        XCTAssertEqual(ledger.handoverReversals.count, 1)
        try ledger.validate()
    }
    func testReportRequiresCorrectEvidenceAndExplicitAcknowledgement() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        try ledger.sign(id, at: Date())
        try ledger.settle(id, value: payment(.mixed, cash: 665_000, bank: 1_500_000))
        XCTAssertThrowsError(try ledger.prepareReport(id, text: "Nội dung"))
        ledger.orders[0].evidence += [file(.signature), file(.transfer)]
        let text = ledger.orders[0].reportText()
        XCTAssertTrue(text.contains("1.500.000")); XCTAssertTrue(text.contains("Phiếu khách ký"))
        let report = try ledger.prepareReport(id, text: text)
        let repeated = try ledger.prepareReport(id, text: text)
        XCTAssertEqual(report.id, repeated.id)
        XCTAssertFalse(ledger.orders[0].reportSent) // Opening/dismissing a share sheet does not mutate the ledger.
        XCTAssertEqual(ledger.orders[0].cash, 665_000)
        try ledger.acknowledgeReport(id, reportID: report.id)
        XCTAssertTrue(ledger.orders[0].reportSent)
        try ledger.settle(id, value: payment(.mixed, cash: 600_000, bank: 1_500_000))
        XCTAssertFalse(ledger.orders[0].reportSent)
        XCTAssertThrowsError(try ledger.acknowledgeReport(id, reportID: report.id))
        XCTAssertEqual(ledger.orders[0].activeAssignments.count, 1)
        XCTAssertEqual(ledger.orders[0].reports[0].evidenceIDs, ledger.orders[0].evidence.map(\.id))
    }
    func testDeferredPaymentRequiresSignatureButDoesNotInventBankMoney() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        try ledger.settle(id, value: payment(.deferred, cash: 0, bank: 0))
        XCTAssertEqual(ledger.orders[0].missingEvidence(), [.signature])
        XCTAssertEqual(ledger.bankPending, 0); XCTAssertEqual(ledger.orders[0].remaining, 2_165_000)
        XCTAssertFalse(ledger.orders[0].reportText().contains("Ảnh giao dịch"))
    }
    func testVoidPreservesCommissionAndMoneyAuditInsteadOfDeleting() throws {
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder())
        try ledger.sign(id, at: Date()); try ledger.void(id, reason: "Nhập nhầm phiếu")
        XCTAssertEqual(ledger.orders.count, 1); XCTAssertEqual(ledger.orders[0].assignments.count, 1)
        XCTAssertEqual(ledger.orders[0].reversals.count, 1); XCTAssertTrue(ledger.orders[0].activeAssignments.isEmpty)
        XCTAssertThrowsError(try ledger.sign(id, at: Date()))
        XCTAssertTrue(ledger.audit.contains { $0.action == "Hủy và điều chỉnh công" })
        try ledger.validate()
    }
    func testCSVIncludesEverySignedSlipAndEscapesSpreadsheetFormulas() throws {
        var ledger = DeliveryLedger()
        for index in 0..<35 {
            var order = invoiceOrder(code: "T-\(index)"); order.customer = "=HYPERLINK(\"bad\")"
            let id = try ledger.insert(order); try ledger.sign(id, at: Date())
        }
        let csv = ledger.csv(in: Date())
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 36)
        XCTAssertTrue(csv.contains("'=HYPERLINK")); XCTAssertEqual(ledger.commissions(in: Date()).count, 35)
    }
    func testDatabaseReopensFullHistoryAndRejectsInvalidSaveAtomically() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let db = try DeliveryDatabase(url: root.appendingPathComponent("test.sqlite"))
        var ledger = DeliveryLedger(); let id = try ledger.insert(invoiceOrder()); try ledger.sign(id, at: Date())
        try db.save(ledger)
        var invalid = ledger; invalid.orders[0].total = -1
        XCTAssertThrowsError(try db.save(invalid)); XCTAssertEqual(try db.load(), ledger)
        let reopened = try DeliveryDatabase(url: root.appendingPathComponent("test.sqlite"))
        XCTAssertEqual(try reopened.load(), ledger)
        var erased = ledger; erased.orders[0].assignments.removeAll()
        XCTAssertThrowsError(try db.save(erased))
        erased = ledger; erased.audit.removeAll()
        XCTAssertThrowsError(try db.save(erased))
        XCTAssertEqual(try db.load(), ledger)
        let broken = root.appendingPathComponent("broken.sqlite"); try Data("not a db".utf8).write(to: broken)
        XCTAssertThrowsError(try DeliveryDatabase(url: broken))
        XCTAssertEqual(try Data(contentsOf: broken), Data("not a db".utf8))
    }
    func testDurableEvidenceAndStreamingBackupRoundTripRejectCorruptionAndMissingPhotos() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let images = root.appendingPathComponent("images"); try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let source = try makePNG(in: root)
        let imported = try EvidenceFiles.importImage(source, role: .invoice, directory: images)
        try FileManager.default.removeItem(at: source) // Photos/iCloud source disappears after successful import.
        try EvidenceFiles.verify(imported, directory: images)
        var ledger = DeliveryLedger(); var order = invoiceOrder(); order.evidence = [imported]
        let id = try ledger.insert(order); try ledger.sign(id, at: Date())
        let archive = root.appendingPathComponent("full.sweepbackup")
        try DeliveryBackup.write(ledger, evidence: images, to: archive)
        let prepared = try DeliveryBackup.prepare(archive, staging: root.appendingPathComponent("restore"))
        XCTAssertEqual(prepared.ledger, ledger); try EvidenceFiles.verify(imported, directory: prepared.staging)
        var bytes = try Data(contentsOf: archive); bytes[bytes.count - 1] ^= 0xFF
        let corrupt = root.appendingPathComponent("corrupt.sweepbackup"); try bytes.write(to: corrupt)
        XCTAssertThrowsError(try DeliveryBackup.prepare(corrupt, staging: root.appendingPathComponent("bad")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad").path))
        try Data(bytes.prefix(30)).write(to: corrupt)
        XCTAssertThrowsError(try DeliveryBackup.prepare(corrupt, staging: root.appendingPathComponent("short")))
        try FileManager.default.removeItem(at: images.appendingPathComponent(imported.filename))
        XCTAssertThrowsError(try DeliveryBackup.write(ledger, evidence: images, to: root.appendingPathComponent("missing.sweepbackup")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.sweepbackup").path))
    }
    func testBill320SchemaAndLegacyCashAreReadWithoutInferringSignedDate() throws {
        let imageKey = "20261112-123400000-123456"
        let id = SHA256.hash(data: Data("sen-bill-v1:\(imageKey)".utf8)).map { String(format: "%02x", $0) }.joined()
        let filename = "Khách - 2.165.000 · \(imageKey).png"
        let bill: [String: Any] = ["schema": "sen-bill-v1", "version": "3.2.0", "id": id, "filename": filename, "imageKey": imageKey,
                                  "name": "Khách", "total": "2165000", "createdAt": "2026-11-12T12:34:00+07:00", "createdMonth": "2026-11"]
        let images = URL(fileURLWithPath: "/test-images")
        let records = try BillImport.decode(JSONSerialization.data(withJSONObject: bill), images: images)
        XCTAssertEqual(records[0].id, "bill:\(id)"); XCTAssertEqual(records[0].total, 2_165_000)
        XCTAssertFalse(records[0].isLegacy)
        let old: [String: Any] = ["id": id, "filename": filename, "name": "Khách", "total": "2165000", "cash": "665000", "bank": "1500000", "deliveredAt": "2026-11-12T12:34:00+07:00", "cancelled": "0"]
        let encoded = String(data: try JSONSerialization.data(withJSONObject: old), encoding: .utf8)!
        let legacy: [String: Any] = ["_schema": "sen-orders-v3", id: encoded]
        let imported = try BillImport.decode(JSONSerialization.data(withJSONObject: legacy), images: images, legacy: true)[0]
        XCTAssertEqual(imported.cash, 665_000); XCTAssertEqual(imported.bank, 1_500_000)
        XCTAssertNotNil(imported.deliveredAt); XCTAssertTrue(imported.note.contains("Chưa có ngày ký nhận"))
        var invalid = bill; invalid["filename"] = "../../outside.png"
        XCTAssertThrowsError(try BillImport.decode(JSONSerialization.data(withJSONObject: invalid), images: images))
        invalid = bill; invalid["total"] = true
        XCTAssertThrowsError(try BillImport.decode(JSONSerialization.data(withJSONObject: invalid), images: images))
    }
    private func invoiceOrder(code: String = "TEST-001") -> DeliveryOrder {
        var order = DeliveryOrder(code: code, customer: "Khách thử", total: 2_165_000); order.evidence = [file(.invoice)]; return order
    }
    private func file(_ role: EvidenceRole) -> DeliveryEvidence {
        DeliveryEvidence(role: role, filename: UUID().uuidString + ".png", sha256: String(repeating: "a", count: 64), bytes: 100)
    }
    private func payment(_ mode: PaymentMode, cash: Int64, bank: Int64, outcome: DeliveryOutcome = .delivered, note: String = "") -> Settlement {
        Settlement(outcome: outcome, mode: mode, cash: cash, bank: bank, note: note, at: Date())
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func makePNG(in root: URL) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        let url = root.appendingPathComponent("source.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return url
    }
}
