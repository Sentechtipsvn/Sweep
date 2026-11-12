import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct OrdersView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var filter = "Tất cả"
    @State private var allDates = true
    @State private var day = Date()
    @State private var newOrder = false
    @State private var bill = false
    private var visible: [DeliveryOrder] {
        store.ledger.orders.filter { order in
            let matches = query.isEmpty || (order.customer + " " + order.code + " " + order.phone).localizedStandardContains(query)
            let dateOK = allDates || Calendar.current.isDate(order.importedAt, inSameDayAs: day)
            let statusOK = filter == "Tất cả" || (filter == "Đang giao" && order.outcome != .delivered && order.voidReason == nil) || (filter == "Cần báo cáo" && order.reportNeeded)
            return matches && dateOK && statusOK
        }.sorted { $0.importedAt > $1.importedAt }
    }
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Bộ lọc", selection: $filter) { ForEach(["Tất cả", "Đang giao", "Cần báo cáo"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Toggle("Mọi ngày", isOn: $allDates)
                    if !allDates { DatePicker("Ngày nhập vào Sweep", selection: $day, displayedComponents: .date) }
                }
                if store.blocked { Text("Sổ chưa mở được. Dữ liệu cũ được giữ nguyên; xem thông báo lỗi.").foregroundStyle(.red) }
                else if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Chưa có đơn trong bộ lọc" : "Không tìm thấy đơn", systemImage: "shippingbox",
                        description: Text("Nhận phiếu từ Ảnh/Tệp hoặc nhập thư mục Bill. Đơn nháp chưa tính công."))
                }
                ForEach(visible) { order in
                    NavigationLink(value: order.id) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(order.customer).font(.headline); Spacer(); Text(VND.format(order.total)).font(.subheadline.bold()).monospacedDigit() }
                            Text(order.code).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(order.voidReason != nil ? "Đã hủy" : order.outcome.rawValue)
                                Spacer()
                                if !order.activeAssignments.isEmpty { Label("Đã tính công", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                                else { Text("Chưa tính công").foregroundStyle(.secondary) }
                            }.font(.caption)
                            if order.remaining > 0 { Text("Còn \(VND.format(order.remaining)) theo ghi nhận").font(.caption).foregroundStyle(.orange) }
                            if order.bank > order.verifiedBank { Text("CK chờ đối soát: \(VND.format(order.bank - order.verifiedBank))").font(.caption).foregroundStyle(.secondary) }
                            if !order.reviewNote.isEmpty { Label("Cần rà soát dữ liệu cũ", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("order.\(order.code)")
                }
            }
            .navigationTitle("Đơn hàng")
            .searchable(text: $query, prompt: "Tên khách, mã phiếu, số điện thoại")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { bill = true } label: { Label("Nhập Bill", systemImage: "tray.and.arrow.down") }.accessibilityIdentifier("orders.bill") }
                ToolbarItem(placement: .topBarTrailing) { Button { newOrder = true } label: { Label("Nhận đơn", systemImage: "plus") }.accessibilityIdentifier("orders.new") }
            }
            .navigationDestination(for: UUID.self) { OrderDetailView(id: $0) }
            .sheet(isPresented: $newOrder) { OrderIntakeView { id in newOrder = false; path.append(id) } }
            .sheet(isPresented: $bill) { BillInboxView { id in bill = false; path.append(id) } }
        }
    }
}

struct OrderIntakeView: View {
    var candidate: BillCandidate? = nil
    let saved: (UUID) -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var customer = ""
    @State private var total = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var hasInvoiceDate = false
    @State private var invoiceDate = Date()
    @State private var signed = false
    @State private var signedAt = Date()
    @State private var allowRepeatedImage = false
    @State private var image: ImportedImage?
    @State private var preview: URL?
    private var source: URL? { image?.url ?? candidate?.image }
    var body: some View {
        NavigationStack {
            Form {
                Section("Phiếu nội bộ có tiền") {
                    if let source { Button { preview = source } label: { EvidenceThumbnail(url: source, height: 220) }.buttonStyle(.plain) }
                    EvidencePicker(title: "Chọn hoặc chụp phiếu") { url in
                        do { image = try await Task.detached { try ImportedImage.copy(from: url) }.value }
                        catch { store.message = error.localizedDescription }
                    }
                    Text("Sweep giữ bản sao để mở offline. Kiểm tra thông tin với ảnh trước khi lưu.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Hồ sơ") {
                    TextField("Mã phiếu duy nhất", text: $code).textInputAutocapitalization(.characters).accessibilityIdentifier("intake.code")
                    TextField("Tên khách", text: $customer).accessibilityIdentifier("intake.customer")
                    MoneyInput(title: "Tổng đơn", text: $total, identifier: "intake.total")
                    TextField("Điện thoại (tùy chọn)", text: $phone).keyboardType(.phonePad)
                    TextField("Địa chỉ (tùy chọn)", text: $address)
                    Toggle("Có ngày trên hóa đơn", isOn: $hasInvoiceDate)
                    if hasInvoiceDate { DatePicker("Ngày hóa đơn", selection: $invoiceDate, displayedComponents: .date) }
                }
                Section("Công đi giao") {
                    Toggle("Đã ký nhận phiếu để đi giao", isOn: $signed).accessibilityIdentifier("intake.signed")
                    if signed { DatePicker("Ngày ký nhận", selection: $signedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                    Text("Xác nhận chữ ký của Sếp khi nhận việc, khác chữ ký khách nhận hàng. Mức hiện tại \(VND.format(store.ledger.settings.fee))/phiếu. Chưa ký thì lưu nháp, chưa tính công.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Đây là phiếu khác hợp lệ dù dùng lại ảnh", isOn: $allowRepeatedImage).font(.caption)
                }
                if let candidate {
                    Section("Xem trước dữ liệu Bill") {
                        Text("Gói \(candidate.id.dropFirst(5).prefix(12)) · \(candidate.isLegacy ? "sổ cũ" : "sen-bill-v1")")
                        if let date = candidate.createdAt { LabeledContent("Ngày lưu bên Bill", value: date.formatted(date: .numeric, time: .shortened)) }
                        LabeledContent("Tiền mặt giữ lại", value: VND.format(candidate.cash))
                        LabeledContent("CK khách báo giữ lại", value: VND.format(candidate.bank))
                        Text(candidate.note.isEmpty ? "Gói nhập không xác nhận ngày ký. Sếp kiểm tra trước khi tính công." : candidate.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(signed ? "Lưu và ghi công ký nhận" : "Lưu đơn nháp") { Task { await save() } }
                    .accessibilityIdentifier("intake.save").disabled(store.busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || total.isEmpty)
            }
            .navigationTitle("Nhận đơn").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .quickLookPreview($preview)
            .onAppear { if let candidate, customer.isEmpty { customer = candidate.customer; total = String(candidate.total) } }
            .disabled(store.busy)
        }
    }
    private func save() async {
        do {
            var order = DeliveryOrder(code: code.trimmingCharacters(in: .whitespacesAndNewlines), customer: customer.trimmingCharacters(in: .whitespacesAndNewlines), total: try VND.parse(total))
            order.phone = phone; order.address = address; order.invoiceAt = hasInvoiceDate ? invoiceDate : nil
            if let candidate {
                guard order.total >= candidate.cash + candidate.bank else { throw DeliveryError.invalid("Tổng sửa thấp hơn khoản thu cũ. Kiểm tra sổ trước khi nhập.") }
                order.sourceID = candidate.id; order.sourceCreatedAt = candidate.createdAt; order.sourceSnapshot = candidate.sourceSnapshot
                order.reviewNote = candidate.isLegacy ? candidate.note : ""
                if candidate.cash > 0 || candidate.bank > 0 || candidate.deliveredAt != nil {
                    let mode: PaymentMode = candidate.cash > 0 && candidate.bank > 0 ? .mixed : candidate.bank > 0 ? .bank : candidate.cash > 0 ? .cash : .none
                    order.settlements = [Settlement(outcome: candidate.deliveredAt == nil ? .pending : .delivered, mode: mode, cash: candidate.cash, bank: candidate.bank, note: candidate.note, at: candidate.deliveredAt ?? candidate.createdAt ?? Date())]
                }
            }
            if let id = await store.create(order, image: source, signedAt: signed ? signedAt : nil, allowRepeatedImage: allowRepeatedImage) { saved(id) }
        } catch { store.message = error.localizedDescription }
    }
}

private final class BillFolderLease {
    let url: URL
    let accessed: Bool
    init(_ url: URL) { self.url = url; accessed = url.startAccessingSecurityScopedResource() }
    deinit { if accessed { url.stopAccessingSecurityScopedResource() } }
}

struct BillInboxView: View {
    let saved: (UUID) -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var folderPicker = false
    @State private var lease: BillFolderLease?
    @State private var result: BillImportResult?
    @State private var loading = false
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Chọn thư mục Bill") { folderPicker = true }
                    Text("Trong Tệp: iCloud Drive → Shortcuts → SenTechTips_AnhDonHang. Sweep chỉ đọc, giữ sổ và ảnh bên Bill nguyên trạng. Mỗi hồ sơ được xem trước rồi Sếp xác nhận nhập.").font(.footnote).foregroundStyle(.secondary)
                    if loading { ProgressView("Đang đọc gói Bill…") }
                }
                if let result {
                    Section("\(result.candidates.count) hồ sơ tìm thấy") {
                        ForEach(result.candidates.filter { query.isEmpty || ($0.customer + " " + $0.filename).localizedStandardContains(query) }) { item in
                            if let old = store.ledger.orders.first(where: { $0.sourceID == item.id }) {
                                Button { saved(old.id) } label: { Label("\(item.customer) · đã nhập, mở lại", systemImage: "checkmark.circle") }
                            } else {
                                NavigationLink { OrderIntakeView(candidate: item, saved: saved) } label: {
                                    VStack(alignment: .leading) { Text(item.customer); Text(VND.format(item.total)).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    if !result.warnings.isEmpty {
                        Section("\(result.warnings.count) mục cần kiểm tra") { ForEach(Array(result.warnings.prefix(30).enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) } }
                    }
                    if result.candidates.isEmpty { Text("Chưa có gói đọc được. Tải thư mục về máy trong Tệp rồi chọn lại.") }
                }
            }.searchable(text: $query, prompt: "Tìm trong gói Bill")
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
