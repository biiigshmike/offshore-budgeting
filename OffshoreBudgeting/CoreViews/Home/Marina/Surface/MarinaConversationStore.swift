//
//  MarinaConversationStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import SwiftData

enum MarinaConversationDisplayRole: Equatable {
    case user
    case assistant
}

struct MarinaConversationDisplayMessage: Identifiable, Equatable {
    let id: String
    let role: MarinaConversationDisplayRole
    let prompt: String?
    let answer: HomeAnswer?
    let generatedAt: Date
}

enum MarinaConversationDisplayAdapter {
    static func messages(from answers: [HomeAnswer]) -> [MarinaConversationDisplayMessage] {
        answers.flatMap { answer -> [MarinaConversationDisplayMessage] in
            let trimmedPrompt = answer.userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let assistantMessage = MarinaConversationDisplayMessage(
                id: "assistant-\(answer.id.uuidString)",
                role: .assistant,
                prompt: nil,
                answer: answer,
                generatedAt: answer.generatedAt
            )

            guard trimmedPrompt.isEmpty == false else {
                return [assistantMessage]
            }

            return [
                MarinaConversationDisplayMessage(
                    id: "user-\(answer.id.uuidString)",
                    role: .user,
                    prompt: trimmedPrompt,
                    answer: nil,
                    generatedAt: answer.generatedAt
                ),
                assistantMessage
            ]
        }
    }
}

// MARK: - Conversation Store

final class MarinaConversationStore {
    static let maxStoredAnswers = 50

    private let userDefaults: UserDefaults
    private let storageKeyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKeyPrefix: String = "home.assistant.answers"
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKeyPrefix
    }

    func loadAnswers(workspaceID: UUID) -> [HomeAnswer] {
        let key = storageKey(for: workspaceID)
        guard let data = userDefaults.data(forKey: key) else { return [] }

        do {
            return try decoder.decode([HomeAnswer].self, from: data)
        } catch {
            return []
        }
    }

    func saveAnswers(_ answers: [HomeAnswer], workspaceID: UUID) {
        let trimmedAnswers = trimmed(answers)
        let key = storageKey(for: workspaceID)

        do {
            let data = try encoder.encode(trimmedAnswers)
            userDefaults.set(data, forKey: key)
        } catch {
            return
        }
    }

    func loadLastCheckIn(workspaceID: UUID) -> Date? {
        userDefaults.object(forKey: checkInStorageKey(for: workspaceID)) as? Date
    }

    func saveLastCheckIn(_ date: Date, workspaceID: UUID) {
        userDefaults.set(date, forKey: checkInStorageKey(for: workspaceID))
    }

    // MARK: - Helpers

    private func storageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).\(workspaceID.uuidString)"
    }

    private func checkInStorageKey(for workspaceID: UUID) -> String {
        "\(storageKeyPrefix).checkIn.\(workspaceID.uuidString)"
    }

    private func trimmed(_ answers: [HomeAnswer]) -> [HomeAnswer] {
        guard answers.count > Self.maxStoredAnswers else { return answers }
        return Array(answers.suffix(Self.maxStoredAnswers))
    }
}

// MARK: - Chat Session Store

@MainActor
final class MarinaChatSessionStore {
    nonisolated static let defaultTitle = "New Chat"

    private let userDefaults: UserDefaults
    private let legacyConversationStore: MarinaConversationStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let migrationKeyPrefix = "home.assistant.chatSessions.migrated"

    init(
        userDefaults: UserDefaults = .standard,
        legacyConversationStore: MarinaConversationStore? = nil
    ) {
        self.userDefaults = userDefaults
        self.legacyConversationStore = legacyConversationStore ?? MarinaConversationStore(userDefaults: userDefaults)
    }

    func sessions(
        workspaceID: UUID,
        modelContext: ModelContext
    ) throws -> [MarinaChatSession] {
        let descriptor = FetchDescriptor<MarinaChatSession>(
            predicate: #Predicate<MarinaChatSession> { session in
                session.workspace?.id == workspaceID
            },
            sortBy: [
                SortDescriptor(\MarinaChatSession.lastOpenedAt, order: .reverse),
                SortDescriptor(\MarinaChatSession.updatedAt, order: .reverse)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func session(
        id: UUID,
        workspaceID: UUID,
        modelContext: ModelContext
    ) throws -> MarinaChatSession? {
        var descriptor = FetchDescriptor<MarinaChatSession>(
            predicate: #Predicate<MarinaChatSession> { session in
                session.id == id && session.workspace?.id == workspaceID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func ensureActiveSession(
        for workspace: Workspace,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaChatSession {
        try migrateLegacyAnswersIfNeeded(for: workspace, modelContext: modelContext, now: now)

        if let session = try sessions(workspaceID: workspace.id, modelContext: modelContext).first {
            try selectSession(session, modelContext: modelContext, now: now)
            return session
        }

        return try createSession(workspace: workspace, modelContext: modelContext, now: now)
    }

    @discardableResult
    func createSession(
        workspace: Workspace,
        title: String? = nil,
        answers: [HomeAnswer] = [],
        followUpContext: MarinaConversationContext? = nil,
        hasCustomTitle: Bool = false,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaChatSession {
        let trimmedAnswers = trimmed(answers)
        let resolvedTitle = titleFromInput(title)
            ?? generatedTitle(from: trimmedAnswers)
            ?? Self.defaultTitle
        let context = followUpContext ?? MarinaConversationContext(recentAnswers: trimmedAnswers)
        let session = MarinaChatSession(
            title: resolvedTitle,
            hasCustomTitle: hasCustomTitle,
            visibleAnswersData: try encodedAnswers(trimmedAnswers),
            followUpContextData: try encodedContext(context),
            workspace: workspace,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now
        )
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    func selectSession(
        _ session: MarinaChatSession,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        session.lastOpenedAt = now
        session.updatedAt = now
        try modelContext.save()
    }

    func saveTranscript(
        _ answers: [HomeAnswer],
        sessionID: UUID,
        workspaceID: UUID,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaConversationContext {
        guard let session = try session(id: sessionID, workspaceID: workspaceID, modelContext: modelContext) else {
            return .empty
        }

        let trimmedAnswers = trimmed(answers)
        let context = MarinaConversationContext(recentAnswers: trimmedAnswers)
        session.visibleAnswersData = try encodedAnswers(trimmedAnswers)
        session.followUpContextData = try encodedContext(context)
        session.updatedAt = now
        session.lastOpenedAt = now

        if session.hasCustomTitle == false,
           let generated = generatedTitle(from: trimmedAnswers) {
            session.title = generated
        }

        try modelContext.save()
        return context
    }

    func saveFollowUpContext(
        _ context: MarinaConversationContext,
        sessionID: UUID,
        workspaceID: UUID,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        guard let session = try session(id: sessionID, workspaceID: workspaceID, modelContext: modelContext) else {
            return
        }
        session.followUpContextData = try encodedContext(context)
        session.updatedAt = now
        try modelContext.save()
    }

    @discardableResult
    func renameSession(
        id: UUID,
        title: String,
        workspaceID: UUID,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaChatSession? {
        guard let session = try session(id: id, workspaceID: workspaceID, modelContext: modelContext),
              let title = titleFromInput(title) else {
            return nil
        }
        session.title = title
        session.hasCustomTitle = true
        session.updatedAt = now
        session.lastOpenedAt = now
        try modelContext.save()
        return session
    }

    @discardableResult
    func clearSession(
        id: UUID,
        workspaceID: UUID,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaChatSession? {
        guard let session = try session(id: id, workspaceID: workspaceID, modelContext: modelContext) else {
            return nil
        }

        session.visibleAnswersData = try encodedAnswers([])
        session.followUpContextData = try encodedContext(.empty)
        if session.hasCustomTitle == false {
            session.title = Self.defaultTitle
        }
        session.updatedAt = now
        session.lastOpenedAt = now
        try modelContext.save()
        return session
    }

    @discardableResult
    func deleteSession(
        id: UUID,
        workspace: Workspace,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> MarinaChatSession {
        if let session = try session(id: id, workspaceID: workspace.id, modelContext: modelContext) {
            modelContext.delete(session)
            try modelContext.save()
        }

        if let fallback = try sessions(workspaceID: workspace.id, modelContext: modelContext).first {
            try selectSession(fallback, modelContext: modelContext, now: now)
            return fallback
        }

        return try createSession(workspace: workspace, modelContext: modelContext, now: now)
    }

    func visibleAnswers(for session: MarinaChatSession) -> [HomeAnswer] {
        guard session.visibleAnswersData.isEmpty == false,
              let answers = try? decoder.decode([HomeAnswer].self, from: session.visibleAnswersData) else {
            return []
        }
        return trimmed(answers)
    }

    func followUpContext(for session: MarinaChatSession) -> MarinaConversationContext {
        guard session.followUpContextData.isEmpty == false,
              let context = try? decoder.decode(MarinaConversationContext.self, from: session.followUpContextData) else {
            return MarinaConversationContext(recentAnswers: visibleAnswers(for: session))
        }
        return context
    }

    func markLegacyMigrationComplete(workspaceID: UUID) {
        userDefaults.set(true, forKey: migrationKey(for: workspaceID))
    }

    // MARK: - Migration

    private func migrateLegacyAnswersIfNeeded(
        for workspace: Workspace,
        modelContext: ModelContext,
        now: Date
    ) throws {
        let workspaceID = workspace.id
        guard userDefaults.bool(forKey: migrationKey(for: workspaceID)) == false else {
            return
        }

        guard try sessions(workspaceID: workspaceID, modelContext: modelContext).isEmpty else {
            markLegacyMigrationComplete(workspaceID: workspaceID)
            return
        }

        let legacyAnswers = legacyConversationStore.loadAnswers(workspaceID: workspaceID)
        guard legacyAnswers.isEmpty == false else {
            markLegacyMigrationComplete(workspaceID: workspaceID)
            return
        }

        _ = try createSession(
            workspace: workspace,
            answers: legacyAnswers,
            followUpContext: MarinaConversationContext(recentAnswers: legacyAnswers),
            modelContext: modelContext,
            now: now
        )
        markLegacyMigrationComplete(workspaceID: workspaceID)
    }

    // MARK: - Encoding

    private func encodedAnswers(_ answers: [HomeAnswer]) throws -> Data {
        try encoder.encode(trimmed(answers))
    }

    private func encodedContext(_ context: MarinaConversationContext) throws -> Data {
        try encoder.encode(context)
    }

    // MARK: - Helpers

    private func migrationKey(for workspaceID: UUID) -> String {
        "\(migrationKeyPrefix).\(workspaceID.uuidString)"
    }

    private func trimmed(_ answers: [HomeAnswer]) -> [HomeAnswer] {
        guard answers.count > MarinaConversationStore.maxStoredAnswers else { return answers }
        return Array(answers.suffix(MarinaConversationStore.maxStoredAnswers))
    }

    private func titleFromInput(_ title: String?) -> String? {
        let trimmed = (title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return trimmed.isEmpty ? nil : limitedTitle(trimmed)
    }

    private func generatedTitle(from answers: [HomeAnswer]) -> String? {
        for answer in answers {
            if let prompt = titleFromInput(answer.userPrompt) {
                return prompt
            }
            if let title = titleFromInput(answer.title) {
                return title
            }
        }
        return nil
    }

    private func limitedTitle(_ title: String) -> String {
        let maxLength = 54
        guard title.count > maxLength else { return title }
        let prefix = String(title.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }
}
