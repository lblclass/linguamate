import AVFoundation
import Foundation
import Observation

/// Text-to-speech for the tutor's replies.
///
/// * Replies are spoken sentence by sentence, so the learner hears the first
///   sentence while the model is still streaming the rest.
/// * Tapping the mic cancels playback immediately (barge-in), like a human
///   conversation partner stopping when you start talking.
@MainActor
@Observable
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    private(set) var lastSpokenText = ""

    /// Invoked when the queue drains (used for hands-free follow-up listening).
    var onFinishSpeaking: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static func availableVoices(for language: SupportedLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.rawValue) }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    static func preferredVoice(for language: SupportedLanguage, settings: AppSettings) -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)
        if let identifier = settings.voiceIdentifiers[language.rawValue],
           let match = voices.first(where: { $0.identifier == identifier }) {
            return match
        }
        for name in language.preferredVoiceNames {
            if let match = voices.first(where: { $0.name == name }) {
                return match
            }
        }
        if let best = voices.first(where: { $0.quality == .premium }) {
            return best
        }
        if let best = voices.first(where: { $0.quality == .enhanced }) {
            return best
        }
        return voices.first ?? AVSpeechSynthesisVoice(language: language.localeIdentifier)
    }

    func speak(_ text: String, language: SupportedLanguage, settings: AppSettings) {
        let spoken = SpeechTextSanitizer.sanitize(text)
        guard !spoken.isEmpty else { return }
        lastSpokenText = spoken
        stop()

        do {
            try AudioSessionManager.activateForPlayback()
        } catch {
            // Playback still usually works; the session error is not fatal.
        }

        let voice = Self.preferredVoice(for: language, settings: settings)
        let rate = Self.clampedRate(settings.speechRate * languageRateFactor(language))
        for sentence in SpeechTextSanitizer.sentences(in: spoken) {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = 1.0
            utterance.postUtteranceDelay = 0.05
            synthesizer.speak(utterance)
        }
        isSpeaking = !spoken.isEmpty
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    static func clampedRate(_ value: Double) -> Float {
        Float(min(max(value, 0.25), 0.65))
    }

    private func languageRateFactor(_ language: SupportedLanguage) -> Double {
        // Japanese TTS sounds fastest at the same nominal rate.
        language == .japanese ? 0.95 : 1.0
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking {
                self.isSpeaking = false
                self.onFinishSpeaking?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }
}

/// Removes everything a speech synthesiser should not read out loud.
enum SpeechTextSanitizer {
    static func sanitize(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "\n", with: " ")
        for token in ["**", "`", "*", "#", ">", "[", "]", "\\"] {
            value = value.replacingOccurrences(of: token, with: "")
        }
        value = removeEmoji(from: value)
        value = value.replacingOccurrences(of: "  ", with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removeEmoji(from text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C))
        }))
    }

    /// Splits into sentence-ish pieces so playback can start early.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
        for character in text {
            current.append(character)
            if terminators.contains(character), current.trimmingCharacters(in: .whitespaces).count > 1 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            result.append(tail)
        }
        return result.isEmpty ? [text] : result
    }
}