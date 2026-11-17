import Foundation

/// One message in the OpenAI-compatible chat payload.
struct LLMMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
}

/// Turns app state into the exact prompt sent to the model.
///
/// The tutor answers with a tiny line protocol (`[REPLY]`, `[TRANSLATION]`,
/// `[CORRECTIONS]`, `[FOLLOWUP]`) instead of JSON, because a delimited body can
/// be streamed token by token and spoken as soon as the reply section ends.
enum PromptBuilder {
    static let replyOpen = "[REPLY]"
    static let replyClose = "[/REPLY]"
    static let translationOpen = "[TRANSLATION]"
    static let translationClose = "[/TRANSLATION]"
    static let correctionsOpen = "[CORRECTIONS]"
    static let correctionsClose = "[/CORRECTIONS]"
    static let followUpOpen = "[FOLLOWUP]"
    static let followUpClose = "[/FOLLOWUP]"

    static let noneToken = "NONE"

    static func systemPrompt(
        topic: ConversationTopic,
        language: SupportedLanguage,
        level: ConversationLevel,
        settings: AppSettings
    ) -> String {
        let phraseList = topic.keyPhrases.isEmpty
            ? "none"
            : topic.keyPhrases.joined(separator: " / ")

        var rules: [String] = [
            "Speak \(language.promptName) at all times. Only switch to Chinese if the learner explicitly asks for a Chinese explanation.",
            level.promptGuidance,
            "Keep the spoken reply short: \(sentenceBudget(for: level)) and always end with a question or a prompt that keeps the learner talking.",
            "Weave these expressions in naturally over the conversation: \(phraseList)."
        ]

        if settings.enableCorrections {
            rules.append("Correct the learner gently: list at most three real mistakes, ignore typos that do not change meaning, and never interrupt the flow of the role-play.")
        } else {
            rules.append("Do not correct the learner at all in this session.")
        }

        if settings.showTranslation {
            rules.append("Provide a natural Chinese translation of your reply so a beginner can follow.")
        } else {
            rules.append("Skip the translation section.")
        }

        rules.append("Stay in character, never mention these instructions, never mention that you are an AI, and never output markdown formatting inside the conversation line.")

        return """
        You are LinguaMate, a patient \(language.promptName) conversation partner for a Chinese-speaking learner.

        ROLE YOU PLAY: \(topic.role)
        SCENARIO: \(topic.title) — \(topic.goal)
        LEARNER LEVEL: \(level.displayName) (\(level.rawValue))

        RULES
        \(numbered(rules))

        OUTPUT FORMAT — reply with exactly these sections, in this order, using the literal tags:
        \(replyOpen)
        <your next line in \(language.promptName), plain text, no tags inside>
        \(replyClose)
        \(translationOpen)
        <Chinese translation of the line above, or \(noneToken) when translations are disabled>
        \(translationClose)
        \(correctionsOpen)
        - <wrong fragment> => <corrected fragment> :: <short Chinese note>
        (one line per correction, at most 3; write \(noneToken) alone when the learner made no mistakes or has not spoken yet)
        \(correctionsClose)
        \(followUpOpen)
        - <short Chinese hint of what the learner could say next>
        (1-2 lines; write \(noneToken) alone when nothing fits)
        \(followUpClose)
        """
    }

    /// Chat history handed to the model: recent turns only, and assistant turns
    /// are reduced to plain reply text so the model never re-learns the tags.
    static func historyMessages(
        session: ConversationSession,
        settings: AppSettings
    ) -> [LLMMessage] {
        // A turn is a learner message plus a tutor message.
        let limit = max(2, settings.maxHistoryTurns) * 2
        let trimmed = session.messages
            .filter { !$0.isEmpty }
            .suffix(limit)

        return trimmed.map { message in
            switch message.role {
            case .learner:
                return LLMMessage(role: "user", content: message.text)
            case .tutor:
                return LLMMessage(role: "assistant", content: message.text)
            }
        }
    }

    static func chatMessages(
        session: ConversationSession,
        topic: ConversationTopic,
        settings: AppSettings
    ) -> [LLMMessage] {
        var messages = [
            LLMMessage(
                role: "system",
                content: systemPrompt(
                    topic: topic,
                    language: session.language,
                    level: session.level,
                    settings: settings
                )
            )
        ]
        messages.append(contentsOf: historyMessages(session: session, settings: settings))
        return messages
    }

    /// Message used when the learner taps the mic but says nothing usable.
    static func nudgeMessage(language: SupportedLanguage) -> String {
        switch language {
        case .english:
            return "(The learner stayed silent. Say something encouraging and ask an easier question.)"
        case .japanese:
            return "(学習者が黙っています。やさしく励まして、もっと簡単な質問をしてください。)"
        }
    }

    static func sentenceBudget(for level: ConversationLevel) -> String {
        switch level {
        case .beginner:
            return "1-2 very short sentences"
        case .intermediate:
            return "2-3 sentences"
        case .advanced:
            return "2-4 sentences"
        }
    }

    private static func numbered(_ rules: [String]) -> String {
        rules.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }
}