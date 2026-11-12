import SwiftUI

/// Presents storage/validation feedback above an intake or settlement sheet as well as the root tabs.
struct DeliveryFeedback: UIViewControllerRepresentable {
    @ObservedObject var store: DeliveryStore
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let message = store.message, !context.coordinator.showing else { return }
        context.coordinator.showing = true
        let coordinator = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { coordinator.showing = false; return }
            while let presented = top.presentedViewController { top = presented }
            let alert = UIAlertController(title: "Sweep", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Đã hiểu", style: .default) { _ in store.message = nil; coordinator.showing = false })
            top.present(alert, animated: true)
        }
    }
    final class Coordinator { var showing = false }
}
