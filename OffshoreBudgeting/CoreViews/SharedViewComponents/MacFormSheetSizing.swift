import SwiftUI

extension View {
    /// Apply at an Add/Edit sheet's presentation root, not to embedded form content.
    /// Reuses the larger Add Budget presentation without requiring native resizing.
    @ViewBuilder
    func macFormSheetSizing() -> some View {
        #if targetEnvironment(macCatalyst)
        self
            .frame(minWidth: 400, idealWidth: 560, maxWidth: .infinity,
                   minHeight: 320, idealHeight: 640, maxHeight: .infinity)
            .presentationSizing(.fitted)
        #else
        self
        #endif
    }
}
