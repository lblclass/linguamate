import Foundation

/// What the conversation view receives while the tutor is answering.
enum TutorStreamEvent: Sendable {
    /// Freshly streamed text of the spoken reply, safe to append to the bubble.
    case replyDelta(String)
    /// The turn is complete; the structured answer is ready.
    case completed(TutorReply)
}

/// A way of producing tutor turns. Implemented by the network engine and the
/// offline demo engine, so the UI never talks to a concrete transport.
protocol TutorEngine {
    var displayName: String { get }
    var isDemo: Bool { get }

    func respond(
        session: ConversationSession,
        topic: ConversationTopic,
        settings: AppSettings
    ) -> AsyncThrowingStream<TutorStreamEvent, Error>
}

/// Builds the engine that matches the current settings.
enum TutorEngineFactory {
    static func makeEngine(settings: AppSettings, apiKey: String) -> TutorEngine {
        if settings.useDemoEngine || apiKey.isEmpty {
            return DemoTutorEngine()
        }
        return OpenAITutorEngine(settings: settings, apiKey: apiKey)
    }
}

/// Streams a turn from an OpenAI-compatible endpoint.
struct OpenAITutorEngine: TutorEngine {
    let settings: AppSettings
    let apiKey: String
    var session: URLSession = LLMClient.makeDefaultSession()

    var displayName: String { "OpenAI 兼容接口 · \(settings.model)" }
    var isDemo: Bool { false }

    func respond(
        session: ConversationSession,
        topic: ConversationTopic,
        settings runtimeSettings: AppSettings
    ) -> AsyncThrowingStream<TutorStreamEvent, Error> {
        let effective = runtimeSettings
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let client = LLMClient(
                        configuration: LLMClient.Configuration(
                            baseURL: try LLMClient.validatedBaseURL(effective.baseURLString),
                            apiKey: apiKey,
                            model: effective.model,
                            temperature: effective.temperature
                        ),
                        session: self.session
                    )
                    let messages = PromptBuilder.chatMessages(
                        session: session,
                        topic: topic,
                        settings: effective
                    )

                    var extractor = StreamingTutorReplyExtractor()
                    for try await delta in client.streamChat(messages: messages) {
                        let fresh = extractor.push(delta)
                        if !fresh.isEmpty {
                            continuation.yield(.replyDelta(fresh))
                        }
                    }
                    _ = extractor.finish()

                    let reply = extractor.parsedReply()
                    guard !reply.trimmedReply.isEmpty else {
                        throw ChatEngineError.emptyResponse
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

}
