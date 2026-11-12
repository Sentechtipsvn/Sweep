import SwiftUI
import QuickLook

struct OrderDetailView: View {
    let id: UUID
    @EnvironmentObject private var store: DeliveryStore
    @State private var preview: URL?
    @State private var settle = false
    @State private var sign = false
    @State private var edit = false
    @State private var void = false
    @State private var bank = false
    @State private var reason = ""
    @State private var excluding = false
    @State private var excludedFile: UUID?
    private var order: DeliveryOrder? { store.order(id) }
    var body: some View {
        Group {
            if let order {
                VStack(spacing: 0) {
                    List {
                        Section {
                            Text(order.customer).font(.title2.bold()).textSelection(.enabled)
                            LabeledContent("Tổng đơn", value: VND.format(order.total)).font(.headline)
                            LabeledContent("Mã phiếu", value: order.code).textSelection(.enabled)
                            if let date = order.invoiceAt { LabeledContent("Ngày hóa đơn", value: date.formatted(date: .numeric, time: .omitted)) }
                            if let invoice = order.activeEvidence.first(where: { $0.role == .invoice }) {
                                Button { preview = store.url(invoice) } label: { EvidenceThumbnail(url: store.url(invoice), height: 200) }.buttonStyle(.plain)
                            }
                            HStack {
                                if let url = phoneURL(order.phone) { Link(destination: url) { Label("Gọi", systemImage: "phone") } }
                                if !order.address.isEmpty, let url = mapURL(order.address) {
                                    Link(destination: url) { Label("Đường", systemImage: "map") }
                                }
                                NavigationLink { BankCompanyView() } label: { Label("QR công ty", systemImage: "qrcode") }
                            }.font(.subheadline).buttonStyle(.bordered)
                            if !order.phone.isEmpty { Text(order.phone).font(.caption).textSelection(.enabled) }
                            if !order.address.isEmpty { Text(order.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        Section("Ký nhận và công đơn") {
                            if let assignment = order.assignments.first {
                                LabeledContent(order.activeAssignments.isEmpty ? "Đã điều chỉnh hủy công" : "Công đã ghi nhận", value: VND.format(assignment.fee))
                                LabeledContent("Ngày Sếp ký nhận", value: assignment.signedAt.formatted(date: .numeric, time: .shortened))
                            } else {
                                Text("Chưa xác nhận ký nhận · chưa tính công").foregroundStyle(.secondary)
                                Button("Xác nhận Sếp đã ký nhận phiếu") { sign = true }.accessibilityIdentifier("order.sign")
                            }
                            Text("Chữ ký khách là chứng từ giao hàng. Thêm ảnh hay báo cáo lại không cộng thêm công.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Giao và tiền") {
                            LabeledContent("Kết quả", value: order.outcome.rawValue)
                            LabeledContent("Tiền mặt đã thu", value: VND.format(order.cash))
                            LabeledContent("CK khách báo", value: VND.format(order.bank))
                            LabeledContent("CK đã đối soát", value: VND.format(order.verifiedBank))
                            LabeledContent("Còn lại theo ghi nhận", value: VND.format(order.remaining)).foregroundStyle(order.remaining > 0 ? .orange : .primary)
                            if let value = order.settlement {
                                Text(value.at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                if !value.note.isEmpty { Text(value.note).font(.footnote) }
                            }
                            if order.bank > order.verifiedBank { Button("Xác nhận CK đã vào công ty…") { reason = ""; bank = true } }
                        }
                        ForEach([EvidenceRole.invoice, .signature, .transfer], id: \.self) { role in
                            Section(role.rawValue) {
                                let files = order.activeEvidence.filter { $0.role == role }
                                if !files.isEmpty {
                                    ScrollView(.horizontal) {
                                        HStack {
                                            ForEach(files) { file in
                                                Button { preview = store.url(file) } label: { EvidenceThumbnail(url: store.url(file), height: 100).frame(width: 100) }.buttonStyle(.plain)
                                                    .contextMenu {
                                                        Button("Loại khỏi bộ báo cáo…", role: .destructive) { excludedFile = file.id; reason = ""; excluding = true }
                                                    }
                                            }
                                        }
                                    }
                                }
                                if order.voidReason == nil { EvidencePicker(title: "Bổ sung \(role.rawValue.lowercased())") { url in await store.attach(url, role: role, to: id) } }
                            }
                        }
                        Section("Báo cáo") {
                            Label(order.reportSent ? "Sếp đã xác nhận gửi" : order.reports.isEmpty ? "Chưa chuẩn bị báo cáo" : "Chưa xác nhận gửi / cần gửi lại", systemImage: order.reportSent ? "checkmark.circle.fill" : "paperplane")
                                .foregroundStyle(order.reportSent ? .green : .secondary)
                            NavigationLink { OrderReportView(id: id) } label: { Label("Chuẩn bị và chia sẻ báo cáo", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("order.report")
                        }
                        if !order.reviewNote.isEmpty {
                            Section("Dữ liệu cũ cần rà soát") {
                                Text(order.reviewNote).font(.footnote).textSelection(.enabled)
                                Button("Đánh dấu đã rà soát dữ liệu cũ") {
                                    _ = store.change { ledger in
                                        guard let i = ledger.orders.firstIndex(where: { $0.id == id }) else { return }
                                        let previous = ledger.orders[i].reviewNote
                                        ledger.orders[i].reviewNote = ""
                                        ledger.record("Sếp xác nhận đã rà soát sổ cũ", orderID: id, previous)
                                    }
                                }
                                Text("Thao tác này chỉ bỏ cờ nhắc, không tự xác nhận ngày ký, ghi công, đối soát CK hoặc gửi báo cáo.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !order.note.isEmpty { Section("Ghi chú hồ sơ") { Text(order.note) } }
                        Section {
                            if !order.exclusions.isEmpty {
                                NavigationLink("Ảnh gốc đã loại khỏi báo cáo (\(order.exclusions.count))") {
                                    List(order.evidence.filter { file in order.exclusions.contains { $0.evidenceID == file.id } }) { file in
                                        Button { preview = store.url(file) } label: {
                                            VStack(alignment: .leading) {
                                                EvidenceThumbnail(url: store.url(file), height: 180)
                                                Text(order.exclusions.first(where: { $0.evidenceID == file.id })?.reason ?? "").font(.caption)
                                            }
                                        }.buttonStyle(.plain)
                                    }.navigationTitle("Ảnh lưu trong lịch sử").quickLookPreview($preview)
                                }
                            }
                            NavigationLink("Lịch sử hồ sơ") { OrderHistoryView(id: id) }
                            if order.voidReason == nil { Button("Hủy hồ sơ nhập nhầm…", role: .destructive) { reason = ""; void = true } }
                            else { Text("Đã hủy: \(order.voidReason ?? "")").foregroundStyle(.secondary) }
                        }
                    }
                    if order.voidReason == nil {
                        Button { settle = true } label: {
                            Label("Chốt giao / thu tiền", systemImage: "checkmark.circle")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.borderedProminent).padding(12).background(.bar).accessibilityIdentifier("order.settle")
                    }
                }
                .sheet(isPresented: $settle) { SettlementView(order: order) }
                .sheet(isPresented: $sign) { SignAssignmentView(id: id) }
                .sheet(isPresented: $edit) { EditOrderView(order: order) }
                .alert("Hủy và điều chỉnh công?", isPresented: $void) {
                    TextField("Lý do nhập nhầm", text: $reason)
                    Button("Hủy hồ sơ", role: .destructive) { _ = store.change { try $0.void(id, reason: reason) } }
                    Button("Giữ hồ sơ", role: .cancel) {}
                } message: { Text("Giữ lịch sử và chứng từ; điều chỉnh công đã ghi. Hồ sơ có khoản thu phải được rà soát tiền trước.") }
                .alert("Công ty đã xác nhận nhận CK?", isPresented: $bank) {
                    TextField("Ai / nội dung xác nhận", text: $reason)
                    Button("Ghi nhận đối soát") { _ = store.change { try $0.verifyBank(id, note: reason) } }
                    Button("Để sau", role: .cancel) {}
                } message: { Text("Ảnh khách chuyển khoản chưa đủ để xác nhận tiền đã vào công ty. Chỉ ghi nhận khi Sếp có thông tin từ công ty.") }
                .alert("Loại ảnh khỏi bộ báo cáo?", isPresented: $excluding) {
                    TextField("Lý do / ảnh bổ sung thay thế", text: $reason)
                    Button("Loại khỏi báo cáo", role: .destructive) { if let excludedFile { _ = store.change { try $0.excludeEvidence(excludedFile, orderID: id, reason: reason) } } }
                    Button("Giữ ảnh", role: .cancel) {}
                } message: { Text("Giữ ảnh gốc và lịch sử. Bộ báo cáo mới sẽ bỏ ảnh này; Sếp thêm ảnh đúng nếu đó là chứng từ bắt buộc.") }
            } else { ContentUnavailableView("Không tìm thấy hồ sơ", systemImage: "doc.questionmark") }
        }
        .navigationTitle("Chi tiết đơn").navigationBarTitleDisplayMode(.inline)
        .toolbar { if order?.voidReason == nil { Button("Sửa") { edit = true } } }
        .quickLookPreview($preview)
        .disabled(store.busy)
    }
    private func phoneURL(_ text: String) -> URL? {
        let number = text.filter { $0.isNumber || $0 == "+" }
        guard number.filter(\.isNumber).count >= 8 else { return nil }
        return URL(string: "tel:\(number)")
    }
    private func mapURL(_ address: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        return components?.url
    }
}

private struct SignAssignmentView: View {
    let id: UUID
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var confirmed = false
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Ngày Sếp ký nhận", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Toggle("Sếp đã ký phiếu nhận việc đi giao", isOn: $confirmed).accessibilityIdentifier("sign.confirm")
                Text("Ghi công \(VND.format(store.ledger.settings.fee)) đúng một lần. Giao thất bại, chưa thu hoặc CK sau vẫn giữ công. Nhập đơn cũ: chọn đúng ngày ký, không dùng ngày nhập ảnh.").font(.footnote).foregroundStyle(.secondary)
                Button("Ghi công ký nhận") { if store.change({ try $0.sign(id, at: date) }) { dismiss() } }.disabled(!confirmed).accessibilityIdentifier("sign.save")
            }.navigationTitle("Xác nhận ký nhận").navigationBarTitleDisplayMode(.inline).toolbar { CloseSheet { dismiss() } }
        }
    }
}

private struct EditOrderView: View {
    let order: DeliveryOrder
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var name: String
    @State private var total: String
    @State private var phone: String
    @State private var address: String
    @State private var note: String
    init(order: DeliveryOrder) {
        self.order = order
        _code = State(initialValue: order.code); _name = State(initialValue: order.customer); _total = State(initialValue: String(order.total))
        _phone = State(initialValue: order.phone); _address = State(initialValue: order.address); _note = State(initialValue: order.note)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Mã phiếu", text: $code); TextField("Tên khách", text: $name)
                MoneyInput(title: "Tổng đơn", text: $total)
                TextField("Điện thoại", text: $phone).keyboardType(.phonePad)
                TextField("Địa chỉ", text: $address); TextField("Ghi chú", text: $note, axis: .vertical)
                Button("Lưu thông tin") {
                    if store.change({ ledger in
                        guard let i = ledger.orders.firstIndex(where: { $0.id == order.id }), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeliveryError.invalid("Thiếu tên / mã phiếu.") }
                        let old = ledger.orders[i]
                        ledger.orders[i].code = code.trimmingCharacters(in: .whitespacesAndNewlines); ledger.orders[i].customer = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ledger.orders[i].total = try VND.parse(total); ledger.orders[i].phone = phone; ledger.orders[i].address = address; ledger.orders[i].note = note
                        ledger.orders[i].revision += 1
                        let before = "\(old.code) · \(old.customer) · \(old.total) · \(old.phone) · \(old.address) · \(old.note)"
                        let after = "\(code) · \(name) · \(total) · \(phone) · \(address) · \(note)"
                        ledger.record("Sửa hồ sơ", orderID: order.id, "Trước: \(before)\nSau: \(after)")
                    }) { dismiss() }
                }
            }.navigationTitle("Sửa hồ sơ").navigationBarTitleDisplayMode(.inline).toolbar { CloseSheet { dismiss() } }
        }
    }
}

struct SettlementView: View {
    let order: DeliveryOrder
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: DeliveryOutcome
    @State private var mode: PaymentMode
    @State private var cash: String
    @State private var bank: String
    @State private var date: Date
    @State private var note: String
    init(order: DeliveryOrder) {
        self.order = order
        _outcome = State(initialValue: order.outcome); _mode = State(initialValue: order.settlement?.mode ?? .none)
        _cash = State(initialValue: String(order.cash)); _bank = State(initialValue: String(order.bank))
        _date = State(initialValue: order.settlement?.at ?? Date()); _note = State(initialValue: order.settlement?.note ?? "")
    }
    private var remaining: Int64? { guard let a = try? VND.parse(cash), let b = try? VND.parse(bank) else { return nil }; return order.total - a - b }
    var body: some View {
        NavigationStack {
            Form {
                Section(order.customer) {
                    LabeledContent("Tổng đơn", value: VND.format(order.total))
                    Picker("Kết quả giao", selection: $outcome) { ForEach(DeliveryOutcome.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("settle.outcome")
                    Picker("Thanh toán", selection: $mode) { ForEach(PaymentMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("settle.mode")
                    DatePicker("Thời điểm chốt", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Số tiền thực tế · giá trị tổng đã ghi nhận") {
                    MoneyInput(title: "Tiền mặt", text: $cash, identifier: "settle.cash")
                    MoneyInput(title: "CK khách báo", text: $bank, identifier: "settle.bank")
                    if let remaining {
                        LabeledContent(remaining < 0 ? "Ghi nhận thừa" : "Còn theo ghi nhận", value: VND.format(abs(remaining)))
                            .foregroundStyle(remaining == 0 ? .green : .orange).accessibilityIdentifier("settle.remaining")
                    }
                    Button("Thu đủ bằng tiền mặt") { cash = String(order.total); bank = "0"; mode = .cash }
                    Button("CK sau, chưa nhận khoản nào") { cash = "0"; bank = "0"; mode = .deferred }
                    Text("Sửa là thay tổng khoản đã ghi của đơn, không cộng thêm lần nữa. Đổi số liệu làm báo cáo cần gửi lại; CK cần đối soát lại. Công ký nhận được giữ nguyên.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Ghi chú / lý do hoãn, thất bại") { TextField("Nội dung", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("settle.note") }
                Section {
                    Button("Lưu chốt giao / tiền") {
                        do {
                            let value = Settlement(outcome: outcome, mode: mode, cash: try VND.parse(cash), bank: try VND.parse(bank), note: note, at: date)
                            if store.change({ try $0.settle(order.id, value: value) }) { dismiss() }
                        } catch { store.message = error.localizedDescription }
                    }.accessibilityIdentifier("settle.save")
                    Text("Có thể lưu khi chưa đủ ảnh. Báo cáo hoàn chỉnh sẽ kiểm tra chứng từ riêng. Hủy chia sẻ không hủy số tiền đã lưu.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Chốt giao / thu tiền").navigationBarTitleDisplayMode(.inline).toolbar { CloseSheet { dismiss() } }
        }
    }
}

struct OrderReportView: View {
    let id: UUID
    @EnvironmentObject private var store: DeliveryStore
    @State private var text = ""
    @State private var initialized = false
    @State private var prepared: DeliveryReport?
    @State private var sharing: DeliveryShare?
    @State private var confirm = false
    @State private var copied = false
    @State private var preview: URL?
    @State private var draftSaved = false
    var body: some View {
        List {
            if let order = store.order(id) {
                Section("Nội dung có thể sửa") {
                    TextEditor(text: $text).frame(minHeight: 240).accessibilityIdentifier("report.text")
                    Button(draftSaved ? "Đã lưu nội dung nháp" : "Lưu nội dung nháp") {
                        if store.change({ try $0.saveReportDraft(id, text: text) }) { draftSaved = true }
                    }.disabled(store.busy)
                    Button(copied ? "Đã sao chép" : "Sao chép nội dung") { UIPasteboard.general.string = text; copied = true }
                    Button("Tạo lại từ số liệu hiện tại") { text = order.reportText(); prepared = nil; copied = false }
                }
                Section("Thứ tự ảnh đính kèm") {
                    let files = [EvidenceRole.invoice, .signature, .transfer].flatMap { role in order.activeEvidence.filter { $0.role == role } }
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        Button { preview = store.url(file) } label: {
                            HStack {
                                EvidenceThumbnail(url: store.url(file), height: 70).frame(width: 60)
                                Text("\(index + 1) · \(file.role.rawValue)")
                                Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                        }.buttonStyle(.plain)
                    }
                    if !order.missingEvidence().isEmpty { Text("Còn thiếu: " + order.missingEvidence().map(\.rawValue).joined(separator: ", ")).foregroundStyle(.orange) }
                    Button("Kiểm tra và chuẩn bị báo cáo") {
                        Task { prepared = await store.prepareReport(id, text: text) }
                    }.disabled(order.settlement == nil || store.busy).accessibilityIdentifier("report.prepare")
                }
                if let prepared, prepared.text == text, prepared.revision == order.revision {
                    Section {
                        Button("Chia sẻ nội dung và ảnh") { share(prepared, order: order, includeText: true) }
                        Button("Chỉ chia sẻ bộ ảnh") { share(prepared, order: order, includeText: false) }
                        Text("Sếp chọn nhóm trong Zalo rồi gửi. Nếu Zalo không nhận kèm văn bản, dùng Sao chép nội dung và chia sẻ riêng ảnh.").font(.caption).foregroundStyle(.secondary)
                        Button(order.reportSent ? "Đã xác nhận gửi" : "Tôi đã gửi báo cáo…") { confirm = true }
                            .disabled(order.reportSent).accessibilityIdentifier("report.ack")
                    }
                }
            }
        }
        .navigationTitle("Báo cáo đơn").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized, let order = store.order(id) else { return }; initialized = true
            if let draft = order.reportDrafts.last, draft.revision == order.revision,
               order.reports.last?.text != draft.text, (order.reports.last?.preparedAt ?? .distantPast) < draft.at { text = draft.text }
            else if let report = order.reports.last, report.revision == order.revision { text = report.text; prepared = report }
            else { text = order.reportText() }
        }
        .onChange(of: text) { _, _ in copied = false; draftSaved = false }
        .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
        .quickLookPreview($preview)
        .alert("Sếp đã gửi đủ nội dung và ảnh?", isPresented: $confirm) {
            Button("Đúng, đã gửi") { if let prepared { _ = store.change { try $0.acknowledgeReport(id, reportID: prepared.id) } } }
            Button("Chưa gửi", role: .cancel) {}
        } message: { Text("Sweep ghi theo xác nhận này. Việc mở hoặc đóng bảng chia sẻ không đánh dấu đã báo cáo.") }
    }
    private func share(_ report: DeliveryReport, order: DeliveryOrder, includeText: Bool) {
        let urls = report.evidenceIDs.compactMap { id in order.evidence.first { $0.id == id }.map { store.url($0) } }
        sharing = DeliveryShare(items: (includeText ? [report.text as Any] : []) + urls.map { $0 as Any })
    }
}

struct OrderHistoryView: View {
    let id: UUID
    @EnvironmentObject private var store: DeliveryStore
    var body: some View {
        List(store.ledger.audit.filter { $0.orderID == id }.reversed()) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.action).font(.headline)
                Text(item.at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text(item.detail).font(.caption).textSelection(.enabled)
            }
        }.navigationTitle("Lịch sử hồ sơ")
    }
}
