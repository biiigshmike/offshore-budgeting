import SwiftUI

struct SettingsCustomThemeView: View {
    @Environment(\.self) private var environment

    @Binding var storedPalette: String

    private var palette: CustomThemePalette {
        CustomThemePalette(storedValue: storedPalette) ?? .startingPalette
    }

    var body: some View {
        colorField("Accent Color", detail: "Colors buttons, links, and selected controls.", field: \.accent)
        colorField("Background Undertone", detail: "Adds a subtle tint behind the top and bottom colors.", field: \.base)
        colorField("Top Glow", detail: "Adds a soft color near the top of Home.", field: \.highlight)
        colorField("Bottom Blend", detail: "Adds a second color that fades in near the bottom.", field: \.wash)

        Text("Changes are saved automatically. Offshore adapts the background colors to light and dark mode.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func colorField(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey,
        field: WritableKeyPath<CustomThemePalette, String>
    ) -> some View {
        ColorPicker(selection: binding(for: field), supportsOpacity: false) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for field: WritableKeyPath<CustomThemePalette, String>) -> Binding<Color> {
        Binding {
            palette.color(at: field)
        } set: { color in
            var updatedPalette = palette
            updatedPalette.setColor(color, at: field, in: environment)
            storedPalette = updatedPalette.storedValue
        }
    }
}
