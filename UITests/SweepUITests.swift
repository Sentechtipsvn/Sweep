import XCTest

final class SweepUITests: XCTestCase {
    func testRecordedTransferStillDisplaysQRCode() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--qr-ui-testing"]
        app.launch()
        let order = app.buttons["order.TEST-001"]
        XCTAssertTrue(order.waitForExistence(timeout: 20)); order.tap()
        reveal(app.buttons["order.qr"], in: app); app.buttons["order.qr"].tap()
        let amount = app.textFields["qr.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.value as? String, "2165000")
        reveal(app.buttons["qr.generate"], in: app)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 45))
        waitUntil(app.buttons["qr.generate"], in: app) { $0.exists && $0.isEnabled }
        attach(app, name: "qr-recorded-transfer-can-show-again")
    }

    func testSharedImageReviewImportQRSetupAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--shared-ui-testing"]
        app.launch()
        let code = app.textFields["intake.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        let populated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "TEST-7856"), object: code)
        XCTAssertEqual(XCTWaiter.wait(for: [populated], timeout: 40), .completed)
        let save = app.buttons["intake.save"]
        waitUntil(save, in: app) { $0.exists && $0.isEnabled }
        attach(app, name: "share-01-review")
        save.tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 20))
        reveal(app.buttons["order.qr"], in: app); app.buttons["order.qr"].tap()
        let setup = app.buttons["Thiết lập tài khoản VietQR"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        attach(app, name: "share-02-qr-needs-account")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--shared-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["order.TEST-7856"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["orders.shared"].exists)
        attach(app, name: "share-03-persisted")
    }

    func testLaunchNavigationAndPermissionEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery"]
        app.launch()
        app.tabBars.buttons["Công cụ"].tap()
        XCTAssertTrue(app.buttons["tool.duplicates"].waitForExistence(timeout: 15))
        attach(app, name: "01-home")
        app.buttons["tool.duplicates"].tap()
        XCTAssertTrue(app.buttons["Cho phép truy cập ảnh"].waitForExistence(timeout: 5))
        attach(app, name: "02-photo-permission")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tool.compress"].tap()
        XCTAssertTrue(app.buttons["Tạo bản nén"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Tạo bản nén"].isEnabled)
        attach(app, name: "03-compress")
        app.tabBars.buttons["Cài đặt"].tap()
        XCTAssertTrue(app.staticTexts["500 ảnh gần nhất"].waitForExistence(timeout: 5))
        attach(app, name: "04-settings")
    }

    func testSignedAssignmentMixedSettlementReportAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery"]
        app.launch()
        let order = app.buttons["order.TEST-001"]
        XCTAssertTrue(order.waitForExistence(timeout: 15)); order.tap()
        reveal(app.buttons["order.sign"], in: app); app.buttons["order.sign"].tap()
        app.buttons["sign.confirm"].tap()
        waitUntil(app.buttons["sign.save"], in: app) { $0.exists && $0.isEnabled }
        app.buttons["sign.save"].tap()
        waitUntil(app.buttons["sign.save"], in: app) { !$0.exists }
        attach(app, name: "05-signed-assignment")
        waitUntil(app.buttons["order.settle"], in: app) { $0.exists && $0.isHittable }
        app.buttons["order.settle"].tap()
        app.buttons["settle.outcome"].tap()
        app.buttons["Giao thất bại"].firstMatch.tap()
        app.buttons["settle.mode"].tap()
        app.buttons["CK + tiền mặt"].firstMatch.tap()
        replace(app.textFields["settle.cash"], with: "600000")
        replace(app.textFields["settle.bank"], with: "1500000")
        dismissKeyboard(in: app)
        let note = app.textFields["settle.note"]
        reveal(note, in: app)
        waitUntil(note, in: app) { $0.exists && $0.isHittable }
        note.tap(); note.typeText("Hen giao lai, da nhan mot phan")
        dismissKeyboard(in: app)
        reveal(app.buttons["settle.save"], in: app); app.buttons["settle.save"].tap()
        XCTAssertTrue(app.buttons["order.settle"].waitForExistence(timeout: 5))
        reveal(app.buttons["order.report"], in: app); app.buttons["order.report"].tap()
        reveal(app.buttons["report.prepare"], in: app); app.buttons["report.prepare"].tap()
        let ack = app.buttons["report.ack"]
        reveal(ack, in: app); XCTAssertTrue(ack.waitForExistence(timeout: 5)); XCTAssertTrue(ack.isEnabled)
        // Preparing/sharing is not a sent receipt. Only the explicit user acknowledgement changes this state.
        attach(app, name: "05-report-awaiting-confirmation")
        ack.tap(); app.alerts.buttons["Đúng, đã gửi"].tap()
        XCTAssertTrue(app.buttons["report.ack"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["report.ack"].isEnabled)
        app.tabBars.buttons["Đối soát"].tap()
        XCTAssertTrue(app.staticTexts["5.000₫"].firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "06-reconciliation")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 10))
        app.buttons["order.TEST-001"].tap()
        reveal(app.staticTexts["65.000₫"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["65.000₫"].firstMatch.exists)
        attach(app, name: "07-persisted-partial-settlement")
    }

    func testBillPreviewOCRImportAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--bill-ui-testing"]
        app.launch()
        app.buttons["orders.receive"].tap(); app.buttons["orders.bill"].tap()
        let candidate = app.buttons["bill.candidate.bill:ui-fixture"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 15)); candidate.tap()
        let code = app.textFields["intake.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        let populated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "TEST-7856"), object: code)
        XCTAssertEqual(XCTWaiter.wait(for: [populated], timeout: 40), .completed)
        let save = app.buttons["intake.save"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        attach(app, name: "08-bill-ocr-review")
        save.tap()
        // LabeledContent exposes its value through the row, not a separate StaticText.
        // Wait for both sheets to finish dismissing before observing the detail screen.
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Mã phiếu"].waitForExistence(timeout: 10))
        attach(app, name: "09-bill-saved-order")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--bill-ui-testing"]
        app.launch()
        let persisted = app.buttons["order.TEST-7856"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "order.TEST-7856").count, 1)
        XCTAssertTrue(app.staticTexts["Chưa tính công"].firstMatch.exists)
        attach(app, name: "10-bill-persisted-list")
        app.buttons["orders.receive"].tap(); app.buttons["orders.bill"].tap()
        let existing = app.buttons["bill.existing.bill:ui-fixture"]
        XCTAssertTrue(existing.waitForExistence(timeout: 10))
        existing.tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 20))
        app.navigationBars["Chi tiết đơn"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "order.TEST-7856").count, 1)
        attach(app, name: "11-bill-no-duplicate")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let collection = app.collectionViews.allElementsBoundByIndex.last { $0.isHittable }
            let table = app.tables.allElementsBoundByIndex.last { $0.isHittable }
            let scroll = collection ?? table ?? app.scrollViews.allElementsBoundByIndex.last { $0.isHittable }
            if let scroll { scroll.swipeUp() } else { app.swipeUp() }
        }
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        waitUntil(app.keyboards.firstMatch, in: app) { !$0.exists }
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let count = (field.value as? String)?.count ?? 1
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2) + value)
    }

    private func waitUntil(_ element: XCUIElement, in app: XCUIApplication, condition: @escaping (XCUIElement) -> Bool) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition(element) }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 8)
        if result != .completed { attach(app, name: "failure-navigation"); print(app.debugDescription) }
        XCTAssertEqual(result, .completed)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
