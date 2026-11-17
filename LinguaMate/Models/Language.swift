import Foundation

/// Languages the tutor can practise with. The learner-facing UI is Chinese,
/// the target language is what the model speaks and what the speech stack uses.
enum SupportedLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    /// BCP-47 tag used by `SFSpeechRecognizer` and `AVSpeechSynthesisVoice`.
    var localeIdentifier: String {
        switch self {
        case .english:
            return "en-US"
        case .japanese:
            return "ja-JP"
        }
    }

    /// Name used inside the system prompt (e.g. "English").
    var promptName: String {
        switch self {
        case .english:
            return "English"
        case .japanese:
            return "Japanese"
        }
    }

    var displayName: String {
        switch self {
        case .english:
            return "英语"
        case .japanese:
            return "日语"
        }
    }

    var endonym: String {
        switch self {
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }

    var flag: String {
        switch self {
        case .english:
            return "🇺🇸"
        case .japanese:
            return "🇯🇵"
        }
    }

    /// Voices we prefer, in order, when the system has them installed.
    var preferredVoiceNames: [String] {
        switch self {
        case .english:
            return ["Samantha (Enhanced)", "Samantha", "Ava", "Alex", "Daniel", "Karen"]
        case .japanese:
            return ["Kyoko (Enhanced)", "Kyoko", "Hattori", "O-ren", "Nanami"]
        }
    }
}

/// Difficulty presets that shape both the prompt and the reply length.
enum ConversationLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner:
            return "入门"
        case .intermediate:
            return "进阶"
        case .advanced:
            return "高阶"
        }
    }

    var detail: String {
        switch self {
        case .beginner:
            return "短句 + 慢速，尽量用高频词"
        case .intermediate:
            return "自然口语，偶尔出现习语"
        case .advanced:
            return "接近母语者的语速与表达"
        }
    }

    /// Injected verbatim into the system prompt.
    var promptGuidance: String {
        switch self {
        case .beginner:
            return "Use very simple, high-frequency words and short sentences (max ~10 words). Speak slowly and repeat key vocabulary."
        case .intermediate:
            return "Use everyday conversational language with occasional idioms. Sentences can be 1-3 clauses long."
        case .advanced:
            return "Speak like a native speaker: natural pace, richer vocabulary, idioms, and follow-up questions that push the learner."
        }
    }

    /// Speech synthesis rate multiplier.
    var speechRateMultiplier: Double {
        switch self {
        case .beginner:
            return 0.85
        case .intermediate:
            return 1.0
        case .advanced:
            return 1.1
        }
    }
}