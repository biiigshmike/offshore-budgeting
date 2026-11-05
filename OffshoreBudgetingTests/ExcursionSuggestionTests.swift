import Foundation
import CoreLocation
import Testing
@testable import Offshore

@MainActor
struct ExcursionSuggestionTests {
    private enum Failure: Error { case scheduling }

    private func suggestion(session: String = "session") -> ExcursionSuggestion {
        ExcursionSuggestion(candidates: [.init(id: "near", name: "Nearby Shop")], workspaceID: UUID(), sessionID: session)
    }

    @Test func payloadPreservesOriginAndBoundsChooser() throws {
        let value = ExcursionSuggestion(candidates: (0..<8).map { .init(id: String($0), name: "Shop \($0)") },
                                       workspaceID: UUID(), sessionID: "original-session")
        let encoded = try #require(value.encoded)
        let decoded = try #require(ExcursionSuggestion.decode(encoded))
        #expect(decoded == value)
        #expect(decoded.candidates.count == 5)
        #expect(ExcursionSuggestion.decode("{}") == nil)
    }

    @Test func failedSchedulingDoesNotConsumeCooldown() async {
        let suite = "ExcursionSuggestionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var attempts = 0
        let service = ShoppingModeSuggestionService(defaults: defaults, sessionIDProvider: { "session" }, schedule: { _, _ in
            attempts += 1
            if attempts == 1 { throw Failure.scheduling }
            return "notification"
        })
        let value = suggestion()
        #expect(await service.send(suggestion: value, currentLocation: nil, isStillValid: { true }) == .failed)
        #expect(await service.send(suggestion: value, currentLocation: nil, isStillValid: { true }) == .scheduled(identifier: "notification"))
        #expect(await service.send(suggestion: value, currentLocation: nil, isStillValid: { true }) == .suppressed)
        #expect(attempts == 2)
    }

    @MainActor private final class SchedulingGate {
        var valid = true
        var completion: CheckedContinuation<String?, Never>?
        var started: CheckedContinuation<Void, Never>?
        func pause() async -> String? {
            await withCheckedContinuation { continuation in
                completion = continuation
                started?.resume()
                started = nil
            }
        }
        func waitUntilStarted() async {
            if completion != nil { return }
            await withCheckedContinuation { started = $0 }
        }
    }

    @Test func inFlightDeliveryCannotDuplicateAndInvalidatedStopIsCanceled() async {
        let suite = "ExcursionSuggestionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = SchedulingGate()
        var canceled: [String] = []
        let service = ShoppingModeSuggestionService(defaults: defaults, sessionIDProvider: { "session" },
            schedule: { _, _ in await gate.pause() }, cancel: { canceled.append($0) })
        let value = suggestion()
        let delivery = Task { await service.send(suggestion: value, currentLocation: nil, isStillValid: { gate.valid }) }
        await gate.waitUntilStarted()
        #expect(await service.send(suggestion: value, currentLocation: nil, isStillValid: { true }) == .suppressed)
        gate.valid = false // Departure, permission loss, or a replaced detection window.
        gate.completion?.resume(returning: "obsolete")
        gate.completion = nil
        #expect(await delivery.value == .suppressed)
        #expect(canceled == ["obsolete"])
        #expect(defaults.object(forKey: "shoppingMode_lastGlobalFireAt") == nil)
    }

    @Test func expiredSessionCannotSchedule() async {
        let suite = "ExcursionSuggestionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var attempts = 0
        let service = ShoppingModeSuggestionService(defaults: defaults, sessionIDProvider: { nil }, schedule: { _, _ in
            attempts += 1
            return "unexpected"
        })
        #expect(await service.send(suggestion: suggestion(), currentLocation: nil, isStillValid: { true }) == .suppressed)
        #expect(attempts == 0)
    }

    @Test func sessionChangingDuringSchedulingCancelsWithoutCooldown() async {
        let suite = "ExcursionSuggestionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var session: String? = "session"
        var canceled: [String] = []
        let service = ShoppingModeSuggestionService(defaults: defaults, sessionIDProvider: { session }, schedule: { _, _ in
            session = nil
            return "stale"
        }, cancel: { canceled.append($0) })
        #expect(await service.send(suggestion: suggestion(), currentLocation: nil, isStillValid: { true }) == .suppressed)
        #expect(canceled == ["stale"])
        #expect(defaults.object(forKey: "shoppingMode_lastGlobalFireAt") == nil)
    }
}
