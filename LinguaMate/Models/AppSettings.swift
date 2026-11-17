import Foundation
import Observation

/// User preferences. Everything here is local-only; the API key lives in the
/// Keychain instead of this struct.
struct AppSettings: Codable, Equatable, Sendable {
    var language: SupportedLanguage = .english
    var level: ConversationLevel = .intermediate

    var baseURLString: String = "https://api.openai.com/v1"
    var model: String = "gpt-4o-mini"
    var temperature: Double = 0.7
    var maxHistoryTurns: Int = 12

    /// When true the app talks to the built-in offline demo engine, which needs
    /// no API key. Useful to try the UX before plugging in a real model.
    var useDemoEngine: Bool = true

    var autoSpeakReplies: Bool = true
    var continueListeningAfterReply: Bool = false
    var showTranslation: Bool = true
    var enableCorrections: Bool = true

    /// Base rate for speech synthesis; the level multiplies it.
    var speechRate: Double = 0.5
    /// Chosen voice per language code (e.g. "en" -> voice identifier).
    var voiceIdentifiers: [String: String] = [:]

    var showsDemoBadge: Bool { useDemoEngine }
}

@Observable
final class AppSettingsStore {
    private static let storageKey = "LinguaMate.AppSettings.v1"

    private let defaults: UserDefaults

    var settings: AppSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func resetToDefaults() {
        settings = AppSettings()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}