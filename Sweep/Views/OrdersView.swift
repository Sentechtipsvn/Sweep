import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct OrdersView: View {
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = SharedInboxStore()
    @State private var sharedInbox = false
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var filter = "Tất cả"
    @State private var allDates = true
    @State private var day = Date()
    @State private var newOrder = false
    @State private var bill = false
    @State private var savedOrder: UUID?
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
                if !inbox.items.isEmpty {
                    Section {
                        Button { sharedInbox = true } label: { Label("\(inbox.items.count) ảnh được chia sẻ · nhận đơn", systemImage: "tray.and.arrow.down.fill") }.accessibilityIdentifier("orders.shared")
                    }
                }
                Section {
                    Picker("Bộ lọc", selection: $filter) { ForEach(["Tất cả", "Đang giao", "Cần báo cáo"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Toggle("Mọi ngày", isOn: $allDates)
                    if !allDates { DatePicker("Ngày nhập vào Sweep", selection: $day, displayedComponents: .date) }
                }
                if store.blocked { Text("Sổ chưa mở được. Dữ liệu cũ được giữ nguyên; xem thông báo lỗi.").foregroundStyle(.red) }
                else if visible.isEmpty {
                    VStack(spacing: 16) {
                        Label(query.isEmpty ? "Chưa có đơn đã lưu" : "Không tìm thấy đơn", systemImage: "shippingbox").font(.headline)
                        Text("Chia sẻ ảnh phiếu từ Zalo vào Sweep, hoặc chọn ảnh bằng nút +. Kho Bill cũ vẫn nhập được.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Nhập đơn từ Bill") { bill = true }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding(.vertical, 28)
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
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Ảnh được chia sẻ", systemImage: "tray.and.arrow.down") { sharedInbox = true }
                        Button("Nhập từ kho Bill", systemImage: "folder") { bill = true }.accessibilityIdentifier("orders.bill")
                    } label: { Label("Nhận ảnh", systemImage: "tray.and.arrow.down") }.accessibilityIdentifier("orders.receive").disabled(store.busy || store.blocked)
                }
                ToolbarItem(placement: .topBarTrailing) { Button { newOrder = true } label: { Label("Nhận đơn", systemImage: "plus") }.accessibilityIdentifier("orders.new").disabled(store.busy || store.blocked) }
            }
            .navigationDestination(for: UUID.self) { OrderDetailView(id: $0) }
            .sheet(isPresented: $newOrder, onDismiss: openSavedOrder) { OrderIntakeView { id in savedOrder = id; newOrder = false } }
            .sheet(isPresented: $bill, onDismiss: openSavedOrder) { BillInboxView { id in savedOrder = id; bill = false } }
            .sheet(isPresented: $sharedInbox, onDismiss: openSavedOrder) { SharedInboxView(inbox: inbox) { id in savedOrder = id; sharedInbox = false } }
            .task { await refreshInbox() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshInbox() } } }
        }
    }
    private func refreshInbox() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--shared-ui-testing") {
            do { try await store.installSharedUITestFixture() } catch { store.message = error.localizedDescription }
        }
        #endif
        await inbox.reload()
        if !inbox.items.isEmpty, !newOrder, !bill, !sharedInbox, !store.busy, !store.blocked { sharedInbox = true }
    }
    private func openSavedOrder() {
        guard let id = savedOrder else { return }
        savedOrder = nil; query = ""; filter = "Tất cả"; allDates = true
        path.append(id)
    }
}

struct OrderIntakeView: View {
    var candidate: BillCandidate? = nil
    var shared: SharedInvoiceInbox.Item? = nil
    let saved: (UUID) -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var customer = ""
    @State private var total = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var deliveryNote = ""
    @State private var initialized = false
    @State private var reading = false
    @State private var readingRequest = UUID()
    @State private var readingStatus = ""
    @State private var validation = ""
    @State private var duplicateID: UUID?
    @State private var hasInvoiceDate = false
    @State private var invoiceDate = Date()
    @State private var signed = false
    @State private var signedAt = Date()
    @State private var allowRepeatedImage = false
    @State private var image: ImportedImage?
    @State private var preview: URL?
    private var source: URL? { image?.url ?? shared?.image ?? candidate?.image }
    var body: some View {
        NavigationStack {
            Form {
                Section("Phiếu nội bộ có tiền") {
                    if let source { Button { preview = source } label: { EvidenceThumbnail(url: source, height: 220) }.buttonStyle(.plain) }
                    EvidencePicker(title: "Chọn hoặc chụp phiếu") { url in
                        do { image = try await Task.detached { try ImportedImage.copy(from: url) }.value }
                        catch { store.message = error.localizedDescription }
                    }
                    Text("Ảnh chưa được nhập vào sổ. Kiểm tra bên dưới rồi bấm Nhập đơn vào Sweep.").font(.caption).foregroundStyle(.secondary)
                    if reading { ProgressView("Đang đọc thông tin trên phiếu…") }
                    if !readingStatus.isEmpty { Text(readingStatus).font(.caption).foregroundStyle(.secondary) }
                    if let source { Button("Đọc lại thông tin còn thiếu từ ảnh") { Task { await readInvoice(source) } }.disabled(reading) }
                }
                Section("Hồ sơ") {
                    TextField("Mã cạnh “Số:” trên phiếu (bắt buộc)", text: $code).textInputAutocapitalization(.characters).accessibilityIdentifier("intake.code")
                    TextField("Tên tiệm tại “Đơn vị:”", text: $customer).accessibilityIdentifier("intake.customer")
                    MoneyInput(title: "Tổng đơn", text: $total, identifier: "intake.total")
                    TextField("Điện thoại trên phiếu (tùy chọn)", text: $phone).keyboardType(.phonePad)
                    if !phone.isEmpty { Text("Số in cạnh NV bán hàng có thể là nhân viên bán hàng. Xác minh trước khi gọi khách.").font(.caption).foregroundStyle(.orange) }
                    TextField("Địa chỉ (tùy chọn)", text: $address)
                    TextField("Ghi chú giao hàng / giờ hẹn", text: $deliveryNote)
                    Text("Mã phiếu, tên tiệm và tổng tiền là bắt buộc. OCR là gợi ý; đối chiếu ảnh trước khi nhập.").font(.caption).foregroundStyle(.secondary)
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
                if !validation.isEmpty {
                    Section {
                        Text(validation).foregroundStyle(.red)
                        if let duplicateID { Button("Đây là đơn đã có: bỏ ảnh chờ và mở hồ sơ") { saved(duplicateID) } }
                    }
                }
            }
            .navigationTitle("Nhận đơn").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .quickLookPreview($preview)
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let candidate {
                    customer = candidate.customer; total = String(candidate.total); code = candidate.code
                    phone = candidate.phone; address = candidate.address; deliveryNote = candidate.deliveryNote
                    if let date = candidate.invoiceDate { invoiceDate = date; hasInvoiceDate = true }
                }
            }
            .task(id: source) { if let source { await readInvoice(source) } }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("keyboard.done") } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if !validation.isEmpty { Text(validation).font(.caption).foregroundStyle(.red) }
                    Button(signed ? "Nhập đơn và ghi công ký nhận" : "Nhập đơn vào Sweep") { Task { await save() } }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                        .accessibilityIdentifier("intake.save").disabled(store.busy || reading)
                }.padding().frame(maxWidth: .infinity).background(.bar)
            }
            .disabled(store.busy)
        }
    }
    @MainActor private func readInvoice(_ url: URL) async {
        let request = UUID(); readingRequest = request; reading = true
        defer { if readingRequest == request { reading = false } }
        do {
            if let shared, image == nil { try await Task.detached { try EvidenceFiles.verify(shared.evidence, directory: shared.directory) }.value }
            let fields = try await Task.detached(priority: .userInitiated) { try InvoiceOCR.read(url) }.value
            guard !Task.isCancelled, source == url, readingRequest == request else { return }
            if code.isEmpty { code = fields.code }
            if customer.isEmpty { customer = fields.customer }
            if total.isEmpty || (candidate == nil && total == "0") { if let value = fields.total { total = String(value) } }
            if phone.isEmpty { phone = fields.phone }
            if address.isEmpty { address = fields.address }
            if deliveryNote.isEmpty { deliveryNote = fields.deliveryNote }
            if !hasInvoiceDate, let date = fields.invoiceDate { invoiceDate = date; hasInvoiceDate = true }
            var missing: [String] = []
            if code.isEmpty { missing.append("mã cạnh Số:") }
            if customer.isEmpty { missing.append("tên tại Đơn vị:") }
            if total.isEmpty { missing.append("tổng tiền") }
            readingStatus = missing.isEmpty ? "Đã điền gợi ý. Kiểm tra với ảnh, rồi bấm Nhập đơn vào Sweep." : "Chưa đọc rõ " + missing.joined(separator: ", ") + ". Sếp điền tay phần còn thiếu."
            if let value = fields.total, let current = try? VND.parse(total), current != value { readingStatus += " Tổng OCR khác số tiền đang điền; em giữ số tiền hiện tại để Sếp đối chiếu." }
        } catch { readingStatus = "Chưa đọc được ảnh: " + error.localizedDescription + " Sếp có thể điền tay." }
    }
    private func save() async {
        validation = ""; duplicateID = nil
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validation = "Điền mã cạnh Số: và tên tại Đơn vị: trước khi nhập."; return
        }
        do {
            var order = DeliveryOrder(code: code.trimmingCharacters(in: .whitespacesAndNewlines), customer: customer.trimmingCharacters(in: .whitespacesAndNewlines), total: try VND.parse(total))
            if let shared {
                if let old = store.ledger.orders.first(where: { $0.sourceID == shared.sourceID }) { saved(old.id); return }
                if let old = store.ledger.orders.first(where: { DeliveryOrder.normalizedCode($0.code) == DeliveryOrder.normalizedCode(order.code) }) {
                    duplicateID = old.id; validation = "Mã \(old.code) đã có: \(old.customer), \(VND.format(old.total)). Ảnh chờ vẫn được giữ. Kiểm tra lại mã hoặc xác nhận đây là đơn cũ."; return
                }
                try await Task.detached { try EvidenceFiles.verify(shared.evidence, directory: shared.directory) }.value
                order.sourceID = shared.sourceID; order.sourceCreatedAt = shared.receivedAt
            }
            order.phone = phone; order.address = address; order.invoiceAt = hasInvoiceDate ? invoiceDate : nil
            order.note = [deliveryNote.isEmpty ? "" : "Giao hàng: \(deliveryNote)", phone.isEmpty ? "" : "Điện thoại trên phiếu cần xác minh người nhận: \(phone)"].filter { !$0.isEmpty }.joined(separator: "\n")
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
        } catch { validation = error.localizedDescription }
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
                    Text("Trong Tệp: iCloud Drive → Shortcuts → SenTechTips_AnhDonHang. Sweep chỉ đọc, giữ sổ và ảnh bên Bill nguyên trạng. Mỗi hồ sơ được xem trước rồi Sếp xác nhận nhập.").font(.footnote).foregroundStyle(.secondary)
                    if loading { ProgressView("Đang đọc gói Bill…") }
                }
                if let result {
                    Section("\(result.candidates.count) hồ sơ tìm thấy · \(result.candidates.filter { item in store.ledger.orders.contains { $0.sourceID == item.id } }.count) đã nhập") {
                        Text("Đây là danh sách xem trước. Chạm một hồ sơ, kiểm tra thông tin rồi bấm Nhập đơn vào Sweep.").font(.footnote).foregroundStyle(.secondary)
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
