import XCTest
@testable import SweepCore

final class FieldUpdateTests: XCTestCase {
    func testCustomerLabelsKeepTheOriginalAndUnbalancedNames() {
        var order = DeliveryOrder(code: "T", customer: "BÁNH AN AN ( HKD ĐOÀN VĂN LUẬT )", total: 1)
        XCTAssertEqual(order.displayCustomer, "BÁNH AN AN")
        XCTAssertTrue(order.customer.contains("HKD"))
        for full in ["(An An)", "Nhà (Chi nhánh) Quận 1", "Nhà (An"] {
            order.customer = full
            XCTAssertEqual(order.displayCustomer, full)
        }
        order.customer = "Tiệm (HKD (A)) (B)"
        XCTAssertEqual(order.displayCustomer, "Tiệm")
    }
    func testOnlyCompletedZaloActivityQualifiesForCleanup() {
        let zalo = "vn.com.vng.zingalo.Share"
        XCTAssertTrue(ReportShareResult.sentToZalo(activity: zalo, completed: true, failed: false))
        for target in [nil, "com.apple.UIKit.activity.CopyToPasteboard", "vn.com.vng.zingalo-other.share"] as [String?] {
            XCTAssertFalse(ReportShareResult.sentToZalo(activity: target, completed: true, failed: false))
        }
        XCTAssertFalse(ReportShareResult.sentToZalo(activity: zalo, completed: false, failed: false))
        XCTAssertFalse(ReportShareResult.sentToZalo(activity: zalo, completed: true, failed: true))
    }
    func testSavedMapLinksRoundTripAndOldCoordinatesRemainUsable() throws {
        let original = DeliveryPlace(customer: "Tiệm", phone: "", address: "Đường A", kind: "Khách hàng", latitude: 10.75, longitude: 106.66)
        let old = try JSONDecoder().decode(DeliveryPlace.self, from: JSONEncoder().encode(original))
        XCTAssertNil(old.mapLink)
        XCTAssertEqual(old.destination, "10.75,106.66")
        XCTAssertNotNil(PlaceMapLink.url(old.editableMapLink))
        for text in ["https://maps.app.goo.gl/abc123", "https://www.google.com/maps/place/shop/@12,105,15z/data=!3d10.75!4d106.66", "https://maps.apple.com/?ll=10,106&q=Shop"] {
            var ledger = DeliveryLedger()
            let place = DeliveryPlace(customer: "Tiệm", phone: "", address: "Đường A", kind: "Khách hàng", mapLink: text)
            try ledger.savePlace(place)
            let backup = try ledger.selectedBackup([.places])
            let restored = try DeliveryLedger().restoring(backup, parts: [.places])
            XCTAssertEqual(restored.places?.first?.destination, text)
            XCTAssertEqual(restored.places?.first?.editableMapLink, text)
        }
        for text in ["", "javascript:alert(1)", "https://example.org", "https://www.google.com/url?q=test", "https://maps.app.goo.gl.evil.example/test", "https://goo.gl/maps/"] {
            XCTAssertNil(PlaceMapLink.url(text))
        }
    }
    func testWorkHolidaysUseVietnameseLunarDatesAndCompanySunday() throws {
        let c = DeliveryMonth.calendar
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { c.date(from: DateComponents(year: y, month: m, day: d, hour: 8))! }
        let ledger = DeliveryLedger()
        for (m,d) in [(1,1),(2,4),(2,6),(2,7),(2,8),(2,9),(4,16),(4,30),(5,1),(9,2)] {
            XCTAssertFalse(AttendanceReminderPolicy.needsEntry(ledger, at: day(2027,m,d)), "\(m)/\(d)")
        }
        XCTAssertTrue(AttendanceReminderPolicy.needsEntry(ledger, at: day(2027,2,10)))
        XCTAssertFalse(AttendanceReminderPolicy.needsEntry(ledger, at: day(2026,4,27))) // Sunday Giỗ Tổ on 26/4
        XCTAssertTrue(AttendanceReminderPolicy.needsEntry(ledger, at: day(2027,4,17)))
        XCTAssertTrue(AttendanceReminderPolicy.dates(ledger, now: day(2027,4,15)).allSatisfy { $0 > day(2027,4,15) })
    }
    func testSelectiveBackupPreservesUnselectedRecordsAndPhotoOnlyIsIdempotent() throws {
        var source = DeliveryLedger()
        var order = DeliveryOrder(code: "123", customer: "Tiệm", total: 999)
        let photo = DeliveryEvidence(role: .invoice, filename: UUID().uuidString + ".jpg", sha256: String(repeating: "a", count: 64), bytes: 4)
        order.evidence = [photo]
        source.orders = [order]
        let place = DeliveryPlace(customer: "Tiệm", phone: "", address: "Đường A", kind: "Khách hàng")
        try source.savePlace(place)
        let places = try source.selectedBackup([.places])
        XCTAssertTrue(places.orders.isEmpty); XCTAssertTrue(places.allEvidence.isEmpty); XCTAssertTrue(places.audit.isEmpty)
        var live = DeliveryLedger()
        let contact = DeliveryContact(name: "N", phone: "", zalo: "", aliases: "", role: "Bán hàng")
        try live.saveContact(contact)
        var result = try live.restoring(places, parts: [.places])
        XCTAssertEqual(result.contacts, live.contacts); XCTAssertEqual(result.places, [place])
        let images = try source.selectedBackup([.photos])
        XCTAssertTrue(images.orders.isEmpty); XCTAssertNil(images.places)
        result = try result.restoring(images, parts: [.photos])
        XCTAssertEqual(result.unfiledPhotos?.first?.evidence, photo)
        XCTAssertEqual(try result.restoring(images, parts: [.photos]), result)
        order.evidence = []; live.orders = [order]
        XCTAssertEqual(try live.restoring(images, parts: [.photos]).orders.first?.evidence, [photo])
        XCTAssertThrowsError(try source.selectedBackup([.orders]))
    }
}
