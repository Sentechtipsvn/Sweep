import XCTest
import UIKit
import SQLite3
@testable import Sweep

@MainActor
final class DeliveryFeedbackTests: XCTestCase {
    func testFailedOperationClearsPreviousSuccessNotice() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DeliveryStore(root: root)
        XCTAssertTrue(store.change { try $0.markAttendance(Date(), state: .work) })
        XCTAssertNotNil(store.successNotice)
        XCTAssertFalse(store.change { _ in throw DeliveryError.invalid("Lỗi kiểm thử") })
        XCTAssertNil(store.successNotice)
    }
    func testCommittedChangeHasToastAndCanBeReadBackFromDatabase() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DeliveryStore(root: root)
        XCTAssertTrue(store.change { try $0.markAttendance(Date(), state: .work) })
        XCTAssertEqual(store.successNotice?.text, "Đã lưu chấm công")
        XCTAssertEqual(try DeliveryDatabase(url: root.appendingPathComponent("Sweep.sqlite")).load(), store.ledger)
    }
    func testSqliteCommitFailureDoesNotPublishSuccessOrChangeLedger() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DeliveryStore(root: root), before = store.ledger
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("Sweep.sqlite").path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER reject_test_commit BEFORE INSERT ON ledger BEGIN SELECT RAISE(ABORT, 'intentional test write failure'); END;", nil, nil, nil), SQLITE_OK)
        XCTAssertFalse(store.change { try $0.markAttendance(Date(), state: .work) })
        XCTAssertEqual(store.ledger, before); XCTAssertNil(store.successNotice); XCTAssertNotNil(store.message)
        XCTAssertEqual(try DeliveryDatabase(url: root.appendingPathComponent("Sweep.sqlite")).load(), before)
    }
    func testToastAppearsAboveSheetsWithoutTakingKeyWindowOrTouches() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let key = scene.windows.first { $0.isKeyWindow }
        let presenter = DeliveryEffectsPresenter(scene: scene); defer { presenter.invalidate() }
        presenter.show(DeliverySuccessNotice(text: "Đã lưu kiểm thử"))
        let overlay = try XCTUnwrap(scene.windows.first { $0.accessibilityIdentifier == "feedback.window" && !$0.isHidden })
        XCTAssertFalse(overlay.isKeyWindow); XCTAssertTrue(scene.windows.first { $0.isKeyWindow } === key)
        XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 120), with: nil))
        let label = try XCTUnwrap(find("feedback.toast", in: overlay) as? UILabel)
        XCTAssertEqual(label.text, "Đã lưu kiểm thử")
    }
    func testReducedMotionKeepsSuccessToastAndOmitsConfetti() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let presenter = DeliveryEffectsPresenter(scene: scene); defer { presenter.invalidate() }
        presenter.show(DeliverySuccessNotice(text: "Hoàn tất giao hàng", completedOrderIDs: [UUID()]), reduceMotion: true)
        let overlay = try XCTUnwrap(scene.windows.first { $0.accessibilityIdentifier == "feedback.window" && !$0.isHidden })
        XCTAssertNotNil(find("feedback.toast", in: overlay))
        XCTAssertNil(find("feedback.celebration", in: overlay))
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Feedback-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews { if let match = find(identifier, in: child) { return match } }
        return nil
    }
}
