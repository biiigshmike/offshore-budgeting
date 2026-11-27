import SwiftUI

struct SheetCloseToolbarItem: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark", action: action)
                .labelStyle(.iconOnly)
        }
    }
}
