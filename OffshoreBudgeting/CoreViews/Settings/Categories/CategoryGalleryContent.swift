import SwiftUI

struct CategoryGalleryContent: View {
    let category: Category
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.title2)
                .foregroundStyle(Color(hex: category.hexColor) ?? .secondary)
                .accessibilityHidden(true)
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .accessibilityLabel(Text(category.name))
        }
        .accessibilityElement(children: .combine)
    }
}
