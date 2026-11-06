import SwiftUI

struct TintedGlassNavigationButton: View {
    nonisolated static let minimumSize: CGFloat = 44
    nonisolated static let minimumGlassHeight: CGFloat = 48

    let title: Text
    let tint: Color
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            Button(action: action) {
                title
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(
                        minWidth: Self.minimumSize,
                        maxWidth: .infinity,
                        minHeight: Self.minimumGlassHeight
                    )
                    .glassEffect(.clear.tint(tint.opacity(0.9)).interactive(), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: action) {
                title
                    .frame(minWidth: Self.minimumSize, maxWidth: .infinity, minHeight: Self.minimumSize)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
    }
}
