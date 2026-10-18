import SwiftUI

extension View {
    @ViewBuilder
    func glassProminentButtonStyleCompat(macBorderShape: ButtonBorderShape = .capsule) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if targetEnvironment(macCatalyst)
            self.buttonStyle(.glassProminent)
                .buttonBorderShape(macBorderShape)
            #else
            self.buttonStyle(.glassProminent)
            #endif
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
