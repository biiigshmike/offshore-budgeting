import SwiftUI

struct AppItemSheetPresenter<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: (Item) -> SheetContent
    @Environment(\.appPresentationActivity) private var activity
    @State private var activityID = UUID()

    func body(content: Content) -> some View {
        content
            .sheet(item: $item, onDismiss: {
                activity?.setPresented(false, id: activityID)
                onDismiss?()
            }) { sheetContent($0).appSheetSizing() }
            .modifier(AppSheetActivityModifier(isPresented: item != nil, activityID: activityID))
    }
}
