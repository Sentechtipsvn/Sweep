import XCTest

final class SweepUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        addUIInterruptionMonitor(withDescription: "Quyền thông báo") { alert in
            for title in ["Allow", "Cho phép"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            return false
        }
    }
    func testSendeliTwoTabsHistoryAndSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery"]
        app.launch()
        XCTAssertTrue(app.buttons["filter.Đang giao"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["filter.Đã giao"].exists)
        XCTAssertFalse(app.buttons["filter.Tất cả"].exists); XCTAssertFalse(app.buttons["orders.receive"].exists); XCTAssertFalse(app.buttons["orders.bill"].exists)
        app.buttons["filter.Đã giao"].tap()
        XCTAssertTrue(app.staticTexts["orders.count"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Lịch sử"].tap()
        reveal(app.buttons["history.all"], in: app); app.buttons["history.all"].tap()
        XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 10))
        let search = app.textFields["orders.search"]; search.tap(); search.typeText("TEST-001")
        XCTAssertTrue(app.buttons["order.TEST-001"].exists)
        attach(app, name: "sendeli-history-all-and-search")
    }
    func testSendeliWorkCardAndCompactDirectories() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--update02-ui-testing", "--monthly-ui-testing"]
        app.launch()
        app.buttons["filter.Đã giao"].tap()
        XCTAssertTrue(app.buttons["orders.work"].waitForExistence(timeout: 20)); app.buttons["orders.work"].tap()
        XCTAssertTrue(app.navigationBars["Việc cần chốt"].waitForExistence(timeout: 10))
        attach(app, name: "sendeli-worklist")
        app.tabBars.buttons["Công cụ"].tap(); app.buttons["Liên hệ"].tap()
        XCTAssertTrue(app.buttons["contact.call"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["contact.zalo"].firstMatch.exists)
        attach(app, name: "sendeli-compact-contacts")
        app.navigationBars.buttons["Công cụ"].tap(); app.buttons["Vị trí"].tap()
        XCTAssertTrue(app.buttons["Điều hướng Google Maps"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["contact.call"].firstMatch.exists)
        attach(app, name: "sendeli-compact-places")
    }
    func testUpdate03CompactHeaderAndReminderPaymentConfirmationPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--reminder-ui-testing"]
        app.launch()
        let search = app.textFields["orders.search"], delivered = app.buttons["filter.Đã giao"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        XCTAssertLessThan(delivered.frame.minY - search.frame.maxY, 60)
        XCTAssertFalse(app.buttons["orders.work"].exists)
        delivered.tap()
        let work = app.buttons["orders.work"]
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        XCTAssertEqual(work.label, "Còn 2 việc cần xử lý")
        let period = app.staticTexts["Đã giao trong ngày"]
        XCTAssertEqual(work.frame.midY, period.frame.midY, accuracy: 5)
        attach(app, name: "update03-compact-delivered-header")
        work.tap()
        let payment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "work.payment.")).firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 10)); payment.tap()
        XCTAssertTrue(app.buttons["work.transfer.confirm"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["flow.bankNow"].exists); XCTAssertFalse(app.buttons["flow.bankLater"].exists)
        attach(app, name: "update03-two-action-payment-sheet")
        tapPillBackground(app.buttons["work.transfer.cancel"])
        XCTAssertTrue(payment.waitForExistence(timeout: 10)); payment.tap()
        tapPillBackground(app.buttons["work.transfer.confirm"])
        XCTAssertTrue(app.alerts.buttons["Xác nhận và hoàn tất"].waitForExistence(timeout: 10))
        app.alerts.buttons["Huỷ"].tap()
        XCTAssertTrue(app.buttons["work.transfer.confirm"].exists)
        tapPillBackground(app.buttons["work.transfer.confirm"])
        app.alerts.buttons["Xác nhận và hoàn tất"].tap()
        XCTAssertTrue(app.navigationBars["Việc cần chốt"].waitForExistence(timeout: 10))
        XCTAssertFalse(payment.exists)
        let freight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "work.freight.")).firstMatch
        XCTAssertTrue(freight.exists); freight.tap()
        tapPillBackground(app.buttons["work.transfer.confirm"])
        app.alerts.buttons["Xác nhận và hoàn tất"].tap()
        XCTAssertTrue(app.navigationBars["Việc cần chốt"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Đơn hàng"].tap()
        XCTAssertFalse(app.buttons["orders.work"].exists)
        attach(app, name: "update03-no-work-after-confirmation")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-delivery" }
        app.launch()
        XCTAssertTrue(app.buttons["filter.Đã giao"].waitForExistence(timeout: 20)); app.buttons["filter.Đã giao"].tap()
        XCTAssertFalse(app.buttons["orders.work"].exists)
        XCTAssertTrue(app.buttons["order.TEST-FREIGHT"].exists)
        attach(app, name: "update03-confirmation-survives-relaunch")
    }
    func testUpdate03HistoryAndSettingsHaveSingleDestinations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--monthly-ui-testing"]
        app.launch()
        app.tabBars.buttons["Lịch sử"].tap()
        let all = app.buttons["history.all"]; reveal(all, in: app)
        XCTAssertTrue(all.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "PHIẾU TÍNH CÔNG ·")).firstMatch.exists)
        attach(app, name: "update03-history-without-repeated-order-list")
        all.tap(); XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Cài đặt"].tap()
        XCTAssertFalse(app.buttons["Liên hệ bán hàng / tài xế"].exists)
        XCTAssertFalse(app.buttons["Dọn dẹp / đặt lại dữ liệu"].exists)
        XCTAssertFalse(app.buttons["Chấm công và lương"].exists)
        XCTAssertTrue(app.buttons["Công đơn và QR công ty"].exists)
        attach(app, name: "update03-settings-without-duplicate-tools")
    }
    func testProductionZEffectsCashCompletionPersistsWithoutReplay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        openAllHistory(app)
        let row = app.buttons["order.REPLAY-FREIGHT"]
        XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        reveal(app.buttons["method.Tiền mặt"], in: app); tapPillBackground(app.buttons["method.Tiền mặt"])
        XCTAssertTrue(app.buttons["flow.cashFull"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.cashFull"])
        XCTAssertTrue(app.alerts.buttons["Đã nhận đủ"].waitForExistence(timeout: 10)); app.alerts.buttons["Đã nhận đủ"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 10))
        if app.alerts["Lưu vị trí giao hàng?"].waitForExistence(timeout: 3) { app.alerts.buttons["Để sau"].tap() }
        attach(app, name: "production-effects-completed-cash-order")
        app.terminate(); app.launch()
        openAllHistory(app)
        XCTAssertTrue(app.buttons["order.REPLAY-FREIGHT"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.images["feedback.celebration"].exists)
        XCTAssertFalse(app.staticTexts["feedback.toast"].exists)
        app.buttons["order.REPLAY-FREIGHT"].tap()
        if app.alerts["Lưu vị trí giao hàng?"].waitForExistence(timeout: 2) { app.alerts.buttons["Để sau"].tap() }
        XCTAssertTrue(app.staticTexts["Đã giao · Tiền mặt chờ nộp"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["feedback.celebration"].exists)
        attach(app, name: "production-effects-no-replay-after-relaunch")
    }

    func testProductionReadOnlyActionsGiveFeedbackAndStillClose() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        if app.alerts.buttons["Đã hiểu"].waitForExistence(timeout: 8) { app.alerts.buttons["Đã hiểu"].tap() }
        let bank = app.buttons["order.REPLAY-BANK"]
        XCTAssertTrue(bank.waitForExistence(timeout: 20)); bank.tap()
        XCTAssertTrue(app.staticTexts["Sổ đang ở chế độ chỉ đọc"].waitForExistence(timeout: 10))
        reveal(app.buttons["method.Chuyển khoản"], in: app); tapPillBackground(app.buttons["method.Chuyển khoản"])
        XCTAssertTrue(app.buttons["flow.bankLater"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.bankLater"])
        XCTAssertTrue(app.staticTexts["flow.problem"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["feedback.toast"].exists)
        XCTAssertTrue(app.navigationBars.buttons["Đóng"].isEnabled); app.navigationBars.buttons["Đóng"].tap()
        app.tabBars.buttons["Công cụ"].tap(); app.buttons["tool.payroll"].tap()
        XCTAssertTrue(app.scrollViews["payroll.content"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.scrollViews["payroll.content"].collectionViews.count, 0)
        attach(app, name: "production-read-only-feedback-and-attendance")
    }

    func testAttendanceLargeTextNavigationUsesPlainScroll() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--delivery-ui-testing", "--reset-delivery"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Công cụ"].waitForExistence(timeout: 20)); app.tabBars.buttons["Công cụ"].tap()
        for _ in 0..<3 {
            let tool = app.buttons["tool.payroll"]
            reveal(tool, in: app); XCTAssertTrue(tool.isHittable); tool.tap()
            let content = app.scrollViews["payroll.content"]
            XCTAssertTrue(content.waitForExistence(timeout: 10)); XCTAssertEqual(content.collectionViews.count, 0)
            app.navigationBars.buttons["Công cụ"].tap()
        }
        let tool = app.buttons["tool.payroll"]; reveal(tool, in: app); tool.tap()
        XCTAssertTrue(app.scrollViews["payroll.content"].waitForExistence(timeout: 10))
        attach(app, name: "attendance-large-text-without-collection-row-layout")
    }

    func testProductionReleaseDeliveryBranches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        let bank = app.buttons["order.REPLAY-BANK"]
        XCTAssertTrue(bank.waitForExistence(timeout: 20)); bank.tap()
        reveal(app.buttons["method.Chuyển khoản"], in: app); tapPillBackground(app.buttons["method.Chuyển khoản"])
        XCTAssertTrue(app.buttons["flow.bankNow"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.bankNow"])
        XCTAssertTrue(app.buttons["flow.confirmTransfer"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Đóng"].tap()
        XCTAssertTrue(app.buttons["method.Chuyển khoản"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["method.Chuyển khoản"])
        XCTAssertTrue(app.buttons["flow.bankLater"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.bankLater"])
        XCTAssertTrue(app.alerts.buttons["Xác nhận, chọn phiếu đã ký"].waitForExistence(timeout: 10)); app.alerts.buttons["Xác nhận, chọn phiếu đã ký"].tap()
        XCTAssertTrue(app.navigationBars["Chứng từ giao hàng"].waitForExistence(timeout: 10))
        attach(app, name: "production-release-transfer-now-and-later")
        app.navigationBars.buttons["Đóng"].tap()
        app.navigationBars["Chi tiết đơn"].buttons.element(boundBy: 0).tap()

        let partial = app.buttons["order.REPLAY-PARTIAL"]
        XCTAssertTrue(partial.waitForExistence(timeout: 10)); partial.tap()
        reveal(app.buttons["method.Tiền mặt"], in: app); tapPillBackground(app.buttons["method.Tiền mặt"])
        XCTAssertTrue(app.buttons["flow.partial"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.partial"])
        let amount = app.textFields["flow.cash"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.5)).tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "600000")
        XCTAssertEqual(amount.value as? String, "600000"); dismissKeyboard(in: app)
        reveal(app.buttons["flow.partialNow"], in: app); app.buttons["flow.partialNow"].tap()
        XCTAssertTrue(app.alerts.buttons["Đã nhận, mở QR phần còn lại"].waitForExistence(timeout: 10)); app.alerts.buttons["Đã nhận, mở QR phần còn lại"].tap()
        XCTAssertTrue(app.buttons["flow.confirmTransfer"].waitForExistence(timeout: 10))
        attach(app, name: "production-release-partial-cash-remaining-transfer")
        app.navigationBars.buttons["Đóng"].tap()
        app.navigationBars["Chi tiết đơn"].buttons.element(boundBy: 0).tap()

        let freight = app.buttons["order.REPLAY-FREIGHT"]
        XCTAssertTrue(freight.waitForExistence(timeout: 10)); freight.tap()
        reveal(app.buttons["method.Giao chành"], in: app); tapPillBackground(app.buttons["method.Giao chành"])
        XCTAssertTrue(app.buttons["flow.freight"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.freight"])
        XCTAssertTrue(app.alerts.buttons["Đã giao, thêm chứng từ"].waitForExistence(timeout: 10)); app.alerts.buttons["Đã giao, thêm chứng từ"].tap()
        XCTAssertTrue(app.navigationBars["Chứng từ giao hàng"].waitForExistence(timeout: 10))
        attach(app, name: "production-release-freight")
        app.navigationBars.buttons["Đóng"].tap()
        app.tabBars.buttons["Lịch sử"].tap()
        assertRow("audit.cashCollected", contains: "600.000₫", in: app)
        assertRow("audit.fee", contains: "15.000₫", in: app)
    }

    func testProductionReleaseAttendanceNavigationAndRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Công cụ"].waitForExistence(timeout: 20)); app.tabBars.buttons["Công cụ"].tap()
        defer { XCUIDevice.shared.orientation = .portrait }
        for iteration in 0..<4 {
            let tool = app.buttons["tool.payroll"]
            reveal(tool, in: app); XCTAssertTrue(tool.waitForExistence(timeout: 10)); tool.tap()
            let content = app.scrollViews["payroll.content"]
            XCTAssertTrue(content.waitForExistence(timeout: 10))
            // The device crash recursed in UICollectionView's visible-cell layout.
            XCTAssertEqual(content.collectionViews.count, 0)
            if iteration == 1 { XCUIDevice.shared.orientation = .landscapeLeft }
            if iteration == 2 { XCUIDevice.shared.orientation = .portrait }
            app.navigationBars.buttons["Công cụ"].tap()
        }
        app.buttons["tool.payroll"].tap()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let today = app.buttons["attendance.day.\(calendar.component(.day, from: Date()))"]
        reveal(today, in: app); XCTAssertTrue(today.waitForExistence(timeout: 10)); today.tap()
        XCTAssertTrue(app.buttons["attendance.save"].waitForExistence(timeout: 10)); app.buttons["attendance.save"].tap()
        XCTAssertTrue(app.scrollViews["payroll.content"].waitForExistence(timeout: 10))
        attach(app, name: "production-release-attendance-rotation-and-save")
    }

    func testPaidOrderActionsExplainGuardAndCanReopenQR() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--qr-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 20)); app.buttons["order.TEST-001"].tap()
        reveal(app.buttons["method.Chuyển khoản"], in: app); tapPillBackground(app.buttons["method.Chuyển khoản"])
        XCTAssertTrue(app.buttons["flow.bankLater"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.bankLater"])
        XCTAssertTrue(app.staticTexts["flow.problem"].waitForExistence(timeout: 10))
        tapPillBackground(app.buttons["flow.bankNow"])
        XCTAssertTrue(app.textFields["qr.amount"].waitForExistence(timeout: 10)); XCTAssertEqual(app.textFields["qr.amount"].value as? String, "2165000")
        app.navigationBars.buttons["Đóng"].tap()
        reveal(app.buttons["method.Giao chành"], in: app); tapPillBackground(app.buttons["method.Giao chành"])
        XCTAssertTrue(app.buttons["flow.freight"].waitForExistence(timeout: 10)); tapPillBackground(app.buttons["flow.freight"])
        XCTAssertTrue(app.staticTexts["flow.problem"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["Đã bàn giao hàng cho chành?"].exists)
        attach(app, name: "paid-order-guards-explain-why-and-preserve-money")
    }

    func testHotfixUnsignedBankOpensAfterSigningAndQRDoesNotRecordPayment() throws {
        let app = openUnsignedDeliveryFlow("Chuyển khoản", expected: "flow.bankNow")
        tapPillBackground(app.buttons["flow.bankNow"])
        XCTAssertTrue(app.buttons["flow.confirmTransfer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Thiết lập tài khoản VietQR"].exists)
        attach(app, name: "hotfix-transfer-now-opens-qr")
        app.navigationBars.buttons["Đóng"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Lịch sử"].tap()
        assertRow("audit.cashCollected", contains: "0₫", in: app)
        assertRow("audit.fee", contains: "5.000₫", in: app)
    }

    func testHotfixPartialCashThenTransferNowPersistsOnlyConfirmedCash() throws {
        let app = openUnsignedDeliveryFlow("Tiền mặt", expected: "flow.partial")
        tapPillBackground(app.buttons["flow.partial"])
        let amount = app.textFields["flow.cash"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        // A center tap can put the caret before the initial right-aligned zero.
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.5)).tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "600000")
        XCTAssertEqual(amount.value as? String, "600000")
        dismissKeyboard(in: app)
        let now = app.buttons["flow.partialNow"]
        reveal(now, in: app); now.tap()
        XCTAssertTrue(app.alerts.buttons["Đã nhận, mở QR phần còn lại"].waitForExistence(timeout: 5))
        app.alerts.buttons["Đã nhận, mở QR phần còn lại"].tap()
        XCTAssertTrue(app.buttons["flow.confirmTransfer"].waitForExistence(timeout: 10))
        attach(app, name: "hotfix-partial-cash-opens-remaining-qr")
        app.navigationBars.buttons["Đóng"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Lịch sử"].tap()
        assertRow("audit.cashCollected", contains: "600.000₫", in: app)
        assertRow("audit.fee", contains: "5.000₫", in: app)
    }

    func testHotfixFreightConfirmationAndHorizontalImageButtons() throws {
        let app = openUnsignedDeliveryFlow("Giao chành", expected: "flow.freight")
        tapPillBackground(app.buttons["flow.freight"])
        XCTAssertTrue(app.alerts.buttons["Chưa giao"].waitForExistence(timeout: 5)); app.alerts.buttons["Chưa giao"].tap()
        XCTAssertTrue(app.buttons["flow.freight"].exists)
        tapPillBackground(app.buttons["flow.freight"])
        XCTAssertTrue(app.alerts.buttons["Đã giao, thêm chứng từ"].waitForExistence(timeout: 5)); app.alerts.buttons["Đã giao, thêm chứng từ"].tap()
        XCTAssertTrue(app.navigationBars["Chứng từ giao hàng"].waitForExistence(timeout: 10))
        let photos = app.buttons.matching(identifier: "evidence.photos").firstMatch
        let camera = app.buttons.matching(identifier: "evidence.camera").firstMatch
        reveal(photos, in: app)
        XCTAssertTrue(photos.exists); XCTAssertTrue(camera.exists)
        XCTAssertLessThan(photos.frame.midX, camera.frame.midX)
        XCTAssertEqual(photos.frame.midY, camera.frame.midY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(photos.frame.height, 44); XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
        attach(app, name: "hotfix-freight-and-horizontal-photo-camera")
        app.navigationBars.buttons["Đóng"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Lịch sử"].tap()
        assertRow("audit.cashCollected", contains: "0₫", in: app)
        assertRow("audit.fee", contains: "5.000₫", in: app)
    }

    private func openUnsignedDeliveryFlow(_ method: String, expected: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery"]
        app.launch()
        let order = app.buttons["order.TEST-001"]
        XCTAssertTrue(order.waitForExistence(timeout: 20)); order.tap()
        let button = app.buttons["method." + method]
        reveal(button, in: app); XCTAssertTrue(button.isEnabled); tapPillBackground(button)
        XCTAssertTrue(app.buttons["sign.confirm"].waitForExistence(timeout: 10))
        app.buttons["sign.confirm"].tap(); app.buttons["sign.save"].tap()
        XCTAssertTrue(app.buttons[expected].waitForExistence(timeout: 10))
        return app
    }
    private func tapPillBackground(_ button: XCUIElement) {
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
    }
    func testUpdate02CompactContactsAndPlaces() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--update02-ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Công cụ"].waitForExistence(timeout: 20)); app.tabBars.buttons["Công cụ"].tap()
        app.buttons["Liên hệ"].tap()
        let call = app.buttons["contact.call"].firstMatch
        XCTAssertTrue(call.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(call.frame.width, 60); XCTAssertGreaterThanOrEqual(call.frame.width, 44)
        XCTAssertGreaterThan(call.frame.midX, app.frame.width * 0.7)
        XCTAssertTrue(app.staticTexts["0900000001"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "contact.zalo").firstMatch.exists)
        attach(app, name: "update02-compact-contacts")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Vị trí"].tap()
        XCTAssertTrue(app.buttons["Google Maps"].waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["contact.call"].firstMatch.frame.width, 60)
        attach(app, name: "update02-compact-places")
    }
    func testUpdate02AttendanceCalendarSavesAndPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Công cụ"].waitForExistence(timeout: 20)); app.tabBars.buttons["Công cụ"].tap()
        app.buttons["tool.payroll"].tap()
        for _ in 0..<2 {
            XCTAssertTrue(app.buttons["payroll.previous"].waitForExistence(timeout: 10)); app.buttons["payroll.previous"].tap()
            XCTAssertTrue(app.buttons["payroll.next"].waitForExistence(timeout: 10)); app.buttons["payroll.next"].tap()
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let today = app.buttons["attendance.day.\(calendar.component(.day, from: Date()))"]
        XCTAssertTrue(today.waitForExistence(timeout: 10)); today.tap()
        XCTAssertTrue(app.buttons["attendance.save"].waitForExistence(timeout: 10)); app.buttons["attendance.save"].tap()
        XCTAssertTrue(app.staticTexts["payroll.net"].waitForExistence(timeout: 10))
        attach(app, name: "update02-attendance-and-salary")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing"]
        app.launch(); app.tabBars.buttons["Công cụ"].tap(); app.buttons["tool.payroll"].tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10)); XCTAssertTrue(today.label.contains("Đi làm"))
    }
    func testReportImageSelectionAndCompactTransferCaption() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--qr-ui-testing"]
        app.launch()
        let order = app.buttons["order.TEST-001"]
        XCTAssertTrue(order.waitForExistence(timeout: 20)); order.tap()
        reveal(app.buttons["order.report"], in: app); app.buttons["order.report"].tap()
        let caption = app.textViews["report.text"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        XCTAssertEqual(caption.value as? String, "Khách thử nghiệm đã chuyển khoản 2.165.000₫")
        let invoice = app.buttons["report.remove.Phiếu nội bộ"]
        let transfer = app.buttons["report.remove.Ảnh giao dịch"]
        XCTAssertTrue(invoice.exists); XCTAssertTrue(transfer.exists)
        XCTAssertFalse(app.buttons["report.remove.Phiếu khách ký"].exists)
        transfer.tap(); XCTAssertFalse(transfer.exists)
        // Image-only edits must survive leaving the composer without changing the caption.
        app.navigationBars["Chia sẻ đơn"].buttons.element(boundBy: 0).tap()
        reveal(app.buttons["order.report"], in: app); app.buttons["order.report"].tap()
        XCTAssertTrue(invoice.waitForExistence(timeout: 10)); XCTAssertFalse(transfer.exists)
        app.buttons["report.chooseImages"].tap()
        let transferChoice = app.buttons["report.select.Ảnh giao dịch"]
        XCTAssertTrue(transferChoice.waitForExistence(timeout: 5)); transferChoice.tap()
        XCTAssertFalse(app.buttons["report.select.Phiếu khách ký"].exists)
        app.buttons["report.imagesDone"].tap()
        let signature = app.buttons["report.remove.Phiếu khách ký"]
        XCTAssertFalse(signature.exists)
        XCTAssertTrue(transfer.exists); XCTAssertTrue(invoice.exists)
        XCTAssertFalse(app.buttons["report.prepare"].exists)
        reveal(app.buttons["report.share"], in: app); app.buttons["report.share"].tap()
        dismissActivity(in: app)
        XCTAssertFalse(app.alerts.buttons["Chưa gửi"].exists)
        XCTAssertTrue(app.buttons["report.ack"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["report.ack"].isEnabled)
        XCTAssertFalse(app.buttons["report.remove.Phiếu khách ký"].exists)
        attach(app, name: "report-two-selected-images-short-caption")
        app.buttons["report.ack"].tap(); app.alerts.buttons["Đúng, đã gửi"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 8))
        attach(app, name: "report-explicit-sent-confirmation")
    }

    func testReconciliationEmptyMonthHasNoFiguresFromAnotherMonth() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery", "--monthly-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Lịch sử"].tap()
        assertRow("audit.count", contains: "1", in: app)
        assertRow("audit.cashCollected", contains: "665.000₫", in: app)
        assertRow("audit.cashHanded", contains: "500.000₫", in: app)
        assertRow("audit.cashHeld", contains: "165.000₫", in: app)
        attach(app, name: "audit-current-month")
        app.swipeDown(); app.swipeDown()
        app.buttons["audit.previous"].tap()
        for id in ["audit.count", "audit.fee", "audit.cashCollected", "audit.cashHanded", "audit.cashDifference"] {
            assertRow(id, contains: id == "audit.count" ? "0" : "0₫", in: app)
        }
        XCTAssertFalse(app.staticTexts["665.000₫"].exists)
        attach(app, name: "audit-empty-month-all-zero")
        app.swipeDown(); app.swipeDown()
        app.buttons["audit.next"].tap()
        assertRow("audit.count", contains: "1", in: app)
        assertRow("audit.cashCollected", contains: "665.000₫", in: app)
    }

    func testIntakeHasOnlyPhotoAndCameraSourcesAtLargeTextSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--delivery-ui-testing", "--reset-delivery"]
        app.launch()
        let newOrder = app.buttons["orders.new"]
        XCTAssertTrue(newOrder.waitForExistence(timeout: 20)); newOrder.tap()
        XCTAssertTrue(app.alerts.buttons["Đã ký"].waitForExistence(timeout: 5)); app.alerts.buttons["Đã ký"].tap()
        let photos = app.buttons["evidence.photos"], camera = app.buttons["evidence.camera"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10)); XCTAssertTrue(camera.exists)
        XCTAssertTrue(photos.label.contains("Chọn ảnh")); XCTAssertTrue(camera.label.contains("Chụp ảnh"))
        XCTAssertLessThan(photos.frame.midX, camera.frame.midX)
        XCTAssertEqual(photos.frame.minY, camera.frame.minY, accuracy: 2)
        XCTAssertFalse(app.buttons["Tệp"].exists)
        attach(app, name: "intake-two-photo-sources-large-text")
    }

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
        XCTAssertTrue(app.alerts.buttons["Đã ký"].waitForExistence(timeout: 20)); app.alerts.buttons["Đã ký"].tap()
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
        XCTAssertTrue(app.alerts.buttons["Xác nhận lưu"].waitForExistence(timeout: 5)); app.alerts.buttons["Xác nhận lưu"].tap()
        XCTAssertTrue(app.buttons["order.settle"].waitForExistence(timeout: 5))
        reveal(app.buttons["order.report"], in: app); app.buttons["order.report"].tap()
        reveal(app.buttons["report.share"], in: app); app.buttons["report.share"].tap()
        dismissActivity(in: app)
        XCTAssertFalse(app.alerts.buttons["Chưa gửi"].exists)
        let ack = app.buttons["report.ack"]
        reveal(ack, in: app); XCTAssertTrue(ack.waitForExistence(timeout: 5)); XCTAssertTrue(ack.isEnabled)
        // Preparing/sharing is not a sent receipt. Only the explicit user acknowledgement changes this state.
        attach(app, name: "05-report-awaiting-confirmation")
        ack.tap(); app.alerts.buttons["Đúng, đã gửi"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Lịch sử"].tap()
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
        XCTAssertTrue(app.alerts.buttons["Đã ký"].waitForExistence(timeout: 5)); app.alerts.buttons["Đã ký"].tap()
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
        XCTAssertTrue(app.staticTexts["TEST-7856"].waitForExistence(timeout: 10))
        attach(app, name: "09-bill-saved-order")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--bill-ui-testing"]
        app.launch()
        let persisted = app.buttons["order.TEST-7856"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "order.TEST-7856").count, 1)
        XCTAssertTrue(app.staticTexts["Đã tính công"].firstMatch.exists)
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

    func testApprovedCashWorkflowAndNewTools() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN", "--delivery-ui-testing", "--reset-delivery", "--seed-delivery"]
        app.launch()
        XCTAssertTrue(app.buttons["order.TEST-001"].waitForExistence(timeout: 20)); app.buttons["order.TEST-001"].tap()
        reveal(app.buttons["order.sign"], in: app); app.buttons["order.sign"].tap(); app.buttons["sign.confirm"].tap(); app.buttons["sign.save"].tap()
        app.swipeDown(); app.swipeDown()
        reveal(app.buttons["method.Tiền mặt"], in: app); app.buttons["method.Tiền mặt"].tap()
        XCTAssertTrue(app.buttons["flow.cashFull"].waitForExistence(timeout: 10)); app.buttons["flow.cashFull"].tap()
        app.alerts.buttons["Đã nhận đủ"].tap()
        XCTAssertTrue(app.navigationBars["Chi tiết đơn"].waitForExistence(timeout: 10))
        if app.alerts["Lưu vị trí giao hàng?"].waitForExistence(timeout: 3) { app.alerts.buttons["Để sau"].tap() }
        attach(app, name: "approved-cash-full-no-report")
        app.tabBars.buttons["Lịch sử"].tap(); assertRow("audit.cashHeld", contains: "2.165.000₫", in: app)
        app.tabBars.buttons["Công cụ"].tap()
        XCTAssertTrue(app.buttons["Vị trí"].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons["Dọn dẹp"].exists); XCTAssertTrue(app.buttons["Liên hệ"].exists)
        attach(app, name: "approved-seven-svg-tools")
        app.buttons["Dọn dẹp"].tap(); XCTAssertTrue(app.buttons["maintenance.reset"].waitForExistence(timeout: 10))
        attach(app, name: "approved-maintenance-backup-before-reset")
    }

    private func openAllHistory(_ app: XCUIApplication) {
        app.tabBars.buttons["Lịch sử"].tap()
        let all = app.buttons["history.all"]; reveal(all, in: app); all.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let collection = app.collectionViews.allElementsBoundByIndex.last { $0.isHittable }
            let table = app.tables.allElementsBoundByIndex.last { $0.isHittable }
            let tagged = ["sweep.groupedScroll", "order.content", "payroll.content"].flatMap { id in
                app.scrollViews.matching(identifier: id).allElementsBoundByIndex
            }.last { $0.isHittable }
            let scroll = tagged ?? collection ?? table ?? app.scrollViews.allElementsBoundByIndex.last { $0.isHittable }
            if let scroll { scroll.swipeUp() } else { app.swipeUp() }
        }
    }

    private func dismissActivity(in app: XCUIApplication) {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 8), close.isHittable { close.tap(); return }
        let localized = app.buttons["Đóng"]
        if localized.exists && localized.isHittable { localized.tap(); return }
        // The system activity sheet also supports the standard modal dismissal gesture.
        app.swipeDown()
    }

    private func assertRow(_ id: String, contains text: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), id)
        let visible = row.label + " " + String(describing: row.value ?? "") + " " + row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(visible.contains(text), "\(id): \(visible)")
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        waitUntil(app.keyboards.firstMatch, in: app) { !$0.exists || !$0.isHittable }
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
