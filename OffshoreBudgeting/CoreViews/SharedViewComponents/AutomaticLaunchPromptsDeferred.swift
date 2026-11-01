import SwiftUI

private struct AutomaticLaunchPromptsDeferredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var automaticLaunchPromptsDeferred: Bool {
        get { self[AutomaticLaunchPromptsDeferredKey.self] }
        set { self[AutomaticLaunchPromptsDeferredKey.self] = newValue }
    }
}
