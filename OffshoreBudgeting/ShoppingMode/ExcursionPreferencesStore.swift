import Foundation
import Combine

@MainActor
final class ExcursionPreferencesStore: ObservableObject {
    static let shared = ExcursionPreferencesStore()
    static let storageKey = "excursion_preferences_v1"
    static let didChange = Notification.Name("ExcursionPreferencesStore.didChange")

    @Published private(set) var value: ExcursionPreferences
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ExcursionPreferences.self, from: data),
           let validated = decoded.validated() {
            value = validated
        } else {
            value = .default
        }
    }

    @discardableResult
    func update(_ preferences: ExcursionPreferences) -> Bool {
        guard let validated = preferences.validated(),
              let data = try? JSONEncoder().encode(validated) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        guard validated != value else { return true }
        value = validated
        NotificationCenter.default.post(name: Self.didChange, object: self)
        return true
    }

    func restoreDefaults() {
        update(.default)
    }
}
