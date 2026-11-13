import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import ImageIO

struct EvidenceThumbnail: View {
    let url: URL
    var height: CGFloat = 160
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
        .task(id: url) {
            let pixels = max(160, min(1200, Int(height * 3)))
            image = await Task.detached(priority: .utility) { Self.thumbnail(url, pixels: pixels) }.value
        }
    }
    nonisolated private static func thumbnail(_ url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// All providers are copied while their read grant/Transferable is alive.
struct EvidencePicker: View {
    let title: String
    let onChoose: (URL) async -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { photoButton; cameraButton }
            } else {
                HStack(spacing: 12) { photoButton; cameraButton }
            }
            if loading { ProgressView() }
        }
        .buttonStyle(.bordered).controlSize(.large).disabled(store.busy || loading)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                loading = true; defer { loading = false; selection = nil }
                do {
                    var ready: URL?
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        ready = try? await Task.detached { try IncomingInvoiceImage.copy(data: data) }.value
                    }
                    if ready == nil, let image = try await item.loadTransferable(type: ImportedImage.self) {
                        ready = try await Task.detached { try IncomingInvoiceImage.copy(from: image.url) }.value
                        withExtendedLifetime(image) {}
                    }
                    guard let ready else { throw DeliveryError.invalid("Chưa tải được ảnh. Mở ảnh trong thư viện rồi chọn lại.") }
                    defer { try? FileManager.default.removeItem(at: ready) }
                    await onChoose(ready)
                } catch { store.message = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: $camera) {
            EvidenceCamera { image in
                camera = false
                guard let image else { return }
                Task {
                    loading = true; defer { loading = false }
                    do {
                        let ready = try SharedInvoiceLoader.copyImage(image)
                        defer { try? FileManager.default.removeItem(at: ready) }
                        await onChoose(ready)
                    } catch { store.message = error.localizedDescription }
                }
            }.ignoresSafeArea()
        }
    }
    private var photoButton: some View {
        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .compatible) {
            Label("Chọn ảnh", systemImage: "photo.on.rectangle").lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("evidence.photos")
    }
    private var cameraButton: some View {
        Button { camera = true } label: {
            Label("Chụp ảnh", systemImage: "camera").lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
        }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera)).accessibilityIdentifier("evidence.camera")
    }
}

private struct EvidenceCamera: UIViewControllerRepresentable {
    let finish: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (UIImage?) -> Void
        init(finish: @escaping (UIImage?) -> Void) { self.finish = finish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finish(info[.originalImage] as? UIImage) }
    }
}

struct DeliveryShare: Identifiable { let id = UUID(); let items: [Any] }
struct DeliveryShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MoneyInput: View {
    let title: String
    @Binding var text: String
    var identifier = ""
    var body: some View {
        HStack {
            Text(title); Spacer(minLength: 8)
            TextField("0", text: $text).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier).monospacedDigit()
            Text("₫").foregroundStyle(.secondary)
        }
    }
}

struct CloseSheet: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent { ToolbarItem(placement: .cancellationAction) { Button("Đóng", action: action) } }
}

struct BankCompanyView: View {
    @EnvironmentObject private var store: DeliveryStore
    @State private var preview: URL?
    var body: some View {
        List {
            Section("Tài khoản nhận của công ty") {
                Text(store.ledger.settings.company.isEmpty ? "Chưa cấu hình tên công ty" : store.ledger.settings.company).font(.headline)
                Text(store.ledger.settings.account.isEmpty ? "Cấu hình tài khoản/QR trong Cài đặt trước khi đưa khách." : store.ledger.settings.account).textSelection(.enabled)
                if let qr = store.ledger.settings.qr {
                    Button { preview = store.url(qr) } label: { EvidenceThumbnail(url: store.url(qr), height: 320) }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("QR công ty").quickLookPreview($preview)
    }
}
