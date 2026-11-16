import SwiftUI

struct SendeliSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var phase
    @State private var index = 0
    @State private var hintOffset: CGFloat = 0
    @State private var hintOpacity = 1.0
    private let hints = ["Tên khách", "Mã phiếu", "Số điện thoại"]
    private var animateHints: Bool { phase == .active && text.isEmpty && !focused && !reduced }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("", text: $text).focused($focused)
                .accessibilityLabel("Tìm đơn theo tên khách, mã phiếu hoặc số điện thoại")
                .accessibilityIdentifier("orders.search")
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        if text.isEmpty && !focused {
                            // One label leaves completely before its replacement enters.
                            Text(hints[index]).foregroundStyle(.secondary)
                                .frame(maxHeight: .infinity, alignment: .leading)
                                .offset(x: hintOffset).opacity(hintOpacity)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        Color.clear.task(id: animateHints) { await rotateHints(width: geometry.size.width) }
                    }.allowsHitTesting(false)
                }.clipped()
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).accessibilityLabel("Xóa tìm kiếm") }
        }.padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
    @MainActor private func rotateHints(width: CGFloat) async {
        hintOffset = 0; hintOpacity = 1
        guard animateHints else { return }
        do {
            try await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                withAnimation(.easeIn(duration: 0.4)) { hintOffset = width * 0.45; hintOpacity = 0 }
                try await Task.sleep(for: .seconds(0.4))
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { index = (index + 1) % hints.count; hintOffset = -min(width * 0.3, 90); hintOpacity = 0 }
                try await Task.sleep(for: .milliseconds(20))
                withAnimation(.easeOut(duration: 0.3)) { hintOffset = 0; hintOpacity = 1 }
                try await Task.sleep(for: .seconds(1.58))
            }
        } catch { hintOffset = 0; hintOpacity = 1 }
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
                    case .payment: Button { payment = item } label: { row(item) }.buttonStyle(.borderless).accessibilityIdentifier("work.payment.\(item.orderID?.uuidString ?? item.id)")
                    case .sales: EmptyView()
                    }
                }
                let sales = items.filter { !$0.actionable }
                if !sales.isEmpty { Section("Bán hàng theo dõi") {
                    ForEach(sales) { item in Button { payment = item } label: { row(item) }.buttonStyle(.borderless).accessibilityIdentifier("work.freight.\(item.orderID?.uuidString ?? item.id)") }
                } }
            }
        }.navigationTitle("Việc cần chốt")
            .sheet(item: $payment) { item in if let id = item.orderID { CustomerTransferConfirmationView(id: id) } }
    }
    private func row(_ item: DeliveryWorkItem) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.headline); Text(item.detail).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 4)
    }
}
