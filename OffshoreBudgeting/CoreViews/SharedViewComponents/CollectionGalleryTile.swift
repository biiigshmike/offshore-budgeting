import SwiftUI

struct CollectionGalleryTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
    }
}
