import SwiftUI

/// The practice screen: transcript, voice input, voice output, corrections.
struct ConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ConversationViewModel
    @FocusState private var isComposerFocused: Bool

    private let bottomAnchor = "transcript-bottom"

    init(appState: AppState, topic: ConversationTopic, existingSession: ConversationSession? = nil) {
        _viewModel = State(
            initialValue: ConversationViewModel(
                appState: appState,
                topic: topic,
                session: existingSession,
                isReviewing: existingSession != nil
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            transcript
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            composer
        }
        .background(Theme.softGradient.ignoresSafeArea())
        .navigationTitle(viewModel.topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if appState.speaker.isSpeaking {
                        Button("停止朗读", systemImage: "speaker.slash") { appState.stopSpeaking() }
                    }
                    Button("重新回答", systemImage: "arrow.clockwise") { viewModel.retryLastTurn() }
                    Button("结束本次对话", systemImage: "checkmark.circle") {
                        viewModel.finish()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { viewModel.startIfNeeded() }
        .onDisappear { viewModel.finish() }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    sessionHeader

                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            language: viewModel.session.language,
                            showsTranslation: appState.settings.showTranslation,
                            isSpeaking: appState.speaker.isSpeaking,
                            onReplay: { viewModel.replay(message) },
                            onUseHint: { hint in
                                viewModel.draft = hint.replacingOccurrences(of: "试试这样说：", with: "")
                            }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(viewModel.topic.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.topic.title)
                        .font(.headline)
                    Text(viewModel.topic.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                BadgePill(text: "\(viewModel.session.language.flag) \(viewModel.session.language.displayName)", color: Theme.languageColor(viewModel.session.language))
                BadgePill(text: viewModel.session.level.displayName)
                if viewModel.session.isDemo {
                    BadgePill(text: "演示模式", color: .orange)
                }
            }
        }
        .cardStyle()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    // MARK: - Composer

    private var composer: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 10) {
            if viewModel.isReviewing {
                reviewNotice
            } else {
                if appState.recognizer.isRecording {
                    listeningIndicator
                }

                HStack(alignment: .bottom, spacing: 10) {
                    micButton

                    TextField("说出或输入你的回答…", text: $viewModel.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .focused($isComposerFocused)
                        .submitLabel(.send)
                        .onSubmit { sendFromComposer() }

                    sendButton
                }
                .padding(.horizontal, 14)

                quickToggles
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var micButton: some View {
        Button {
            isComposerFocused = false
            viewModel.toggleListening()
        } label: {
            Image(systemName: appState.recognizer.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(appState.recognizer.isRecording ? Color.red : Theme.accent)
                )
                .overlay(
                    Circle()
                        .stroke(
                            appState.recognizer.isRecording ? Color.red.opacity(0.35) : Theme.accent.opacity(0.25),
                            lineWidth: appState.recognizer.isRecording ? 6 * appState.recognizer.level + 2 : 0
                        )
                )
                .scaleEffect(appState.recognizer.isRecording ? 1 + 0.08 * appState.recognizer.level : 1)
                .animation(.easeOut(duration: 0.12), value: appState.recognizer.level)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isResponding)
        .opacity(viewModel.isResponding ? 0.5 : 1)
        .accessibilityLabel(appState.recognizer.isRecording ? "结束录音" : "开始录音")
    }

    private var sendButton: some View {
        Button(action: sendFromComposer) {
            Image(systemName: viewModel.isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(viewModel.isResponding ? Color.secondary : Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend && !viewModel.isResponding)
        .accessibilityLabel(viewModel.isResponding ? "停止回答" : "发送")
    }

    private var listeningIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("正在聆听…（停顿 3 秒自动结束）")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("完成") { viewModel.toggleListening() }
                    .font(.caption.weight(.semibold))
            }

            Text(appState.recognizer.transcript.isEmpty ? "请开始说话" : appState.recognizer.transcript)
                .font(.subheadline)
                .foregroundStyle(appState.recognizer.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .padding(.horizontal, 14)
    }

    private var reviewNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("这是历史记录，只读")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("继续对话") {
                viewModel.isReviewing = false
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .padding(.horizontal, 14)
    }

    private var quickToggles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toggleChip("自动朗读", systemImage: "speaker.wave.2", isOn: appState.settings.autoSpeakReplies) {
                    appState.update { $0.autoSpeakReplies.toggle() }
                    if !appState.settings.autoSpeakReplies { appState.stopSpeaking() }
                }
                toggleChip("中文翻译", systemImage: "character.book.closed", isOn: appState.settings.showTranslation) {
                    appState.update { $0.showTranslation.toggle() }
                }
                toggleChip("语法纠正", systemImage: "pencil.and.outline", isOn: appState.settings.enableCorrections) {
                    appState.update { $0.enableCorrections.toggle() }
                }
                if appState.speaker.isSpeaking {
                    Button {
                        appState.stopSpeaking()
                    } label: {
                        chipLabel("停止朗读", systemImage: "speaker.slash", isOn: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func toggleChip(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title, systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, systemImage: String, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(isOn ? Theme.accent.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .foregroundStyle(isOn ? Theme.accent : Color.secondary)
    }

    private func sendFromComposer() {
        if viewModel.isResponding {
            viewModel.stopResponding()
            return
        }
        let text = viewModel.draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isComposerFocused = false
        viewModel.sendLearnerMessage(text)
    }
}

#Preview {
    NavigationStack {
        ConversationView(
            appState: AppState(),
            topic: TopicCatalog.englishTopics[0]
        )
    }
}
