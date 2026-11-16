import SwiftUI

enum SweepStyle {
    static let green = Color(red: 90/255, green: 200/255, blue: 125/255)
    static let blue = Color(red: 0, green: 122/255, blue: 1)
}
struct SweepPill: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selected = false
    var expanded = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(configuration.role == .destructive ? Color.red : SweepStyle.blue)
            .frame(maxWidth: expanded ? .infinity : nil, minHeight: 44).padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .background(selected ? SweepStyle.green.opacity(0.22) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? SweepStyle.green : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && isEnabled && selected { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            }
    }
}

struct SweepCompactPill: ButtonStyle {
    var expanded = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(SweepStyle.blue)
            .fixedSize(horizontal: !expanded && !typeSize.isAccessibilitySize, vertical: true)
            .padding(.horizontal, expanded ? 10 : 16).padding(.vertical, expanded ? 6 : 0)
            .frame(maxWidth: expanded ? .infinity : nil, minHeight: 44)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
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
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Gọi " + phone).accessibilityIdentifier("contact.call")
        }
    }
}
