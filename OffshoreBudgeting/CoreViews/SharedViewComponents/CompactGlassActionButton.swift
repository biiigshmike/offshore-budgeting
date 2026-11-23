import SwiftUI

struct CompactGlassActionButton: View {
    let title: LocalizedStringKey
    var fillsAvailableWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            capsule
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var capsule: some View {
        let label = Text(title)
            .foregroundStyle(.primary)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, minHeight: 33)

        if #available(iOS 26.0, macCatalyst 26.0, *) {
            label.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            label
                .background(.quaternary, in: .capsule)
                .overlay { Capsule().strokeBorder(.quaternary) }
        }
    }
}
