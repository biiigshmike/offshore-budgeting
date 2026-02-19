import SwiftUI

struct SettingsHelpView: View {
    @State private var searchText: String = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        normalizedSearchText.isEmpty == false
    }

    private var searchResults: [GeneratedHelpTopic] {
        guard isSearching else { return [] }

        return GeneratedHelpContent.topics.filter { topic in
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
                            topicNavigationLink(topic)
                        }
                    }
                }
            } else {
                Section("Getting Started") {
                    ForEach(GeneratedHelpContent.gettingStartedTopics) { topic in
                        topicNavigationLink(topic)
                    }
                }

                Section("Core Screens") {
                    ForEach(GeneratedHelpContent.coreScreenTopics) { topic in
                        topicNavigationLink(topic)
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

    private func topicNavigationLink(_ topic: GeneratedHelpTopic) -> some View {
        NavigationLink {
            HelpTopicDetailView(topic: topic)
        } label: {
            HelpRowLabel(
                iconSystemName: topic.iconSystemName,
                title: topic.title,
                iconStyle: HelpIconStyle(generatedStyle: topic.iconStyle)
            )
        }
    }
}

// MARK: - Topic Detail

struct HelpTopicDetailView: View {
    let topic: GeneratedHelpTopic

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
                                    sectionTitle: topic.title,
                                    slot: slot,
                                    style: .hero
                                )
                                .padding(.vertical, 4)
                            }
                        case .miniScreenshot:
                            if let slot = Int(line.value) {
                                HelpScreenshotPlaceholder(
                                    sectionTitle: topic.title,
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

    let sectionTitle: String
    let slot: Int
    let style: Style

    private var assetName: String {
        let sanitizedSection = sectionTitle.replacingOccurrences(of: " ", with: "")
        return "Help-\(sanitizedSection)-\(slot)"
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
                    Text("\(sectionTitle) Screenshot \(slot)")
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

    #if canImport(UIKit)
    private func platformImage(named name: String) -> UIImage? { UIImage(named: name) }
    #elseif canImport(AppKit)
    private func platformImage(named name: String) -> NSImage? { NSImage(named: name) }
    #else
    private func platformImage(named name: String) -> Any? { nil }
    #endif
}

#if canImport(UIKit)
private extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
private extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

#Preview("Help") {
    NavigationStack {
        SettingsHelpView()
    }
}
