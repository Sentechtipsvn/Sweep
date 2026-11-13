import UIKit
import UniformTypeIdentifiers
import ImageIO
import PhotosUI

/// Runs inside the sender's share sheet. No private openURL/UIApplication workaround.
@MainActor
final class ShareViewController: UIViewController, PHPickerViewControllerDelegate {
    private let imageView = UIImageView()
    private let status = UILabel()
    private let saveButton = UIButton(type: .system)
    private let photoButton = UIButton(type: .system)
    private let detailsButton = UIButton(type: .system)
    private var errorDetails = ""
    private var inboxReady = false
    private var saving = false
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
        imageView.isHidden = true
        imageView.heightAnchor.constraint(equalToConstant: 240).isActive = true
        status.font = .preferredFont(forTextStyle: .body); status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0; status.text = "Đang nhận ảnh…"
        var config = UIButton.Configuration.filled(); config.title = "Gửi đến Sweep"; config.baseBackgroundColor = .systemGreen
        config.cornerStyle = .large; saveButton.configuration = config; saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveShare), for: .touchUpInside)
        var photoConfig = UIButton.Configuration.tinted(); photoConfig.title = "Chọn từ Ảnh"; photoConfig.image = UIImage(systemName: "photo.on.rectangle"); photoConfig.imagePadding = 10
        photoConfig.baseBackgroundColor = .systemGreen; photoButton.configuration = photoConfig; photoButton.isEnabled = false
        photoButton.addTarget(self, action: #selector(choosePhoto), for: .touchUpInside)
        detailsButton.setTitle("Chi tiết lỗi", for: .normal); detailsButton.isHidden = true
        detailsButton.addTarget(self, action: #selector(showDetails), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [header, imageView, status, photoButton, detailsButton, saveButton])
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
            _ = try SharedInvoiceInbox.live()
            inboxReady = true; photoButton.isEnabled = true
            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            var images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.canLoadObject(ofClass: UIImage.self) }
            if images.isEmpty, providers.count == 1, providers[0].hasItemConformingToTypeIdentifier(UTType.data.identifier) { images = providers }
            guard images.count == 1, let provider = images.first else { throw DeliveryError.invalid("Mỗi lần nhận một ảnh phiếu. Sếp có thể chọn lại ảnh từ thư viện.") }
            await load(provider)
        } catch { showError(error) }
    }

    private func load(_ provider: NSItemProvider) async {
        cleanup(); imageView.image = nil; imageView.isHidden = true
        saveButton.isEnabled = false; photoButton.isEnabled = false; detailsButton.isHidden = true
        status.text = "Đang nhận ảnh…"
        do {
            let url = try await SharedInvoiceLoader.load(from: provider)
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
            imageURL = url
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 900
               ] as CFDictionary) { imageView.image = UIImage(cgImage: thumbnail); imageView.isHidden = false }
            status.text = "Ảnh sẵn sàng. Gửi đến Sweep để nhập đơn."
            saveButton.isEnabled = true
        } catch { if !Task.isCancelled { showError(error) } }
        photoButton.isEnabled = inboxReady
    }

    @objc private func choosePhoto() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images; config.selectionLimit = 1; config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config); picker.delegate = self
        present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        work?.cancel(); work = Task { await load(provider) }
    }
    private func showError(_ error: Error) {
        errorDetails = error.localizedDescription; detailsButton.isHidden = false
        status.text = inboxReady ? "Chưa đọc được ảnh chia sẻ. Sếp có thể chọn ảnh từ thư viện để tiếp tục." : errorDetails
        photoButton.isEnabled = inboxReady
    }
    @objc private func showDetails() {
        let alert = UIAlertController(title: "Thông tin nguồn ảnh", message: errorDetails, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Sao chép", style: .default) { [weak self] _ in UIPasteboard.general.string = self?.errorDetails })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func saveShare() {
        guard let imageURL else { return }
        saving = true; photoButton.isEnabled = false; saveButton.isEnabled = false; status.text = "Đang lưu ảnh…"
        work = Task {
            do {
                try await Task.detached(priority: .userInitiated) { _ = try SharedInvoiceInbox.live().add(imageURL) }.value
                cleanup()
                extensionContext?.completeRequest(returningItems: nil)
            } catch { saving = false; showError(error); saveButton.isEnabled = true }
        }
    }
    @objc private func cancelShare() {
        // Once a durable write starts, let it finish instead of racing cancellation with publication.
        guard !saving else { return }
        work?.cancel(); cleanup()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
    private func cleanup() {
        if let imageURL { try? FileManager.default.removeItem(at: imageURL) }; imageURL = nil
    }
    deinit { work?.cancel(); if let imageURL { try? FileManager.default.removeItem(at: imageURL) } }
}
