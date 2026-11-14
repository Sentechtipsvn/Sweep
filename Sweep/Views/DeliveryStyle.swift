import SwiftUI

enum SweepStyle {
    static let green = Color(red: 90/255, green: 200/255, blue: 125/255)
    static let blue = Color(red: 0, green: 122/255, blue: 1)
}
struct SweepPill: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(SweepStyle.blue)
            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .background(selected ? SweepStyle.green.opacity(0.22) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? SweepStyle.green : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
