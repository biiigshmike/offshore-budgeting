import SwiftUI

struct SettingsThemeView: View {
    @AppStorage(AppearanceTheme.storageKey) private var themeID = AppearanceTheme.offshoreDefault.rawValue
    @AppStorage(CustomThemePalette.storageKey) private var customPalette = ""
    @Environment(\.appearanceTheme) private var theme

    private var customAccentSwatch: Color {
        CustomThemePalette(storedValue: customPalette)?.color(at: \.accent) ?? .gray.opacity(0.35)
    }

    var body: some View {
        List {
            Section {
                ForEach(AppearanceTheme.allCases) { preset in
                    Button {
                        themeID = preset.id
                    } label: {
                        HStack {
                            Circle()
                                .fill(preset.accent)
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            Text(preset.title)
                            Spacer()
                            if preset.id == theme.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(preset.id == theme.id ? .isSelected : [])
                    .accessibilityIdentifier("appearanceTheme_\(preset.id)")
                }

                Button(action: selectCustomTheme) {
                    HStack {
                        Circle()
                            .fill(customAccentSwatch)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text("Custom")
                        Spacer()
                        if theme.id == CustomThemePalette.themeID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(theme.id == CustomThemePalette.themeID ? .isSelected : [])
                .accessibilityIdentifier("appearanceTheme_custom")
            } footer: {
                Text("Changes the app accent and the Home background.")
            }

            Section("Preview") {
                if theme.id == CustomThemePalette.themeID {
                    SettingsCustomThemeView(storedPalette: $customPalette)
                }

                SettingsThemePreview()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Theme")
    }

    private func selectCustomTheme() {
        if CustomThemePalette(storedValue: customPalette) == nil {
            customPalette = CustomThemePalette.startingPalette.storedValue
        }
        themeID = CustomThemePalette.themeID
    }
}
