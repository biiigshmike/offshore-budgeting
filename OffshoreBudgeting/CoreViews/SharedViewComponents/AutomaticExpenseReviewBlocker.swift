import SwiftUI

/// Native alerts and popovers do not use appSheet. Register their bindings too,
/// so returning to the foreground never interrupts an outstanding decision.
private struct AutomaticExpenseReviewBlocker: ViewModifier {
    let isPresented: Bool
    @Environment(\.appPresentationActivity) private var activity
    @State private var activityID = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in
                activity?.setPresented(presented, id: activityID)
            }
            .onDisappear { activity?.setPresented(false, id: activityID) }
    }
}

extension View {
    func blocksAutomaticExpenseReview(while isPresented: Bool) -> some View {
        modifier(AutomaticExpenseReviewBlocker(isPresented: isPresented))
    }
}
