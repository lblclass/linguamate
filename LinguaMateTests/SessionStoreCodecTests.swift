import XCTest
@testable import LinguaMate

@MainActor
final class SessionStoreCodecTests: XCTestCase {

    private func makeSession() -> ConversationSession {
        var session = ConversationSession(
            topicID: "ja-ramen",
            topicTitle: "拉面店点单",
            topicEmoji: "🍜",
            language: .japanese,
            level: .beginner
        )
        session.messages = [
            ChatMessage(role: .tutor, text: "ご注文は?", translation: "您要点什么？"),
            ChatMessage(
                role: .learner,
                text: "ラーメンをください",
                corrections: [Correction(original: "を", corrected: "を", note: "正确")]
            ),
            ChatMessage(role: .tutor, text: "かしこまりました。", followUps: ["麺はかためでお願いします"])
        ]
        return session
    }

    func testRoundTripKeepsEveryField() throws {
        let original = makeSession()
        let data = try SessionStore.encode([original])
        let decoded = try SessionStore.decode(data)

        XCTAssertEqual(decoded.count, 1)
        let session = try XCTUnwrap(decoded.first)
        XCTAssertEqual(session.id, original.id)
        XCTAssertEqual(session.topicTitle, "拉面店点单")
        XCTAssertEqual(session.language, .japanese)
        XCTAssertEqual(session.level, .beginner)
        XCTAssertEqual(session.messages.count, 3)
        XCTAssertEqual(session.messages[0].translation, "您要点什么？")
        XCTAssertEqual(session.messages[1].corrections.first?.note, "正确")
        XCTAssertEqual(session.messages[2].followUps, ["麺はかためでお願いします"])
        XCTAssertEqual(session.startedAt.timeIntervalSince1970, original.startedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.turnCount, 1)
    }

    func testDecodingGarbageThrows() {
        let garbage = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try SessionStore.decode(garbage))
    }

    func testEmptyHistoryEncodesAsEmptyArray() throws {
        let data = try SessionStore.encode([])
        XCTAssertEqual(String(data: data, encoding: .utf8)?.contains("["), true)
        XCTAssertEqual(try SessionStore.decode(data).count, 0)
    }

    func testStorePersistsToDiskAndReloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linguamate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sessions.json")
        let store = SessionStore(fileURL: url)
        store.upsert(makeSession())

        let reloaded = SessionStore(fileURL: url)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.totalTurns, 1)
    }
}

/// Guards the prompt contract against a real recorded model answer: if the
/// model drifts away from the tagged format, this test fails first.
final class RecordedModelAnswerTests: XCTestCase {

    func testRecordedEnglishAnswerParses() {
        let reply = TutorReplyParser.parse(RunFixtures.recordedEnglishAnswer)
        XCTAssertFalse(reply.reply.isEmpty)
        XCTAssertNotNil(reply.translation)
        XCTAssertFalse(reply.reply.contains(PromptBuilder.replyOpen))
        XCTAssertFalse(reply.reply.contains(PromptBuilder.correctionsOpen))
    }

    func testRecordedJapaneseAnswerParses() {
        let reply = TutorReplyParser.parse(RunFixtures.recordedJapaneseAnswer)
        XCTAssertFalse(reply.reply.isEmpty)
        XCTAssertFalse(reply.reply.contains(PromptBuilder.replyOpen))
        XCTAssertTrue(reply.reply.contains("。") || reply.reply.contains("か") || reply.reply.contains("ね"))
    }

    func testRecordedAnswersStreamIntoTheSameReply() {
        for recorded in [RunFixtures.recordedEnglishAnswer, RunFixtures.recordedJapaneseAnswer] {
            var extractor = StreamingTutorReplyExtractor()
            var streamed = ""
            for chunk in stride(from: 0, to: recorded.count, by: 9).map({ offset -> String in
                let start = recorded.index(recorded.startIndex, offsetBy: offset)
                let end = recorded.index(start, offsetBy: min(9, recorded.count - offset))
                return String(recorded[start..<end])
            }) {
                streamed += extractor.push(chunk)
            }
            streamed += extractor.finish()
            XCTAssertEqual(
                streamed.trimmingCharacters(in: .whitespacesAndNewlines),
                TutorReplyParser.parse(recorded).reply,
                "流式结果与整体解析不一致"
            )
        }
    }
}