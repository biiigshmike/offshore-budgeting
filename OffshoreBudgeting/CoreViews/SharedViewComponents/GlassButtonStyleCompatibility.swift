import SwiftUI

extension View {
    @ViewBuilder
    func glassProminentButtonStyleCompat() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func glassButtonStyleCompat() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
