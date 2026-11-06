import SwiftUI

@Observable
final class HelpTopicPagerHost {
    struct Presentation {
        let owner: UUID
        let previousTitle: String?
        let nextTitle: String?
        let onBack: () -> Void
        let onNext: () -> Void
    }

    var presentation: Presentation?

    static func supportsTabAccessory(verticalSizeClass: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize) -> Bool {
        verticalSizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
    }

    func dismiss(owner: UUID) {
        if presentation?.owner == owner {
            presentation = nil
        }
    }
}
