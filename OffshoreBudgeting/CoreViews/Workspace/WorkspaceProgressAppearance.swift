import SwiftUI

struct WorkspaceProgressAppearance {
    let tint: Color
    let gaugeForeground: Color

    init(percentage: Int) {
        let (hex, foreground): (String, Color) = switch percentage {
        case 20: ("#FA7200", .black)
        case 40: ("#FFA600", .black)
        case 60: ("#E6C600", .black)
        case 80: ("#8CD500", .black)
        case 100: ("#00B64D", .black)
        default: ("#E51E38", .white)
        }

        tint = Color(hex: hex) ?? .accentColor
        gaugeForeground = foreground
    }
}
