import SwiftUI

struct AppSheetPresenter<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let usesPageSizing: Bool
    @ViewBuilder let sheetContent: () -> SheetContent
    @Environment(\.appPresentationActivity) private var activity
    @State private var activityID = UUID()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                activity?.setPresented(false, id: activityID)
                onDismiss?()
            }) {
                if usesPageSizing {
                    sheetContent().appSheetSizing()
                } else {
                    sheetContent()
                }
            }
            .modifier(AppSheetActivityModifier(isPresented: isPresented, activityID: activityID))
    }
}
