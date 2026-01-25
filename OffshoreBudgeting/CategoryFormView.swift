//
//  CategoryFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

struct CategoryFormView: View {

    @Binding var name: String
    @Binding var color: Color

    // MARK: - Shared Validation

    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSave(name: String) -> Bool {
        !trimmedName(name).isEmpty
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
    }
}

// MARK: - Color <-> Hex helpers

extension CategoryFormView {

    static func hexString(from color: Color) -> String {
        #if canImport(UIKit)
        let ui = UIColor(color)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#3B82F6"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )

        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns

        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )

        #else
        return "#3B82F6"
        #endif
    }

    static func color(fromHex hex: String) -> Color {
        Color(hex: hex) ?? .blue
    }
}
