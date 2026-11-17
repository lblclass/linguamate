import AVFoundation
import Foundation
import Observation
import Speech

/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` for push-to-talk recognition.
///
/// Behaviour worth knowing:
/// * partial results stream into `transcript` so the UI can show what was heard;
/// * a simple RMS silence detector ends the utterance automatically, which is
///   what makes hands-free practice feel natural;
/// * on-device recognition is used whenever the device supports it (offline and
///   private), otherwise the server recognizer is used.
@MainActor
@Observable
final class SpeechRecognizer {
    enum Status: Equatable {
        case idle
        case listening
        case unavailable(String)

        var isListening: Bool {
            if case .listening = self { return true }
            return false
        }
    }

    enum SpeechError: LocalizedError {
        case permissionDenied
        case recognizerUnavailable(String)
        case audioEngineFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "需要麦克风与语音识别权限，请到「设置 → 隐私与安全性」中开启。"
            case .recognizerUnavailable(let locale):
                return "当前设备暂不支持 \(locale) 的语音识别，可以改用键盘输入。"
            case .audioEngineFailed(let detail):
                return "麦克风启动失败：\(detail)"
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var transcript = ""
    /// Normalised microphone level (0...1) for the waveform in the UI.
    private(set) var level: Double = 0

    /// Called with the final transcript when an utterance ends by itself.
    var onUtteranceFinished: ((String) -> Void)?

    var silenceThreshold: Double = 0.008
    var silenceDuration: TimeInterval = 3
    var maximumUtteranceDuration: TimeInterval = 45

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var requestBox: RecognitionRequestBox?
    private var language: SupportedLanguage = .english
    private var startedAt: Date?
    private var didFinish = false
    private var isStopping = false
    private var committedTranscript = ""
    private var recognitionGeneration = 0
    private var silenceDetector = UtteranceSilenceDetector()

    var isRecording: Bool { status.isListening }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        return speechStatus == .authorized && microphoneGranted
    }

    // MARK: - Recording

    func start(language: SupportedLanguage) async throws {
        guard !isRecording else { return }
        self.language = language

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable else {
            status = .unavailable(language.localeIdentifier)
            throw SpeechError.recognizerUnavailable(language.localeIdentifier)
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            status = .unavailable("permission")
            throw SpeechError.permissionDenied
        }

        do {
            try AudioSessionManager.activateForConversation()
        } catch {
            throw SpeechError.audioEngineFailed(error.localizedDescription)
        }

        let engine = AVAudioEngine()
        let requestBox = RecognitionRequestBox()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw SpeechError.audioEngineFailed("麦克风输入不可用")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            requestBox.append(buffer)
            let rms = SpeechRecognizer.rms(of: buffer)
            Task { @MainActor [weak self] in
                self?.handleAudioLevel(rms)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechError.audioEngineFailed(error.localizedDescription)
        }

        self.audioEngine = engine
        self.recognizer = recognizer
        self.requestBox = requestBox
        transcript = ""
        committedTranscript = ""
        didFinish = false
        isStopping = false
        silenceDetector.reset()
        startedAt = Date()
        status = .listening
        beginRecognitionTask(recognizer: recognizer, requestBox: requestBox)
    }

    private func beginRecognitionTask(recognizer: SFSpeechRecognizer, requestBox: RecognitionRequestBox) {
        recognitionGeneration += 1
        let generation = recognitionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        requestBox.update(request)
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.recognitionGeneration,
                      self.status.isListening,
                      !self.didFinish else { return }

                if let result {
                    let partial = result.bestTranscription.formattedString
                    self.transcript = Self.joinedTranscript(
                        self.committedTranscript,
                        partial,
                        language: self.language
                    )
                    if result.isFinal {
                        self.committedTranscript = self.transcript
                        self.beginRecognitionTask(recognizer: recognizer, requestBox: requestBox)
                        return
                    }
                }

                if error != nil {
                    self.stopInternal()
                }
            }
        }
    }

    /// Ends the utterance and reports whatever was recognised.
    func finishUtterance() {
        guard !didFinish else { return }
        didFinish = true
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopInternal()
        onUtteranceFinished?(text)
    }

    /// Stops the microphone without reporting a result (user cancelled).
    func cancel() {
        didFinish = true
        stopInternal()
        transcript = ""
    }

    private func stopInternal() {
        guard !isStopping else { return }
        isStopping = true
        recognitionGeneration += 1

        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        requestBox?.update(nil)
        request?.endAudio()
        task?.cancel()

        audioEngine = nil
        request = nil
        task = nil
        recognizer = nil
        requestBox = nil
        committedTranscript = ""
        level = 0
        silenceDetector.reset()
        startedAt = nil
        status = .idle
        isStopping = false
    }

    // MARK: - Levels

    private func handleAudioLevel(_ rms: Double) {
        guard status.isListening else { return }
        level = min(1, rms * 18)

        let now = Date()
        if let startedAt, now.timeIntervalSince(startedAt) > maximumUtteranceDuration {
            finishUtterance()
            return
        }

        let hasTranscript = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if silenceDetector.shouldFinish(
            rms: rms,
            threshold: silenceThreshold,
            duration: silenceDuration,
            hasTranscript: hasTranscript,
            now: now
        ) {
            finishUtterance()
        }
    }

    nonisolated static func joinedTranscript(
        _ committed: String,
        _ partial: String,
        language: SupportedLanguage
    ) -> String {
        let left = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        return language == .japanese ? left + right : left + " " + right
    }

    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = samples[index]
            sum += sample * sample
        }
        let mean = sum / Float(frameLength)
        return Double(mean.squareRoot())
    }
}

struct UtteranceSilenceDetector {
    private(set) var silenceStartedAt: Date?

    mutating func reset() {
        silenceStartedAt = nil
    }

    mutating func shouldFinish(
        rms: Double,
        threshold: Double,
        duration: TimeInterval,
        hasTranscript: Bool,
        now: Date
    ) -> Bool {
        guard hasTranscript, rms < threshold else {
            silenceStartedAt = nil
            return false
        }
        guard let started = silenceStartedAt else {
            silenceStartedAt = now
            return false
        }
        return now.timeIntervalSince(started) >= duration
    }
}

private final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func update(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }
}
