import XCTest

final class SweepUITests: XCTestCase {
    func testLaunchNavigationAndPermissionEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
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

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
