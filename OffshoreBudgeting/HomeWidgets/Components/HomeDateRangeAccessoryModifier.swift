import SwiftUI

struct HomeDateRangeAccessoryModifier: ViewModifier {
    let accessory: HomeDateRangeAccessory
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, macCatalyst 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                rangeControls
            }
        } else if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.tabViewBottomAccessory {
                if isEnabled {
                    rangeControls
                }
            }
        } else {
            content
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private var rangeControls: some View {
        HomeDateRangeControls(startDate: accessory.startDate, endDate: accessory.endDate,
                        presentsSheet: true, onApply: accessory.apply)
            .id(accessory.ownerID)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
    }
}
