import SwiftUI

/// Presents storage/validation feedback above an intake or settlement sheet as well as the root tabs.
struct DeliveryFeedback: UIViewControllerRepresentable {
    @ObservedObject var store: DeliveryStore
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        if store.message != nil { context.coordinator.effects?.dismissFeedback() }
        if store.message == nil, let notice = store.successNotice, context.coordinator.lastNotice != notice.id {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                guard store.message == nil, store.successNotice?.id == notice.id, coordinator.lastNotice != notice.id,
                      let scene = controller.view.window?.windowScene ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
                coordinator.lastNotice = notice.id
                if coordinator.effects == nil { coordinator.effects = DeliveryEffectsPresenter(scene: scene) }
                coordinator.effects?.show(notice)
            }
        }
        guard let message = store.message, !context.coordinator.showing else { return }
        context.coordinator.showing = true
        let coordinator = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { coordinator.showing = false; return }
            while let presented = top.presentedViewController { top = presented }
            let alert = UIAlertController(title: "Sendeli", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Đã hiểu", style: .default) { _ in store.message = nil; coordinator.showing = false })
            top.present(alert, animated: true)
        }
    }
    final class Coordinator {
        var showing = false
        var lastNotice: UUID?
        var effects: DeliveryEffectsPresenter?
    }
}
