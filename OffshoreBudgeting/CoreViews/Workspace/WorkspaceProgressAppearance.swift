import SwiftUI

struct WorkspaceProgressAppearance {
    let tint: Color

    init(percentage: Int) {
        let hex = switch percentage {
        case 20: "#FA7200"
        case 40: "#FFA600"
        case 60: "#E6C600"
        case 80: "#8CD500"
        case 100: "#00B64D"
        default: "#E51E38"
        }

        tint = Color(hex: hex) ?? .accentColor
    }
}
