import SwiftUI

struct SendeliSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var index = 0
    private let hints = ["Tên khách", "Mã phiếu", "Số điện thoại"]
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("", text: $text).focused($focused)
                .accessibilityLabel("Tìm đơn theo tên khách, mã phiếu hoặc số điện thoại")
                .accessibilityIdentifier("orders.search")
                .overlay(alignment: .leading) {
                    if text.isEmpty && !focused {
                        Text(hints[index]).foregroundStyle(.secondary).id(index)
                            .transition(reduced ? .opacity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.clipped()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).accessibilityLabel("Xóa tìm kiếm") }
        }.padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .task(id: phase == .active && text.isEmpty && !focused && !reduced) {
                guard phase == .active, text.isEmpty, !focused, !reduced else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    withAnimation(.easeInOut(duration: 0.35)) { index = (index + 1) % hints.count }
                }
            }
    }
}
struct AllDeliveryOrdersView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var query = ""
    var body: some View {
        List {
            SendeliSearchField(text: $query).listRowBackground(Color.clear)
            ForEach(store.ledger.orders.filter { query.isEmpty || ($0.customer + " " + $0.code + " " + $0.phone).localizedStandardContains(query) }.sorted { $0.importedAt > $1.importedAt }) { order in
                NavigationLink { OrderDetailView(id: order.id) } label: { SendeliOrderRow(order: order) }
                    .accessibilityIdentifier("order.\(order.code)")
            }
        }.navigationTitle("Tất cả đơn hàng")
    }
}
struct SendeliOrderRow: View {
    let order: DeliveryOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(order.customer).font(.headline); Spacer(); Text(VND.format(order.total)).font(.subheadline.bold()).monospacedDigit() }
            Text(order.code).font(.caption).foregroundStyle(.secondary)
            HStack {
                SweepOrderStatus(order: order); Spacer()
                if !order.activeAssignments.isEmpty { Label("Đã tính công", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                else { Text("Chưa tính công").foregroundStyle(.secondary) }
            }.font(.caption)
            if order.remaining > 0 && !order.taskComplete { Text("Chưa thu \(VND.format(order.remaining))").font(.caption).foregroundStyle(.orange) }
            if !order.reviewNote.isEmpty { Label("Cần rà soát dữ liệu cũ", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical, 6)
    }
}
struct DeliveryWorkView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var payment: DeliveryWorkItem?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            let items = DeliveryWorkItem.items(store.ledger, now: clock.date)
            List {
                ForEach(items.filter(\.actionable)) { item in
                    switch item.kind {
                    case .attendance: NavigationLink { PayrollView() } label: { row(item) }
                    case .cash: NavigationLink { HandoverView() } label: { row(item) }
                    case .report:
                        if let id = item.orderID { NavigationLink { OrderReportView(id: id) } label: { row(item) } }
                    case .payment: Button { payment = item } label: { row(item) }.buttonStyle(.borderless)
                    case .sales: EmptyView()
                    }
                }
                if items.filter(\.actionable).isEmpty { Text("Đã xử lý hết việc cần chốt.").foregroundStyle(.secondary) }
                let sales = items.filter { !$0.actionable }
                if !sales.isEmpty { Section("Bán hàng theo dõi") {
                    ForEach(sales) { item in if let id = item.orderID { NavigationLink { OrderDetailView(id: id) } label: { row(item) } } }
                } }
            }
        }.navigationTitle("Việc cần chốt")
            .sheet(item: $payment) { item in if let id = item.orderID { DeliveryFlowView(id: id, method: .bank) } }
    }
    private func row(_ item: DeliveryWorkItem) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.headline); Text(item.detail).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 4)
    }
}
