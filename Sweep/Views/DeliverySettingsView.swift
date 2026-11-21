import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DeliverySettingsView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var fee = ""
    @State private var company = ""
    @State private var account = ""
    @State private var bankID = ""
    @State private var accountNumber = ""
    @State private var accountName = ""
    var body: some View {
        Form {
            Section("Công phiếu ký nhận") {
                MoneyInput(title: "Mức công / phiếu", text: $fee)
                Text("Chỉ áp dụng cho lần ký mới. Các phiếu đã ký giữ mức công cũ.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Tài khoản nhận của công ty") {
                TextField("Tên công ty", text: $company)
                TextField("Ngân hàng · STK · Chủ tài khoản", text: $account, axis: .vertical).lineLimit(3...6)
                Text("Thông tin ghi chú cũ và ảnh QR được giữ nguyên. QR tự điền số tiền dùng tài khoản VietQR bên dưới.").font(.caption).foregroundStyle(.secondary)
            }
            Section("VietQR theo từng đơn") {
                TextField("Mã ngân hàng / BIN, ví dụ VCB hoặc 970436", text: $bankID).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("settings.bankID")
                TextField("Số tài khoản nhận tiền", text: $accountNumber).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("settings.accountNumber")
                TextField("Tên chủ tài khoản", text: $accountName).textInputAutocapitalization(.characters).accessibilityIdentifier("settings.accountName")
                Text("Lưu một lần, sau đó mở QR chuyển khoản trong từng đơn. Ưu tiên khoản còn lại; nếu đã ghi nhận đủ tiền, vẫn tạo lại được QR mà không đổi sổ.").font(.caption).foregroundStyle(.secondary)
                Text("Khi tạo QR, ngân hàng, số tài khoản, tên chủ tài khoản, số tiền và nội dung mã phiếu được gửi tới VietQR.io. Ảnh phiếu không được gửi. Tên chủ tài khoản do Sếp nhập, không phải kết quả xác minh từ ngân hàng.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Lưu cấu hình") {
                do {
                    let amount = try VND.parse(fee)
                    let fields = [bankID, accountNumber, accountName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    let qrAccount: VietQRAccount? = fields.allSatisfy(\.isEmpty) ? nil : VietQRAccount(bankID: fields[0], accountNumber: fields[1], accountName: fields[2])
                    try qrAccount?.validate()
                    if store.change({ ledger in
                        let old = ledger.settings
                        ledger.settings.fee = amount; ledger.settings.company = company; ledger.settings.account = account
                        ledger.settings.vietQR = qrAccount
                        ledger.record("Cấu hình giao hàng", "Công \(old.fee) → \(amount); công ty \(old.company) → \(company); tài khoản \(old.account) → \(account)")
                    }) { store.message = "Đã lưu cấu hình. Phiếu đã ký giữ nguyên mức công." }
                } catch { store.message = error.localizedDescription }
            }
            Section("Ảnh QR công ty") {
                if let qr = store.ledger.settings.qr { EvidenceThumbnail(url: store.url(qr), height: 240) }
                EvidencePicker(title: "Lưu / thay ảnh QR") { url, _ in await store.attach(url, role: .companyQR, to: nil) }
                NavigationLink("Xem màn hình đưa khách") { BankCompanyView() }
            }
        }
        .sendeliNavigationTitle("Cấu hình giao hàng").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fee = String(store.ledger.settings.fee); company = store.ledger.settings.company; account = store.ledger.settings.account
            bankID = store.ledger.settings.vietQR?.bankID ?? ""; accountNumber = store.ledger.settings.vietQR?.accountNumber ?? ""; accountName = store.ledger.settings.vietQR?.accountName ?? ""
        }
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
    @State private var exporting = BackupPart.all
    @State private var restoring = Set<BackupPart>()
    @State private var preview: URL?
    @State private var recoveries: [URL] = []
    var body: some View {
        Form {
            Section("Chọn dữ liệu sao lưu") {
                BackupPartPicker(available: BackupPart.all, selected: $exporting)
                LabeledContent("Hồ sơ", value: "\(store.ledger.orders.count)")
                LabeledContent("Ảnh bền vững", value: "\(store.ledger.allEvidence.count)")
                Button("Xuất bản sao lưu") { Task { if let url = await store.exportBackup(parts: exporting) { sharing = DeliveryShare(items: [url]) } } }.disabled(exporting.isEmpty)
                Text("Chọn Lưu vào Tệp trong bảng chia sẻ, rồi chọn nơi Sếp giữ bản sao. Chỉ các mục được chọn sẽ được ghi vào tệp.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Khôi phục từ .sweepbackup") {
                Button("Chọn bản sao lưu để kiểm tra") { importing = true }
                if loading || store.busy { ProgressView("Đang kiểm tra dữ liệu và ảnh…") }
                if let prepared {
                    Text("Đã kiểm tra \(prepared.ledger.orders.count) hồ sơ và \(prepared.ledger.allEvidence.count) ảnh, đúng hash.")
                    BackupPartPicker(available: prepared.parts, selected: $restoring)
                    Button("Khôi phục các mục đã chọn…") { confirm = true }.disabled(restoring.isEmpty)
                }
                Text("Vị trí, danh bạ, công lương và đơn đã chọn sẽ thay mục tương ứng. Nếu chỉ chọn ảnh, ảnh được bổ sung vào đơn trùng ID. Ảnh còn lại có thể mở bên dưới.").font(.caption).foregroundStyle(.secondary)
            }
            if let photos = store.ledger.unfiledPhotos, !photos.isEmpty {
                Section("Ảnh khôi phục chưa gắn đơn") {
                    ForEach(photos, id: \.evidence.id) { photo in
                        Button { preview = store.url(photo.evidence) } label: {
                            HStack { EvidenceThumbnail(url: store.url(photo.evidence), height: 56).frame(width: 68)
                                Text(photo.evidence.role.rawValue) }
                        }
                    }
                }
            }
            if !recoveries.isEmpty {
                Section("Bản giữ trước các lần khôi phục") {
                    ForEach(recoveries, id: \.self) { url in
                        Button { sharing = DeliveryShare(items: [url]) } label: {
                            Label("Xuất bản lưu trước thay đổi · \(url.lastPathComponent.dropFirst(15).prefix(8))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
        .sendeliNavigationTitle("Sao lưu và khôi phục").navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .disabled(store.busy || loading)
        .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            Task {
                loading = true; defer { loading = false }
                if let old = prepared { try? FileManager.default.removeItem(at: old.staging); prepared = nil }
                do {
                    let source = try result.get()
                    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Restore-\(UUID().uuidString)", isDirectory: true)
                    let archive = try await Task.detached(priority: .utility) { try DeliveryBackup.prepare(source, staging: staging) }.value
                    prepared = archive; restoring = archive.parts
                } catch CocoaError.userCancelled { } catch { store.message = error.localizedDescription }
            }
        }
        .alert("Khôi phục các mục đã chọn?", isPresented: $confirm) {
            Button("Khôi phục bản đã kiểm tra", role: .destructive) {
                Task { if let value = prepared, await store.restore(value, parts: restoring) { try? FileManager.default.removeItem(at: value.staging); prepared = nil; refreshRecoveries() } }
            }
            Button("Giữ sổ đang dùng", role: .cancel) {}
        } message: {
            Text(BackupPart.allCases.filter(restoring.contains).map(\.title).joined(separator: " · ") + ". Sendeli giữ một bản sổ trước khi khôi phục.")
        }
        .onAppear { refreshRecoveries() }
    }
    private func refreshRecoveries() {
        recoveries = ((try? FileManager.default.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("Before-") && $0.pathExtension == "sweepbackup" }
    }
}

private struct BackupPartPicker: View {
    let available: Set<BackupPart>
    @Binding var selected: Set<BackupPart>
    var body: some View {
        Button(selected == available ? "Bỏ chọn tất cả" : "Chọn tất cả") {
            selected = selected == available ? [] : available
        }
        ForEach(BackupPart.allCases.filter(available.contains), id: \.self) { part in
            Button {
                if !selected.contains(part) {
                    selected.insert(part)
                    if part == .orders { selected.insert(.photos) }
                } else {
                    selected.remove(part)
                    if part == .photos { selected.remove(.orders) }
                }
            } label: {
                HStack {
                    Text(part.title)
                    Spacer()
                    Image(systemName: selected.contains(part) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(part) ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(selected.contains(part) ? "Đã chọn" : "Chưa chọn")
            .accessibilityIdentifier("backup.part." + part.rawValue)
        }
    }
}
