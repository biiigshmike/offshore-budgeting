//
//  MarinaModelAvailability.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

struct MarinaModelAvailability {
    enum Status: Equatable {
        case available
        case unavailable(reason: String)
    }

    func currentStatus() -> Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return availabilityStatus()
        } else {
            return .unavailable(reason: "runtime_unavailable")
        }
        #else
        availabilityStatus()
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private func availabilityStatus() -> MarinaModelAvailability.Status {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        return .available
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return .unavailable(reason: "device_not_eligible")
        case .appleIntelligenceNotEnabled:
            return .unavailable(reason: "apple_intelligence_not_enabled")
        case .modelNotReady:
            return .unavailable(reason: "model_not_ready")
        @unknown default:
            return .unavailable(reason: "unknown")
        }
    }
}
#else
private func availabilityStatus() -> MarinaModelAvailability.Status {
    .unavailable(reason: "framework_unavailable")
}
#endif
