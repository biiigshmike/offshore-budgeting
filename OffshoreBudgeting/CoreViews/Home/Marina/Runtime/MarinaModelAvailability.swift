//
//  MarinaModelAvailability.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

protocol MarinaModelAvailabilityProviding {
    func currentStatus() -> MarinaModelAvailability.Status
}

struct MarinaModelAvailability {
    enum UnavailableReason: String, Equatable {
        case deviceNotEligible = "device_not_eligible"
        case appleIntelligenceNotEnabled = "apple_intelligence_not_enabled"
        case modelNotReady = "model_not_ready"
        case unsupportedLocale = "unsupported_locale"
        case runtimeUnavailable = "runtime_unavailable"
        case frameworkUnavailable = "framework_unavailable"
        case unknown = "unknown"
    }

    enum Status: Equatable {
        case available
        case unavailable(reason: UnavailableReason)

        var unavailableReason: UnavailableReason? {
            guard case .unavailable(let reason) = self else { return nil }
            return reason
        }

        var traceValue: String {
            switch self {
            case .available:
                return "available"
            case .unavailable(let reason):
                return reason.rawValue
            }
        }
    }

    func currentStatus() -> Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return availabilityStatus()
        } else {
            return .unavailable(reason: .runtimeUnavailable)
        }
        #else
        availabilityStatus()
        #endif
    }
}

extension MarinaModelAvailability: MarinaModelAvailabilityProviding {}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private func availabilityStatus() -> MarinaModelAvailability.Status {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        guard model.supportsLocale(.current) else {
            return .unavailable(reason: .unsupportedLocale)
        }
        return .available
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return .unavailable(reason: .deviceNotEligible)
        case .appleIntelligenceNotEnabled:
            return .unavailable(reason: .appleIntelligenceNotEnabled)
        case .modelNotReady:
            return .unavailable(reason: .modelNotReady)
        @unknown default:
            return .unavailable(reason: .unknown)
        }
    }
}
#else
private func availabilityStatus() -> MarinaModelAvailability.Status {
    .unavailable(reason: .frameworkUnavailable)
}
#endif
