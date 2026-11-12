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
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// All providers are copied while their read grant/Transferable is alive.
struct EvidencePicker: View {
    let title: String
    let onChoose: (URL) async -> Void
    @EnvironmentObject private var store: DeliveryStore
    @State private var selection: PhotosPickerItem?
    @State private var filePicker = false
    @State private var camera = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            HStack {
                PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) { Label("Ảnh", systemImage: "photo") }
                Button { filePicker = true } label: { Label("Tệp", systemImage: "folder") }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Label("Chụp", systemImage: "camera") }
                }
            }.buttonStyle(.bordered).disabled(store.busy)
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let image = try await item.loadTransferable(type: ImportedImage.self) else { throw DeliveryError.invalid("Không đọc được ảnh.") }
                    defer { withExtendedLifetime(image) {} }
                    await onChoose(image.url)
                } catch { store.message = error.localizedDescription }
                selection = nil
            }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.jpeg, .png, .heic]) { result in
            Task {
                do {
                    let source = try result.get()
                    let image = try await Task.detached { try ImportedImage.copy(from: source) }.value
                    defer { withExtendedLifetime(image) {} }
                    await onChoose(image.url)
                } catch { store.message = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: $camera) {
            EvidenceCamera { image in
                camera = false
                guard let image else { return }
                Task {
                    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    defer { try? FileManager.default.removeItem(at: destination) }
                    do {
                        guard let data = image.jpegData(compressionQuality: 0.95) else { throw DeliveryError.invalid("Chưa đọc được ảnh vừa chụp.") }
                        try data.write(to: destination, options: .atomic); await onChoose(destination)
                    } catch { store.message = error.localizedDescription }
                }
            }.ignoresSafeArea()
        }
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
