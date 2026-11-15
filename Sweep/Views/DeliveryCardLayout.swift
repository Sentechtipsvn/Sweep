import SwiftUI

/// These bounded screens deliberately use a plain scroll view. A self-sizing
/// collection-view row containing the attendance grid recursed during navigation
/// on the reported iOS 18.7.8 device (build 11 crash).
struct SweepGroupedScroll<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .buttonStyle(SweepPill())
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("sweep.groupedScroll")
    }
}

struct SweepCard<Content: View>: View {
    private let title: String?
    private let content: Content
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
