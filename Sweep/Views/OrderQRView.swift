import SwiftUI
import WebKit

struct OrderQRView: View {
    private struct Request: Equatable { let id = UUID(); let url: URL }
    let id: UUID
    var suggested: Int64? = nil
    @EnvironmentObject private var store: DeliveryStore
    @State private var amount = ""
    @State private var requested: Request?
    @State private var requestedAmount = ""
    @State private var svg: Data?
    @State private var loading = false
    @State private var problem = ""
    private var order: DeliveryOrder? { store.order(id) }
    var body: some View {
        Form {
            if let order {
                Section {
                    Text(order.customer).font(.headline)
                    LabeledContent("Mã phiếu", value: order.code)
                    LabeledContent("Tổng đơn", value: VND.format(order.total))
                    LabeledContent("Còn lại theo ghi nhận", value: VND.format(order.remaining))
                }
                if let account = store.ledger.settings.vietQR {
                    Section("Tài khoản nhận") {
                        LabeledContent("Ngân hàng / BIN", value: account.bankID)
                        LabeledContent("Số tài khoản", value: account.accountNumber).textSelection(.enabled)
                        Text(account.accountName).font(.headline)
                    }
                    Section("Chuyển khoản cho đơn này") {
                        MoneyInput(title: "Số tiền QR", text: $amount, identifier: "qr.amount")
                        Text("Nội dung: \(VietQR.transferNote(code: order.code))").font(.subheadline)
                        Button("Tạo QR chuyển khoản") { generate() }
                            .accessibilityIdentifier("qr.generate").disabled(loading || order.voidReason != nil)

                        if loading { ProgressView("Đang tạo VietQR…") }
                        if !problem.isEmpty { Text(problem).foregroundStyle(.orange); Button("Thử lại") { generate() }.disabled(loading) }
                        if let svg {
                            QRImage(svg: svg).frame(height: 340).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityLabel("Mã QR chuyển khoản cho đơn \(order.code), \(amount) đồng")
                            Text("\(VND.format((try? VND.parse(amount)) ?? 0))").font(.title2.bold()).frame(maxWidth: .infinity).monospacedDigit()
                        }
                        Text("Quý khách kiểm tra số tiền trước khi chuyển khoản")
                            .font(.headline).foregroundStyle(Color(red: 86/255, green: 1, blue: 44/255))
                            .padding().frame(maxWidth: .infinity).background(Color(red: 0.07, green: 0.2, blue: 0.15), in: RoundedRectangle(cornerRadius: 16))

                    }
                } else {
                    Section {
                        Text("Điền ngân hàng, số tài khoản và chủ tài khoản một lần trước khi tạo QR theo đơn.")
                        NavigationLink("Thiết lập tài khoản VietQR") { DeliverySettingsView() }
                    }
                }
            }
        }
        .navigationTitle("QR chuyển khoản").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .onAppear { if amount.isEmpty, let order { amount = String(suggested ?? VietQR.suggestedAmount(for: order)); generate() } }
        .onChange(of: amount) { _, value in if value != requestedAmount { invalidate() } }
        .onChange(of: store.ledger.settings.vietQR) { _, _ in invalidate() }
        .onChange(of: order) { _, _ in invalidate() }
        .task(id: requested) {
            guard let request = requested else { return }
            loading = true; defer { if requested == request { loading = false } }
            do {
                let data = try await VietQRService.svg(for: request.url)
                guard !Task.isCancelled, requested == request else { return }; svg = data
            } catch {
                guard !Task.isCancelled, requested == request else { return }
                problem = "Chưa tải được QR: " + error.localizedDescription
            }
        }
    }
    private func invalidate() { requested = nil; svg = nil; problem = ""; loading = false }
    private func generate() {
        invalidate()
        guard let order, let account = store.ledger.settings.vietQR else { return }
        do { requestedAmount = amount; requested = Request(url: try VietQR.url(account: account, order: order, amount: VND.parse(amount))) }
        catch { problem = error.localizedDescription }
    }
}

/// Display SVG as an inert image in a local, script-free document. No external navigation/resources.
private struct QRImage: UIViewRepresentable {
    let svg: Data
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .white
        web.scrollView.isScrollEnabled = false; web.isUserInteractionEnabled = false
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.data != svg else { return }; context.coordinator.data = svg
        web.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>html,body{margin:0;height:100%;background:white}body{display:grid;place-items:center}img{width:100%;height:100%;object-fit:contain}</style>
        </head><body><img alt="VietQR" src="data:image/svg+xml;base64,\(svg.base64EncodedString())"></body></html>
        """, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data: Data? }
}
