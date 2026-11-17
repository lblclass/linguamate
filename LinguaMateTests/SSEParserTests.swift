import XCTest
@testable import LinguaMate

final class SSEParserTests: XCTestCase {

    func testParsesDataLinesAndIgnoresNoise() {
        var decoder = SSEDecoder()
        let payloads = decoder.push(
            """
            : ping

            event: message
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: [DONE]

            """
        )
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first, "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}")
        XCTAssertEqual(payloads.last, SSEDecoder.doneToken)
    }

    func testReassemblesLineSplitAcrossChunks() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("da").isEmpty)
        XCTAssertTrue(decoder.push("ta: {\"a\":").isEmpty)
        let payloads = decoder.push("1}\n")
        XCTAssertEqual(payloads, ["{\"a\":1}"])
    }

    func testHandlesCRLFAndBlankDataLines() {
        var decoder = SSEDecoder()
        let payloads = decoder.push("data:\n\n\ndata: x\r\n")
        XCTAssertEqual(payloads, ["x"])
    }

    func testFlushEmitsTrailingLineWithoutNewline() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("data: tail").isEmpty)
        XCTAssertEqual(decoder.flush(), ["tail"])
        XCTAssertTrue(decoder.flush().isEmpty)
    }

    func testExtractsDeltaContent() {
        let payload = "{\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}"
        XCTAssertNil(OpenAIChunk.deltaContent(fromJSON: payload))

        let withContent = "{\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}"
        XCTAssertEqual(OpenAIChunk.deltaContent(fromJSON: withContent), "你好")

        let legacy = "{\"choices\":[{\"text\":\"legacy\"}]}"
        XCTAssertEqual(OpenAIChunk.deltaContent(fromJSON: legacy), "legacy")

        XCTAssertNil(OpenAIChunk.deltaContent(fromJSON: "not json"))
    }

    func testDetectsInStreamError() {
        let payload = "{\"error\":{\"message\":\"rate limited\"}}"
        XCTAssertEqual(OpenAIChunk.streamErrorMessage(fromJSON: payload), "rate limited")
        XCTAssertNil(OpenAIChunk.streamErrorMessage(fromJSON: "{\"choices\":[]}"))
    }

    func testParsesNonStreamedCompletionBody() {
        let body = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"OK\"}}]}".data(using: .utf8)!
        XCTAssertEqual(ChatCompletionParser.text(fromJSON: body), "OK")
    }

    func testBuildsChatCompletionsEndpoint() throws {
        let url = try LLMClient.endpointURL(baseURLString: "https://api.openai.com/v1")
        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")

        let withSlash = try LLMClient.endpointURL(baseURLString: "http://localhost:11434/v1/")
        XCTAssertEqual(withSlash.absoluteString, "http://localhost:11434/v1/chat/completions")

        let alreadyComplete = try LLMClient.endpointURL(baseURLString: "https://proxy.example.com/v1/chat/completions")
        XCTAssertEqual(alreadyComplete.absoluteString, "https://proxy.example.com/v1/chat/completions")

        XCTAssertThrowsError(try LLMClient.endpointURL(baseURLString: ""))
    }

    func testRequestCarriesAuthHeaderAndStreamFlag() throws {
        let client = LLMClient(
            configuration: LLMClient.Configuration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: "sk-test",
                model: "gpt-4o-mini",
                temperature: 0.3
            )
        )
        let request = try client.makeRequest(messages: [LLMMessage(role: "user", content: "hi")], stream: true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")

        let missingKey = LLMClient(
            configuration: LLMClient.Configuration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                apiKey: "",
                model: "gpt-4o-mini",
                temperature: 0.3
            )
        )
        XCTAssertThrowsError(try missingKey.makeRequest(messages: [], stream: true))
    }
}