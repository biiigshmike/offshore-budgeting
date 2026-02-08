//
//  HomeAssistantFoundation.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import SwiftUI

// MARK: - Assistant State

enum HomeAssistantState: Equatable {
    case collapsed
    case presented
}

// MARK: - Launcher Bar (iPhone)

struct HomeAssistantLauncherBar: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "message")
                    .font(.subheadline.weight(.semibold))

                Text("Ask about your budget")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(launcherBackgroundStyle, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var launcherBackgroundStyle: AnyShapeStyle {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.bar)
        }
        #endif

        return AnyShapeStyle(.thinMaterial)
    }
}

// MARK: - Presented Panel

struct HomeAssistantPanelView: View {
    let onDismiss: () -> Void
    let shouldUseLargeMinimumSize: Bool

    var body: some View {
        let content = NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Assistant is ready.")
                    .font(.headline)

                Text("This panel is the foundation for suggested questions and answers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .navigationTitle("Assistant")
        }
        .toolbarBackground(panelHeaderBackgroundStyle, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)

        if shouldUseLargeMinimumSize {
            content.frame(minWidth: 700, minHeight: 520)
        } else {
            content
        }
    }

    private var panelHeaderBackgroundStyle: AnyShapeStyle {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.bar)
        }
        #endif

        return AnyShapeStyle(.thinMaterial)
    }
}
