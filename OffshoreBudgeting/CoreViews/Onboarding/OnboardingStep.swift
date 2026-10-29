/// Stable persisted IDs. Removed steps are resolved without renumbering saved progress.
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case workspaces = 1
    case privacy = 2
    case categories = 4
    case cards = 5
    case presets = 6

    static let ordered: [Self] = [.welcome, .workspaces, .privacy, .categories, .cards, .presets]

    static func resolve(_ savedValue: Int) -> Self {
        if let step = Self(rawValue: savedValue) { return step }
        switch savedValue {
        case 3: return .categories
        case 7...: return .presets
        default: return .welcome
        }
    }

    var next: Self {
        let index = Self.ordered.firstIndex(of: self)!
        return Self.ordered[min(index + 1, Self.ordered.count - 1)]
    }

    var previous: Self {
        let index = Self.ordered.firstIndex(of: self)!
        return Self.ordered[max(index - 1, 0)]
    }
}
