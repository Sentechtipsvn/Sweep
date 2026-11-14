import SwiftUI

struct ReconciliationView: View {
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var month = DeliveryMonth.start(Date())
    @State private var observedMonth = DeliveryMonth.start(Date())
    @State private var query = ""
    @State private var accountantCount = ""
    @State private var accountantAmount = ""
    @State private var handover = false
    @State private var sharing: DeliveryShare?
    private var summary: MonthlyReconciliation { MonthlyReconciliation(ledger: store.ledger, month: month) }
    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.timeZone = DeliveryMonth.calendar.timeZone
        f.dateFormat = "MM/yyyy"; return f.string(from: month)
    }
    var body: some View {
        let totals = summary
        List {
            Section {
                HStack {
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Tháng trước").accessibilityIdentifier("audit.previous")
                    Spacer(); Text("Tháng \(monthTitle)").font(.headline); Spacer()
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Tháng sau").accessibilityIdentifier("audit.next")
                }.buttonStyle(.borderless)
            }
            Section("Công giao hàng") {
                LabeledContent("Phiếu tính công", value: "\(totals.count)").accessibilityIdentifier("audit.count")
                LabeledContent("Tổng tiền đơn", value: VND.format(totals.commissions.reduce(0) { $0 + $1.0.total }))
                LabeledContent("Tiền công", value: VND.format(totals.fee)).font(.headline).foregroundStyle(.green).accessibilityIdentifier("audit.fee")
                Button("Xuất danh sách tháng (CSV)") { exportMonth() }
            }
            Section("Tiền mặt") {
                LabeledContent("Đã thu trong tháng", value: VND.format(totals.cashCollected)).accessibilityIdentifier("audit.cashCollected")
                LabeledContent("Đã nộp trong tháng", value: VND.format(totals.cashHanded)).accessibilityIdentifier("audit.cashHanded")
                LabeledContent("Chênh lệch thu − nộp", value: VND.format(totals.cashDifference)).font(.headline).accessibilityIdentifier("audit.cashDifference")
                if totals.cashDifference < 0 { Text("Có tiền nộp từ khoản đã thu trước tháng này.").font(.caption).foregroundStyle(.secondary) }
                LabeledContent("Còn giữ đến hiện tại · gồm tháng trước", value: VND.format(store.ledger.cashHeld)).font(.headline).accessibilityIdentifier("audit.cashHeld")
                Button("Ghi nộp tiền") { handover = true }.accessibilityIdentifier("audit.handover")
                NavigationLink("Lịch sử nộp trong tháng") {
                    List {
                        if totals.handovers.isEmpty { Text("Chưa có lần nộp tiền.").foregroundStyle(.secondary) }
                        ForEach(totals.handovers) { value in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(VND.format(value.amount)).font(.headline)
                                Text(value.at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text(value.note).font(.footnote)
                                if let reversal = store.ledger.handoverReversals.first(where: { $0.handoverID == value.id }) { Text("Đã điều chỉnh: \(reversal.reason)").font(.caption).foregroundStyle(.orange) }
                                else { NavigationLink("Sửa lần ghi nhầm") { HandoverCorrectionView(value: value) } }
                            }
                        }
                    }.navigationTitle("Tiền đã nộp")
                }
            }
            Section("Phân loại đã giao trong tháng") {
                ForEach([DeliveryRoute.cashFull, .transferNow, .transferLater, .freight], id: \.self) { route in
                    let orders = totals.orders.filter { $0.settlement?.route == route }
                    NavigationLink {
                        List(orders) { order in
                            NavigationLink { OrderDetailView(id: order.id) } label: { VStack(alignment: .leading) { Text(order.customer); Text(order.workflowStatus).font(.caption).foregroundStyle(.secondary) } }
                        }.navigationTitle(route.rawValue)
                    } label: { LabeledContent(route.rawValue, value: "\(orders.count)") }
                }
            }
            Section("Phiếu tính công · \(totals.count)") {
                if totals.commissions.isEmpty { Text("Chưa có phiếu trong tháng.").foregroundStyle(.secondary) }
                ForEach(totals.commissions.filter { query.isEmpty || ($0.0.customer + $0.0.code + $0.0.phone).localizedStandardContains(query) }, id: \.1.id) { order, assignment in
                    NavigationLink { OrderDetailView(id: order.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(order.customer); Spacer(); Text(VND.format(assignment.fee)) }
                            Text("\(order.code) · \(assignment.signedAt.formatted(date: .numeric, time: .omitted)) · \(order.outcome.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Lịch sử").searchable(text: $query, prompt: "Tên khách, mã phiếu, số điện thoại")
        .sheet(isPresented: $handover) { HandoverView() }
        .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
        .onAppear { rollMonthIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollMonthIfNeeded() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollMonthIfNeeded() }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    private func moveMonth(_ offset: Int) {
        month = DeliveryMonth.calendar.date(byAdding: .month, value: offset, to: month) ?? month
        accountantCount = ""; accountantAmount = ""
    }
    private func rollMonthIfNeeded() {
        let now = Date()
        let next = DeliveryMonth.rollover(selected: month, observed: observedMonth, now: now)
        if next != month { month = next; accountantCount = ""; accountantAmount = "" }
        observedMonth = DeliveryMonth.start(now)
    }
    private func exportMonth() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-cong-\(monthTitle.replacingOccurrences(of: "/", with: "-"))-\(UUID().uuidString.prefix(6)).csv")
        do { try Data(store.ledger.csv(in: month, calendar: DeliveryMonth.calendar).utf8).write(to: url, options: .atomic); sharing = DeliveryShare(items: [url]) }
        catch { store.message = error.localizedDescription }
    }
}

private struct HandoverCorrectionView: View {
    let value: CashHandover
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirm = false
    var body: some View {
        Form {
            LabeledContent("Lần đã ghi nộp", value: VND.format(value.amount))
            Text(value.note)
            Text("Chỉ dùng khi ghi nhầm vào sổ. Tiền đã nộp thật vẫn phải đối chiếu với người nhận; thao tác này không tạo giao dịch hoàn tiền.").font(.footnote).foregroundStyle(.secondary)
            TextField("Lý do điều chỉnh", text: $reason, axis: .vertical)
            Button("Hủy bản ghi nhập nhầm…", role: .destructive) { confirm = true }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .navigationTitle("Điều chỉnh nộp tiền")
        .alert("Hủy ghi nhận lần nộp này?", isPresented: $confirm) {
            Button("Điều chỉnh, giữ lịch sử", role: .destructive) { if store.change({ try $0.reverseHandover(value.id, reason: reason) }) { dismiss() } }
            Button("Giữ nguyên", role: .cancel) {}
        } message: { Text("Tiền còn giữ sẽ tăng lại \(VND.format(value.amount)). Lý do: \(reason)") }
    }
}

private struct HandoverView: View {
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var at = Date()
    @State private var note = ""
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Tiền mặt còn giữ", value: VND.format(store.ledger.cashHeld))
                MoneyInput(title: "Nộp thực tế", text: $amount)
                DatePicker("Thời điểm nộp", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("Người nhận / xác nhận đã nộp", text: $note, axis: .vertical)
                Button("Kiểm tra và ghi nộp tiền…") { confirm = true }.disabled(amount.isEmpty || note.isEmpty)
            }.navigationTitle("Nộp tiền công ty").navigationBarTitleDisplayMode(.inline).toolbar { CloseSheet { dismiss() } }
                .alert("Xác nhận đã nộp tiền?", isPresented: $confirm) {
                    Button("Đã nộp, ghi vào sổ") {
                        do { let value = try VND.parse(amount); if store.change({ try $0.handover(value, at: at, note: note) }) { dismiss() } }
                        catch { store.message = error.localizedDescription }
                    }
                    Button("Kiểm tra lại", role: .cancel) {}
                } message: { Text("Số tiền \(amount)₫ · \(note). Ghi khi Sếp đã thực sự nộp, không phải chỉ chuẩn bị nộp.") }
        }
    }
}
