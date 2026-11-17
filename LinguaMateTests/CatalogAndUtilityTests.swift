import XCTest
@testable import LinguaMate

final class TopicCatalogTests: XCTestCase {

    func testBothLanguagesHaveEnoughTopics() {
        for language in SupportedLanguage.allCases {
            let topics = TopicCatalog.topics(for: language)
            XCTAssertGreaterThanOrEqual(topics.count, 8, "\(language) 的场景太少")
            XCTAssertGreaterThanOrEqual(TopicCatalog.categories(for: language).count, 3)
        }
    }

    func testTopicIdentifiersAreUniqueAndNamespaced() {
        for language in SupportedLanguage.allCases {
            let topics = TopicCatalog.topics(for: language)
            let ids = Set(topics.map(\.id))
            XCTAssertEqual(ids.count, topics.count, "重复的主题 id")
            for topic in topics {
                XCTAssertTrue(topic.id.hasPrefix(language.rawValue), "\(topic.id) 前缀不对")
                XCTAssertEqual(topic.language, language)
            }
        }
    }

    func testEveryTopicIsFullySpecified() {
        for language in SupportedLanguage.allCases {
            for topic in TopicCatalog.topics(for: language) {
                XCTAssertFalse(topic.title.isEmpty, topic.id)
                XCTAssertFalse(topic.summary.isEmpty, topic.id)
                XCTAssertFalse(topic.role.isEmpty, topic.id)
                XCTAssertFalse(topic.goal.isEmpty, topic.id)
                XCTAssertFalse(topic.openingLine.isEmpty, topic.id)
                XCTAssertFalse(topic.category.isEmpty, topic.id)
                XCTAssertFalse(topic.emoji.isEmpty, topic.id)
                XCTAssertFalse(topic.keyPhrases.isEmpty, topic.id)
            }
        }
    }

    func testLookupByID() {
        XCTAssertEqual(TopicCatalog.topic(id: "en-coffee", language: .english)?.title, "咖啡店点单")
        XCTAssertEqual(TopicCatalog.topic(id: "ja-konbini", language: .japanese)?.title, "便利店购物")
        XCTAssertNil(TopicCatalog.topic(id: "en-coffee", language: .japanese))
    }
}

final class SpeechTextSanitizerTests: XCTestCase {

    func testStripsMarkdownAndEmoji() {
        let sanitized = SpeechTextSanitizer.sanitize("**Hello** 🎧 there `code`")
        XCTAssertFalse(sanitized.contains("*"))
        XCTAssertFalse(sanitized.contains("`"))
        XCTAssertFalse(sanitized.contains("🎧"))
        XCTAssertTrue(sanitized.contains("Hello"))
    }

    func testSplitsSentencesForBothLanguages() {
        XCTAssertEqual(SpeechTextSanitizer.sentences(in: "Hi there. How are you?").count, 2)
        XCTAssertEqual(SpeechTextSanitizer.sentences(in: "こんにちは。元気ですか？").count, 2)
        XCTAssertEqual(SpeechTextSanitizer.sentences(in: "No terminator here").count, 1)
    }

    func testEmptyInputFallsBackToOriginal() {
        XCTAssertEqual(SpeechTextSanitizer.sentences(in: ""), [""])
    }
}

final class DemoReplyComposerTests: XCTestCase {

    func testDetectsKnownEnglishMistakes() {
        let corrections = DemoReplyComposer.detectCorrections(in: "I go to school yesterday", language: .english)
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections[0].corrected, "I went to school yesterday")
    }

    func testShortPhraseRulesDoNotFireOnCleanText() {
        XCTAssertTrue(DemoReplyComposer.detectCorrections(in: "I went to school yesterday", language: .english).isEmpty)
        XCTAssertTrue(DemoReplyComposer.detectCorrections(in: "今日はいい天気ですね。", language: .japanese).isEmpty)
    }

    func testCapsCorrectionsAtThree() {
        let messy = "I go to school yesterday. He go there. I am agree. I have 20 years old. very like it"
        XCTAssertLessThanOrEqual(DemoReplyComposer.detectCorrections(in: messy, language: .english).count, 3)
    }

    func testReplyIsDeterministicAndTopicAware() {
        let topic = TopicCatalog.topic(id: "en-coffee", language: .english)!
        let first = DemoReplyComposer.reply(to: "A latte please", topic: topic, language: .english, level: .intermediate, turnIndex: 1)
        let second = DemoReplyComposer.reply(to: "A latte please", topic: topic, language: .english, level: .intermediate, turnIndex: 1)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.reply.contains("size"))
        XCTAssertFalse(first.followUps.isEmpty)
    }

    func testJapaneseReplyUsesJapanese() {
        let topic = TopicCatalog.topic(id: "ja-konbini", language: .japanese)!
        let reply = DemoReplyComposer.reply(to: "これをください", topic: topic, language: .japanese, level: .beginner, turnIndex: 1)
        XCTAssertTrue(reply.reply.contains("温めますか") || reply.reply.contains("サイズ"))
        XCTAssertNotNil(reply.translation)
    }

    func testCorrectionsAndTranslationCanBeSwitchedOff() {
        let topic = TopicCatalog.topic(id: "en-coffee", language: .english)!
        let reply = DemoReplyComposer.reply(
            to: "I go to school yesterday",
            topic: topic,
            language: .english,
            level: .intermediate,
            enableCorrections: false,
            showTranslation: false,
            turnIndex: 0
        )
        XCTAssertTrue(reply.corrections.isEmpty)
        XCTAssertNil(reply.translation)
    }

    func testStreamingChunksRebuildTheText() {
        let text = "Nice! What size would you like?"
        XCTAssertEqual(DemoTutorEngine.chunks(of: text).joined(), text)
        XCTAssertTrue(DemoTutorEngine.chunks(of: "").isEmpty)
    }
}

@MainActor
final class ConversationViewModelHelperTests: XCTestCase {

    func testRemainderReturnsWholeTextWhenNothingSpoken() {
        XCTAssertEqual(ConversationViewModel.remainder(of: "Hello there.", alreadySpoken: ""), "Hello there.")
    }

    func testRemainderSkipsTheAlreadySpokenPrefix() {
        let remainder = ConversationViewModel.remainder(of: "Hello there. How are you?", alreadySpoken: "Hello there.")
        XCTAssertEqual(remainder, "How are you?")
    }

    func testRemainderHandlesJapaneseText() {
        let remainder = ConversationViewModel.remainder(of: "こんにちは。元気ですか。", alreadySpoken: "こんにちは。")
        XCTAssertEqual(remainder, "元気ですか。")
    }

    func testRemainderIsEmptyWhenEverythingWasSpoken() {
        XCTAssertEqual(ConversationViewModel.remainder(of: "All done.", alreadySpoken: "All done.  "), "")
    }

    func testSpeechRateIsClamped() {
        XCTAssertEqual(SpeechSynthesizer.clampedRate(0.5), 0.5)
        XCTAssertEqual(SpeechSynthesizer.clampedRate(5), 0.65)
        XCTAssertEqual(SpeechSynthesizer.clampedRate(0.01), 0.25)
    }
}

final class SessionExporterTests: XCTestCase {

    func testPlainTextContainsTurnsAndCorrections() {
        var session = ConversationSession(
            topicID: "en-coffee",
            topicTitle: "咖啡店点单",
            topicEmoji: "☕️",
            language: .english,
            level: .intermediate
        )
        session.messages = [
            ChatMessage(role: .tutor, text: "What can I get you?", translation: "您想喝点什么？"),
            ChatMessage(
                role: .learner,
                text: "I want a latte",
                corrections: [Correction(original: "I want a latte", corrected: "I'd like a latte", note: "更礼貌")]
            )
        ]
        let text = SessionExporter.plainText(for: session)
        XCTAssertTrue(text.contains("咖啡店点单"))
        XCTAssertTrue(text.contains("AI: What can I get you?"))
        XCTAssertTrue(text.contains("我: I want a latte"))
        XCTAssertTrue(text.contains("译文: 您想喝点什么？"))
        XCTAssertTrue(text.contains("-> I'd like a latte"))
    }
}

final class UtteranceSilenceDetectorTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000)

    func testShortPauseDoesNotEndUtterance() {
        var detector = UtteranceSilenceDetector()
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start))
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(2.9)))
    }

    func testThreeSecondPauseEndsUtterance() {
        var detector = UtteranceSilenceDetector()
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start))
        XCTAssertTrue(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(3)))
    }

    func testSpeechResetsThePauseTimer() {
        var detector = UtteranceSilenceDetector()
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start))
        XCTAssertFalse(detector.shouldFinish(rms: 0.05, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(2)))
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(2.5)))
        XCTAssertTrue(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(5.5)))
    }

    func testNoTranscriptKeepsListening() {
        var detector = UtteranceSilenceDetector()
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: false, now: start))
        XCTAssertFalse(detector.shouldFinish(rms: 0.001, threshold: 0.008, duration: 3, hasTranscript: false, now: start.addingTimeInterval(10)))
    }

    func testSoftSpeechStaysAboveTheLoweredThreshold() {
        var detector = UtteranceSilenceDetector()
        XCTAssertFalse(detector.shouldFinish(rms: 0.01, threshold: 0.008, duration: 3, hasTranscript: true, now: start))
        XCTAssertFalse(detector.shouldFinish(rms: 0.01, threshold: 0.008, duration: 3, hasTranscript: true, now: start.addingTimeInterval(10)))
    }
}

final class SpeechTranscriptJoinTests: XCTestCase {

    func testEnglishChunksAreJoinedWithASpace() {
        XCTAssertEqual(
            SpeechRecognizer.joinedTranscript("I would like", "a coffee", language: .english),
            "I would like a coffee"
        )
    }

    func testJapaneseChunksAreJoinedWithoutASpace() {
        XCTAssertEqual(
            SpeechRecognizer.joinedTranscript("コーヒーを", "ください", language: .japanese),
            "コーヒーをください"
        )
    }

    func testEmptyChunksAreIgnored() {
        XCTAssertEqual(SpeechRecognizer.joinedTranscript("", "hello", language: .english), "hello")
        XCTAssertEqual(SpeechRecognizer.joinedTranscript("hello", "  ", language: .english), "hello")
    }
}
