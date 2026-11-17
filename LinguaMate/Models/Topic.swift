import Foundation

/// A conversation scenario built into the app. Topics are static data so the
/// app is useful the second it launches, without any server round-trip.
struct ConversationTopic: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var language: SupportedLanguage
    var category: String
    /// Chinese title shown in the picker.
    var title: String
    var emoji: String
    /// Chinese one-line description.
    var summary: String
    /// Who the model plays, written in English for the system prompt.
    var role: String
    /// What the learner should get out of the session (English, for the prompt).
    var goal: String
    /// First utterance of the tutor, in the target language.
    var openingLine: String
    /// Target-language phrases the tutor should weave into the conversation.
    var keyPhrases: [String]
}

extension ConversationTopic {
    var displayTitle: String { "\(emoji) \(title)" }
}