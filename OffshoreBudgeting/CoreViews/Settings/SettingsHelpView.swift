import SwiftUI

struct SettingsHelpView: View {
    @State private var searchText: String = ""
    private let faqEngine = HelpFAQEngine()

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        normalizedSearchText.isEmpty == false
    }

    private var faqResolution: HelpFAQResolution? {
        guard isSearching else { return nil }
        return faqEngine.resolve(
            prompt: normalizedSearchText,
            topics: GeneratedHelpContent.allLeafTopics
        )
    }

    private var searchResults: [GeneratedHelpLeafTopic] {
        guard isSearching else { return [] }

        return GeneratedHelpContent.allLeafTopics.filter { topic in
            topic.faqSearchText.localizedCaseInsensitiveContains(normalizedSearchText)
        }
    }

    private var unresolvedSuggestions: [GeneratedHelpLeafTopic] {
        guard let faqResolution, faqResolution.answer == nil else { return [] }
        return faqResolution.suggestions
    }

    var body: some View {
        let currentFAQResolution = faqResolution

        List {
            if isSearching {
                Section {
                    Text("Ask in plain language. Marina answers from Help topics only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let answer = currentFAQResolution?.answer {
                    Section("Marina FAQ Answer") {
                        faqAnswerCard(answer)
                    }
                }

                Section("Results") {
                    if let currentFAQResolution, currentFAQResolution.answer == nil {
                        Text("I need a clearer help question, but I can suggest likely topics.")
                            .foregroundStyle(.secondary)

                        ForEach(unresolvedSuggestions) { topic in
                            leafTopicNavigationLink(topic)
                        }
                    }

                    if searchResults.isEmpty {
                        if currentFAQResolution?.answer != nil {
                            Text("No matching help topics.")
                                .foregroundStyle(.secondary)
                        }
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
            prompt: "Search or ask a help question"
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

    @ViewBuilder
    private func faqAnswerCard(_ answer: HelpFAQAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answer.title)
                .font(.headline)

            Text(answer.narrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(confidenceLabel(for: answer.confidence))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let sectionTitle = answer.match.sectionTitle,
                   sectionTitle.isEmpty == false
                {
                    Text("|")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sectionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let topic = GeneratedHelpContent.leafTopic(for: answer.match.topicID) {
                NavigationLink {
                    HelpTopicDetailView(topic: topic)
                } label: {
                    Label("Open Topic", systemImage: "arrow.right.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confidenceLabel(for confidence: HelpFAQConfidence) -> String {
        switch confidence {
        case .high:
            return "Best match"
        case .medium:
            return "Likely match"
        case .low:
            return "Low confidence"
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

    @State private var currentTopicID: String
    @State private var selectedMediaIDsBySectionID: [String: String] = [:]
    @State private var fullscreenPresentation: HelpFullscreenPresentation?

    private let topAnchorID: String = "help-topic-top-anchor"

    init(topic: GeneratedHelpLeafTopic) {
        self.topic = topic
        _currentTopicID = State(initialValue: topic.id)
    }

    private var currentTopic: GeneratedHelpLeafTopic {
        GeneratedHelpContent.leafTopic(for: currentTopicID) ?? topic
    }

    private var orderedTopicsInDestination: [GeneratedHelpLeafTopic] {
        guard let destination = GeneratedHelpContent.destination(for: currentTopic.destinationID) else {
            return [currentTopic]
        }

        let topics = GeneratedHelpContent.leafTopics(for: destination)
        return topics.isEmpty ? [currentTopic] : topics
    }

    private var currentTopicIndex: Int? {
        orderedTopicsInDestination.firstIndex(where: { $0.id == currentTopic.id })
    }

    private var previousTopic: GeneratedHelpLeafTopic? {
        guard let index = currentTopicIndex, index > 0 else { return nil }
        return orderedTopicsInDestination[index - 1]
    }

    private var nextTopic: GeneratedHelpLeafTopic? {
        guard let index = currentTopicIndex, index + 1 < orderedTopicsInDestination.count else { return nil }
        return orderedTopicsInDestination[index + 1]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorID)

                    ForEach(currentTopic.sections) { section in
                        sectionContent(section)
                    }
                }
                .padding()
            }
            .navigationTitle(currentTopic.title)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HelpTopicPagerBar(
                    previousTitle: previousTopic?.title,
                    nextTitle: nextTopic?.title,
                    onBack: goToPreviousTopic,
                    onNext: goToNextTopic
                )
            }
            .onChange(of: currentTopicID) { _, _ in
                selectedMediaIDsBySectionID = [:]
                fullscreenPresentation = nil

                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(topAnchorID, anchor: .top)
                }
            }
            .fullScreenCover(item: $fullscreenPresentation) { presentation in
                HelpSectionFullscreenViewer(topicTitle: currentTopic.title, presentation: presentation)
            }
        }
    }

    // MARK: - Section UI

    @ViewBuilder
    private func sectionContent(_ section: GeneratedHelpSection) -> some View {
        let mediaItems = currentTopic.mediaItems(for: section)
        let selectedItem = selectedMediaItem(for: section, from: mediaItems)
        let sectionTitle = selectedItem?.displayTitle ?? section.header

        if let header = sectionTitle {
            Text(header)
                .font(.title3.weight(.semibold))
        }

        if mediaItems.isEmpty {
            HelpSectionBodyCard(text: section.bodyText)
        } else if let selectedItem {
            HelpSectionMediaStrip(
                mediaItems: mediaItems,
                selectedMediaID: selectedItem.id
            ) { tappedItem in
                handleMediaTap(tappedItem, section: section, allItems: mediaItems)
            }

            HelpSectionBodyCard(text: selectedItem.bodyText)
        }
    }

    private func selectedMediaItem(
        for section: GeneratedHelpSection,
        from mediaItems: [GeneratedHelpSectionMediaItem]
    ) -> GeneratedHelpSectionMediaItem? {
        guard let fallbackItem = mediaItems.first else { return nil }

        let selectedID = selectedMediaIDsBySectionID[section.id] ?? fallbackItem.id
        return mediaItems.first(where: { $0.id == selectedID }) ?? fallbackItem
    }

    private func handleMediaTap(
        _ tappedItem: GeneratedHelpSectionMediaItem,
        section: GeneratedHelpSection,
        allItems: [GeneratedHelpSectionMediaItem]
    ) {
        guard !allItems.isEmpty else { return }

        let currentSelectedID = selectedMediaIDsBySectionID[section.id]

        if currentSelectedID == nil {
            selectedMediaIDsBySectionID[section.id] = tappedItem.id
            return
        }

        if currentSelectedID == tappedItem.id {
            fullscreenPresentation = HelpFullscreenPresentation(
                sectionTitle: section.header ?? "Help",
                mediaItems: allItems,
                selectedMediaID: tappedItem.id
            )
        } else {
            selectedMediaIDsBySectionID[section.id] = tappedItem.id
        }
    }

    private func goToPreviousTopic() {
        guard let previousTopic else { return }
        currentTopicID = previousTopic.id
    }

    private func goToNextTopic() {
        guard let nextTopic else { return }
        currentTopicID = nextTopic.id
    }
}

private struct HelpTopicPagerBar: View {
    let previousTitle: String?
    let nextTitle: String?
    let onBack: () -> Void
    let onNext: () -> Void

    private var isBackEnabled: Bool {
        previousTitle != nil
    }

    private var isNextEnabled: Bool {
        nextTitle != nil
    }

    private var backTint: Color {
        isBackEnabled ? Color("OffshoreDepth") : Color("OffshoreWave")
    }

    private var nextTint: Color {
        isNextEnabled ? Color("AccentColor") : Color("OffshoreWave")
    }

    private var previousDisplayTitle: String {
        previousTitle ?? "Start of Section"
    }

    private var nextDisplayTitle: String {
        nextTitle ?? "End of Section"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 10) {
                styledPagerButton(
                    action: onBack,
                    isEnabled: isBackEnabled,
                    tint: backTint
                ) {
                    VStack(spacing: 3) {
                        Text("Back")
                            .font(.footnote.weight(.semibold))
                        Text(previousDisplayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }

                styledPagerButton(
                    action: onNext,
                    isEnabled: isNextEnabled,
                    tint: nextTint
                ) {
                    VStack(spacing: 3) {
                        Text("Next")
                            .font(.footnote.weight(.semibold))
                        Text(nextDisplayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func styledPagerButton<Label: View>(
        action: @escaping () -> Void,
        isEnabled: Bool,
        tint: Color,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let button = Button(action: action) {
            label()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .tint(tint)
        .disabled(!isEnabled)

        if #available(iOS 26.0, macCatalyst 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}

private struct HelpFullscreenPresentation: Identifiable {
    let id: UUID = UUID()
    let sectionTitle: String
    let mediaItems: [GeneratedHelpSectionMediaItem]
    let selectedMediaID: String
}

// MARK: - Section Media

private struct HelpSectionMediaStrip: View {
    let mediaItems: [GeneratedHelpSectionMediaItem]
    let selectedMediaID: String
    let onTap: (GeneratedHelpSectionMediaItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(mediaItems) { item in
                    Button {
                        onTap(item)
                    } label: {
                        HelpSectionThumbnail(
                            item: item,
                            isSelected: item.id == selectedMediaID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
    }
}

private struct HelpSectionThumbnail: View {
    let item: GeneratedHelpSectionMediaItem
    let isSelected: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var thumbnailSize: CGSize {
        #if targetEnvironment(macCatalyst)
        return CGSize(width: 200, height: 140)
        #else
        if horizontalSizeClass == .regular {
            return CGSize(width: 200, height: 140)
        }
        return CGSize(width: 176, height: 124)
        #endif
    }

    private var imageSize: CGSize {
        CGSize(width: thumbnailSize.width - 4, height: thumbnailSize.height - 4)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            if let image = platformImage(named: item.assetName) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: imageSize.width, height: imageSize.height)
                    .overlay {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.headline)
                    Text("Import: \(item.assetName)")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.25) : .clear,
            radius: isSelected ? 8 : 0,
            x: 0,
            y: isSelected ? 2 : 0
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.assetName))
    }
}

private struct HelpSectionBodyCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Fullscreen Media

private struct HelpSectionFullscreenViewer: View {
    let topicTitle: String
    let presentation: HelpFullscreenPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMediaID: String

    init(topicTitle: String, presentation: HelpFullscreenPresentation) {
        self.topicTitle = topicTitle
        self.presentation = presentation
        _selectedMediaID = State(initialValue: presentation.selectedMediaID)
    }

    private var selectedItem: GeneratedHelpSectionMediaItem? {
        presentation.mediaItems.first(where: { $0.id == selectedMediaID }) ?? presentation.mediaItems.first
    }

    private var selectedCaptionText: String? {
        guard let selectedItem else { return nil }
        return selectedItem.fullscreenCaptionText ?? selectedItem.bodyText
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $selectedMediaID) {
                    ForEach(presentation.mediaItems) { item in
                        HelpZoomableImage(assetName: item.assetName)
                            .tag(item.id)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                if let selectedCaptionText {
                    Text(selectedCaptionText)
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.black.opacity(0.62))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    }
                }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topicTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text(presentation.sectionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct HelpZoomableImage: View {
    let assetName: String

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if let image = platformImage(named: assetName) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleZoom()
                    }
                    .gesture(magnifyAndPanGesture)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.title)
                    Text("Missing asset")
                        .font(.headline)
                    Text("Import: \(assetName)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magnifyAndPanGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let updatedScale = max(1, min(lastScale * value, 4))
                    scale = updatedScale
                }
                .onEnded { _ in
                    lastScale = scale

                    if scale <= 1.01 {
                        resetPan()
                    }
                },
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard scale > 1 else { return }

                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    if scale <= 1.01 {
                        resetPan()
                    } else {
                        lastOffset = offset
                    }
                }
        )
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if scale > 1.01 {
                scale = 1
                lastScale = 1
                resetPan()
            } else {
                scale = 2
                lastScale = 2
            }
        }
    }

    private func resetPan() {
        offset = .zero
        lastOffset = .zero
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
