import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import ImageIO

private enum EvidenceThumbnails {
    static let cache: NSCache<NSURL, UIImage> = {
        let value = NSCache<NSURL, UIImage>(); value.countLimit = 80; value.totalCostLimit = 24 * 1024 * 1024; return value
    }()
}

/// SwiftUI onAppear can run before a modal transition finishes. Offer alerts only once UIKit has appeared.
struct SweepAppearanceAction: UIViewControllerRepresentable {
    let action: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(action: action) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.action = action }
    final class Controller: UIViewController {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            DispatchQueue.main.async { [weak self] in self?.action() }
        }
    }
}

struct EvidenceThumbnail: View {
    let url: URL
    var height: CGFloat = 160
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: image != nil)
        .task(id: url) {
            let key = url.appendingPathExtension("thumb-\(Int(height))") as NSURL
            if let cached = EvidenceThumbnails.cache.object(forKey: key) { image = cached; return }
            let pixels = max(160, min(1200, Int(height * 3)))
            let result = await Task.detached(priority: .utility) { Self.thumbnail(url, pixels: pixels) }.value
            guard !Task.isCancelled else { return }
            if let result { EvidenceThumbnails.cache.setObject(result, forKey: key, cost: (result.cgImage?.bytesPerRow ?? 0) * (result.cgImage?.height ?? 0)) }
            image = result
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
    let onChoose: (URL, String?) async -> Void
    @EnvironmentObject private var store: DeliveryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            HStack(alignment: .top, spacing: 10) { photoButton; cameraButton }
            if loading { ProgressView() }
        }
        .buttonStyle(SweepPill()).disabled(store.busy || store.blocked || loading)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                loading = true; defer { loading = false; selection = nil }
                do {
                    let ready = try await loadEvidencePhoto(item)
                    defer { try? FileManager.default.removeItem(at: ready) }
                    await onChoose(ready, item.itemIdentifier)
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
                        await onChoose(ready, nil)
                    } catch { store.message = error.localizedDescription }
                }
            }.ignoresSafeArea()
        }
    }
    private var photoButton: some View {
        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .compatible, photoLibrary: .shared()) {
            sourceLabel("Chọn ảnh", icon: "photo.on.rectangle")
        }.accessibilityIdentifier("evidence.photos")
    }
    private var cameraButton: some View {
        Button { camera = true } label: {
            sourceLabel("Chụp ảnh", icon: "camera")
        }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera)).accessibilityIdentifier("evidence.camera")
    }
    @ViewBuilder private func sourceLabel(_ title: String, icon: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title.replacingOccurrences(of: " ", with: "\n"))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel(title)
        } else {
            Label(title, systemImage: icon)
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
    @Environment(\.dismiss) private var dismiss
    var completion: ((UIActivity.ActivityType?, Bool, Error?) -> Void)? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, error in
            DispatchQueue.main.async {
                if let completion { completion(activity, completed, error) }
                else { dismiss() }
            }
        }
        return controller
    }
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
        }.frame(minHeight: 44)
    }
}

struct CloseSheet: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent { ToolbarItem(placement: .topBarTrailing) { Button("Đóng", action: action) } }
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
        }.sendeliNavigationTitle("QR công ty").quickLookPreview($preview)
    }
}

extension View {
    func sendeliNavigationTitle(_ title: String) -> some View {
        navigationTitle(title).background(BackTitleInstaller().frame(width: 0, height: 0))
    }
}

private struct BackTitleInstaller: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        func install() {
            guard let stack = navigationController else { return }
            for page in stack.viewControllers {
                page.navigationItem.backButtonDisplayMode = .default
                page.navigationItem.backButtonTitle = "Trở về"
            }
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
    }
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.install() }
}


private func loadEvidencePhoto(_ item: PhotosPickerItem) async throws -> URL {
    var ready: URL?
    if let data = try? await item.loadTransferable(type: Data.self) {
        ready = try? await Task.detached { try IncomingInvoiceImage.copy(data: data) }.value
    }
    if ready == nil, let image = try await item.loadTransferable(type: ImportedImage.self) {
        ready = try await Task.detached { try IncomingInvoiceImage.copy(from: image.url) }.value
        withExtendedLifetime(image) {}
    }
    guard let ready else { throw DeliveryError.invalid("Chưa tải được ảnh. Mở ảnh trong thư viện rồi chọn lại.") }
    return ready
}

struct EditablePhoto: View {
    let url: URL
    let height: CGFloat
    let title: String
    var editable = true
    let replace: (URL, String?) async -> Void
    let remove: () -> Void
    @EnvironmentObject private var store: DeliveryStore
    @State private var picker = false
    @State private var choice: PhotosPickerItem?
    @State private var preview = false
    @State private var removing = false
    var body: some View {
        Button { preview = true } label: { EvidenceThumbnail(url: url, height: height) }
            .buttonStyle(.plain)
            .contextMenu {
                if editable {
                    Button("Đổi ảnh") { picker = true }
                    Button("Xoá khỏi đơn", role: .destructive) { removing = true }
                }
            }
            .alert("Xoá ảnh khỏi đơn?", isPresented: $removing) {
                Button("Xoá khỏi đơn", role: .destructive, action: remove)
                Button("Giữ ảnh", role: .cancel) {}
            } message: { Text(title) }
            .photosPicker(isPresented: $picker, selection: $choice, matching: .images, preferredItemEncoding: .compatible, photoLibrary: .shared())
            .onChange(of: choice) { _, item in
                guard let item else { return }
                Task {
                    defer { choice = nil }
                    do {
                        let ready = try await loadEvidencePhoto(item)
                        defer { try? FileManager.default.removeItem(at: ready) }
                        await replace(ready, item.itemIdentifier)
                    } catch { store.message = error.localizedDescription }
                }
            }
            .sheet(isPresented: $preview) {
                NavigationStack {
                    GeometryReader { geometry in EvidenceThumbnail(url: url, height: geometry.size.height) }
                        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { CloseSheet { preview = false } }
                }
            }
    }
}

struct OrderPhoto: View {
    let order: DeliveryOrder
    let file: DeliveryEvidence
    let height: CGFloat
    @EnvironmentObject private var store: DeliveryStore
    var body: some View {
        EditablePhoto(url: store.url(file), height: height, title: [order.code, order.displayCustomer, file.role.rawValue].joined(separator: " · "), editable: order.voidReason == nil) { url, asset in
            await store.attach(url, role: file.role, to: order.id, asset: asset, replacing: file.id)
        } remove: {
            _ = store.change { try $0.excludeEvidence(file.id, orderID: order.id, reason: "Chọn nhầm ảnh") }
        }
    }
}
