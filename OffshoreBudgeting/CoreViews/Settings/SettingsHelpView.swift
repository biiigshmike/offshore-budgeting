import SwiftUI

struct SettingsHelpView: View {
    @State private var searchText: String = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        normalizedSearchText.isEmpty == false
    }

    private var searchResults: [GeneratedHelpLeafTopic] {
        guard isSearching else { return [] }

        return GeneratedHelpContent.allLeafTopics.filter { topic in
            topic.searchableText.localizedCaseInsensitiveContains(normalizedSearchText)
        }
    }

    var body: some View {
        List {
            if isSearching {
                Section("Results") {
                    if searchResults.isEmpty {
                        Text("No matching help topics.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchResults) { topic in
                            leafTopicNavigationLink(topic)
                        }
                    }
                }
            } else {
                Section("Getting Started") {
                    ForEach(GeneratedHelpContent.gettingStartedDestinations) { destination in
                        destinationNavigationLink(destination)
                    }
                }

                Section("Core Screens") {
                    ForEach(GeneratedHelpContent.coreScreenDestinations) { destination in
                        destinationNavigationLink(destination)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
    }

    // MARK: - Navigation

    private func destinationNavigationLink(_ destination: GeneratedHelpDestination) -> some View {
        NavigationLink {
            HelpDestinationTopicsView(destination: destination)
        } label: {
            HelpRowLabel(
                iconSystemName: destination.iconSystemName,
                title: destination.title,
                iconStyle: HelpIconStyle(generatedStyle: destination.iconStyle)
            )
        }
    }

    private func leafTopicNavigationLink(_ topic: GeneratedHelpLeafTopic) -> some View {
        NavigationLink {
            HelpTopicDetailView(topic: topic)
        } label: {
            Text(topic.title)
        }
    }
}

// MARK: - Destination Topics

private struct HelpDestinationTopicsView: View {
    let destination: GeneratedHelpDestination

    var body: some View {
        List {
            ForEach(GeneratedHelpContent.leafTopics(for: destination)) { topic in
                NavigationLink {
                    HelpTopicDetailView(topic: topic)
                } label: {
                    Text(topic.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(destination.title)
    }
}

// MARK: - Topic Detail

struct HelpTopicDetailView: View {
    let topic: GeneratedHelpLeafTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(topic.sections) { section in
                    if let header = section.header {
                        Text(header)
                            .font(.title3.weight(.semibold))
                        Divider()
                    }

                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        switch line.kind {
                        case .text:
                            Text(line.value)
                        case .bullet:
                            Text("• \(line.value)")
                        case .heroScreenshot:
                            if let slot = Int(line.value) {
                                HelpScreenshotPlaceholder(
                                    topic: topic,
                                    slot: slot,
                                    style: .hero
                                )
                                .padding(.vertical, 4)
                            }
                        case .miniScreenshot:
                            if let slot = Int(line.value) {
                                HelpScreenshotPlaceholder(
                                    topic: topic,
                                    slot: slot,
                                    style: .mini
                                )
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if section.id != topic.sections.last?.id {
                        Spacer().frame(height: 8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(topic.title)
    }
}

// MARK: - Row UI

private enum HelpIconStyle {
    case gray
    case blue
    case purple
    case red
    case green
    case orange

    init(generatedStyle: GeneratedHelpIconStyle) {
        switch generatedStyle {
        case .gray:
            self = .gray
        case .blue:
            self = .blue
        case .purple:
            self = .purple
        case .red:
            self = .red
        case .green:
            self = .green
        case .orange:
            self = .orange
        }
    }

    var background: Color {
        switch self {
        case .gray: return Color(.systemGray)
        case .blue: return Color(.systemBlue)
        case .purple: return Color(.systemPurple)
        case .red: return Color(.systemRed)
        case .green: return Color(.systemGreen)
        case .orange: return Color(.systemOrange)
        }
    }
}

private struct HelpRowLabel: View {
    let iconSystemName: String
    let title: String
    let iconStyle: HelpIconStyle

    var body: some View {
        HStack(spacing: 16) {
            HelpIconTile(systemName: iconSystemName, style: iconStyle)
            Text(title)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
    }
}

private struct HelpIconTile: View {
    let systemName: String
    let style: HelpIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(style.background)

            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: - Screenshot Loader

private struct HelpScreenshotPlaceholder: View {
    enum Style {
        case hero
        case mini
    }

    let topic: GeneratedHelpLeafTopic
    let slot: Int
    let style: Style

    private var assetName: String {
        if let assetPrefix = topic.assetPrefix {
            return "\(assetPrefix)-\(slot)"
        }

        let fallbackTitle = topic.title.replacingOccurrences(of: " ", with: "")
        return "Help-\(fallbackTitle)-\(slot)"
    }

    var body: some View {
        if let image = platformImage(named: assetName) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: style == .hero ? .infinity : 420, alignment: .leading)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: style == .hero ? 26 : 14,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: style == .hero ? 26 : 14,
                        style: .continuous
                    )
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(
                    cornerRadius: style == .hero ? 26 : 14,
                    style: .continuous
                )
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(
                    cornerRadius: style == .hero ? 26 : 14,
                    style: .continuous
                )
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)

                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: style == .hero ? 22 : 18, weight: .regular))
                    Text("\(topic.title) Screenshot \(slot)")
                        .font(.subheadline.weight(.semibold))
                    Text("Add asset: \(assetName)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: style == .hero ? .infinity : 420, alignment: .leading)
        }
    }
}

// MARK: - Platform Image Helpers

#if canImport(UIKit)
import UIKit
private typealias NativeImage = UIImage

private func platformImage(named name: String) -> NativeImage? {
    UIImage(named: name)
}

private extension Image {
    init(platformImage: NativeImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif canImport(AppKit)
import AppKit
private typealias NativeImage = NSImage

private func platformImage(named name: String) -> NativeImage? {
    NSImage(named: name)
}

private extension Image {
    init(platformImage: NativeImage) {
        self.init(nsImage: platformImage)
    }
}
#endif
