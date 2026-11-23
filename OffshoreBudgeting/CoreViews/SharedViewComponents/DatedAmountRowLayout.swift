import SwiftUI

struct DatedAmountRowLayout<Amount: View, Details: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let titleFont: Font
    let date: Date
    let dateFont: Font
    let category: Category?
    let showsCategory: Bool
    let card: Card?
    @ViewBuilder let amount: () -> Amount
    @ViewBuilder let details: (HorizontalAlignment) -> Details

    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 4

    private var markerWidth: CGFloat? {
        if card != nil { return 20 }
        return showsCategory ? 12 : nil
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: rowSpacing) {
                titleLine
                dateLine
                VStack(alignment: .leading, spacing: 2) {
                    amount()
                    details(.leading)
                }
                .padding(.top, 2)
                .padding(.leading, markerWidth.map { $0 + columnSpacing } ?? 0)
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: columnSpacing, verticalSpacing: rowSpacing) {
                GridRow(alignment: .firstTextBaseline) {
                    titleLine
                    amount()
                        .gridColumnAlignment(.trailing)
                }
                GridRow(alignment: .firstTextBaseline) {
                    dateLine
                    details(.trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var titleLine: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            if let markerWidth, showsCategory {
                SharedCategoryDotView(category: category)
                    .frame(width: markerWidth)
                    .padding(.top, 6)
                    .accessibilityElement()
                    .accessibilityLabel(category?.name ?? String(localized: "Uncategorized"))
            }
            Text(title)
                .font(titleFont)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLine: some View {
        HStack(spacing: columnSpacing) {
            if let card {
                SharedRowCardArtwork(name: card.name, themeRaw: card.theme, effectRaw: card.effect)
            } else if let markerWidth {
                Color.clear
                    .frame(width: markerWidth, height: 0)
                    .accessibilityHidden(true)
            }
            Text(date, format: AppDateFormat.abbreviatedDateStyle)
                .font(dateFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
