import SwiftUI

enum SweepStyle {
    static let green = Color(red: 90/255, green: 200/255, blue: 125/255)
    static let blue = Color(red: 0, green: 122/255, blue: 1)
}
struct SweepPill: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
struct SweepCallButton: View {
    let phone: String
    var body: some View {
        if let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }), !phone.isEmpty {
            Link(destination: url) {
                Text("Gọi").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(red: 0.03, green: 0.18, blue: 0.09))
                    .frame(width: 52, height: 52).background(SweepStyle.green, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Gọi " + phone).accessibilityIdentifier("contact.call")
        }
    }
}
