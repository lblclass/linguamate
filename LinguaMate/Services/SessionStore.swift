import Foundation
import Observation

/// Conversation history, persisted as one JSON document in the app's
/// Documents directory. Local-only by design: no transcripts leave the device
/// except in the request the learner explicitly sends to their own model.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [ConversationSession] = []
    private(set) var lastError: String?

    /// Keeps the file small on long-term use.
    var maximumStoredSessions = 120

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base.appendingPathComponent("sessions.json")
        }
        load()
    }

    var storageURL: URL { fileURL }

    var totalTurns: Int {
        sessions.reduce(0) { $0 + $1.turnCount }
    }

    func upsert(_ session: ConversationSession) {
        var stored = session
        stored.updatedAt = Date()
        if let index = sessions.firstIndex(where: { $0.id == stored.id }) {
            sessions[index] = stored
        } else {
            sessions.insert(stored, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        if sessions.count > maximumStoredSessions {
            sessions = Array(sessions.prefix(maximumStoredSessions))
        }
        persist()
    }

    func delete(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        sessions.removeAll()
        persist()
    }

    func session(id: UUID) -> ConversationSession? {
        sessions.first { $0.id == id }
    }

    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try Self.decode(data)
            lastError = nil
        } catch {
            sessions = []
            lastError = "历史记录读取失败：\(error.localizedDescription)"
        }
    }

    func persist() {
        do {
            let data = try Self.encode(sessions)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "历史记录保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Pure codec (unit tested)

    nonisolated static func encode(_ sessions: [ConversationSession]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sessions)
    }

    nonisolated static func decode(_ data: Data) throws -> [ConversationSession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ConversationSession].self, from: data)
    }
}