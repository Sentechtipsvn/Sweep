import UIKit

/// A non-key, pass-through window keeps feedback above sheets without changing
/// SwiftUI list/calendar sizing or presenting another modal controller.
@MainActor
final class DeliveryEffectsPresenter {
    private let window: SweepEffectsWindow
    private var toast: SweepSuccessToast?
    private var confetti: UIView?
    private var dismissToast: DispatchWorkItem?
    private var dismissConfetti: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    init(scene: UIWindowScene) {
        window = SweepEffectsWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.accessibilityIdentifier = "feedback.window"
        window.windowLevel = .normal + 1
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.accessibilityViewIsModal = false
        window.rootViewController = controller
        window.backgroundColor = .clear
        window.isHidden = false
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if UIAccessibility.isReduceMotionEnabled { self?.stopConfetti() } }
        })
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func show(_ notice: DeliverySuccessNotice, reduceMotion: Bool? = nil) {
        guard UIApplication.shared.applicationState == .active, let root = window.rootViewController?.view else { return }
        let reduced = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        dismissToast?.cancel()
        toast?.layer.removeAllAnimations(); toast?.removeFromSuperview()
        if reduced { stopConfetti() }
        if !notice.completedOrderIDs.isEmpty && !reduced { celebrate(in: root) }
        let card = SweepSuccessToast(text: notice.text)
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8),
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 500)
        ])
        root.layoutIfNeeded()
        toast = card
        card.alpha = 0
        card.transform = reduced ? .identity : CGAffineTransform(translationX: 0, y: -(root.safeAreaInsets.top + card.bounds.height + 24))
        UIView.animate(withDuration: reduced ? 0.15 : 0.32, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.2, options: [.allowUserInteraction, .beginFromCurrentState]) {
            card.alpha = 1; card.transform = .identity
        }
        card.animateTick(reduced: reduced)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: notice.text)
        let work = DispatchWorkItem { [weak self, weak card] in
            guard let self, let card, self.toast === card else { return }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction]) {
                card.alpha = 0
                if !reduced && !UIAccessibility.isReduceMotionEnabled { card.transform = CGAffineTransform(translationX: 0, y: -30) }
            } completion: { [weak self, weak card] _ in
                card?.removeFromSuperview()
                if self?.toast === card { self?.toast = nil }
            }
        }
        dismissToast = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (UIAccessibility.isVoiceOverRunning ? 5 : 2.7), execute: work)
    }
    private func celebrate(in root: UIView) {
        stopConfetti()
        let canvas = UIView(frame: root.bounds)
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.isUserInteractionEnabled = false
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "Hoa giấy mừng hoàn tất giao hàng"
        canvas.accessibilityIdentifier = "feedback.celebration"
        canvas.accessibilityTraits = .image
        root.addSubview(canvas); confetti = canvas
        let width = max(1, root.bounds.width), height = max(1, root.bounds.height)
        let colors: [UIColor] = [.systemGreen, .systemBlue, .systemYellow, .white, .systemTeal]
        let now = CACurrentMediaTime()
        // 24 pieces burst from the lower corners, then 36 fall from above.
        // All movement runs in Core Animation, not a per-frame SwiftUI update.
        for index in 0..<60 {
            let paper = CALayer()
            let size = CGSize(width: CGFloat.random(in: 5...9), height: CGFloat.random(in: 4...7))
            paper.bounds = CGRect(origin: .zero, size: size)
            paper.cornerRadius = 1
            paper.backgroundColor = colors[index % colors.count].cgColor
            paper.opacity = 0
            canvas.layer.addSublayer(paper)
            let burst = index < 24
            let path = CGMutablePath()
            if burst {
                let left = index % 2 == 0
                path.move(to: CGPoint(x: left ? 24 : width - 24, y: height - 80))
                path.addQuadCurve(to: CGPoint(x: CGFloat.random(in: 0...width), y: height * CGFloat.random(in: 0.08...0.32)),
                                  control: CGPoint(x: left ? width * 0.25 : width * 0.75, y: height * 0.18))
            } else {
                let x = CGFloat.random(in: 0...width)
                path.move(to: CGPoint(x: x, y: -24))
                path.addCurve(to: CGPoint(x: x + CGFloat.random(in: -70...70), y: height + 30),
                              control1: CGPoint(x: x - 45, y: height * 0.3), control2: CGPoint(x: x + 45, y: height * 0.7))
            }
            let position = CAKeyframeAnimation(keyPath: "position")
            position.path = path; position.calculationMode = .paced
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0; rotation.toValue = CGFloat.random(in: -8...8)
            let tumble = CABasicAnimation(keyPath: "transform.rotation.x")
            tumble.fromValue = 0; tumble.toValue = CGFloat.random(in: 2...10)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]; opacity.keyTimes = [0, 0.08, 0.75, 1]
            let group = CAAnimationGroup()
            group.animations = [position, rotation, tumble, opacity]
            group.duration = burst ? 0.65 : Double.random(in: 1.55...1.9)
            for animation in group.animations ?? [] { animation.duration = group.duration }
            group.beginTime = now + (burst ? 0 : Double.random(in: 0.32...0.5))
            paper.add(group, forKey: "celebration")
        }
        for x in [CGFloat(24), width - 24] {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: -18, y: -18, width: 36, height: 36)).cgPath
            ring.position = CGPoint(x: x, y: height - 80)
            ring.fillColor = UIColor.clear.cgColor; ring.strokeColor = UIColor.systemGreen.cgColor; ring.lineWidth = 3; ring.opacity = 0
            canvas.layer.addSublayer(ring)
            let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 0.3; scale.toValue = 2.5
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0.8; fade.toValue = 0
            let group = CAAnimationGroup(); group.animations = [scale, fade]; group.duration = 0.35
            scale.duration = group.duration; fade.duration = group.duration
            ring.add(group, forKey: "pop")
        }
        let work = DispatchWorkItem { [weak self] in self?.stopConfetti() }
        dismissConfetti = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
    private func stopConfetti() { dismissConfetti?.cancel(); dismissConfetti = nil; confetti?.removeFromSuperview(); confetti = nil }
    private func clear() {
        dismissToast?.cancel(); dismissToast = nil; toast?.removeFromSuperview(); toast = nil; stopConfetti()
    }
    func invalidate() { clear(); window.isHidden = true }
    func dismissFeedback() { clear() }
}

private final class SweepEffectsWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class SweepSuccessToast: UIVisualEffectView {
    private let tick = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    init(text: String) {
        super.init(effect: UIBlurEffect(style: .systemMaterial))
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 20; layer.cornerCurve = .continuous; clipsToBounds = true
        layer.borderWidth = 0.5; layer.borderColor = UIColor.separator.cgColor
        tick.tintColor = .systemGreen; tick.contentMode = .scaleAspectFit; tick.isAccessibilityElement = false
        let label = UILabel()
        label.text = text; label.font = .preferredFont(forTextStyle: .subheadline); label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 3; label.textColor = .label
        label.accessibilityIdentifier = "feedback.toast"
        let row = UIStackView(arrangedSubviews: [tick, label]); row.axis = .horizontal; row.spacing = 12; row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            tick.widthAnchor.constraint(equalToConstant: 26), tick.heightAnchor.constraint(equalToConstant: 26),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func animateTick(reduced: Bool) {
        guard !reduced else { return }
        tick.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(withDuration: 0.3, delay: 0.06, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: [.allowUserInteraction]) { self.tick.transform = .identity }
    }
}
