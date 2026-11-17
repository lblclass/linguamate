import Foundation

/// Offline tutor used when no API key is configured (or "演示模式" is on).
///
/// It keeps the whole product testable — speech in, speech out, corrections,
/// history — and it is the fallback when the network is unavailable. The text
/// it produces is computed by `DemoReplyComposer`, a pure function.
struct DemoTutorEngine: TutorEngine {
    /// Delay between simulated stream chunks, so the UI shows real streaming.
    var chunkDelay: Duration = .milliseconds(180)
    var simulateStreaming = true

    var displayName: String { "离线演示模式" }
    var isDemo: Bool { true }

    func respond(
        session: ConversationSession,
        topic: ConversationTopic,
        settings: AppSettings
    ) -> AsyncThrowingStream<TutorStreamEvent, Error> {
        let learnerText = session.messages.last(where: { $0.role == .learner })?.text ?? ""
        let turnIndex = session.turnCount
        let reply = DemoReplyComposer.reply(
            to: learnerText,
            topic: topic,
            language: session.language,
            level: session.level,
            enableCorrections: settings.enableCorrections,
            showTranslation: settings.showTranslation,
            turnIndex: turnIndex
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if simulateStreaming {
                        for chunk in Self.chunks(of: reply.reply) {
                            try Task.checkCancellation()
                            try await Task.sleep(for: chunkDelay)
                            continuation.yield(.replyDelta(chunk))
                        }
                    } else {
                        continuation.yield(.replyDelta(reply.reply))
                    }
                    continuation.yield(.completed(reply))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ChatEngineError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Splits a sentence into word-sized chunks to imitate token streaming.
    static func chunks(of text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "。" || character == "," || character == "." || character == "、" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// Pure, deterministic demo answers: what a tiny rule-based language partner
/// would say. Deterministic behaviour keeps the unit tests honest.
enum DemoReplyComposer {
    struct Rule {
        var pattern: String
        var corrected: String
        var note: String
    }

    static let englishRules: [Rule] = [
        Rule(pattern: "i go to school yesterday", corrected: "I went to school yesterday", note: "过去的事要用过去式 went。"),
        Rule(pattern: "he go ", corrected: "he goes ", note: "第三人称单数动词要加 -s。"),
        Rule(pattern: "i am agree", corrected: "I agree", note: "agree 是动词，不需要 be 动词。"),
        Rule(pattern: "i have 20 years old", corrected: "I am 20 years old", note: "说年龄用 be 动词，不是 have。"),
        Rule(pattern: "very like", corrected: "really like", note: "修饰动词用 really 更自然。"),
        Rule(pattern: "i want go", corrected: "I want to go", note: "want 后面接 to do。"),
        Rule(pattern: "in the last week", corrected: "last week", note: "last week 前面不加介词。"),
        Rule(pattern: "i am interesting in", corrected: "I am interested in", note: "-ing 修饰事物，-ed 修饰人的感受。")
    ]

    static let japaneseRules: [Rule] = [
        Rule(pattern: "私は学生を", corrected: "私は学生です", note: "判断句要用「です」，不用「を」。"),
        Rule(pattern: "行くです", corrected: "行きます", note: "动词礼貌形应是「行きます」。"),
        Rule(pattern: "ますです", corrected: "ます", note: "「ます」本身就是礼貌形，不需要再加「です」。"),
        Rule(pattern: "とても好きを", corrected: "とても好きです", note: "「好き」是形容动词，用「です」。"),
        Rule(pattern: "飲みたいを", corrected: "飲みたいです", note: "句尾要用「です」收尾。"),
        Rule(pattern: "ありがとうございますです", corrected: "ありがとうございます", note: "「ございます」已是完整敬语。")
    ]

    static func detectCorrections(in text: String, language: SupportedLanguage) -> [Correction] {
        let rules = language == .english ? englishRules : japaneseRules
        let haystack = text.lowercased()
        var results: [Correction] = []
        for rule in rules where haystack.contains(rule.pattern) {
            results.append(
                Correction(original: rule.pattern, corrected: rule.corrected, note: rule.note)
            )
        }
        return Array(results.prefix(3))
    }

    static func reply(
        to learnerText: String,
        topic: ConversationTopic,
        language: SupportedLanguage,
        level: ConversationLevel,
        enableCorrections: Bool = true,
        showTranslation: Bool = true,
        turnIndex: Int = 0
    ) -> TutorReply {
        let trimmed = learnerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrections = enableCorrections ? detectCorrections(in: trimmed, language: language) : []

        let acknowledgement: String
        if trimmed.isEmpty {
            acknowledgement = language == .english
                ? "No worries, take your time."
                : "大丈夫ですよ、ゆっくりでいいです。"
        } else {
            acknowledgement = acknowledgements(for: language)[turnIndex % acknowledgements(for: language).count]
        }

        let line = followUpLine(for: topic, language: language, turnIndex: turnIndex)
        let replyText = "\(acknowledgement) \(line)"

        let translation = showTranslation ? "\(translatedAcknowledgement(acknowledgement, language: language))\(translatedFollowUp(for: topic, language: language, turnIndex: turnIndex))" : nil

        let followUps = followUpHints(for: topic, language: language)

        return TutorReply(
            reply: replyText,
            translation: translation,
            corrections: corrections,
            followUps: followUps
        )
    }

    // MARK: - Phrase banks

    static func acknowledgements(for language: SupportedLanguage) -> [String] {
        switch language {
        case .english:
            return ["Nice!", "Got it, thank you.", "That sounds great.", "Ah, I see."]
        case .japanese:
            return ["なるほど。", "いいですね。", "そうなんですね。", "ありがとうございます。"]
        }
    }

    static func followUpLine(for topic: ConversationTopic, language: SupportedLanguage, turnIndex: Int) -> String {
        let bank = followUps(for: topic, language: language)
        guard !bank.isEmpty else { return language == .english ? "Tell me more." : "もっと教えてください。" }
        return bank[turnIndex % bank.count]
    }

    static func followUps(for topic: ConversationTopic, language: SupportedLanguage) -> [String] {
        switch topic.id {
        case "en-coffee", "ja-ramen", "ja-konbini", "en-restaurant":
            return language == .english
                ? ["Would you like anything else?", "What size would you like?", "Is that for here or to go?"]
                : ["ほかにはいかがですか。", "サイズはどうしますか。", "ご一緒に何かお持ちしますか。"]
        case "en-interview", "ja-baito", "ja-jikoshoukai":
            return language == .english
                ? ["Can you give me an example from your last job?", "What are you looking for in this role?", "How soon could you start?"]
                : ["前の経験から具体例を挙げてもらえますか。", "この仕事で何を学びたいですか。", "いつから働けますか。"]
        case "ja-byouin", "en-doctor":
            return language == .english
                ? ["How long has this been going on?", "Any fever or other symptoms?", "Are you taking any medication?"]
                : ["いつからですか。", "熱はありますか。", "ほかに気になることはありますか。"]
        default:
            return language == .english
                ? ["What do you think?", "How about you?", "Could you tell me more about that?"]
                : ["あなたはどう思いますか。", "そちらはどうですか。", "もう少し詳しく教えてもらえますか。"]
        }
    }

    static func followUpHints(for topic: ConversationTopic, language: SupportedLanguage) -> [String] {
        if !topic.keyPhrases.isEmpty {
            return Array(topic.keyPhrases.prefix(2)).map { "试试这样说：\($0)" }
        }
        return language == .english ? ["用一句话回答即可", "试着反问他一个问题"] : ["短く答えてみましょう", "相手にも質問してみましょう"]
    }

    static func translatedAcknowledgement(_ acknowledgement: String, language: SupportedLanguage) -> String {
        guard language == .japanese else { return "" }
        return ""
    }

    static func translatedFollowUp(for topic: ConversationTopic, language: SupportedLanguage, turnIndex: Int) -> String {
        let chinese = chineseFollowUps(for: topic)
        guard !chinese.isEmpty else { return "（演示模式：这里显示模型给出的中文翻译）" }
        return chinese[turnIndex % chinese.count]
    }

    static func chineseFollowUps(for topic: ConversationTopic) -> [String] {
        switch topic.id {
        case "en-coffee", "ja-ramen", "ja-konbini", "en-restaurant":
            return ["还需要别的吗？", "您要什么尺寸？", "在这里吃还是带走？"]
        case "en-interview", "ja-baito", "ja-jikoshoukai":
            return ["能举一个上份工作的例子吗？", "你希望在这份工作里得到什么？", "你什么时候能开始？"]
        default:
            return ["你觉得怎么样？", "你呢？", "能再多说一点吗？"]
        }
    }
}