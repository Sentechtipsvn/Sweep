import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

final class ShareAndQRTests: XCTestCase {
    private let account = VietQRAccount(bankID: "VCB", accountNumber: "0012345678", accountName: "CONG TY THU NGHIEM")

    func testQRContainsExactIntegerAmountAccountAndOrderCode() throws {
        let order = DeliveryOrder(code: "3877", customer: "Không gửi tên khách", total: 5_350_000)
        let url = try VietQR.url(account: account, order: order, amount: order.remaining)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "https"); XCTAssertEqual(parts.host, "img.vietqr.io")
        XCTAssertEqual(parts.path, "/image/VCB-0012345678-qr_only.svg")
        let fields = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields, ["amount": "5350000", "addInfo": "TT DON 3877", "accountName": account.accountName])
        XCTAssertFalse(url.absoluteString.contains("Không"))
    }

    func testQRUsesRemainderAndAllowsReissuingWithoutChangingPayments() throws {
        var order = DeliveryOrder(code: "DH-12", customer: "Test", total: 2_165_000)
        order.settlements = [Settlement(outcome: .delivered, mode: .mixed, cash: 600_000, bank: 1_500_000, note: "", at: Date())]
        XCTAssertEqual(order.remaining, 65_000)
        XCTAssertEqual(VietQR.suggestedAmount(for: order), 65_000)
        XCTAssertNoThrow(try VietQR.url(account: account, order: order, amount: 65_000))
        XCTAssertNoThrow(try VietQR.url(account: account, order: order, amount: order.total))
        for amount in [Int64(-1), 0, order.total + 1, VND.maximum + 1] { XCTAssertThrowsError(try VietQR.url(account: account, order: order, amount: amount)) }
        order.voidReason = "Hủy phiếu"
        XCTAssertThrowsError(try VietQR.url(account: account, order: order, amount: 1))
        order.voidReason = nil; order.settlements[0].cash = 665_000
        let before = order
        XCTAssertEqual(order.remaining, 0)
        XCTAssertEqual(VietQR.suggestedAmount(for: order), 1_500_000)
        XCTAssertNoThrow(try VietQR.url(account: account, order: order, amount: order.total))
        XCTAssertEqual(order, before)
    }

    func testFullyVerifiedOrderStillHasAnAmountForShowingItsQRAgain() throws {
        var order = DeliveryOrder(code: "DEMO", customer: "Test", total: 123_000)
        let payment = Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: 123_000, note: "", at: Date())
        order.settlements = [payment]
        order.bankChecks = [BankVerification(settlementID: payment.id, amount: payment.bank, note: "Đã kiểm tra")]
        let before = order
        XCTAssertEqual(VietQR.suggestedAmount(for: order), order.total)
        XCTAssertNoThrow(try VietQR.url(account: account, order: order, amount: order.total))
        XCTAssertEqual(order, before)
    }

    func testQRRejectsPathInjectionAndNormalizesTransferNote() throws {
        for bank in ["../VCB", "VCB?amount=1", "VCB/ABC", "", "VCB-1"] {
            XCTAssertThrowsError(try VietQRAccount(bankID: bank, accountNumber: "123", accountName: "TEST").validate())
        }
        for number in ["../123", "123&amount=1", "123 456", String(repeating: "1", count: 20)] {
            XCTAssertThrowsError(try VietQRAccount(bankID: "VCB", accountNumber: number, accountName: "TEST").validate())
        }
        XCTAssertEqual(VietQR.transferNote(code: "Đơn #38/77 & thử"), "TT DON DON 38 77 THU")
        XCTAssertLessThanOrEqual(VietQR.transferNote(code: String(repeating: "A", count: 100)).count, 50)
    }

    func testOldLedgerWithoutVietQRStillLoadsAndNewSettingsRoundTrip() throws {
        let data = try DeliveryCoding.encode(DeliveryLedger())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any]); settings.removeValue(forKey: "vietQR"); json["settings"] = settings
        let old = try DeliveryCoding.decode(DeliveryLedger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.settings.vietQR); XCTAssertEqual(old.settings.fee, 5_000)
        var next = old; next.settings.vietQR = account
        try next.validate()
        XCTAssertEqual(try DeliveryCoding.decode(DeliveryLedger.self, from: DeliveryCoding.encode(next)), next)
    }

    func testShareSurvivesRelaunchAndCopiesSourceBeforeDeletingPending() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png"); try png().write(to: source)
        let inbox = SharedInvoiceInbox(directory: root.appendingPathComponent("Inbox"))
        let queued = try inbox.add(source)
        try FileManager.default.removeItem(at: source)
        let reopened = SharedInvoiceInbox(directory: inbox.directory)
        let scan = try reopened.scan(); XCTAssertEqual(scan.items.map(\.id), [queued.id]); XCTAssertTrue(scan.warnings.isEmpty)
        let item = try XCTUnwrap(scan.items.first)
        try EvidenceFiles.verify(item.evidence, directory: item.directory)
        let evidence = root.appendingPathComponent("Evidence"); try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let file = try EvidenceFiles.importImage(item.image, role: .invoice, directory: evidence)
        var order = DeliveryOrder(code: "3877", customer: "Test", total: 5_350_000); order.sourceID = item.sourceID; order.evidence = [file]
        let db = try DeliveryDatabase(url: root.appendingPathComponent("ledger.sqlite"))
        var ledger = DeliveryLedger(); let id = try ledger.insert(order); try db.save(ledger)
        // A crash after commit but before queue cleanup cannot create a second order.
        var retry = try db.load(); XCTAssertEqual(try retry.insert(order), id); XCTAssertEqual(retry.orders.count, 1)
        try reopened.remove(item)
        XCTAssertTrue(try reopened.scan().items.isEmpty)
        try EvidenceFiles.verify(file, directory: evidence)
    }

    func testBrokenShareDoesNotHideValidImageAndRejectsNonImage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png"); try png().write(to: source)
        let inbox = SharedInvoiceInbox(directory: root.appendingPathComponent("Inbox")); let valid = try inbox.add(source)
        let bad = inbox.directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: bad.appendingPathComponent("manifest.json"))
        let scan = try inbox.scan(); XCTAssertEqual(scan.items.map(\.id), [valid.id]); XCTAssertEqual(scan.warnings.count, 1)
        try Data("not an image".utf8).write(to: source)
        XCTAssertThrowsError(try inbox.add(source))
        XCTAssertEqual(try inbox.scan().items.count, 1)
        let staging = try FileManager.default.contentsOfDirectory(atPath: inbox.directory.path).filter { $0.hasPrefix(".staging-") }
        XCTAssertTrue(staging.isEmpty)
    }

    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage()); let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
