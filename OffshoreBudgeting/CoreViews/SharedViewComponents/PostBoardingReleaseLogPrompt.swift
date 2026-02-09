//
//  PostBoardingReleaseLogPrompt.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/9/26.
//

import SwiftUI

extension View {

    // MARK: - What's New Prompt Modifier

    func whatsNewForCurrentRelease() -> some View {
        modifier(PostBoardingReleaseLogPromptModifier())
    }
}

// MARK: - Modifier

private struct PostBoardingReleaseLogPromptModifier: ViewModifier {

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("releaseLogs_seenReleaseIDs") private var seenReleaseIDsCSV: String = ""

    @State private var showingReleasePrompt: Bool = false

    private var currentSection: SettingsReleaseLogsView.ReleaseSection? {
        SettingsReleaseLogsView.currentReleaseSection
    }

    func body(content: Content) -> some View {
        let base = content
            .onAppear {
                showingReleasePrompt = shouldShowPrompt()
            }

        if shouldAttachSheet {
            base.sheet(isPresented: $showingReleasePrompt) {
                if let section = currentSection {
                    CurrentReleaseLogSheet(section: section) {
                        markCurrentReleaseSeen()
                        showingReleasePrompt = false
                    }
                }
            }
        } else {
            base
        }
    }

    private var shouldAttachSheet: Bool {
        guard didCompleteOnboarding else { return false }
        guard let section = currentSection else { return false }
        return hasSeen(section.id) == false
    }

    private func shouldShowPrompt() -> Bool {
        guard didCompleteOnboarding else { return false }
        guard let section = currentSection else { return false }
        return hasSeen(section.id) == false
    }

    private func hasSeen(_ releaseID: String) -> Bool {
        seenReleaseIDSet.contains(releaseID)
    }

    private var seenReleaseIDSet: Set<String> {
        Set(
            seenReleaseIDsCSV
                .split(separator: ",")
                .map { String($0) }
        )
    }

    private func markCurrentReleaseSeen() {
        guard let section = currentSection else { return }
        var next = seenReleaseIDSet
        next.insert(section.id)
        seenReleaseIDsCSV = next.sorted().joined(separator: ",")
    }
}

// MARK: - Sheet

private struct CurrentReleaseLogSheet: View {

    let section: SettingsReleaseLogsView.ReleaseSection
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("What’s New in \(section.version) (\(section.build))")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(section.items) { item in
                        CurrentReleaseLogItemRow(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if #available(iOS 26.0, *) {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            } else {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

// MARK: - Row

private struct CurrentReleaseLogItemRow: View {

    let item: SettingsReleaseLogsView.ReleaseItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
