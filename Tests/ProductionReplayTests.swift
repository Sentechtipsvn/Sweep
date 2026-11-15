import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SweepCore

/// Makes normal persisted data for testing an unmodified production Release app.
/// The fixture exporter is in the test target, never in the installed app.
final class ProductionReplayTests: XCTestCase {
    func testPersistedDeliveryAndAttendanceReplay() throws {
        let export = ProcessInfo.processInfo.environment["SWEEP_REPLAY_OUTPUT"]
        let root = export.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if export == nil { addTeardownBlock { try? FileManager.default.removeItem(at: root) } }
        let evidence = root.appendingPathComponent("Evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        defer { try? FileManager.default.removeItem(at: source) }
        var ledger = DeliveryLedger()
        for code in ["REPLAY-BANK", "REPLAY-PARTIAL", "REPLAY-FREIGHT"] {
            var order = DeliveryOrder(code: code, customer: "Khách kiểm tra Release", total: 2_165_000)
            order.evidence = [try EvidenceFiles.importImage(source, role: .invoice, directory: evidence)]
            let id = try ledger.insert(order); try ledger.sign(id, at: Date())
        }
        try ledger.markAttendance(Date(), state: .work)
        let database = try DeliveryDatabase(url: root.appendingPathComponent("Sweep.sqlite"))
        try database.save(ledger)
        let restored = try database.load()
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.orders.count, 3)
        XCTAssertEqual(restored.commissions(in: Date(), calendar: PayrollDates.calendar).count, 3)
        XCTAssertEqual(restored.cashHeld, 0)
        XCTAssertEqual(restored.payroll?.period(Date()).entries.count, 1)
        // Also replay a real migration failure: valid old ledger, missing image.
        // The app must retain its data and explain the read-only state.
        let legacyRoot = root.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot.appendingPathComponent("Evidence"), withIntermediateDirectories: true)
        var legacy = ledger; legacy.schema = 2; legacy.payroll = nil
        let legacyDatabase = try DeliveryDatabase(url: legacyRoot.appendingPathComponent("Sweep.sqlite"))
        try legacyDatabase.save(legacy)
        XCTAssertEqual(try legacyDatabase.load(), legacy)
    }
}
