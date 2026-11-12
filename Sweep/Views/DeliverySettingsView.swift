import SwiftUI
import UniformTypeIdentifiers

struct DeliverySettingsView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var fee = ""
    @State private var company = ""
    @State private var account = ""
    var body: some View {
        Form {
            Section("Công phiếu ký nhận") {
                MoneyInput(title: "Mức công / phiếu", text: $fee)
                Text("Chỉ áp dụng cho lần ký mới. Các phiếu đã ký giữ mức công cũ.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Tài khoản nhận của công ty") {
                TextField("Tên công ty", text: $company)
                TextField("Ngân hàng · STK · Chủ tài khoản", text: $account, axis: .vertical).lineLimit(3...6)
                Text("Nhập đúng tài khoản công ty trước khi đưa khách. Sweep dùng ảnh QR Sếp cung cấp.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Lưu cấu hình") {
                do {
                    let amount = try VND.parse(fee)
                    if store.change({ ledger in
                        let old = ledger.settings
                        ledger.settings.fee = amount; ledger.settings.company = company; ledger.settings.account = account
                        ledger.record("Cấu hình giao hàng", "Công \(old.fee) → \(amount); công ty \(old.company) → \(company); tài khoản \(old.account) → \(account)")
                    }) { store.message = "Đã lưu cấu hình. Phiếu đã ký giữ nguyên mức công." }
                } catch { store.message = error.localizedDescription }
            }
            Section("Ảnh QR công ty") {
                if let qr = store.ledger.settings.qr { EvidenceThumbnail(url: store.url(qr), height: 240) }
                EvidencePicker(title: "Lưu / thay ảnh QR") { url in await store.attach(url, role: .companyQR, to: nil) }
                NavigationLink("Xem màn hình đưa khách") { BankCompanyView() }
            }
        }
        .navigationTitle("Cấu hình giao hàng").navigationBarTitleDisplayMode(.inline)
        .onAppear { fee = String(store.ledger.settings.fee); company = store.ledger.settings.company; account = store.ledger.settings.account }
        .disabled(store.busy)
    }
}

struct DeliveryBackupView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var importing = false
    @State private var loading = false
    @State private var prepared: DeliveryBackup.Prepared?
    @State private var sharing: DeliveryShare?
    @State private var confirm = false
    var body: some View {
        Form {
            Section("Sao lưu sổ và toàn bộ chứng từ") {
                LabeledContent("Hồ sơ", value: "\(store.ledger.orders.count)")
                LabeledContent("Ảnh bền vững", value: "\(store.ledger.allEvidence.count)")
                Button("Xuất bản sao lưu đầy đủ") { Task { if let url = await store.exportBackup() { sharing = DeliveryShare(items: [url]) } } }
                Text("Chọn Lưu vào Tệp trong bảng chia sẻ, rồi chọn nơi Sếp giữ bản sao. Bản sao gồm thông tin khách và ảnh; giữ ở nơi Sếp quản lý.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Khôi phục từ .sweepbackup") {
                Button("Chọn bản sao lưu để kiểm tra") { importing = true }
                if loading || store.busy { ProgressView("Đang kiểm tra dữ liệu và ảnh…") }
                if let prepared {
                    Text("Đã kiểm tra \(prepared.ledger.orders.count) hồ sơ và \(prepared.ledger.allEvidence.count) ảnh, đúng hash.")
                    Button("Thay sổ hiện tại bằng bản đã kiểm tra…", role: .destructive) { confirm = true }
                }
                Text("Khôi phục thay toàn bộ sổ, không gộp hai sổ. Sweep giữ một bản trước khôi phục trên máy; ảnh thiếu hoặc sai hash sẽ bị từ chối trước khi thay dữ liệu.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sao lưu và khôi phục").navigationBarTitleDisplayMode(.inline)
        .disabled(store.busy || loading)
        .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            Task {
                loading = true; defer { loading = false }
                if let old = prepared { try? FileManager.default.removeItem(at: old.staging); prepared = nil }
                do {
                    let source = try result.get()
                    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Restore-\(UUID().uuidString)", isDirectory: true)
                    prepared = try await Task.detached(priority: .utility) { try DeliveryBackup.prepare(source, staging: staging) }.value
                } catch { store.message = error.localizedDescription }
            }
        }
        .alert("Thay toàn bộ sổ hiện tại?", isPresented: $confirm) {
            Button("Khôi phục bản đã kiểm tra", role: .destructive) {
                Task { if let value = prepared, await store.restore(value) { try? FileManager.default.removeItem(at: value.staging); prepared = nil; store.message = "Đã khôi phục đầy đủ sổ và ảnh." } }
            }
            Button("Giữ sổ đang dùng", role: .cancel) {}
        } message: { Text("Sổ \(store.ledger.orders.count) hồ sơ hiện tại sẽ được thay bằng \(prepared?.ledger.orders.count ?? 0) hồ sơ của bản sao. Xuất bản hiện tại ra Tệp trước nếu Sếp cần giữ riêng.") }
        .onDisappear { if let prepared, !store.busy { try? FileManager.default.removeItem(at: prepared.staging) } }
    }
}
