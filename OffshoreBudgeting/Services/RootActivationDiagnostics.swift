//
//  RootActivationDiagnostics.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/16/26.
//

import SwiftUI
import QuartzCore

enum RootActivationDiagnostics {
    static func measure<T>(
        _ eventPrefix: String,
        metadata: [String: String] = [:],
        work: () -> T
    ) -> T {
        MainActor.assumeIsolated {
            TabFlickerDiagnostics.markEvent("\(eventPrefix)Started", metadata: metadata)
        }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        var completedMetadata = metadata
        completedMetadata["elapsedMs"] = String(format: "%.1f", elapsedMs)
        MainActor.assumeIsolated {
            TabFlickerDiagnostics.markEvent("\(eventPrefix)Finished", metadata: completedMetadata)
        }
        return result
    }
}

private struct RootActivationBodyReporter: ViewModifier {
    let root: String
    let context: AppTabActivationContext

    @State private var lastEmissionID: String = ""
    @State private var hasAppearedVisible: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                emitPhaseIfNeeded(trigger: "appear")
            }
            .onChange(of: context) { _, _ in
                emitPhaseIfNeeded(trigger: "contextChanged")
            }
    }

    private func emitPhaseIfNeeded(trigger: String) {
        let semanticPhase = semanticPhaseName
        let emissionID = "\(semanticPhase)|\(context.phase.rawValue)|\(context.token)"
        guard emissionID != lastEmissionID else { return }
        lastEmissionID = emissionID

        let metadata = [
            "root": root,
            "phase": semanticPhase,
            "activationPhase": context.phase.rawValue,
            "token": String(context.token),
            "trigger": trigger,
            "source": context.phase == .inactive ? "deactivation" : "firstFrame"
        ]
        let startedAt = DispatchTime.now().uptimeNanoseconds
        MainActor.assumeIsolated {
            TabFlickerDiagnostics.markEvent("rootBodyPhaseStarted", metadata: metadata)
        }

        if context.phase != .inactive {
            hasAppearedVisible = true
        }

        DispatchQueue.main.async {
            guard lastEmissionID == emissionID else { return }
            var completedMetadata = metadata
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            completedMetadata["elapsedMs"] = String(format: "%.1f", elapsedMs)
            MainActor.assumeIsolated {
                TabFlickerDiagnostics.markEvent("rootBodyEnqueuedFinished", metadata: completedMetadata)
            }
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            guard lastEmissionID == emissionID else { return }
            var completedMetadata = metadata
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            completedMetadata["elapsedMs"] = String(format: "%.1f", elapsedMs)
            MainActor.assumeIsolated {
                TabFlickerDiagnostics.markEvent("rootBodyPhaseFinished", metadata: completedMetadata)
                TabFlickerDiagnostics.markEvent("rootBodyFrameCommittedFinished", metadata: completedMetadata)
            }
        }
        CATransaction.commit()
    }

    private var semanticPhaseName: String {
        switch context.phase {
        case .inactive:
            return "inactive"
        case .activating, .active:
            return hasAppearedVisible ? "reentry" : "initial"
        }
    }
}

extension View {
    func rootActivationBodyReporter(
        root: String,
        context: AppTabActivationContext
    ) -> some View {
        modifier(RootActivationBodyReporter(root: root, context: context))
    }
}
