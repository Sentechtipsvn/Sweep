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
#endif
