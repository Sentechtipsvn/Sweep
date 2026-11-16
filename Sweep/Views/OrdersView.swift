import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct OrdersView: View {
    @EnvironmentObject private var store: DeliveryStore
    @EnvironmentObject private var router: SweepRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = SharedInboxStore()
    @State private var sharedInbox = false
    @State private var refreshingInbox = false
    @State private var inboxRefreshRequested = false
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var filter = "Đang giao"
    @State private var period = DeliveryPeriod.day
    @State private var showWork = false
    @State private var newOrder = false
    @State private var savedOrder: UUID?
    private func visible(_ now: Date) -> [DeliveryOrder] {
        store.ledger.orders.filter { order in
            let matches = query.isEmpty || (order.customer + " " + order.code + " " + order.phone).localizedStandardContains(query)
            return matches && order.voidReason == nil && (filter == "Đang giao" ? order.outcome != .delivered : period.contains(order, now: now))
        }.sorted {
            (filter == "Đã giao" ? ($0.firstDeliveredAt ?? $0.importedAt) : $0.importedAt) > (filter == "Đã giao" ? ($1.firstDeliveredAt ?? $1.importedAt) : $1.importedAt)
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                let orders = visible(clock.date)
                let work = DeliveryWorkItem.items(store.ledger, now: clock.date)
                List {
                    Section {
                        VStack(spacing: 12) {
                            SendeliSearchField(text: $query)
                            HStack(spacing: 6) {
                                ForEach(["Đang giao", "Đã giao"], id: \.self) { value in
                                    Button(value) { filter = value }.buttonStyle(SweepPill(selected: filter == value)).accessibilityIdentifier("filter.\(value)")
                                }
                                if filter == "Đã giao" {
                                    Menu { Picker("Thời gian giao", selection: $period) { ForEach(DeliveryPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 30, height: 44) }
                                        .accessibilityLabel("Lọc đơn đã giao")
                                }
                            }
                            if filter == "Đã giao" {
                                ViewThatFits(in: .horizontal) {
                                    HStack { Text(period.rawValue).foregroundStyle(.secondary); Spacer(minLength: 8); workButton(count: work.count) }
                                    VStack(alignment: .trailing, spacing: 4) { Text(period.rawValue).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading); workButton(count: work.count) }
                                }.font(.caption)
                            }
                        }.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }.listRowBackground(Color.clear)
                    if !inbox.items.isEmpty { Section {
                        Button { sharedInbox = true } label: { Label("\(inbox.items.count) ảnh được chia sẻ · nhận đơn", systemImage: "tray.and.arrow.down.fill") }.accessibilityIdentifier("orders.shared")
                    } }
                    if store.blocked { Text("Sổ đang chỉ đọc. Xem thông báo lỗi mở sổ.").foregroundStyle(.red) }
                    if orders.isEmpty {
                        VStack(spacing: 16) {
                            Text(query.isEmpty ? "Chưa có đơn trong danh sách này" : "Không tìm thấy đơn").foregroundStyle(.secondary)
                            if filter == "Đang giao" { Button("Chọn ảnh đơn hàng") { newOrder = true }.buttonStyle(SweepPill(selected: true)) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(orders) { order in
                        NavigationLink(value: order.id) { SendeliOrderRow(order: order) }.accessibilityIdentifier("order.\(order.code)")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if filter == "Đã giao" { Text("\(orders.count) đơn").font(.system(size: 16)).frame(maxWidth: .infinity).padding(.vertical, 7).background(.bar).accessibilityIdentifier("orders.count") }
                }
            }
            .navigationTitle("Đơn hàng")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { newOrder = true } label: { Label("Nhận đơn", systemImage: "plus") }.accessibilityIdentifier("orders.new").disabled(store.busy || store.blocked) } }
            .navigationDestination(for: UUID.self) { OrderDetailView(id: $0) }
            .navigationDestination(isPresented: $showWork) { DeliveryWorkView() }
            .sheet(isPresented: $newOrder, onDismiss: openSavedOrder) { OrderIntakeView { id in savedOrder = id; newOrder = false } }
            .sheet(isPresented: $sharedInbox, onDismiss: openSavedOrder) { SharedInboxView(inbox: inbox) { id in savedOrder = id; sharedInbox = false } }
            .task { await refreshInbox(); if let id = router.orderID, store.order(id) != nil { path = [id]; router.orderID = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .sweepInboxReceived)) { _ in Task { await refreshInbox() } }
            .onChange(of: router.orderID) { _, id in if let id, store.order(id) != nil { path = [id]; router.orderID = nil } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshInbox() } } }
        }
    }
    @ViewBuilder private func workButton(count: Int) -> some View {
        if count > 0 {
            Button("Còn \(count) việc cần xử lý") { showWork = true }
                .buttonStyle(.borderless).foregroundStyle(.blue)
                .accessibilityIdentifier("orders.work")
        }
    }
    private func refreshInbox() async {
        guard !refreshingInbox else { inboxRefreshRequested = true; return }
        refreshingInbox = true; defer { refreshingInbox = false }
        repeat {
            inboxRefreshRequested = false
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--shared-ui-testing") {
                do { try await store.installSharedUITestFixture() } catch { store.message = error.localizedDescription }
            }
            #endif
            await inbox.reload()
            if !inbox.items.isEmpty, !newOrder, !sharedInbox, !store.busy, !store.blocked { sharedInbox = true }
        } while inboxRefreshRequested
    }
    private func openSavedOrder() {
        guard let id = savedOrder else { return }
        savedOrder = nil; query = ""; filter = "Đang giao"; path.append(id)
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
    @State private var askSigned = false
    @State private var signatureOffered = false
    @State private var signed = false
    @State private var salesperson = ""
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
                    EvidencePicker(title: "Ảnh phiếu") { url in
                        do { image = try await Task.detached { try ImportedImage.copy(from: url) }.value }
                        catch { store.message = error.localizedDescription }
                    }
                    if reading { ProgressView("Đang đọc thông tin trên phiếu…") }
                    if !readingStatus.isEmpty { Text(readingStatus).font(.caption).foregroundStyle(.secondary) }
                    if let source { Button("Đọc lại thông tin còn thiếu từ ảnh") { Task { await readInvoice(source) } }.disabled(reading) }
                }
                Section("Hồ sơ") {
                    TextField("Mã phiếu", text: $code).textInputAutocapitalization(.characters).accessibilityIdentifier("intake.code")
                    TextField("Tên khách hàng", text: $customer).accessibilityIdentifier("intake.customer")
                    MoneyInput(title: "Tổng đơn", text: $total, identifier: "intake.total")
                    TextField("Số điện thoại khách", text: $phone).keyboardType(.phonePad)
                    TextField("Địa chỉ giao hàng", text: $address)
                    TextField("Ghi chú giao hàng / giờ hẹn", text: $deliveryNote)
                    Toggle("Có ngày trên hóa đơn", isOn: $hasInvoiceDate)
                    if hasInvoiceDate { DatePicker("Ngày hóa đơn", selection: $invoiceDate, displayedComponents: .date) }
                }
                Section("Ký nhận") {
                    if signed {
                        Label("Đã ký nhận phiếu", systemImage: "checkmark.seal.fill").foregroundStyle(SweepStyle.green).accessibilityIdentifier("intake.signed")
                    } else {
                        Button("Xác nhận đơn đã ký chưa") { askSigned = true }.accessibilityIdentifier("intake.confirmSignature")
                    }
                    if signed { DatePicker("Ngày ký nhận", selection: $signedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                    LabeledContent("Công mỗi phiếu", value: VND.format(store.ledger.settings.fee))
                    Toggle("Đây là phiếu khác hợp lệ dù dùng lại ảnh", isOn: $allowRepeatedImage).font(.caption)
                }
                if let candidate {
                    Section("Xem trước dữ liệu Bill") {
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
                if let at = shared?.signedAt { signed = true; signedAt = at }
                if let candidate {
                    customer = candidate.customer; total = String(candidate.total); code = candidate.code
                    phone = candidate.phone; address = candidate.address; deliveryNote = candidate.deliveryNote
                    if let date = candidate.invoiceDate { invoiceDate = date; hasInvoiceDate = true }
                }
            }
            .background(SweepAppearanceAction {
                guard !signatureOffered else { return }; signatureOffered = true
                if !signed, shared?.signedAt == nil { askSigned = true }
            }.frame(width: 0, height: 0))
            .alert("Đơn này bạn đã ký chưa?", isPresented: $askSigned) {
                Button("Đã ký") { signed = true }
                Button("Bỏ qua", role: .cancel) { dismiss() }
            }
            .task(id: source) { if let source { await readInvoice(source) } }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("keyboard.done") } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if !signed {
                        Button("Xác nhận ký nhận phiếu") { askSigned = true }.buttonStyle(SweepCompactPill())
                    }
                    Button(signed ? "Nhập đơn và ghi công ký nhận" : "Nhập đơn vào Sendeli") { Task { await save() } }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).controlSize(.large)
                        .accessibilityIdentifier("intake.save").disabled(store.busy || reading || !signed || source == nil)
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
            if salesperson.isEmpty { salesperson = fields.salesperson }
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
            readingStatus = missing.isEmpty ? "" : "Chưa đọc rõ " + missing.joined(separator: ", ") + "."
            if let value = fields.total, let current = try? VND.parse(total), current != value { readingStatus += " Tổng OCR khác số tiền đang điền; em giữ số tiền hiện tại để Sếp đối chiếu." }
        } catch { readingStatus = "Chưa đọc được ảnh: " + error.localizedDescription + " Sếp có thể điền tay." }
    }
    private func save() async {
        validation = ""; duplicateID = nil
        guard signed, source != nil else { validation = "Chọn ảnh và xác nhận đã ký nhận."; return }
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
            order.salesperson = salesperson; order.phone = phone; order.address = address; order.invoiceAt = hasInvoiceDate ? invoiceDate : nil
            order.note = InvoiceParser.cleanStoredNote(deliveryNote)
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
