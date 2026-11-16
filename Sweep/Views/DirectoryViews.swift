import SwiftUI
import MapKit
import CoreLocation
import ContactsUI
import PhotosUI
import Vision

func openGoogleMaps(_ destination: String) {
    guard let native = DeliveryDirections.googleMaps(address: destination), let web = DeliveryDirections.googleMaps(address: destination, native: false) else { return }
    UIApplication.shared.open(UIApplication.shared.canOpenURL(native) ? native : web)
}
struct ZaloContactButton: View {
    let phone: String
    var savedLink = ""
    var title = "Zalo"
    var compact = false
    @State private var showFallback = false
    private var destination: URL? { ContactLinks.zalo(savedLink) ?? ContactLinks.zaloPhoneCandidate(phone) }
    var body: some View {
        if let destination {
            Button {
                UIApplication.shared.open(destination, options: [.universalLinksOnly: true]) { opened in
                    if !opened { showFallback = true }
                }
            } label: {
                if compact { Text("Zalo").font(.system(size: 11, weight: .semibold)).frame(width: 44, height: 44).background(Color.blue.opacity(0.12), in: Circle()).accessibilityLabel("Zalo") }
                else { Text(title) }
            }.buttonStyle(SendeliZaloStyle(compact: compact)).accessibilityIdentifier("contact.zalo")
                .alert("Chưa mở được liên hệ Zalo", isPresented: $showFallback) {
                    Button("Mở liên kết bằng trình duyệt") { UIApplication.shared.open(destination) }
                    if !phone.isEmpty { Button("Sao chép số") { UIPasteboard.general.string = phone } }
                    Button("Đóng", role: .cancel) {}
                } message: {
                    Text("Liên kết theo số có thể bị Zalo hoặc quyền riêng tư của người nhận giới hạn. Sếp có thể tìm bằng số hoặc lưu link từ QR của đúng người.")
                }
        }
    }
}
private struct DirectoryHeading: View {
    let title: String
    let kind: String
    let edit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var editLabel: some View {
        HStack(spacing: 2) {
            Text(kind).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
            Button(action: edit) { Image(systemName: "pencil").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Sửa " + title)
        }
    }
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); editLabel }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                editLabel
            }
        }
    }
}
private struct ContactDraft: Identifiable {
    var id = UUID()
    var contact: DeliveryContact?
    var name = ""
    var phone = ""
}
struct ContactsView: View {
    var editable = false
    var seller: String? = nil
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    @State private var draft: ContactDraft?
    @State private var picker = false
    @State private var picked: ContactDraft?
    private var contacts: [DeliveryContact] {
        let all = store.ledger.contacts ?? []
        guard let seller else { return all }
        let matches = all.filter { $0.matches(seller) }
        return matches.isEmpty ? all.filter { $0.role == "Bán hàng" } : matches
    }
    var body: some View {
        List {
            if seller != nil { Text("Chọn đúng người bán hàng trên phiếu để liên hệ.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(contacts.filter { query.isEmpty || ($0.name + $0.phone + $0.aliases).localizedStandardContains(query) }) { contact in
                VStack(alignment: .leading, spacing: 8) {
                    DirectoryHeading(title: contact.name, kind: contact.role) { draft = ContactDraft(contact: contact) }
                    HStack(spacing: 8) {
                        Text(contact.phone).font(.subheadline).textSelection(.enabled)
                        Spacer(minLength: 4)
                        SweepCallButton(phone: contact.phone)
                        ZaloContactButton(phone: contact.phone, savedLink: contact.zalo, compact: true)
                    }
                }.padding(.vertical, 2)
                .contextMenu {
                    if !contact.phone.isEmpty { Button("Sao chép số", systemImage: "doc.on.doc") { UIPasteboard.general.string = contact.phone } }
                    Button("Sửa liên hệ", systemImage: "pencil") { draft = ContactDraft(contact: contact) }
                }
            }
            if contacts.isEmpty { Text("Chưa có liên hệ. Chọn từ Danh bạ hoặc thêm thủ công.").foregroundStyle(.secondary) }
        }.navigationTitle("Liên hệ nhanh").searchable(text: $query, prompt: "Tên, số điện thoại")
            .toolbar {
                Menu {
                    Button("Chọn từ Danh bạ", systemImage: "person.crop.circle.badge.plus") { picker = true }
                    Button("Nhập thủ công", systemImage: "square.and.pencil") { draft = ContactDraft() }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Thêm liên hệ")
            }
            .sheet(isPresented: $picker, onDismiss: { if let picked { draft = picked; self.picked = nil } }) {
                SweepContactPicker(select: { name, phone in picked = ContactDraft(name: name, phone: phone); picker = false }, cancel: { picker = false })
            }
            .sheet(item: $draft) { value in
                NavigationStack { ContactEditor(contact: value.contact, initialName: value.name, initialPhone: value.phone) }
            }
    }
}
struct ContactEditor: View {
    var contact: DeliveryContact? = nil
    var initialName = ""
    var initialPhone = ""
    var role = "Bán hàng"
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var zalo = ""
    @State private var aliases = ""
    @State private var kind = "Bán hàng"
    @State private var remove = false
    @State private var duplicate: DeliveryContact?
    @State private var confirmDuplicate = false
    @State private var qr: PhotosPickerItem?
    @State private var qrCandidate = ""
    @State private var confirmQR = false
    @State private var readingQR = false
    var body: some View {
        Form {
            Section {
                TextField("Tên", text: $name)
                TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                Picker("Nhóm", selection: $kind) { ForEach(["Bán hàng", "Tài xế", "Chành xe", "Khác"], id: \.self) { Text($0) } }
                TextField("Mã trên phiếu, ví dụ TEL", text: $aliases)
                Text("Nhiều mã cách nhau bằng dấu phẩy. Không dùng số khách để liên hệ bán hàng.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Zalo · không bắt buộc") {
                    ZaloContactButton(phone: phone, savedLink: zalo, title: "Thử mở Zalo")
                    TextField("Dán liên kết Zalo nếu có", text: $zalo).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PhotosPicker(selection: $qr, matching: .images, preferredItemEncoding: .compatible) { Label("Đọc QR Zalo từ ảnh", systemImage: "qrcode") }.disabled(readingQR)
                    if readingQR { ProgressView("Đang đọc QR…") }
                    if !phone.isEmpty { Button("Sao chép số để tìm trong Zalo") { UIPasteboard.general.string = phone } }
                    Text("Thử mở bằng số điện thoại; nếu không đúng người, dùng liên kết từ QR hoặc sao chép số để tìm. QR được xem trước khi lưu.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Lưu liên hệ") { saveCheckingDuplicate() }.buttonStyle(SweepPill(selected: true))
            if let contact { Button("Xoá liên hệ", role: .destructive) { remove = true }
                .alert("Xoá \(contact.name)?", isPresented: $remove) {
                    Button("Xoá", role: .destructive) { if store.change({ $0.contacts?.removeAll { $0.id == contact.id } }) { dismiss() } }
                    Button("Huỷ", role: .cancel) {}
                }
            }
        }.navigationTitle(contact == nil ? "Thêm liên hệ" : "Sửa liên hệ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Xong") { dismiss() } } }
            .onAppear { name = contact?.name ?? initialName; phone = contact?.phone ?? initialPhone; zalo = contact?.zalo ?? ""; aliases = contact?.aliases ?? ""; kind = contact?.role ?? role }
            .alert("Số này đã có trong Sendeli", isPresented: $confirmDuplicate) {
                Button("Cập nhật liên hệ đã có") { persist(replacing: duplicate) }
                Button("Giữ thành người riêng") { persist(replacing: nil) }
                Button("Hủy", role: .cancel) {}
            } message: { Text(duplicate?.name ?? "") }
            .alert("Dùng liên kết QR này?", isPresented: $confirmQR) {
                Button("Dùng liên kết") { zalo = qrCandidate }
                Button("Hủy", role: .cancel) {}
            } message: { Text(qrCandidate) }
            .onChange(of: qr) { _, item in
                guard let item else { return }
                Task {
                    readingQR = true; defer { readingQR = false; qr = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), data.count <= 80 * 1024 * 1024 else { throw DeliveryError.invalid("Chưa tải được ảnh QR hoặc ảnh quá lớn.") }
                        let values = try await Task.detached(priority: .userInitiated) {
                            let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                            try VNImageRequestHandler(data: data).perform([request])
                            return (request.results ?? []).compactMap(\.payloadStringValue).filter { ContactLinks.zalo($0) != nil }
                        }.value
                        guard Set(values).count == 1, let first = values.first else { throw DeliveryError.invalid("Ảnh cần có một QR liên kết Zalo hợp lệ. Sếp chọn lại ảnh hoặc dán link.") }
                        qrCandidate = first; confirmQR = true
                    } catch { store.message = error.localizedDescription }
                }
            }
    }
    private func saveCheckingDuplicate() {
        let key = ContactLinks.phoneKey(phone)
        duplicate = (store.ledger.contacts ?? []).first { $0.id != contact?.id && !key.isEmpty && ContactLinks.phoneKey($0.phone) == key }
        if duplicate != nil { confirmDuplicate = true } else { persist(replacing: nil) }
    }
    private func persist(replacing other: DeliveryContact?) {
        let value = DeliveryContact(id: other?.id ?? contact?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), zalo: other != nil && zalo.isEmpty ? other!.zalo : zalo.trimmingCharacters(in: .whitespacesAndNewlines), aliases: other != nil && aliases.isEmpty ? other!.aliases : aliases, role: kind)
        if store.change({ try $0.saveContact(value) }) { dismiss() }
    }
}
private stru…21343 tokens truncated…illInboxView: View {
    let saved: (UUID) -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var folderPicker = false
    @State private var lease: BillFolderLease?
    @State private var selected: BillCandidate?
    @State private var importedID: UUID?
    @State private var result: BillImportResult?
    @State private var loading = false
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Chọn SenTechTips_AnhDonHang") { folderPicker = true }
                    Text("Trong Tệp: iCloud Drive → Shortcuts → SenTechTips_AnhDonHang. Sendeli chỉ đọc, giữ sổ và ảnh bên Bill nguyên trạng. Mỗi hồ sơ được xem trước rồi Sếp xác nhận nhập.").font(.footnote).foregroundStyle(.secondary)
                    if loading { ProgressView("Đang đọc gói Bill…") }
                }
                if let result {
                    Section("\(result.candidates.count) hồ sơ tìm thấy · \(result.candidates.filter { item in store.ledger.orders.contains { $0.sourceID == item.id } }.count) đã nhập") {
                        Text("Đây là danh sách xem trước. Chạm một hồ sơ, kiểm tra thông tin rồi bấm Nhập đơn vào Sendeli.").font(.footnote).foregroundStyle(.secondary)
                        ForEach(result.candidates.filter { query.isEmpty || ($0.customer + " " + $0.filename).localizedStandardContains(query) }) { item in
                            if let old = store.ledger.orders.first(where: { $0.sourceID == item.id }) {
                                Button { saved(old.id) } label: { Label("\(item.customer) · đã nhập, mở lại", systemImage: "checkmark.circle") }.accessibilityIdentifier("bill.existing.\(item.id)")
                            } else {
                                Button { selected = item } label: {
                                    VStack(alignment: .leading) { Text(item.customer); Text(VND.format(item.total)).font(.caption).foregroundStyle(.secondary) }
                                }.accessibilityIdentifier("bill.candidate.\(item.id)")
                            }
                        }
                    }
                    if !result.warnings.isEmpty {
                        Section("\(result.warnings.count) mục cần kiểm tra") { ForEach(Array(result.warnings.prefix(30).enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) } }
                    }
                    if result.candidates.isEmpty { Text("Chưa có gói đọc được. Tải thư mục về máy trong Tệp rồi chọn lại.") }
                }
            }.searchable(text: $query, prompt: "Tìm trong gói Bill")
                .sheet(item: $selected, onDismiss: {
                    if let id = importedID { importedID = nil; saved(id) }
                }) { item in
                    OrderIntakeView(candidate: item) { id in importedID = id; selected = nil }
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--bill-ui-testing"), result == nil {
                        do { result = try store.billUITestResult() } catch { store.message = error.localizedDescription }
                    }
                    #endif
                }
                .navigationTitle("Nhập từ Bill").navigationBarTitleDisplayMode(.inline)
                .toolbar { CloseSheet { dismiss() } }
                .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { selection in
                    Task {
                        loading = true; defer { loading = false }
                        do {
                            let access = BillFolderLease(try selection.get()); lease = access
                            let root = access.url
                            result = try await Task.detached(priority: .userInitiated) { try BillImport.scan(root) }.value
                        } catch { store.message = error.localizedDescription }
                    }
                }
        }
    }
}
