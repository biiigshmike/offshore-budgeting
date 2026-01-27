//
//  LocalAuthenticationService.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import Foundation
import LocalAuthentication

enum BiometricsKind: Equatable {
    case faceID
    case touchID
    case none

    var displayName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }
}

enum LocalAuthenticationService {

    struct BiometricAvailability {
        let kind: BiometricsKind
        let isAvailable: Bool
        let errorMessage: String?
    }

    /// Use this for UI (Face ID vs Touch ID vs not available).
    static func biometricAvailability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?

        // Important: calling canEvaluatePolicy sets biometryType correctly.
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        let kind: BiometricsKind
        switch context.biometryType {
        case .faceID: kind = .faceID
        case .touchID: kind = .touchID
        default: kind = .none
        }

        let message = error.map { userFriendlyMessage(for: $0) }
        return BiometricAvailability(kind: kind, isAvailable: canEvaluate, errorMessage: message)
    }

    /// This is what you use to unlock the app.
    /// Uses deviceOwnerAuthentication so the system can fall back to passcode when appropriate.
    static func authenticateForUnlock(localizedReason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.biometryNotAvailable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, evalError in
                if let evalError = evalError as? LAError {
                    switch evalError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        // Treat cancels as a simple "false", no need to throw.
                        continuation.resume(returning: false)
                    default:
                        continuation.resume(throwing: evalError)
                    }
                    return
                }

                if let evalError = evalError {
                    continuation.resume(throwing: evalError)
                    return
                }

                continuation.resume(returning: success)
            }
        }
    }

    static func userFriendlyMessage(for error: Error) -> String {
        if let laError = error as? LAError {
            switch laError.code {
            case .authenticationFailed:
                return "Authentication failed. Please try again."
            case .passcodeNotSet:
                return "A device passcode is not set. Set a passcode in Settings to use app lock."
            case .biometryNotAvailable:
                return "Face ID / Touch ID is not available on this device."
            case .biometryNotEnrolled:
                return "Face ID / Touch ID is not set up. Enroll in Settings to use app lock."
            case .biometryLockout:
                return "Face ID / Touch ID is temporarily locked. Use your device passcode to unlock it."
            case .userCancel, .appCancel, .systemCancel:
                return "Authentication was canceled."
            case .invalidContext:
                return "Authentication context became invalid. Please try again."
            default:
                return laError.localizedDescription
            }
        }

        return error.localizedDescription
    }
}
