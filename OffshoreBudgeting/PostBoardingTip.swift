//
//  PostBoardingTip.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

/// Full-page “tips & hints” sheet shown once per key, until SettingsGeneralView resets them.
/// Usage:
///     HomeView(...)
///         .postBoardingTip(
///             key: "home",
///             title: "Home",
///             systemImage: "house.fill",
///             message: "Tap any widget to see deeper metrics. Use the calendar to change ranges."
///         )
extension View {
    func postBoardingTip(
        key: String,
        title: String,
        systemImage: String,
        message: String,
        buttonTitle: String = "Continue"
    ) -> some View {
        modifier(PostBoardingTipModifier(
            key: key,
            title: title,
            systemImage: systemImage,
            message: message,
            buttonTitle: buttonTitle
        ))
    }
}

private struct PostBoardingTipModifier: ViewModifier {

    let key: String
    let title: String
    let systemImage: String
    let message: String
    let buttonTitle: String

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    // Controlled by SettingsGeneralView -> "Reset Tips & Hints"
    @AppStorage("tips_resetToken") private var tipsResetToken: Int = 0

    // Persisted seen keys
    @AppStorage("tips_seenKeys") private var seenKeysCSV: String = ""
    @AppStorage("tips_seen_lastResetToken") private var lastResetToken: Int = 0

    @State private var showingTip: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                normalizeForResetIfNeeded()
                showingTip = shouldShowTip()
            }
            .onChange(of: tipsResetToken) { _, _ in
                normalizeForResetIfNeeded()
                showingTip = shouldShowTip()
            }
            .sheet(isPresented: $showingTip, onDismiss: markSeen) {
                TipSheet(
                    title: title,
                    systemImage: systemImage,
                    message: message,
                    buttonTitle: buttonTitle
                )
            }
    }

    private func normalizeForResetIfNeeded() {
        guard lastResetToken != tipsResetToken else { return }
        // New reset token, clear seen keys.
        seenKeysCSV = ""
        lastResetToken = tipsResetToken
    }

    private func shouldShowTip() -> Bool {
        guard didCompleteOnboarding else { return false }
        let seen = Set(seenKeysCSV.split(separator: ",").map { String($0) })
        return !seen.contains(key)
    }

    private func markSeen() {
        var seen = Set(seenKeysCSV.split(separator: ",").map { String($0) })
        seen.insert(key)
        seenKeysCSV = seen.sorted().joined(separator: ",")
    }
}

private struct TipSheet: View {

    let title: String
    let systemImage: String
    let message: String
    let buttonTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: systemImage)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title.weight(.bold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .padding(.top, 28)
        .presentationDetents([.large])
    }
}
