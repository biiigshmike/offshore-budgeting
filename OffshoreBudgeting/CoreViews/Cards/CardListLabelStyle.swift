import SwiftUI

/// Preserve the thumbnail's intrinsic width instead of a system symbol's icon slot.
struct CardListLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .fixedSize()
            configuration.title
        }
    }
}
