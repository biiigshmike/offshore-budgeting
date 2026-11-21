import SwiftUI

enum CollectionViewMode: String, CaseIterable, Identifiable {
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: String(localized: "List", comment: "Collection list layout option.")
        case .gallery: String(localized: "Gallery", comment: "Collection gallery layout option.")
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        }
    }
}
