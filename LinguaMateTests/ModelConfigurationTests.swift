import XCTest
@testable import LinguaMate

final class ModelConfigurationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LinguaMateTests.ModelConfiguration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultModelSettings() {
        let settings = AppSettings()

        XCTAssertEqual(settings.baseURLString, "https://api.openai.com/v1")
        XCTAssertEqual(settings.model, "gpt-4o-mini")
        XCTAssertEqual(settings.temperature, 0.7)
        XCTAssertTrue(settings.useDemoEngine)
    }

    func testSettingsPersistAndReload() {
        let store = AppSettingsStore(defaults: defaults)
        store.update { settings in
            settings.baseURLString = "https://example.com/v1/"
            settings.model = "test-model"
            settings.temperature = 0.2
            settings.useDemoEngine = false
        }

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.baseURLString, "https://example.com/v1/")
        XCTAssertEqual(reloaded.settings.model, "test-model")
        XCTAssertEqual(reloaded.settings.temperature, 0.2)
        XCTAssertFalse(reloaded.settings.useDemoEngine)
    }

    func testCorruptStoredSettingsFallBackToDefaults() {
        defaults.set(Data("not-json".utf8), forKey: "LinguaMate.AppSettings.v1")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, AppSettings())
    }

    func testEngineFallsBackToDemoWithoutKeyOrWhenDemoIsEnabled() {
        var settings = AppSettings()
        settings.useDemoEngine = false

        XCTAssertTrue(TutorEngineFactory.makeEngine(settings: settings, apiKey: "").isDemo)
        XCTAssertFalse(TutorEngineFactory.makeEngine(settings: settings, apiKey: "sk-test").isDemo)

        settings.useDemoEngine = true
        XCTAssertTrue(TutorEngineFactory.makeEngine(settings: settings, apiKey: "sk-test").isDemo)
    }

    func testEndpointNormalization() throws {
        let standard = try LLMClient.endpointURL(baseURLString: "https://api.openai.com/v1")
        XCTAssertEqual(standard.absoluteString, "https://api.openai.com/v1/chat/completions")

        let whitespaceAndSlash = try LLMClient.endpointURL(baseURLString: "  http://localhost:11434/v1/ \n")
        XCTAssertEqual(whitespaceAndSlash.absoluteString, "http://localhost:11434/v1/chat/completions")

        let completePath = try LLMClient.endpointURL(
            baseURLString: "https://proxy.example.com/v1/chat/completions/"
        )
        XCTAssertEqual(completePath.absoluteString, "https://proxy.example.com/v1/chat/completions")
    }

    func testEndpointRejectsMissingSchemeHostOrUnsupportedScheme() {
        let invalidValues = [
            "",
            "   ",
            "api.openai.com/v1",
            "https://",
            "ftp://example.com/v1"
        ]

        for value in invalidValues {
            XCTAssertThrowsError(try LLMClient.endpointURL(baseURLString: value), "Expected rejection for \(value)")
        }
    }

    func testRequestCarriesConfigurationForNonStreamingCompletion() throws {
        let client = makeClient(apiKey: "sk-test")
        let request = try client.makeRequest(
            messages: [LLMMessage(role: "user", content: "ping")],
            stream: false
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(json["stream"])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["temperature"] as? Double, 0.2)

        let withoutTemperature = try client.makeRequest(
            messages: [LLMMessage(role: "user", content: "ping")],
            stream: false,
            includeTemperature: false
        )
        let bodyWithoutTemperature = try XCTUnwrap(withoutTemperature.httpBody)
        let jsonWithoutTemperature = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyWithoutTemperature) as? [String: Any]
        )
        XCTAssertNil(jsonWithoutTemperature["temperature"])
    }

    func testCompleteReturnsTextAndParsesAPIErrors() async throws {
        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 200,
                body: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
            )
        }
        let text = try await makeClient().complete(messages: [LLMMessage(role: "user", content: "ping")])
        XCTAssertEqual(text, "OK")

        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 200,
                body: Data(#"{"error":{"message":"rate limited"}}"#.utf8)
            )
        }
        do {
            _ = try await makeClient().complete(messages: [LLMMessage(role: "user", content: "ping")])
            XCTFail("Expected an API error")
        } catch ChatEngineError.api(let message) {
            XCTAssertEqual(message, "rate limited")
        }

        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 401,
                body: Data(#"{"error":{"message":"invalid key"}}"#.utf8)
            )
        }
        do {
            _ = try await makeClient().complete(messages: [LLMMessage(role: "user", content: "ping")])
            XCTFail("Expected an HTTP error")
        } catch ChatEngineError.http(let status, let body) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(body, "invalid key")
        }
    }

    func testCompleteRetriesWithoutTemperatureForFixedTemperatureModel() async throws {
        StubURLProtocol.responseProvider = { _ in
            if StubURLProtocol.capturedRequests.count == 1 {
                return .init(
                    statusCode: 400,
                    body: Data(
                        #"{"error":{"message":"Unsupported value: 'temperature' does not support 0.2 with this model. Only the default (1) value is supported."}}"#.utf8
                    )
                )
            }
            return .init(
                statusCode: 200,
                body: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
            )
        }

        let text = try await makeClient().complete(messages: [LLMMessage(role: "user", content: "ping")])

        XCTAssertEqual(text, "OK")
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 2)
        let firstBody = try XCTUnwrap(StubURLProtocol.capturedRequests[0].body)
        let secondBody = try XCTUnwrap(StubURLProtocol.capturedRequests[1].body)
        let firstJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        XCTAssertNotNil(firstJSON["temperature"])
        XCTAssertNil(secondJSON["temperature"])
    }

    @MainActor
    func testConnectionUsesDraftKeyAndStreamingPath() async throws {
        let store = AppSettingsStore(defaults: defaults)
        store.update { settings in
            settings.useDemoEngine = false
            settings.baseURLString = "https://example.com/v1"
            settings.model = "test-model"
        }
        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n".utf8)
            )
        }
        let appState = AppState(
            settingsStore: store,
            apiKey: "saved-key",
            session: makeStubSession()
        )

        let result = await appState.testConnection(apiKeyOverride: "  draft-key  ")

        guard case .success(let message) = result else {
            return XCTFail("Expected a successful connection test")
        }
        XCTAssertEqual(message, "连接成功，模型回复：OK")
        let request = try XCTUnwrap(StubURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer draft-key")
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["temperature"] as? Double, 0)
    }

    @MainActor
    func testConnectionRetriesWithoutTemperatureForFixedTemperatureModel() async throws {
        let store = AppSettingsStore(defaults: defaults)
        store.update { settings in
            settings.useDemoEngine = false
            settings.baseURLString = "https://example.com/v1"
            settings.model = "fixed-temperature-model"
            settings.temperature = 0.7
        }
        StubURLProtocol.responseProvider = { _ in
            if StubURLProtocol.capturedRequests.count == 1 {
                return .init(
                    statusCode: 400,
                    body: Data(
                        #"{"error":{"message":"Unsupported value: 'temperature' does not support 0.7 with this model. Only the default (1) value is supported."}}"#.utf8
                    )
                )
            }
            return .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n".utf8)
            )
        }
        let appState = AppState(settingsStore: store, apiKey: "sk-test", session: makeStubSession())

        let result = await appState.testConnection()

        guard case .success(let message) = result else {
            return XCTFail("Fixed-temperature model should succeed after retry")
        }
        XCTAssertEqual(message, "连接成功，模型回复：OK")
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 2)
        let firstBody = try XCTUnwrap(StubURLProtocol.capturedRequests[0].body)
        let secondBody = try XCTUnwrap(StubURLProtocol.capturedRequests[1].body)
        let firstJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let secondJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        XCTAssertEqual(firstJSON["temperature"] as? Double, 0)
        XCTAssertNil(secondJSON["temperature"])
    }

    @MainActor
    func testConnectionShortCircuitsInDemoModeOrWithoutKey() async {
        let store = AppSettingsStore(defaults: defaults)
        let demoState = AppState(settingsStore: store, apiKey: "", session: makeStubSession())

        switch await demoState.testConnection() {
        case .success(let message):
            XCTAssertTrue(message.contains("离线演示模式"))
        case .failure(let error):
            XCTFail("Demo mode should not fail: \(error)")
        }

        store.update { $0.useDemoEngine = false }
        let missingKeyState = AppState(settingsStore: store, apiKey: "", session: makeStubSession())
        switch await missingKeyState.testConnection() {
        case .success:
            XCTFail("Missing API key should fail")
        case .failure(let error):
            guard case ChatEngineError.missingAPIKey = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    @MainActor
    func testConnectionSurfacesSSEAndHTTPErrors() async {
        let store = AppSettingsStore(defaults: defaults)
        store.update {
            $0.useDemoEngine = false
            $0.baseURLString = "https://example.com/v1"
        }
        let appState = AppState(settingsStore: store, apiKey: "sk-test", session: makeStubSession())

        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data("data: {\"error\":{\"message\":\"rate limited\"}}\n\n".utf8)
            )
        }
        switch await appState.testConnection() {
        case .success:
            XCTFail("SSE error should fail")
        case .failure(let error):
            guard case ChatEngineError.api(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "rate limited")
        }

        StubURLProtocol.responseProvider = { _ in
            .init(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":{"message":"invalid key"}}"#.utf8)
            )
        }
        switch await appState.testConnection() {
        case .success:
            XCTFail("HTTP error should fail")
        case .failure(let error):
            guard case ChatEngineError.http(let status, let body) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(body, "invalid key")
        }
    }

    private func makeClient(apiKey: String = "sk-test") -> LLMClient {
        LLMClient(
            configuration: LLMClient.Configuration(
                baseURL: URL(string: "https://example.com/v1")!,
                apiKey: apiKey,
                model: "test-model",
                temperature: 0.2
            ),
            session: makeStubSession()
        )
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol {
    struct Response {
        var statusCode: Int
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data
    }

    struct CapturedRequest {
        var request: URLRequest
        var body: Data?
    }

    private static let lock = NSLock()
    private static var storedResponseProvider: ((URLRequest) -> Response)?
    private static var storedRequests: [CapturedRequest] = []

    static var responseProvider: ((URLRequest) -> Response)? {
        get { lock.withLock { storedResponseProvider } }
        set { lock.withLock { storedResponseProvider = newValue } }
    }

    static var capturedRequests: [CapturedRequest] {
        lock.withLock { storedRequests }
    }

    static func reset() {
        lock.withLock {
            storedResponseProvider = nil
            storedRequests = []
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let captured = CapturedRequest(request: request, body: Self.bodyData(from: request))
        let provider = Self.lock.withLock { () -> ((URLRequest) -> Response)? in
            Self.storedRequests.append(captured)
            return Self.storedResponseProvider
        }
        let response = provider?(request) ?? Response(statusCode: 500, body: Data())
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: response.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}
