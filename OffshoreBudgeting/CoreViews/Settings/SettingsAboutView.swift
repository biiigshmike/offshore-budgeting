import SwiftUI

struct SettingsAboutView: View {

    private var appDisplayName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? bundleName ?? "App"
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // Placeholders you can replace later
    private let appStoreURL = URL(string: "https://apps.apple.com")!
    private let developerWebsiteURL = URL(string: "https://offshore-budgeting.notion.site/Offshore-Budgeting-295b42cd2e6c80cf817dd73a5761bb7e")!

    var body: some View {
        List {
            Section {
                AboutAppIdentityRow(appDisplayName: appDisplayName)

                LabeledContent("Version", value: shortVersion)

                LabeledContent("Build", value: buildNumber)
            }

            Section {
                Link(destination: appStoreURL) {
                    AboutRow(systemImage: "square.and.arrow.up", title: "View in App Store")
                }

                Link(destination: developerWebsiteURL) {
                    AboutRow(systemImage: "safari", title: "Developer Website")
                }
            }

            Section {
                NavigationLink {
                    SettingsReleaseLogsView()
                } label: {
                    AboutRow(systemImage: "doc.text", title: "Release Logs")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
    }
}

// MARK: - App Identity Row

private struct AboutAppIdentityRow: View {

    let appDisplayName: String

    var body: some View {
        HStack(spacing: 14) {
            Image("SettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(appDisplayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Row

private struct AboutRow: View {

    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))

                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 30, height: 30)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview("About") {
    NavigationStack {
        SettingsAboutView()
    }
}
