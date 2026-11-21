import SwiftUI

/// Only the worklist uses this sheet. The delivery buttons retain their existing flows.
struct CustomerTransferConfirmationView: View {
    let id: UUID
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var pending: CustomerTransferConfirmation?
    @State private var problem = ""
    var body: some View {
        NavigationStack {
            SweepGroupedScroll {
                if let order = store.order(id) {
                    SweepCard {
                        Text(order.displayCustomer).font(.subheadline.weight(.semibold))
                        LabeledContent("Mã phiếu", value: order.code)
                        LabeledContent("Còn chờ chuyển", value: VND.format(order.remaining))
                    }
                    if !problem.isEmpty { Text(problem).foregroundStyle(.red).accessibilityIdentifier("work.transfer.problem") }
                    SweepCard {
                        Button("Khách chuyển khoản rồi") {
                            guard let payment = order.settlement else { return }
                            pending = CustomerTransferConfirmation(settlementID: payment.id, amount: order.remaining)
                        }.buttonStyle(SweepPill())
                            .disabled(store.busy || store.blocked || order.remaining <= 0 || order.voidReason != nil)
                            .accessibilityIdentifier("work.transfer.confirm")
                        Button("Huỷ", role: .cancel) { dismiss() }.buttonStyle(SweepPill())
                            .accessibilityIdentifier("work.transfer.cancel")
                    }
                }
            }
            .sendeliNavigationTitle("Xác nhận chuyển khoản").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .alert("Khách đã chuyển đủ phần còn lại?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { value in
                Button("Xác nhận và hoàn tất") {
                    if store.change({ try $0.confirmCustomerTransfer(id, settlementID: value.settlementID, amount: value.amount) }) { dismiss() }
                    else { problem = store.message ?? "Chưa lưu được xác nhận."; store.message = nil }
                }
                Button("Huỷ", role: .cancel) {}
            } message: { value in
                Text("Xác nhận đã nhận \(VND.format(value.amount)). Nhắc tiền sẽ được bỏ sau khi lưu.")
            }
        }
    }
}
