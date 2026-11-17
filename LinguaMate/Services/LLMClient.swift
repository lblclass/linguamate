import Foundation

/// Minimal OpenAI-compatible client: `/chat/completions` with streamed SSE.
/// Works with OpenAI, Azure OpenAI gateways, DeepSeek, Moonshot, Ollama,
/// LM Studio and anything else that speaks the same wire format.
struct LLMClient {
    struct Configuration: Sendable {
        var baseURL: URL
        var apiKey: String
        var model: String
        var temperature: Double
    }

    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration, session: URLSession = LLMClient.makeDefaultSession()) {
        self.configuration = configuration
        self.session = session
    }

    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    static func validatedBaseURL(_ baseURLString: String) throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw ChatEngineError.invalidBaseURL(baseURLString)
        }
        return url
    }

    static func endpointURL(baseURLString: String) throws -> URL {
        let baseURL = try validatedBaseURL(baseURLString)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ChatEngineError.invalidBaseURL(baseURLString)
        }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }
        components.path = path
        guard let url = components.url else {
            throw ChatEngineError.invalidBaseURL(baseURLString)
        }
        return url
    }

    func makeRequest(
        messages: [LLMMessage],
        stream: Bool,
        includeTemperature: Bool = true
    ) throws -> URLRequest {
        guard !configuration.apiKey.isEmpty else { throw ChatEngineError.missingAPIKey }
        var request = URLRequest(url: try Self.endpointURL(baseURLString: configuration.baseURL.absoluteString))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if includeTemperature {
            payload["temperature"] = configuration.temperature
        }
        if stream {
            payload["stream"] = true
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    /// Streams raw content deltas of the assistant message.
    func streamChat(messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var includeTemperature = true
                    while true {
                        let request = try makeRequest(
                            messages: messages,
                            stream: true,
                            includeTemperature: includeTemperature
                        )
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            throw ChatEngineError.emptyResponse
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            let body = try await Self.readErrorBody(from: bytes)
                            if includeTemperature,
                               Self.shouldRetryWithoutTemperature(status: http.statusCode, body: body) {
                                includeTemperature = false
                                continue
                            }
                            let message = ChatCompletionParser.errorMessage(fromJSON: Data(body.utf8)) ?? body
                            throw ChatEngineError.http(status: http.statusCode, body: message)
                        }

                        var decoder = SSEDecoder()
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            for payload in decoder.push(line + "\n") {
                                if try handle(payload: payload, continuation: continuation) { return }
                            }
                        }
                        for payload in decoder.flush() {
                            if try handle(payload: payload, continuation: continuation) { return }
                        }
                        continuation.finish()
                        return
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: ChatEngineError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns true when the stream is complete.
    private func handle(
        payload: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws -> Bool {
        if payload == SSEDecoder.doneToken {
            continuation.finish()
            return true
        }
        if let message = OpenAIChunk.streamErrorMessage(fromJSON: payload) {
            throw ChatEngineError.api(message)
        }
        if let delta = OpenAIChunk.deltaContent(fromJSON: payload) {
            continuation.yield(delta)
        }
        return false
    }

    /// Single non-streamed completion, used by the "test connection" button.
    func complete(messages: [LLMMessage]) async throws -> String {
        var includeTemperature = true
        while true {
            let request = try makeRequest(
                messages: messages,
                stream: false,
                includeTemperature: includeTemperature
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatEngineError.emptyResponse }
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            guard (200..<300).contains(http.statusCode) else {
                if includeTemperature,
                   Self.shouldRetryWithoutTemperature(status: http.statusCode, body: rawBody) {
                    includeTemperature = false
                    continue
                }
                let body = ChatCompletionParser.errorMessage(fromJSON: data) ?? rawBody
                throw ChatEngineError.http(status: http.statusCode, body: body)
            }
            if let message = ChatCompletionParser.errorMessage(fromJSON: data) {
                if includeTemperature,
                   Self.shouldRetryWithoutTemperature(status: http.statusCode, body: message) {
                    includeTemperature = false
                    continue
                }
                throw ChatEngineError.api(message)
            }
            guard let text = ChatCompletionParser.text(fromJSON: data) else {
                throw ChatEngineError.emptyResponse
            }
            return text
        }
    }

    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            if !body.isEmpty { body += "\n" }
            body += line
            if body.count > 4000 { break }
        }
        return body
    }

    private static func shouldRetryWithoutTemperature(status: Int, body: String) -> Bool {
        guard (400..<500).contains(status) else { return false }
        let message = body.lowercased()
        guard message.contains("temperature"),
              message.contains("does not support")
                || message.contains("unsupported value")
                || message.contains("only the default") else {
            return false
        }
        return true
    }
}

/// Parser for non-streamed `/chat/completions` bodies.
enum ChatCompletionParser {
    static func text(fromJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        if let text = first["text"] as? String {
            return text
        }
        return nil
    }

    static func errorMessage(fromJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["error"] as? String {
            return message
        }
        guard let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String ?? error["detail"] as? String
    }
}
