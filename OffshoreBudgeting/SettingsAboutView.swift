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
    private let developerWebsiteURL = URL(string: "https://example.com")!

    var body: some View {
        List {
            Section {
                AboutAppCard(
                    appDisplayName: appDisplayName,
                    shortVersion: shortVersion,
                    buildNumber: buildNumber
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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

// MARK: - App Card

private struct AboutAppCard: View {

    let appDisplayName: String
    let shortVersion: String
    let buildNumber: String

    var body: some View {
        VStack(spacing: 12) {
            Image("SettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text(appDisplayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Version \(shortVersion) • Build \(buildNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
        )
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
