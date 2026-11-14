import SwiftUI

enum DeliveryMethod: String, Identifiable { case cash = "Tiền mặt", bank = "Chuyển khoản", freight = "Giao chành"; var id: String { rawValue } }
struct DeliveryFlowView: View {
    let id: UUID
    let method: DeliveryMethod
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var stage = "start"
    @State private var partial = ""
    @State private var bankAmount = ""
    @State private var confirmCash = false
    @State private var confirmBank = false
    @State private var confirmFreight = false
    @State private var confirmLater = false
    @State private var routeToReport = false
    private var order: DeliveryOrder? { store.order(id) }
    var body: some View {
        NavigationStack {
            Group {
                if let order {
                    if stage == "qr" {
                        VStack(spacing: 0) {
                            OrderQRView(id: id, suggested: order.remaining)
                            Button("Đã nhận chuyển khoản…") { bankAmount = String(order.remaining); confirmBank = true }
                                .buttonStyle(SweepPill(selected: true)).padding().background(.bar)
                                .disabled(order.remaining <= 0)
                        }
                    } else if stage == "proof" {
                        List {
                            Section {
                                Text(order.customer).font(.headline)
                                Text(order.shareText())
                            }
                            ForEach(order.requiredReportRoles, id: \.self) { role in
                                Section(role.rawValue) {
                                    ForEach(order.activeEvidence.filter { $0.role == role }) { file in EvidenceThumbnail(url: store.url(file), height: 150) }
                                    EvidencePicker(title: role == .invoice ? "Phiếu có số tiền" : role.rawValue) { url in await store.attach(url, role: role, to: id) }
                                }
                            }
                            Section {
                                NavigationLink { OrderReportView(id: id) } label: { Label("Kiểm tra và gửi nhóm", systemImage: "square.and.arrow.up") }
                                    .disabled(!order.missingEvidence().isEmpty).accessibilityIdentifier("flow.report")
                            }
                        }
                    } else {
                        Form {
                            Section {
                                Text(order.customer).font(.headline)
                                LabeledContent("Tổng đơn", value: VND.format(order.total))
                                if order.cash > 0 { LabeledContent("Tiền mặt đã ghi", value: VND.format(order.cash)) }
                                if order.bank > 0 { LabeledContent("Chuyển khoản đã ghi", value: VND.format(order.bank)) }
                            }
                            if order.total <= 0 { Text("Kiểm tra tổng tiền trong Sửa đơn trước khi chốt.").foregroundStyle(.red) }
                            if method == .cash {
                                Section {
                                    Button("Thu đủ tiền mặt") { confirmCash = true }.buttonStyle(SweepPill(selected: true)).accessibilityIdentifier("flow.cashFull")
                                    Button("Thu một phần") { partial = String(order.cash); stage = "partial" }.buttonStyle(SweepPill()).accessibilityIdentifier("flow.partial")
                                }.disabled(order.bank > 0 || order.total <= 0)
                                if stage == "partial" {
                                    Section("Tiền mặt thực nhận") {
                                        MoneyInput(title: "Đã nhận", text: $partial, identifier: "flow.cash")
                                        if let c = try? VND.parse(partial), c <= order.total { LabeledContent("Còn lại", value: VND.format(order.total-c)) }
                                        Button("Phần còn lại chuyển khoản ngay") { savePartial(now: true) }
                                        Button("Phần còn lại chuyển khoản sau…") { confirmLater = true }
                                    }
                                }
                            } else if method == .bank {
                                Section {
                                    Button("Chuyển khoản ngay") { stage = "qr" }.buttonStyle(SweepPill(selected: true)).disabled(order.remaining <= 0)
                                    Button("Chuyển khoản sau…") { confirmLater = true }.buttonStyle(SweepPill()).disabled(order.bank > 0 || order.remaining <= 0)
                                    if order.bank > 0 { Button("Tiếp tục gửi chứng từ") { stage = "proof" }.buttonStyle(SweepPill()) }
                                }
                            } else {
                                Section {
                                    Text("Gửi phiếu nhà xe đã ký và ảnh hàng đã gửi. Bán hàng theo dõi tiền.").font(.subheadline)
                                    Button("Đã giao hàng cho chành…") { confirmFreight = true }.buttonStyle(SweepPill(selected: true)).disabled(order.cash > 0 || order.bank > 0)
                                }
                            }
                            Section { Button("Huỷ", role: .cancel) { dismiss() } }
                        }
                    }
                }
            }
            .navigationTitle(stage == "proof" ? "Chứng từ giao hàng" : method.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .disabled(store.busy)
            .alert("Đã thu đủ tiền mặt?", isPresented: $confirmCash) {
                Button("Đã nhận đủ") { if let o = order, save(cash: o.total, bank: 0, route: .cashFull) { stage = "done"; dismiss() } }
                Button("Kiểm tra lại", role: .cancel) {}
            } message: { Text("\(VND.format(order?.total ?? 0)). Không cần báo cáo ảnh; mang tiền và phiếu xuất kho về công ty.") }
            .alert("Ghi khoản chuyển thực nhận", isPresented: $confirmBank) {
                TextField("Số tiền đã chuyển", text: $bankAmount).keyboardType(.numberPad)
                Button("Xác nhận khoản thực nhận") { confirmTransfer() }
                Button("Chưa nhận", role: .cancel) {}
            } message: { Text("Kiểm tra giao dịch thực tế. Đóng QR không ghi nhận tiền.") }
            .alert("Khách chuyển khoản sau?", isPresented: $confirmLater) {
                Button("Xác nhận, chọn phiếu đã ký") {
                    if method == .cash { savePartial(now: false) }
                    else if let o = order, save(cash: o.cash, bank: o.bank, route: .transferLater) { stage = "proof" }
                }
                Button("Huỷ", role: .cancel) {}
            } message: { Text("Chỉ gửi phiếu xuất kho khách đã ký; không gửi phiếu có giá.") }
            .alert("Đã bàn giao hàng cho chành?", isPresented: $confirmFreight) {
                Button("Đã giao, thêm chứng từ") { if save(cash: 0, bank: 0, route: .freight) { stage = "proof" } }
                Button("Chưa giao", role: .cancel) {}
            }
        }
    }
    private func save(cash: Int64, bank: Int64, route: DeliveryRoute) -> Bool {
        let mode: PaymentMode = cash > 0 && bank > 0 ? .mixed : bank > 0 ? .bank : cash > 0 ? .cash : .deferred
        return store.change { try $0.settle(id, value: Settlement(outcome: .delivered, mode: mode, cash: cash, bank: bank, note: "", at: Date(), route: route)) }
    }
    private func savePartial(now: Bool) {
        guard let order else { return }
        do {
            let c = try VND.parse(partial)
            guard c < order.total, c + order.bank < order.total else { throw DeliveryError.invalid("Thu đủ: chọn Thu đủ tiền mặt. Khoản thu một phần phải nhỏ hơn tổng đơn.") }
            if c == 0 && now { stage = "qr"; return }
            if save(cash: c, bank: order.bank, route: .transferLater) { stage = now ? "qr" : "proof" }
        } catch { store.message = error.localizedDescription }
    }
    private func confirmTransfer() {
        guard let order else { return }
        do {
            let amount = try VND.parse(bankAmount)
            guard amount > 0, amount <= order.remaining else { throw DeliveryError.invalid("Khoản chuyển phải lớn hơn 0 và không vượt phần còn lại.") }
            if save(cash: order.cash, bank: order.bank + amount, route: .transferNow) { stage = "proof" }
        } catch { store.message = error.localizedDescription }
    }
}
