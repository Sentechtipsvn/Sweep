import SwiftUI
import AppIntents

extension Notification.Name {
    static let sweepInboxReceived = Notification.Name("SweepInboxReceived")
    static let sweepRenewalSelected = Notification.Name("SweepRenewalSelected")
}
@MainActor
final class SweepRouter: ObservableObject {
    @Published var tab = 0
    @Published var tools: [String] = []
    @Published var settings: [String] = []
    @Published var orderID: UUID?
    func open(_ url: URL) {
        guard url.scheme == "sweep", url.user == nil, url.password == nil,
              let host = url.host, url.query == nil, url.fragment == nil else { return }
        switch host {
        case "attendance", "payroll":
            guard url.path.isEmpty else { return }; tab = 2; tools = ["payroll"]
        case "renewal":
            guard url.path.isEmpty else { return }; tab = 3; settings = ["renewal"]
        case "order":
            guard let id = UUID(uuidString: String(url.path.dropFirst())), url.path.split(separator: "/").count == 1 else { return }
            orderID = id; tab = 0
        default: break
        }
    }
}
struct ReceiveSweepInvoice: AppIntent {
    static var title: LocalizedStringResource = "Nhận phiếu Sweep"
    static var description = IntentDescription("Nhận ảnh chia sẻ và mở Sweep để kiểm tra, đọc và nhập đơn.")
    static var openAppWhenRun = true
    @Parameter(title: "Ảnh phiếu") var image: IntentFile
    func perform() async throws -> some IntentResult {
        let bytes = image.data
        guard !bytes.isEmpty, bytes.count <= 80 * 1024 * 1024 else { throw DeliveryError.invalid("Chọn một ảnh phiếu tối đa 80 MB.") }
        _ = try await Task.detached(priority: .userInitiated) {
            let url = try IncomingInvoiceImage.copy(data: bytes)
            defer { try? FileManager.default.removeItem(at: url) }
            return try SharedInvoiceInbox.live().add(url)
        }.value
        await MainActor.run { NotificationCenter.default.post(name: .sweepInboxReceived, object: nil) }
        return .result()
    }
}
struct SweepShortcutGuide: View {
    var body: some View {
        List {
            Section("Nhận ảnh và mở Sweep") {
                Text("Trong Phím tắt, tạo phím tắt “Nhận phiếu Sweep”, bật Hiển thị trong bảng chia sẻ và nhận đầu vào là Hình ảnh.")
                Text("Thêm tác vụ “Nhận phiếu Sweep” của ứng dụng Sweep, chọn Ảnh phiếu = Đầu vào phím tắt.")
                Text("Trong Zalo hoặc Ảnh: Chia sẻ → Nhận phiếu Sweep. App nhận ảnh vào hàng đợi rồi mở trang kiểm tra đơn.")
            }
            Section {
                Text("Cần thử trên iPhone với phiên bản Zalo đang dùng. Đây là đường Phím tắt; biểu tượng Sweep trong bảng chia sẻ vẫn là tiện ích nhận ảnh, không tự bật app chính.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Nhận ảnh bằng Phím tắt").navigationBarTitleDisplayMode(.inline)
    }
}
