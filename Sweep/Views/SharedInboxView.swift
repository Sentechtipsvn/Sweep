import SwiftUI

@MainActor
final class SharedInboxStore: ObservableObject {
    @Published private(set) var items: [SharedInvoiceInbox.Item] = []
    @Published private(set) var warnings: [String] = []
    @Published private(set) var problem = ""
    private var loading = false

    func reload() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do {
            let scan = try await Task.detached(priority: .utility) { try SharedInvoiceInbox.live().scan() }.value
            items = scan.items; warnings = scan.warnings; problem = ""
        } catch { problem = error.localizedDescription }
    }
    func remove(_ item: SharedInvoiceInbox.Item) async -> Bool {
        do {
            try await Task.detached(priority: .utility) { try SharedInvoiceInbox.live().remove(item) }.value
            await reload(); return true
        } catch { problem = error.localizedDescription; return false }
    }
}

struct SharedInboxView: View {
    @ObservedObject var inbox: SharedInboxStore
    let saved: (UUID) -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SharedInvoiceInbox.Item?
    @State private var discarding: SharedInvoiceInbox.Item?
    @State private var imported: UUID?
    @State private var autoOpened = false
    var body: some View {
        NavigationStack {
            List {
                if !inbox.problem.isEmpty { Section { Text(inbox.problem).foregroundStyle(.orange) } }
                Section("\(inbox.items.count) ảnh chờ nhận") {
                    if inbox.items.isEmpty { Text("Chưa có ảnh chờ nhận.").foregroundStyle(.secondary) }
                    ForEach(inbox.items) { item in
                        Button { selected = item } label: {
                            HStack {
                                EvidenceThumbnail(url: item.image, height: 70).frame(width: 100)
                                VStack(alignment: .leading) {
                                    Text("Kiểm tra và nhập phiếu").font(.headline)
                                    Text(item.receivedAt.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.accessibilityIdentifier("shared.item")
                            .swipeActions { Button("Xóa ảnh chờ", role: .destructive) { discarding = item } }
                    }
                }
                if !inbox.warnings.isEmpty { Section("Cần kiểm tra") { ForEach(Array(inbox.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) } } }
            }
            .navigationTitle("Ảnh được chia sẻ").navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheet { dismiss() } }
            .refreshable { await inbox.reload() }
            .sheet(item: $selected, onDismiss: { if let id = imported { imported = nil; saved(id) } }) { item in
                OrderIntakeView(shared: item) { id in
                    Task {
                        // The ledger commit must precede removing the queue item. sourceID makes a retry idempotent.
                        if !(await inbox.remove(item)) { store.message = "Đơn đã lưu, nhưng ảnh chờ chưa dọn được. Nhập lại sẽ mở đúng hồ sơ cũ. " + inbox.problem }
                        imported = id; selected = nil
                    }
                }
            }
            .alert("Xóa ảnh chờ nhận?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
                Button("Xóa ảnh chờ", role: .destructive) { if let item = discarding { Task { _ = await inbox.remove(item) } }; discarding = nil }
                Button("Giữ lại", role: .cancel) { discarding = nil }
            } message: { Text("Chỉ bỏ ảnh trong hộp thư Sweep. Đơn đã nhập và ảnh gốc trong Zalo không bị thay đổi.") }
            .task {
                guard !autoOpened else { return }; autoOpened = true
                if inbox.items.count == 1 { selected = inbox.items.first }
            }
        }
    }
}
