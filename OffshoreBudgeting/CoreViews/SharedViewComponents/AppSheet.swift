import SwiftUI
import UIKit

extension View {
    /// Uses page sizing on iPad and Mac Catalyst unless content supplies its own sizing.
    /// iPhone keeps its native sizing.
    func appSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        usesPageSizing: Bool = true,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(AppSheetPresenter(isPresented: isPresented, onDismiss: onDismiss, usesPageSizing: usesPageSizing, sheetContent: content))
    }

    func appSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(AppItemSheetPresenter(item: item, onDismiss: onDismiss, sheetContent: content))
    }

    @ViewBuilder
    func appSheetSizing() -> some View {
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
