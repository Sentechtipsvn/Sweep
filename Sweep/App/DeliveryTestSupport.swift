#if DEBUG
import UIKit

extension DeliveryStore {
    func installUITestFixture() {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing"), ledger.orders.isEmpty else { return }
        do {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
                ("PHIEU THU NGHIEM\nTEST-001\n2.165.000 VND" as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
            }
            let source = root.appendingPathComponent("fixture.png")
            try image.pngData()!.write(to: source)
            defer { try? FileManager.default.removeItem(at: source) }
            var order = DeliveryOrder(code: "TEST-001", customer: "Khách thử nghiệm", total: 2_165_000)
            for role in [EvidenceRole.invoice, .signature, .transfer] { order.evidence.append(try EvidenceFiles.importImage(source, role: role, directory: evidenceDirectory)) }
            _ = change { _ = try $0.insert(order) }
        } catch { message = error.localizedDescription }
    }
}

extension DeliveryStore {
    func installSharedUITestFixture() throws {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") else { return }
        let marker = root.appendingPathComponent("shared-fixture-sent")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let source = try billUITestResult().candidates[0].image!
        _ = try SharedInvoiceInbox.live().add(source)
        try Data().write(to: marker)
    }

    func billUITestResult() throws -> BillImportResult {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 800)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 800))
            ("Ngay 12 thang 11 nam 2026\nSo: TEST-7856\nDon vi: TIEM THU UI\nDia chi: 12 Duong Mau\nDien thoai: 0900000000\nDia chi giao hang: Truoc 10h\nTien hang: 2.165.000" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black])
        }
        let url = root.appendingPathComponent("bill-ui-invoice.png")
        try image.pngData()!.write(to: url)
        return BillImportResult(candidates: [BillCandidate(id: "bill:ui-fixture", filename: url.lastPathComponent, customer: "TIEM THU UI", total: 2_165_000, isLegacy: true, image: url)], warnings: [])
    }
}
#endif
