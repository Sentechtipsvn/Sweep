import XCTest
@testable import SweepCore

final class AppGroupConfigurationTests: XCTestCase {
    func testAltStoreRemappingTakesPrecedenceOverOriginalGroup() {
        let mapped = "group.com.sentechtipsvn.sweep.TESTTEAM01"
        XCTAssertEqual(AppGroupConfiguration.identifiers(in: ["SweepAppGroupIdentifier": "group.com.sentechtipsvn.sweep", "ALTAppGroups": [mapped]]), [mapped])
    }
    func testNormalSigningKeepsConfiguredGroup() {
        XCTAssertEqual(AppGroupConfiguration.identifiers(in: ["SweepAppGroupIdentifier": "group.com.sentechtipsvn.sweep"]), ["group.com.sentechtipsvn.sweep"])
    }
    func testEmptyOrMalformedInjectedGroupsDoNotPretendOriginalGroupIsGranted() {
        let cases: [Any] = [[String](), "group.fake", ["../escape", "", "group.bad/name"]]
        for value in cases {
            XCTAssertTrue(AppGroupConfiguration.identifiers(in: ["SweepAppGroupIdentifier": "group.original", "ALTAppGroups": value]).isEmpty)
        }
    }
    func testAppAndExtensionChooseSameDeterministicGroups() {
        let groups = ["group.sweep.B", "group.sweep.A", "group.sweep.B"]
        let app = AppGroupConfiguration.identifiers(in: ["CFBundleIdentifier": "app.remapped", "ALTAppGroups": groups])
        let ext = AppGroupConfiguration.identifiers(in: ["CFBundleIdentifier": "app.remapped.share", "ALTAppGroups": Array(groups.reversed())])
        XCTAssertEqual(app, ["group.sweep.A", "group.sweep.B"]); XCTAssertEqual(app, ext)
    }
}
