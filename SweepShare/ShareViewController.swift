import UIKit
import UniformTypeIdentifiers
import ImageIO

/// Runs inside the sender's share sheet. No private openURL/UIApplication workaround.
@MainActor
final class ShareViewController: UIViewController {
    private let imageView = UIImageView()
    private let status = UILabel()
    private let saveButton = UIButton(type: .system)
    private var imageURL: URL?
    private var work: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: 400, height: 530)
        let title = UILabel(); title.text = "Nhận phiếu vào Sweep"; title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true; title.numberOfLines = 0
        let cancel = UIButton(type: .system)
        cancel.setTitle("Hủy", for: .normal)
        cancel.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, cancel]); header.spacing = 12
        imageView.contentMode = .scaleAspectFit
        imageView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        status.font = .preferredFont(forTextStyle: .body); status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0; status.text = "Đang nhận ảnh…"
        var config = UIButton.Configuration.filled(); config.title = "Gửi đến Sweep"; config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .large; saveButton.configuration = config; saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveShare), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [header, imageView, status, saveButton])
        stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        work = Task { await receive() }
    }

    private func receive() async {
        do {
            _ = try SharedInvoiceInbox.live() // Fail visibly if re-signing removed the group entitlement.
            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            var images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.canLoadObject(ofClass: UIImage.self) }
            if images.isEmpty, providers.count == 1, providers[0].hasItemConformingToTypeIdentifier(UTType.data.identifier) { images = providers }
            guard images.count == 1, let provider = images.first else { throw DeliveryError.invalid("Mỗi lần nhận một ảnh phiếu JPEG, PNG hoặc HEIC. Chọn ảnh trong Zalo rồi chia sẻ lại.") }
            let url = try await SharedInvoiceLoader.load(from: provider)
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
            imageURL = url
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 900
               ] as CFDictionary) { imageView.image = UIImage(cgImage: thumbnail) }
            status.text = "Gửi ảnh vào hộp thư Sweep. Khi mở Sweep, ảnh sẽ hiện để Sếp kiểm tra và nhập đơn."
            saveButton.isEnabled = true
        } catch { status.text = error.localizedDescription }
    }

    @objc private func saveShare() {
        guard let imageURL else { return }
        saveButton.isEnabled = false; status.text = "Đang lưu ảnh…"
        work = Task {
            do {
                try await Task.detached(priority: .userInitiated) { _ = try SharedInvoiceInbox.live().add(imageURL) }.value
                cleanup()
                extensionContext?.completeRequest(returningItems: nil)
            } catch { status.text = error.localizedDescription; saveButton.isEnabled = true }
        }
    }
    @objc private func cancelShare() {
        // Once a durable write starts, let it finish instead of racing cancellation with publication.
        guard imageURL == nil || saveButton.isEnabled else { return }
        work?.cancel(); cleanup()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
    private func cleanup() {
        if let imageURL { try? FileManager.default.removeItem(at: imageURL) }; imageURL = nil
    }
    deinit { work?.cancel(); if let imageURL { try? FileManager.default.removeItem(at: imageURL) } }
}
