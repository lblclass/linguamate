import Foundation

/// Who produced a message in the transcript.
enum MessageRole: String, Codable, Sendable {
    case learner
    case tutor
}

/// A single grammar / word-choice correction produced by the tutor.
struct Correction: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var original: String
    var corrected: String
    var note: String

    var isEmpty: Bool {
        original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One bubble in the conversation.
struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var role: MessageRole
    var text: String
    var translation: String?
    var corrections: [Correction] = []
    var followUps: [String] = []
    var createdAt: Date = Date()
    /// True when the reply came from the offline demo engine (no API key).
    var isDemo = false

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Structured answer of the tutor for one turn.
struct TutorReply: Equatable, Sendable {
    var reply: String
    var translation: String?
    var corrections: [Correction]
    var followUps: [String]

    static let empty = TutorReply(reply: "", translation: nil, corrections: [], followUps: [])

    var trimmedReply: String {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A persisted conversation.
struct ConversationSession: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var topicID: String
    var topicTitle: String
    var topicEmoji: String = "💬"
    var language: SupportedLanguage
    var level: ConversationLevel
    var startedAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [ChatMessage] = []
    var isDemo = false

    var turnCount: Int {
        messages.filter { $0.role == .learner }.count
    }

    var isEmpty: Bool {
        messages.isEmpty
    }

    var preview: String {
        if let text = messages.last(where: { !$0.isEmpty })?.text {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        return "还没有开始对话"
    }

    var summaryLine: String {
        var parts = [language.displayName, level.displayName, "\(turnCount) 轮"]
        if isDemo { parts.append("演示") }
        return parts.joined(separator: " · ")
    }
}

/// Errors surfaced by the tutor engines.
enum ChatEngineError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case http(status: Int, body: String)
    case api(String)
    case cancelled
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有配置 API Key，请到「设置」里填写，或打开离线演示模式。"
        case .invalidBaseURL(let value):
            return "Base URL 不合法：\(value)"
        case .http(let status, let body):
            let detail = body.isEmpty ? "" : "：\(body.prefix(240))"
            return "服务返回 HTTP \(status)\(detail)"
        case .api(let message):
            return "模型服务返回错误：\(message)"
        case .cancelled:
            return "已取消"
        case .emptyResponse:
            return "模型没有返回内容，请稍后再试。"
        }
    }
}
