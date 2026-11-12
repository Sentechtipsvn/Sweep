import SwiftUI

struct ReconciliationView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var month = Date()
    @State private var accountantCount = ""
    @State private var accountantAmount = ""
    @State private var handover = false
    @State private var sharing: DeliveryShare?
    private var entries: [(DeliveryOrder, SignedAssignment)] { store.ledger.commissions(in: month).sorted { $0.1.signedAt < $1.1.signedAt } }
    private var fees: Int64 { entries.reduce(0) { $0 + $1.1.fee } }
    private var monthTitle: String { let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "MM/yyyy"; return f.string(from: month) }
    var body: some View {
        List {
            Section("Công theo ngày ký nhận") {
                HStack {
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Tháng trước")
                    Spacer(); Text("Tháng \(monthTitle)").font(.headline); Spacer()
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Tháng sau")
                }.buttonStyle(.borderless)
                LabeledContent("Phiếu ký hợp lệ", value: "\(entries.count)").accessibilityIdentifier("audit.count")
                LabeledContent("Công đã ghi nhận", value: VND.format(fees)).font(.headline).foregroundStyle(.green)
                Text("Tính cả phiếu giao thất bại / chưa thu. Mức công lưu theo từng lượt ký, không phải lương đã nhận.").font(.caption).foregroundStyle(.secondary)
                Button("Xuất toàn bộ phiếu tháng này (CSV)") {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-cong-\(monthTitle.replacingOccurrences(of: "/", with: "-"))-\(UUID().uuidString.prefix(6)).csv")
                    do { try Data(store.ledger.csv(in: month).utf8).write(to: url, options: .atomic); sharing = DeliveryShare(items: [url]) }
                    catch { store.message = error.localizedDescription }
                }
            }
            Section("Đối chiếu với kế toán · chưa lưu vào sổ") {
                HStack { Text("Số phiếu kế toán"); TextField("Chưa nhập", text: $accountantCount).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                MoneyInput(title: "Công kế toán", text: $accountantAmount)
                if let count = Int(accountantCount), count >= 0 { Text("Sweep − kế toán: \(entries.count - count) phiếu").font(.subheadline) }
                if !accountantAmount.isEmpty, let amount = try? VND.parse(accountantAmount) { Text("Chênh công: \(VND.format(fees - amount))").font(.subheadline) }
                Text("Dùng danh sách mã phiếu phía dưới / CSV để tìm phần chênh, chưa kết luận bên nào đúng.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Tiền mặt công ty · toàn sổ") {
                LabeledContent("Đã thu", value: VND.format(store.ledger.cashCollected))
                LabeledContent("Đã nộp", value: VND.format(store.ledger.cashHanded))
                LabeledContent("Còn giữ", value: VND.format(store.ledger.cashHeld)).font(.headline)
                Button("Ghi lần nộp tiền…") { handover = true }.accessibilityIdentifier("audit.handover")
                NavigationLink("Lịch sử nộp tiền") {
                    List(store.ledger.handovers.reversed()) { value in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(VND.format(value.amount)).font(.headline)
                            Text(value.at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text(value.note).font(.footnote)
                        }
                    }.navigationTitle("Tiền đã nộp")
                }
                Text("Tiền công tách riêng. Sweep không tự trừ công khỏi tiền phải nộp.").font(.caption).foregroundStyle(.secondary)
            }
            Section("CK chờ đối soát công ty · toàn sổ") {
                LabeledContent("Chưa xác nhận vào công ty", value: VND.format(store.ledger.bankPending))
                ForEach(store.ledger.orders.filter { $0.bank > $0.verifiedBank }) { order in
                    NavigationLink { OrderDetailView(id: order.id) } label: { LabeledContent(order.customer, value: VND.format(order.bank - order.verifiedBank)) }
                }
            }
            Section("Phiếu tính công trong tháng · \(entries.count)") {
                ForEach(entries, id: \.1.id) { order, assignment in
                    NavigationLink { OrderDetailView(id: order.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(order.customer); Spacer(); Text(VND.format(assignment.fee)) }
                            Text("\(order.code) · \(assignment.signedAt.formatted(date: .numeric, time: .omitted)) · \(order.outcome.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Đối soát")
        .sheet(isPresented: $handover) { HandoverView() }
        .sheet(item: $sharing) { DeliveryShareSheet(items: $0.items) }
    }
    private func moveMonth(_ offset: Int) { month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month; accountantCount = ""; accountantAmount = "" }
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
