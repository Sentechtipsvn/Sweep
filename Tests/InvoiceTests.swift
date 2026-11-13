import XCTest
import Foundation
import CryptoKit
import CoreGraphics
import CoreText
import ImageIO
@testable import SweepCore

final class InvoiceTests: XCTestCase {
    private let text = """
    Ngày 12 tháng 11 năm 2026
    Số : 7856
    Người mua hàng :    NV bán hàng : NHÂN VIÊN THỬ
    Đơn vị : BÁNH THỬ NGHIỆM    Điện thoại : 0900000000
    Địa chỉ : 12 Đường Mẫu, TP HCM
    Địa chỉ giao hàng : Trước 10h sáng
    Tên hàng hóa Số lượng Thành tiền
    Mặt hàng mẫu 1 2.200.000
    Chiết khấu -64.000
    Tiền hàng 2.200.000
    Tổng thanh toán: 2.136.000
    """
    func testHeaderLabelsKeepVietnameseAndNeverUseSalespersonAsCustomer() throws {
        let fields = InvoiceParser.parse(text)
        XCTAssertEqual(fields.code, "7856")
        XCTAssertEqual(fields.customer, "BÁNH THỬ NGHIỆM")
        XCTAssertEqual(fields.address, "12 Đường Mẫu, TP HCM")
        XCTAssertEqual(fields.phone, "0900000000")
        XCTAssertEqual(fields.deliveryNote, "Trước 10h sáng")
        XCTAssertEqual(fields.total, 2_136_000)
        XCTAssertNotNil(fields.invoiceDate)
        XCTAssertEqual(InvoiceParser.parse(text.decomposedStringWithCanonicalMapping), fields)
    }
    func testUnaccentedOCRAndSplitRows() {
        let f = InvoiceParser.parse("So: AB-123\nDon vi:\nTIEM THU\nDia chi: 12 Duong Mau\nDia chi giao hang: Sau 9h\nDien thoai: +84 900 000 000\nTien hang\n1.000.000")
        XCTAssertEqual(f.customer, "TIEM THU"); XCTAssertEqual(f.code, "AB-123")
        XCTAssertEqual(f.total, 1_000_000); XCTAssertEqual(f.deliveryNote, "Sau 9h")
        XCTAssertEqual(f.phone, "+84900000000")
    }
    func testNeverInventTotalFromItemDiscountOrWords() {
        for value in ["-108.000", "1,25", "1O8.000", "Mười triệu đồng", "1.000.000  200.000"] {
            XCTAssertNil(InvoiceParser.parse("Tiền hàng: " + value).total)
        }
        let fields = InvoiceParser.parse("Số lượng: 10\nThành tiền\n5.000.000\nChiết khấu -108.000\nNV bán hàng: NGƯỜI BÁN")
        XCTAssertTrue(fields.code.isEmpty); XCTAssertTrue(fields.customer.isEmpty); XCTAssertNil(fields.total)
    }
    func testExtendedBillKeepsIdentityAndLegacyMoney() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let images = root.appendingPathComponent("Ảnh Đơn Hàng"), inbox = root.appendingPathComponent("Đơn mới")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = "20261112-123400000-123456"
        let id = SHA256.hash(data: Data("sen-bill-v1:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        let filename = "TIEM - 2.136.000 · \(key).png"
        try Data([0]).write(to: images.appendingPathComponent(filename))
        var record: [String: String] = ["id": id, "filename": filename, "name": "TIEM", "total": "2136000", "cash": "600000", "bank": "1000000"]
        try JSONSerialization.data(withJSONObject: ["_schema": "sen-orders-v3", id: record]).write(to: root.appendingPathComponent("orders.json"))
        record.merge(["schema": "sen-bill-v1", "version": "3.3.0", "imageKey": key, "invoiceCode": "7856", "address": "12 Đường Mẫu", "phone": "0900000000", "deliveryNote": "Trước 10h", "cash": "0", "bank": "0"]) { _, new in new }
        try JSONSerialization.data(withJSONObject: record).write(to: inbox.appendingPathComponent(id + ".json"))
        let result = try BillImport.scan(root)
        XCTAssertEqual(result.candidates.count, 1)
        let f = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(f.id, "bill:\(id)"); XCTAssertEqual(f.code, "7856")
        XCTAssertEqual(f.phone, "0900000000"); XCTAssertEqual(f.address, "12 Đường Mẫu")
        XCTAssertEqual(f.cash, 600_000); XCTAssertEqual(f.bank, 1_000_000)
        XCTAssertTrue(f.isLegacy); XCTAssertTrue(result.warnings.isEmpty)
    }
    func testNativeVisionReadsSyntheticInvoice() throws {
        // Exercise Vision itself on a locally drawn invoice, without publishing real customer images.
        let context = try XCTUnwrap(CGContext(data: nil, width: 1800, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let font = CTFontCreateWithName("Helvetica" as CFString, 34, nil)
        for (i, row) in text.split(separator: "\n").enumerated() {
            let attributed = NSAttributedString(string: String(row), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            context.textPosition = CGPoint(x: 50, y: CGFloat(930 - i * 65))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let f = try InvoiceOCR.read(url)
        XCTAssertEqual(f.code, "7856")
        XCTAssertEqual(f.total, 2_136_000)
        XCTAssertFalse(f.customer.isEmpty); XCTAssertFalse(f.address.isEmpty)
    }
}
