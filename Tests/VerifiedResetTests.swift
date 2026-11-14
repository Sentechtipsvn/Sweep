import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

final class VerifiedResetTests: XCTestCase {
    func testOnlyVerifiedMatchingBackupCanResetLedgerAndRestoreIt() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let image = root.appendingPathComponent("source.png")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let out = try XCTUnwrap(CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(out, try XCTUnwrap(ctx.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(out))
        var order = DeliveryOrder(code: "RESET", customer: "Khách", total: 1000)
        order.evidence = [try EvidenceFiles.importImage(image, role: .invoice, directory: root)]
        var ledger = DeliveryLedger(); let id = try ledger.insert(order); try ledger.sign(id, at: Date())
        try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .cash, cash: 1000, bank: 0, note: "", at: Date(), route: .cashFull))
        let db = try DeliveryDatabase(url: root.appendingPathComponent("test.sqlite")); try db.save(ledger)
        let backup = root.appendingPathComponent("test.sweepbackup")
        try DeliveryBackup.write(ledger, evidence: root, to: backup)
        let verified = try DeliveryBackup.prepare(backup, staging: root.appendingPathComponent("verified"))
        var updated = ledger; try updated.handover(100, at: Date(), note: "Nộp")
        try db.save(updated)
        XCTAssertThrowsError(try db.reset(using: verified)); XCTAssertEqual(try db.load(), updated)
        try db.save(ledger, replacing: true)
        try db.reset(using: verified)
        XCTAssertEqual(try db.load(), DeliveryLedger())
        XCTAssertEqual(verified.ledger.cashHeld, 1000)
        try db.save(verified.ledger, replacing: true); XCTAssertEqual(try db.load(), ledger)
        try EvidenceFiles.verify(order.evidence[0], directory: verified.staging)
    }
}
