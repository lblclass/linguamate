import Foundation
import Observation

/// Root object injected into the view tree. Owns settings, history, the speech
/// stack and the API key, and hands out tutor engines.
@MainActor
@Observable
final class AppState {
    let settingsStore: AppSettingsStore
    let sessionStore: SessionStore
    let recognizer: SpeechRecognizer
    let speaker: SpeechSynthesizer

    private let session: URLSession
    private(set) var apiKey: String
    private(set) var keychainMessage: String?

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        sessionStore: SessionStore? = nil,
        recognizer: SpeechRecognizer? = nil,
        speaker: SpeechSynthesizer? = nil,
        apiKey: String? = nil,
        session: URLSession? = nil
    ) {
        self.settingsStore = settingsStore
        self.sessionStore = sessionStore ?? SessionStore()
        self.recognizer = recognizer ?? SpeechRecognizer()
        self.speaker = speaker ?? SpeechSynthesizer()
        self.apiKey = apiKey ?? (KeychainStore.read() ?? "")
        self.session = session ?? LLMClient.makeDefaultSession()
    }

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        settingsStore.update(mutate)
    }

    var isDemoMode: Bool {
        settings.useDemoEngine || apiKey.isEmpty
    }

    func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.save(trimmed)
            apiKey = trimmed
            keychainMessage = trimmed.isEmpty ? "已清除 API Key" : "API Key 已保存到 Keychain"
        } catch {
            // Keeps the key for this launch even if the Keychain is unavailable
            // (for example in a locked simulator), so the user is not blocked.
            apiKey = trimmed
            keychainMessage = "无法写入 Keychain：\(error.localizedDescription)"
        }
    }

    func makeEngine() -> TutorEngine {
        TutorEngineFactory.makeEngine(settings: settings, apiKey: apiKey)
    }

    func speak(_ text: String, language: SupportedLanguage) {
        speaker.speak(text, language: language, settings: settings)
    }

    func stopSpeaking() {
        speaker.stop()
    }

    /// Sends a one-line prompt to the configured endpoint to check base URL,
    /// network and credentials in one shot.
    func testConnection(apiKeyOverride: String? = nil) async -> Result<String, Error> {
        guard !settings.useDemoEngine else {
            return .success("当前是离线演示模式，无需联网。")
        }
        let testKey = (apiKeyOverride ?? apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testKey.isEmpty else {
            return .failure(ChatEngineError.missingAPIKey)
        }
        do {
            let client = LLMClient(
                configuration: LLMClient.Configuration(
                    baseURL: try LLMClient.validatedBaseURL(settings.baseURLString),
                    apiKey: testKey,
                    model: settings.model,
                    temperature: 0
                ),
                session: session
            )
            var answer = ""
            for try await delta in client.streamChat(messages: [
                LLMMessage(role: "user", content: "Reply with the single word: OK")
            ]) {
                answer += delta
                if answer.count >= 40 { break }
            }
            let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAnswer.isEmpty else {
                throw ChatEngineError.emptyResponse
            }
            return .success("连接成功，模型回复：\(trimmedAnswer.prefix(40))")
        } catch {
            return .failure(error)
        }
    }
}
