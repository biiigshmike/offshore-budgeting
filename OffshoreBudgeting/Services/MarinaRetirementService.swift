import SwiftData

/// Temporary upgrade compatibility. Remove this service and its launch/sync hooks
/// before a rebuilt Marina writes conversations or aliases to these models.
@MainActor
struct MarinaRetirementService {
    /// Intentionally covers every workspace, including orphaned assistant records.
    /// A separate context keeps a failed retirement from rolling back user edits.
    static func purgeLegacyRecords(in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try purgeLegacyRecords(in: context)
    }

    static func purgeLegacyRecords(
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        // Complete both fetches before staging any deletes, so a fetch failure is harmless.
        let sessions = try context.fetch(FetchDescriptor<MarinaChatSession>())
        let aliases = try context.fetch(FetchDescriptor<AssistantAliasRule>())
        guard !sessions.isEmpty || !aliases.isEmpty else { return }
        for session in sessions { context.delete(session) }
        for alias in aliases { context.delete(alias) }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
