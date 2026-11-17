import XCTest
@testable import LinguaMate

final class TutorReplyParserTests: XCTestCase {

    private let fullReply = """
    [REPLY]
    Sure! Would you like it for here or to go?
    [/REPLY]
    [TRANSLATION]
    好的！您要在这里喝还是带走？
    [/TRANSLATION]
    [CORRECTIONS]
    - I want a coffee large => I'd like a large coffee :: 形容词顺序和点单语气
    - i go yesterday => I went yesterday :: 时态
    [/CORRECTIONS]
    [FOLLOWUP]
    - 试试这样说：Could I get a large latte?
    - 也可以说：for here, please.
    [/FOLLOWUP]
    """

    func testParsesAllSections() {
        let reply = TutorReplyParser.parse(fullReply)
        XCTAssertEqual(reply.reply, "Sure! Would you like it for here or to go?")
        XCTAssertEqual(reply.translation, "好的！您要在这里喝还是带走？")
        XCTAssertEqual(reply.corrections.count, 2)
        XCTAssertEqual(reply.corrections[0].original, "I want a coffee large")
        XCTAssertEqual(reply.corrections[0].corrected, "I'd like a large coffee")
        XCTAssertEqual(reply.corrections[0].note, "形容词顺序和点单语气")
        XCTAssertEqual(reply.followUps.count, 2)
        XCTAssertEqual(reply.followUps[0], "试试这样说：Could I get a large latte?")
    }

    func testHandlesNoneTokens() {
        let raw = """
        [REPLY]
        Great job!
        [/REPLY]
        [TRANSLATION]
        做得好！
        [/TRANSLATION]
        [CORRECTIONS]
        NONE
        [/CORRECTIONS]
        [FOLLOWUP]
        NONE
        [/FOLLOWUP]
        """
        let reply = TutorReplyParser.parse(raw)
        XCTAssertEqual(reply.reply, "Great job!")
        XCTAssertTrue(reply.corrections.isEmpty)
        XCTAssertTrue(reply.followUps.isEmpty)
    }

    func testMissingTranslationTagYieldsNilTranslation() {
        let raw = "[REPLY]\nHello there.\n[/REPLY]\n[CORRECTIONS]\nNONE\n[/CORRECTIONS]"
        let reply = TutorReplyParser.parse(raw)
        XCTAssertEqual(reply.reply, "Hello there.")
        XCTAssertNil(reply.translation)
    }

    func testUnclosedTagsKeepEverythingReadable() {
        let raw = "[REPLY]\nこれはテストです。\n[TRANSLATION]\n这是测试。"
        let reply = TutorReplyParser.parse(raw)
        XCTAssertEqual(reply.reply, "これはテストです。")
        XCTAssertEqual(reply.translation, "这是测试。")
    }

    func testPlainAnswerWithoutTagsIsAuthoredAsReply() {
        let reply = TutorReplyParser.parse("こんにちは、元気ですか。")
        XCTAssertEqual(reply.reply, "こんにちは、元気ですか。")
        XCTAssertTrue(reply.corrections.isEmpty)
    }

    func testLowercaseTagsAreAccepted() {
        let raw = "[reply]\nHi!\n[/reply]\n[translation]\n你好！\n[/translation]"
        let reply = TutorReplyParser.parse(raw)
        XCTAssertEqual(reply.reply, "Hi!")
        XCTAssertEqual(reply.translation, "你好！")
    }

    func testCorrectionVariants() {
        XCTAssertEqual(
            TutorReplyParser.parseCorrectionLine("- I has => I have :: 主谓一致")?.original,
            "I has"
        )
        XCTAssertEqual(
            TutorReplyParser.parseCorrectionLine("- 私は学生を → 私は学生です :: 助词")?.corrected,
            "私は学生です"
        )
        XCTAssertEqual(
            TutorReplyParser.parseCorrectionLine("- \"I am agree\" -> \"I agree\" :: 动词")?.corrected,
            "I agree"
        )
        XCTAssertNil(TutorReplyParser.parseCorrectionLine("- NONE"))
        XCTAssertNil(TutorReplyParser.parseCorrectionLine("   "))
    }

    func testJSONAnswerFallback() {
        let raw = """
        {"reply":"How was your weekend?","translation":"你周末过得怎么样？","corrections":[{"original":"very like","corrected":"really like","note":"副词"}],"follow_ups":["试试这样说：It was fun."]}
        """
        let reply = TutorReplyParser.parse(raw)
        XCTAssertEqual(reply.reply, "How was your weekend?")
        XCTAssertEqual(reply.translation, "你周末过得怎么样？")
        XCTAssertEqual(reply.corrections.first?.corrected, "really like")
        XCTAssertEqual(reply.followUps.first, "试试这样说：It was fun.")
    }

    func testStripsStrayQuotesAndTagsFromReply() {
        let quoted = TutorReplyParser.parse("[REPLY]\n\"Hi there\"\n[/REPLY]")
        XCTAssertEqual(quoted.reply, "Hi there")

        let noisy = TutorReplyParser.parse("### Hi there ###\n[REPLY]\nHi there\n[/REPLY]")
        XCTAssertEqual(noisy.reply, "Hi there")
    }
}

final class StreamingTutorReplyExtractorTests: XCTestCase {

    func testEmitsReplyAsItStreams() {
        var extractor = StreamingTutorReplyExtractor()
        var spoken = ""
        let stream = "[REPLY]\nHello! How are you today?\n[/REPLY]\n[TRANSLATION]\n你好！\n[/TRANSLATION]"
        for character in stream {
            spoken += extractor.push(String(character))
        }
        spoken += extractor.finish()
        XCTAssertEqual(spoken.trimmingCharacters(in: .whitespacesAndNewlines), "Hello! How are you today?")
        XCTAssertFalse(spoken.contains("["))
    }

    func testEmitsNothingBeforeTheReplyTagArrives() {
        var extractor = StreamingTutorReplyExtractor()
        XCTAssertEqual(extractor.push("[REP"), "")
        XCTAssertEqual(extractor.push("LY]\nHi"), "Hi")
    }

    func testPlainTextStreamFallsBackToWholeAnswer() {
        var extractor = StreamingTutorReplyExtractor()
        var spoken = ""
        for chunk in ["こんにちは", "、元気", "ですか。"] {
            spoken += extractor.push(chunk)
        }
        spoken += extractor.finish()
        XCTAssertEqual(spoken, "こんにちは、元気ですか。")
    }

    func testParsedReplyMatchesFullParseAfterStreaming() {
        var extractor = StreamingTutorReplyExtractor()
        let stream = "[REPLY]\nHi\n[/REPLY]\n[TRANSLATION]\n你好\n[/TRANSLATION]\n[CORRECTIONS]\n- a => b :: c\n[/CORRECTIONS]\n[FOLLOWUP]\n- hint\n[/FOLLOWUP]"
        for chunk in stride(from: 0, to: stream.count, by: 7).map({ offset -> String in
            let start = stream.index(stream.startIndex, offsetBy: offset)
            let end = stream.index(start, offsetBy: min(7, stream.count - offset))
            return String(stream[start..<end])
        }) {
            _ = extractor.push(chunk)
        }
        _ = extractor.finish()
        let streamed = extractor.parsedReply()
        let reference = TutorReplyParser.parse(stream)
        XCTAssertEqual(streamed.reply, reference.reply)
        XCTAssertEqual(streamed.translation, reference.translation)
        XCTAssertEqual(streamed.corrections.count, reference.corrections.count)
        for (lhs, rhs) in zip(streamed.corrections, reference.corrections) {
            XCTAssertEqual(lhs.original, rhs.original)
            XCTAssertEqual(lhs.corrected, rhs.corrected)
            XCTAssertEqual(lhs.note, rhs.note)
        }
        XCTAssertEqual(streamed.followUps, reference.followUps)
    }
}
