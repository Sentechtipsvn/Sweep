import SwiftUI
import UniformTypeIdentifiers

struct MaintenanceView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var folder = false
    @State private var reset = false
    @State private var confirm = false
    @State private var confirmation = ""
    @State private var backupFolder: URL?
    @State private var result = ""
    var body: some View {
        Form {
            Section("Dọn bộ nhớ tạm") {
                Text("Xoá bản ảnh chia sẻ và tệp tạm có thể tạo lại. Giữ sổ, chứng từ và liên hệ.").font(.subheadline)
                Button("Sao lưu và dọn cache") { reset = false; folder = true }.buttonStyle(SweepPill())
            }
            Section("Bắt đầu dùng chính thức") {
                Text("Đặt lại toàn bộ dữ liệu thử nghiệm: đơn, ảnh trong Sweep, tiền, công, vị trí, liên hệ, cấu hình và ảnh chờ nhập. Không xoá ảnh trong thư viện hay Zalo.").font(.subheadline)
                Button("Sao lưu và xoá dữ liệu thử nghiệm…", role: .destructive) { reset = true; folder = true }.accessibilityIdentifier("maintenance.reset")
            }
            Section {
                Text("Chọn thư mục sao lưu ngoài Sweep. Chỉ xoá sau khi bản sao đã ghi xong và kiểm tra lại đầy đủ.").font(.caption).foregroundStyle(.secondary)
                if store.busy { ProgressView("Đang sao lưu và kiểm tra…") }
                if !result.isEmpty { Text(result).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Dọn dẹp").disabled(store.busy)
            .fileImporter(isPresented: $folder, allowedContentTypes: [.folder]) { selection in
                do { backupFolder = try selection.get(); confirmation = ""; confirm = true }
                catch { if (error as NSError).code != NSUserCancelledError { store.message = error.localizedDescription } }
            }
            .alert(reset ? "Xoá sạch dữ liệu thử nghiệm?" : "Sao lưu rồi dọn cache?", isPresented: $confirm) {
                if reset { TextField("Nhập XOA để xác nhận", text: $confirmation).textInputAutocapitalization(.characters) }
                Button(reset ? "Sao lưu và xoá sạch" : "Sao lưu và dọn", role: reset ? .destructive : nil) {
                    Task { if let dir = backupFolder, let backup = await store.maintain(backupFolder: dir, reset: reset) { result = "Đã hoàn tất. Bản sao: " + backup.lastPathComponent } }
                }.disabled(reset && confirmation != "XOA")
                Button("Huỷ", role: .cancel) {}
            } message: { Text(reset ? "Toàn bộ sổ và cấu hình trong Sweep sẽ bị xoá sau khi sao lưu. Nhập XOA để tiếp tục." : "Giữ nguyên dữ liệu giao hàng. Nếu sao lưu lỗi, Sweep không dọn.") }
    }
}
