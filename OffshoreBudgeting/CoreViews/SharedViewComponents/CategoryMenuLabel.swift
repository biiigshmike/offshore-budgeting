import SwiftUI

struct CategoryMenuLabel: View {
    let category: Category?
    var isSelected: Bool? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Label {
            if let category {
                Text(category.name)
            } else {
                Text("Uncategorized")
            }
        } icon: {
            if let image = EntityMenuImageCache.category(
                hexColor: category?.hexColor,
                colorScheme: colorScheme,
                scale: displayScale,
                isSelected: isSelected
            ) {
                Image(uiImage: image)
                    .renderingMode(.original)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
