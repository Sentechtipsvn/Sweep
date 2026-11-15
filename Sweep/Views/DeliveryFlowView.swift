import SwiftUI

enum DeliveryMethod: String, Identifiable { case cash = "Tiền mặt", bank = "Chuyển khoản", freight = "Giao chành"; var id: String { rawValue } }
struct DeliveryFlowView: View {
    private enum Stage { case start, partial, qr, proof }
    private enum Confirmation {
        case cash, partialNow, bank, freight, later
        var title: String {
            switch self {
            case .cash: return "Đã thu đủ tiền mặt?"
            case .partialNow: return "Xác nhận tiền mặt đã nhận?"
            case .bank: return "Ghi khoản chuyển thực nhận"
            case .freight: return "Đã bàn giao hàng cho chành?"
            case .later: return "Khách chuyển khoản sau?"
            }
        }
    }
    let id: UUID
    let method: DeliveryMethod
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var stage = Stage.start
    @State private var partial = ""
    @State private var bankAmount = ""
    @State private var confirmation: Confirmation?
    @State private var problem = ""
    private var order: DeliveryOrder? { store.order(id) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !problem.isEmpty { Text(problem).font(.callout).foregroundStyle(.red).padding().accessibilityIdentifier("flow.problem") }
                if let order {
                    if stage == .qr {
                        VStack(spacing: 0) {
                            OrderQRView(id: id, suggested: order.remaining)
                            Button("Đã nhận chuyển khoản…") { bankAmount = String(order.remaining); confirmation = .bank }
                                .buttonStyle(SweepPill(selected: true)).padding().background(.bar)
                                .accessibilityIdentifier("flow.confirmTransfer")
                                .disabled(order.remaining <= 0)
                        }
                    } else if stage == .proof {
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
                                    Button("Thu đủ tiền mặt") { confirmation = .cash }.buttonStyle(SweepPill(selected: true)).accessibilityIdentifier("flow.cashFull")
                                    Button("Thu một phần") { partial = String(order.cash); stage = .partial }.buttonStyle(SweepPill()).accessibilityIdentifier("flow.partial")
                                }.disabled(order.bank > 0 || order.total <= 0)
                                if stage == .partial {
                                    Section("Tiền mặt thực nhận") {
                                        MoneyInput(title: "Đã nhận", text: $partial, identifier: "flow.cash")
                                        if let c = try? VND.parse(partial), c <= order.total { LabeledContent("Còn lại", value: VND.format(order.total-c)) }
                                        Button("Phần còn lại chuyển khoản ngay") { confirmation = .partialNow }.accessibilityIdentifier("flow.partialNow")
                                        Button("Phần còn lại chuyển khoản sau…") { confirmation = .later }.accessibilityIdentifier("flow.partialLater")
                                    }
                                }
                            } else if method == .bank {
                                Section {
                                    Button("Chuyển khoản ngay") { stage = .qr }.buttonStyle(SweepPill(selected: true)).disabled(order.remaining <= 0).accessibilityIdentifier("flow.bankNow")
                                    Button("Chuyển khoản sau…") { confirmation = .later }.buttonStyle(SweepPill()).disabled(order.bank > 0 || order.remaining <= 0).accessibilityIdentifier("flow.bankLater")
                                    if order.bank > 0 { Button("Tiếp tục gửi chứng từ") { stage = .proof }.buttonStyle(SweepPill()) }
                                }
                            } else {
                                Section {
                                    Text("Gửi phiếu nhà xe đã ký và ảnh hàng đã gửi. Bán hàng theo dõi tiền.").font(.subheadline)
                                    Button("Đã giao hàng cho chành…") { confirmation = .freight }.buttonStyle(SweepPill(selected: true)).disabled(order.cash > 0 || order.bank > 0).accessibilityIdentifier("flow.freight")
                                }
                            }
                            Section { Button("Huỷ", role: .cancel) { dismiss() } }
                        }
                    }
                }
            }
            .navigationTitle(stage == .proof ? "Chứng từ giao hàng" : method.rawValue).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                CloseSheet { dismiss() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Xong") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
            .disabled(store.busy || store.blocked)
            .alert(confirmation?.title ?? "", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { value in
                switch value {
                case .cash:
                    Button("Đã nhận đủ") { if let o = order, save(cash: o.total, bank: 0, route: .cashFull) { dismiss() } }
                    Button("Kiểm tra lại", role: .cancel) {}
                case .bank:
                    TextField("Số tiền đã chuyển", text: $bankAmount).keyboardType(.numberPad)
                    Button("Xác nhận khoản thực nhận") { confirmTransfer() }
                    Button("Chưa nhận", role: .cancel) {}
                case .partialNow:
                    Button("Đã nhận, mở QR phần còn lại") { savePartial(now: true) }
                    Button("Kiểm tra lại", role: .cancel) {}
                case .later:
                    Button("Xác nhận, chọn phiếu đã ký") {
                        if method == .cash { savePartial(now: false) }
                        else if let o = order, save(cash: o.cash, bank: o.bank, route: .transferLater) { stage = .proof }
                    }
                    Button("Huỷ", role: .cancel) {}
                case .freight:
                    Button("Đã giao, thêm chứng từ") { if save(cash: 0, bank: 0, route: .freight) { stage = .proof } }
                    Button("Chưa giao", role: .cancel) {}
                }
            } message: { value in
                switch value {
                case .cash: Text("\(VND.format(order?.total ?? 0)). Không cần báo cáo ảnh; mang tiền và phiếu xuất kho về công ty.")
                case .bank: Text("Kiểm tra giao dịch thực tế. Đóng QR không ghi nhận tiền.")
                case .partialNow: Text("Tiền mặt \(partial)₫ sẽ được lưu trước khi mở QR. Đóng QR vẫn giữ khoản đã nhận.")
                case .later: Text("Chỉ gửi phiếu xuất kho khách đã ký; không gửi phiếu có giá.")
                case .freight: Text("Ghi nhận đã giao chành và bổ sung đúng chứng từ. Chưa ghi nhận tiền khách chuyển.")
                }
            }
        }
    }
    private func save(cash: Int64, bank: Int64, route: DeliveryRoute) -> Bool {
        let mode: PaymentMode = cash > 0 && bank > 0 ? .mixed : bank > 0 ? .bank : cash > 0 ? .cash : .deferred
        let saved = store.change { try $0.settle(id, value: Settlement(outcome: .delivered, mode: mode, cash: cash, bank: bank, note: "", at: Date(), route: route)) }
        problem = saved ? "" : store.message ?? "Chưa lưu được. Sếp kiểm tra trạng thái sổ rồi thử lại."
        if !saved { store.message = nil }
        return saved
    }
    private func savePartial(now: Bool) {
        guard let order else { return }
        do {
            let c = try VND.parse(partial)
            guard c >= order.cash else { throw DeliveryError.invalid("Đã ghi nhận tiền mặt \(VND.format(order.cash)). Dùng Điều chỉnh giao / tiền nếu cần sửa khoản đã lưu.") }
            guard c + order.bank <= order.total else { throw DeliveryError.invalid("Khoản đã nhận vượt tổng đơn. Kiểm tra lại số tiền.") }
            if c == order.total, order.bank == 0 {
                if save(cash: c, bank: 0, route: .cashFull) { dismiss() }; return
            }
            if c == 0 && now { stage = .qr; return }
            if save(cash: c, bank: order.bank, route: .transferLater) { stage = now ? .qr : .proof }
        } catch { problem = error.localizedDescription }
    }
    private func confirmTransfer() {
        guard let order else { return }
        do {
            let amount = try VND.parse(bankAmount)
            guard amount > 0, amount <= order.remaining else { throw DeliveryError.invalid("Khoản chuyển phải lớn hơn 0 và không vượt phần còn lại.") }
            if save(cash: order.cash, bank: order.bank + amount, route: .transferNow) { stage = .proof }
        } catch { problem = error.localizedDescription }
    }
}
