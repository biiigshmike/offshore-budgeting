import SwiftUI

/// Shared action metadata for Marina's panel menu and Mac window menu.
struct MarinaToolbarAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var isEnabled = true
    var isDestructive = false
    let perform: () -> Void
}
