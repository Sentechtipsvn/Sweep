#if DEBUG
import UIKit
import AppIntents

extension DeliveryStore {
    func installUpdate02UITestFixture() {
        guard ledger.contacts?.isEmpty != false else { return }
        _ = change { ledger in
            try ledger.saveContact(DeliveryContact(name: "Liên hệ thử 01", phone: "0900000001", zalo: "", aliases: "TEL", role: "Bán hàng"))
            try ledger.saveContact(DeliveryContact(name: "Liên hệ thử 02", phone: "0900000002", zalo: "", aliases: "", role: "Tài xế"))
            try ledger.savePlace(DeliveryPlace(customer: "Điểm giao thử", phone: "0900000003", address: "Địa chỉ thử nghiệm", kind: "Khách hàng"))
        }
    }
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
    func installReminderUITestFixture() {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing"),
              let first = ledger.orders.first, first.settlement == nil,
              let invoice = first.evidence.first else { return }
        _ = change { ledger in
            var freight = DeliveryOrder(code: "TEST-FREIGHT", customer: "Khách giao chành", total: 1_500_000)
            freight.evidence = [try EvidenceFiles.importImage(url(invoice), role: .invoice, directory: evidenceDirectory)]
            let freightID = try ledger.insert(freight)
            for (id, route) in [(first.id, DeliveryRoute.transferLater), (freightID, .freight)] {
                let index = ledger.orders.firstIndex { $0.id == id }!
                for role in [EvidenceRole.signature, .freightSignature, .goods] where !ledger.orders[index].activeEvidence.contains(where: { $0.role == role }) {
                    ledger.orders[index].evidence.append(try EvidenceFiles.importImage(url(invoice), role: role, directory: evidenceDirectory))
                }
                try ledger.sign(id, at: Date())
                try ledger.settle(id, value: Settlement(outcome: .delivered, mode: .deferred, cash: 0, bank: 0, note: "", at: Date(), route: route))
                let order = ledger.orders[index]
                let report = try ledger.prepareReport(id, text: order.shareText(), evidenceIDs: order.defaultShareEvidenceIDs)
                try ledger.acknowledgeReport(id, reportID: report.id)
            }
            try ledger.markAttendance(Date(), state: .work)
        }
    }
    func installMonthlyUITestFixture() {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing"), let order = ledger.orders.first, order.settlement == nil else { return }
        _ = change { ledger in
            try ledger.sign(order.id, at: Date())
            try ledger.settle(order.id, value: Settlement(outcome: .delivered, mode: .mixed, cash: 665_000, bank: 1_500_000, note: "", at: Date(), route: .transferNow))
            try ledger.handover(500_000, at: Date(), note: "UI test monthly remittance")
        }
    }

    func installQRUITestFixture() {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing"), let order = ledger.orders.first else { return }
        _ = change { ledger in
            // Official VietQR documentation's public example; never part of a Release build.
            ledger.settings.vietQR = VietQRAccount(bankID: "ICB", accountNumber: "113366668888", accountName: "PUBLIC DEMO ACCOUNT")
            try ledger.sign(order.id, at: Date())
            try ledger.settle(order.id, value: Settlement(outcome: .delivered, mode: .bank, cash: 0, bank: order.total, note: "UI test: recorded transfer", at: Date(), route: .transferNow))
        }
    }

    func installSharedUITestFixture() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--delivery-ui-testing") else { return }
        let marker = root.appendingPathComponent("shared-fixture-sent")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try Data().write(to: marker)
        do {
            let source = try billUITestResult().candidates[0].image
            if ProcessInfo.processInfo.arguments.contains("--shortcut-file") || ProcessInfo.processInfo.arguments.contains("--shortcut-bytes") {
                var intent = ReceiveSweepInvoice()
                if ProcessInfo.processInfo.arguments.contains("--shortcut-file") {
                    intent.image = IntentFile(fileURL: source)
                } else {
                    intent.image = IntentFile(data: try Data(contentsOf: source), filename: "phieu.png", type: .png)
                }
                _ = try await intent.perform()
                return
            }
            guard let image = UIImage(contentsOfFile: source.path) else { throw DeliveryError.invalid("Không mở được ảnh mẫu UI.") }
            let received = try await SharedInvoiceLoader.load(from: NSItemProvider(item: image, typeIdentifier: "public.image"))
            defer { try? FileManager.default.removeItem(at: received) }
            _ = try SharedInvoiceInbox.live().add(received)
        } catch { try? FileManager.default.removeItem(at: marker); throw error }
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
