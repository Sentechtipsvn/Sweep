import SwiftUI

enum SweepStyle {
    static let green = Color(red: 90/255, green: 200/255, blue: 125/255)
    static let blue = Color(red: 0, green: 122/255, blue: 1)
}
/// A single material layer, with an angled highlight like a Control Center capsule.
private struct GlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    let selected: Bool
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.background {
            Capsule().fill(.thinMaterial)
                .overlay { if opaque { Capsule().fill(Color(uiColor: .secondarySystemBackground)) } }
                .overlay { Capsule().fill(selected ? (dark ? Color.white : Color.black).opacity(0.82) : Color.white.opacity(0.035)) }
                .overlay {
                    Capsule().strokeBorder(LinearGradient(colors: [
                        .white.opacity(dark ? 0.65 : 0.94), .white.opacity(0.13),
                        .primary.opacity(0.13), .white.opacity(0.42)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
        }.contentShape(Capsule())
    }
}
struct SweepPill: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selected = false
    var expanded = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.role == .destructive ? Color.red : selected ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .frame(maxWidth: expanded ? .infinity : nil, minHeight: 44)
            .modifier(GlassSurface(selected: selected))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .scaleEffect(enabled && configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: configuration.isPressed)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct SweepOrderStatus: View {
    let order: DeliveryOrder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 5) {
            if order.taskComplete && order.voidReason == nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SweepStyle.green)
                    .transition(.scale.combined(with: .opacity)).accessibilityHidden(true)
            }
            Text(order.workflowStatus).foregroundStyle(order.taskComplete && order.voidReason == nil ? SweepStyle.green : Color.secondary)
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: order.workflowStatus)
    }
}

struct SweepDayPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
struct SweepCallButton: View {
    let phone: String
    var body: some View {
        if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }), !phone.isEmpty {
            Link(destination: url) {
                Image(systemName: "phone.fill").font(.system(size: 20)).foregroundStyle(.blue)
                    .frame(minHeight: 28)
            }.buttonStyle(SweepPill(expanded: false)).accessibilityLabel("Gọi " + phone).accessibilityIdentifier("contact.call")
        }
    }
}
