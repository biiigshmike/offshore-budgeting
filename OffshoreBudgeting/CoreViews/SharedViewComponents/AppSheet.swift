import SwiftUI
import UIKit

extension View {
    /// All app sheets use page sizing on iPad and Mac Catalyst; iPhone keeps its native sizing.
    func appSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().appSheetSizing()
        }
    }

    func appSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item).appSheetSizing()
        }
    }

    @ViewBuilder
    private func appSheetSizing() -> some View {
        #if targetEnvironment(macCatalyst)
        self.presentationSizing(.page)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.presentationSizing(.page)
        } else {
            self
        }
        #endif
    }
}
