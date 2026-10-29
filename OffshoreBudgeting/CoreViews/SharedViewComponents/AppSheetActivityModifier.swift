import SwiftUI

struct AppSheetActivityModifier: ViewModifier {
    let isPresented: Bool
    let activityID: UUID
    @Environment(\.appPresentationActivity) private var activity

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in
                // A false binding may mean dismissal has only just started.
                if presented { activity?.setPresented(true, id: activityID) }
            }
            .onDisappear { activity?.setPresented(false, id: activityID) }
    }
}
