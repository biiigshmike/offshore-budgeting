import SwiftUI

/// Scene-local reservations include dismissal animations, so deferred launch work
/// cannot compete with an existing form, help sheet, or onboarding tip.
@Observable @MainActor
final class AppPresentationActivity {
    private(set) var reservations: Set<UUID> = []
    var isBusy: Bool { !reservations.isEmpty }

    func setPresented(_ presented: Bool, id: UUID) {
        if presented { reservations.insert(id) } else { reservations.remove(id) }
    }
}

struct AppPresentationActivityKey: EnvironmentKey {
    static let defaultValue: AppPresentationActivity? = nil
}

extension EnvironmentValues {
    var appPresentationActivity: AppPresentationActivity? {
        get { self[AppPresentationActivityKey.self] }
        set { self[AppPresentationActivityKey.self] = newValue }
    }
}
