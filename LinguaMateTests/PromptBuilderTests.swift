import XCTest
@testable import LinguaMate

final class PromptBuilderTests: XCTestCase {

    private func makeSession(
        language: SupportedLanguage = .english,
        level: ConversationLevel = .intermediate,
        messages: [ChatMessage] = []
    ) -> ConversationSession {
        ConversationSession(
            topicID: TopicCatalog.topics(for: language)[0].id,
            topicTitle: "t",
            language: language,
            level: level,
            messages: messages
        )
    }

    func testSystemPromptDescribesScenarioAndProtocol() {
        let topic = TopicCatalog.topics(for: .english)[0]
        let prompt = PromptBuilder.systemPrompt(
            topic: topic,
            language: .english,
            level: .beginner,
            settings: AppSettings()
        )

        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains(topic.role))
        XCTAssertTrue(prompt.contains(topic.title))
        XCTAssertTrue(prompt.contains(ConversationLevel.beginner.promptGuidance))
        XCTAssertTrue(prompt.contains(topic.keyPhrases[0]))
        XCTAssertTrue(prompt.contains(PromptBuilder.replyOpen))
        XCTAssertTrue(prompt.contains(PromptBuilder.followUpClose))
        XCTAssertTrue(prompt.contains("1-2 very short sentences"))
        XCTAssertTrue(prompt.contains("1."))
    }

    func testJapanesePromptUsesTargetLanguageName() {
        let topic = TopicCatalog.topics(for: .japanese)[0]
        let prompt = PromptBuilder.systemPrompt(
            topic: topic,
            language: .japanese,
            level: .advanced,
            settings: AppSettings()
        )
        XCTAssertTrue(prompt.contains("Japanese"))
        XCTAssertTrue(prompt.contains("Speak Japanese at all times"))
        XCTAssertFalse(prompt.contains("Speak English at all times"))
    }

    func testCorrectionsCanBeDisabled() {
        let topic = TopicCatalog.topics(for: .english)[0]
        var settings = AppSettings()
        settings.enableCorrections = false
        let prompt = PromptBuilder.systemPrompt(topic: topic, language: .english, level: .intermediate, settings: settings)
        XCTAssertTrue(prompt.contains("Do not correct the learner at all"))
        XCTAssertFalse(prompt.contains("Correct the learner gently"))

        settings.enableCorrections = true
        let withCorrections = PromptBuilder.systemPrompt(topic: topic, language: .english, level: .intermediate, settings: settings)
        XCTAssertTrue(withCorrections.contains("Correct the learner gently"))
    }

    func testTranslationCanBeDisabled() {
        let topic = TopicCatalog.topics(for: .japanese)[0]
        var settings = AppSettings()
        settings.showTranslation = false
        let prompt = PromptBuilder.systemPrompt(topic: topic, language: .japanese, level: .intermediate, settings: settings)
        XCTAssertTrue(prompt.contains("Skip the translation section"))
    }

    func testHistoryIsTrimmedAndRolesAreMapped() {
        var messages: [ChatMessage] = []
        for index in 0..<40 {
            messages.append(ChatMessage(role: index % 2 == 0 ? .learner : .tutor, text: "m\(index)"))
        }
        var settings = AppSettings()
        settings.maxHistoryTurns = 3
        let session = makeSession(messages: messages)

        let history = PromptBuilder.historyMessages(session: session, settings: settings)
        XCTAssertEqual(history.count, 6)
        XCTAssertEqual(history.first?.content, "m34")
        XCTAssertEqual(history.first?.role, "user")
        XCTAssertEqual(history.last?.content, "m39")
        XCTAssertEqual(history.last?.role, "assistant")
    }

    func testHistorySkipsEmptyMessages() {
        let session = makeSession(messages: [
            ChatMessage(role: .learner, text: "hello"),
            ChatMessage(role: .tutor, text: "   "),
            ChatMessage(role: .tutor, text: "hi")
        ])
        let history = PromptBuilder.historyMessages(session: session, settings: AppSettings())
        XCTAssertEqual(history.count, 2)
    }

    func testChatMessagesStartWithSystemPrompt() {
        let topic = TopicCatalog.englishTopics[0]
        let session = makeSession(messages: [ChatMessage(role: .learner, text: "hi")])
        let messages = PromptBuilder.chatMessages(session: session, topic: topic, settings: AppSettings())
        XCTAssertEqual(messages.first?.role, "system")
        XCTAssertEqual(messages.last?.content, "hi")
        XCTAssertEqual(messages.count, 2)
    }

    func testNudgeMessageExistsForBothLanguages() {
        XCTAssertFalse(PromptBuilder.nudgeMessage(language: .english).isEmpty)
        XCTAssertFalse(PromptBuilder.nudgeMessage(language: .japanese).isEmpty)
    }
}
