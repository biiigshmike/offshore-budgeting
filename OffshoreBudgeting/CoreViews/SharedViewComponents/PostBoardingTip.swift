//
//  PostBoardingTip.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

// MARK: - PostBoardingTip Item Model

struct PostBoardingTipItem: Identifiable, Equatable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String

    init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }
}

/// Full-page “tips & hints” sheet shown once per key, until SettingsGeneralView resets them.
///
/// Usage:
///     HomeView(...)
///         .postBoardingTip(
///             key: "tip.home.v1",
///             title: "Home",
///             items: [
///                 .init(systemImage: "house.fill", title: "Landing Page", detail: "Welcome to your budget dashboard. This is the page you will see each time you open the app."),
///                 .init(systemImage: "widget.small", title: "Widgets", detail: #"Tap "Edit" to pin, reorder, or remove widgets so the view fits you."#)
///             ]
///         )
///
extension View {

    // MARK: - Post Boarding Tip Modifier

    func postBoardingTip(
        key: String,
        title: String,
        items: [PostBoardingTipItem],
        buttonTitle: String = "Continue"
    ) -> some View {
        modifier(PostBoardingTipModifier(
            key: key,
            title: title,
            items: items,
            buttonTitle: buttonTitle
        ))
    }
}

// MARK: - Modifier

private struct PostBoardingTipModifier: ViewModifier {

    let key: String
    let title: String
    let items: [PostBoardingTipItem]
    let buttonTitle: String

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    // Controlled by SettingsGeneralView -> "Reset Tips & Hints"
    @AppStorage("tips_resetToken") private var tipsResetToken: Int = 0

    // Persisted seen keys
    @AppStorage("tips_seenKeys") private var seenKeysCSV: String = ""
    @AppStorage("tips_seen_lastResetToken") private var lastResetToken: Int = 0
    @AppStorage("releaseLogs_seenReleaseIDs") private var seenReleaseIDsCSV: String = ""

    @State private var showingTip: Bool = false

    func body(content: Content) -> some View {
        let base = content
            .onAppear {
                normalizeForResetIfNeeded()
                showingTip = shouldShowTip()
            }
            .onChange(of: tipsResetToken) { _, _ in
                normalizeForResetIfNeeded()
                showingTip = shouldShowTip()
            }

        if shouldAttachSheet {
            base.sheet(isPresented: $showingTip, onDismiss: markSeen) {
                TipSheet(
                    title: title,
                    items: items,
                    buttonTitle: buttonTitle
                )
            }
        } else {
            base
        }
    }

    /// Important: don't attach a `.sheet` modifier once the tip is not eligible to show.
    /// In complex hierarchies (e.g. `NavigationSplitView`), extra "inactive" sheet presenters can
    /// cause sluggish or conflicted presentation of other sheets.
    private var shouldAttachSheet: Bool {
        guard didCompleteOnboarding else { return false }
        guard !items.isEmpty else { return false }
        guard hasPendingCurrentReleaseLog == false else { return false }

        let seen = Set(seenKeysCSV.split(separator: ",").map { String($0) })
        return !seen.contains(key)
    }

    private func normalizeForResetIfNeeded() {
        guard lastResetToken != tipsResetToken else { return }
        // New reset token, clear seen keys.
        seenKeysCSV = ""
        lastResetToken = tipsResetToken
    }

    private func shouldShowTip() -> Bool {
        guard didCompleteOnboarding else { return false }
        guard !items.isEmpty else { return false }
        guard hasPendingCurrentReleaseLog == false else { return false }

        let seen = Set(seenKeysCSV.split(separator: ",").map { String($0) })
        return !seen.contains(key)
    }

    private var hasPendingCurrentReleaseLog: Bool {
        guard let currentRelease = SettingsReleaseLogsView.currentReleaseSection else { return false }
        let seenReleaseIDs = Set(seenReleaseIDsCSV.split(separator: ",").map { String($0) })
        return seenReleaseIDs.contains(currentRelease.id) == false
    }

    private func markSeen() {
        var seen = Set(seenKeysCSV.split(separator: ",").map { String($0) })
        seen.insert(key)
        seenKeysCSV = seen.sorted().joined(separator: ",")
    }
}

// MARK: - Sheet

private struct TipSheet: View {

    let title: String
    let items: [PostBoardingTipItem]
    let buttonTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {

            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.horizontal, 22)

            // Items
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        TipItemRow(item: item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if #available(iOS 26.0, *) {
                Button {
                    dismiss()
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            } else {
                Button {
                    dismiss()
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Row

private struct TipItemRow: View {

    let item: PostBoardingTipItem

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

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
