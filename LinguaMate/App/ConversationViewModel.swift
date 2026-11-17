import Foundation
import Observation

/// Drives a single conversation: appends the learner's turn, streams the
/// tutor's answer into a placeholder bubble, and speaks it as it arrives.
@MainActor
@Observable
final class ConversationViewModel {
    private(set) var session: ConversationSession
    private(set) var isResponding = false
    var errorMessage: String?
    var draft = ""
    /// History sessions are opened read-only.
    var isReviewing: Bool

    let topic: ConversationTopic
    private let appState: AppState
    private var streamTask: Task<Void, Never>?
    private var hasStarted = false

    init(appState: AppState, topic: ConversationTopic, session: ConversationSession? = nil, isReviewing: Bool = false) {
        self.appState = appState
        self.topic = topic
        self.isReviewing = isReviewing
        if let session {
            self.session = session
            self.hasStarted = true
        } else {
            let language = appState.settings.language
            self.session = ConversationSession(
                topicID: topic.id,
                topicTitle: topic.title,
                topicEmoji: topic.emoji,
                language: language,
                level: appState.settings.level,
                isDemo: appState.isDemoMode
            )
        }
    }

    var messages: [ChatMessage] { session.messages }
    var isSpeaking: Bool { appState.speaker.isSpeaking }
    var isListening: Bool { appState.recognizer.isRecording }

    var canSend: Bool {
        !isReviewing && !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Lifecycle

    /// Speaks the topic's built-in opening line so a session starts instantly,
    /// with zero model latency.
    func startIfNeeded() {
        guard !hasStarted, !isReviewing else { return }
        hasStarted = true
        let opening = ChatMessage(role: .tutor, text: topic.openingLine, isDemo: session.isDemo)
        session.messages.append(opening)
        if appState.settings.autoSpeakReplies {
            appState.speak(opening.text, language: session.language)
        }
        persist()
    }

    func persist() {
        guard !session.messages.isEmpty else { return }
        appState.sessionStore.upsert(session)
    }

    func finish() {
        streamTask?.cancel()
        streamTask = nil
        isResponding = false
        appState.stopSpeaking()
        appState.recognizer.cancel()
        persist()
    }

    // MARK: - Speaking

    func replay(_ message: ChatMessage) {
        appState.speak(message.text, language: session.language)
    }

    func toggleListening() {
        if appState.recognizer.isRecording {
            appState.recognizer.finishUtterance()
            return
        }
        // Barge-in: stop the tutor immediately when the learner starts talking.
        appState.stopSpeaking()
        appState.recognizer.onUtteranceFinished = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.errorMessage = "没有听清，请再说一次，或直接用键盘输入。"
                } else {
                    self.sendLearnerMessage(text)
                }
            }
        }
        Task {
            do {
                try await appState.recognizer.start(language: session.language)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Turns

    func sendLearnerMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isReviewing else { return }
        appState.recognizer.cancel()
        session.messages.append(ChatMessage(role: .learner, text: trimmed))
        draft = ""
        requestTurn()
    }

    func retryLastTurn() {
        guard !isResponding, !isReviewing else { return }
        if session.messages.last?.role == .tutor {
            session.messages.removeLast()
        }
        requestTurn()
    }

    func stopResponding() {
        streamTask?.cancel()
        streamTask = nil
        isResponding = false
        appState.stopSpeaking()
        if session.messages.last?.role == .tutor, session.messages.last?.isEmpty == true {
            session.messages.removeLast()
        }
        persist()
    }

    private func requestTurn() {
        guard !isResponding else { return }
        let snapshot = session
        isResponding = true
        errorMessage = nil

        let settings = appState.settings
        let engine = appState.makeEngine()
        let placeholder = ChatMessage(role: .tutor, text: "", isDemo: engine.isDemo)
        session.messages.append(placeholder)
        let placeholderID = placeholder.id

        var spokenText = ""

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in engine.respond(session: snapshot, topic: self.topic, settings: settings) {
                    try Task.checkCancellation()
                    switch event {
                    case .replyDelta(let delta):
                        self.append(delta, to: placeholderID)
                        if settings.autoSpeakReplies {
                            spokenText += self.speakCompletedSentences(from: delta, spokenSoFar: spokenText)
                        }
                    case .completed(let reply):
                        self.completeTurn(reply, placeholderID: placeholderID, spokenText: spokenText, settings: settings)
                    }
                }
            } catch is CancellationError {
                // User cancelled; the placeholder is removed by stopResponding().
            } catch {
                self.append(error.localizedDescription, to: placeholderID)
                self.errorMessage = error.localizedDescription
                self.removeIfEmpty(placeholderID)
            }
            self.isResponding = false
            self.persist()
        }
    }

    private func append(_ delta: String, to id: UUID) {
        guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        session.messages[index].text += delta
    }

    private func removeIfEmpty(_ id: UUID) {
        guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
        if session.messages[index].isEmpty {
            session.messages.remove(at: index)
        }
    }

    /// Speaks whole sentences as soon as they are complete and returns what was
    /// handed to the synthesiser, so the tail is spoken only once at the end.
    private func speakCompletedSentences(from delta: String, spokenSoFar: String) -> String {
        let combined = spokenSoFar + delta
        let sentences = SpeechTextSanitizer.sentences(in: combined)
        guard sentences.count > 1 else { return "" }
        let speakable = sentences.dropLast()
        let text = speakable.joined(separator: " ")
        guard !text.isEmpty else { return "" }
        appState.speak(text, language: session.language)
        return text
    }

    private func completeTurn(_ reply: TutorReply, placeholderID: UUID, spokenText: String, settings: AppSettings) {
        guard let index = session.messages.firstIndex(where: { $0.id == placeholderID }) else { return }
        let finalText = reply.trimmedReply.isEmpty ? session.messages[index].text : reply.trimmedReply
        session.messages[index].text = finalText
        session.messages[index].translation = settings.showTranslation ? reply.translation : nil
        session.messages[index].corrections = settings.enableCorrections ? reply.corrections : []
        session.messages[index].followUps = reply.followUps
        session.isDemo = session.isDemo || session.messages[index].isDemo

        if settings.autoSpeakReplies {
            let remainder = Self.remainder(of: finalText, alreadySpoken: spokenText)
            if !remainder.isEmpty {
                appState.speak(remainder, language: session.language)
            }
        }
    }

    /// Text of `full` that has not been handed to the synthesiser yet.
    nonisolated static func remainder(of full: String, alreadySpoken: String) -> String {
        guard !alreadySpoken.isEmpty else { return full }
        let trimmedSpoken = alreadySpoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSpoken.isEmpty else { return full }
        let fullCharacters = Array(full)
        let spokenCharacters = Array(trimmedSpoken)
        var match = 0
        while match < fullCharacters.count, match < spokenCharacters.count, fullCharacters[match] == spokenCharacters[match] {
            match += 1
        }
        return String(fullCharacters.dropFirst(match)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}