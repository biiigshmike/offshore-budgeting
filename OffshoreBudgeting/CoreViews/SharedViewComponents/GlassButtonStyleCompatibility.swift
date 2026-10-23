import SwiftUI

extension View {
    @ViewBuilder
    func glassProminentButtonStyleCompat(catalystShape: ButtonBorderShape = .capsule) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if targetEnvironment(macCatalyst)
            self.buttonStyle(.glassProminent)
                .buttonBorderShape(catalystShape)
            #else
            self.buttonStyle(.glassProminent)
            #endif
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func glassButtonStyleCompat(catalystShape: ButtonBorderShape = .capsule) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if targetEnvironment(macCatalyst)
            self.buttonStyle(.glass)
                .buttonBorderShape(catalystShape)
            #else
            self.buttonStyle(.glass)
            #endif
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
