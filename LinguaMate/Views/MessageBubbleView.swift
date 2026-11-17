import SwiftUI

/// One chat bubble. Tutor bubbles can carry a translation, corrections and
/// follow-up hints; learner bubbles stay simple.
struct MessageBubbleView: View {
    let message: ChatMessage
    let language: SupportedLanguage
    let showsTranslation: Bool
    let isSpeaking: Bool
    let onReplay: () -> Void
    let onUseHint: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .tutor {
                avatar
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .tutor ? .leading : .trailing, spacing: 8) {
                bubble
                if message.role == .tutor {
                    if showsTranslation, let translation = message.translation, !translation.isEmpty {
                        translationView(translation)
                    }
                    if !message.corrections.isEmpty {
                        correctionsView
                    }
                    if !message.followUps.isEmpty {
                        hintsView
                    }
                }
            }

            if message.role == .learner {
                Color.clear.frame(width: 0)
            } else {
                Spacer(minLength: 40)
            }
        }
    }

    private var avatar: some View {
        Text(language.flag)
            .font(.title3)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.languageColor(language).opacity(0.15)))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在思考…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .tutor ? Color.primary : Color.white)
                    .textSelection(.enabled)
            }

            if message.role == .tutor, !message.isEmpty {
                HStack(spacing: 10) {
                    Button(action: onReplay) {
                        Label(isSpeaking ? "朗读中" : "朗读", systemImage: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)

                    if message.isDemo {
                        BadgePill(text: "演示")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(message.role == .tutor ? Theme.tutorBubble : Theme.accent)
        )
    }

    private func translationView(_ translation: String) -> some View {
        Text(translation)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private var correctionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("小纠正", systemImage: "pencil.and.outline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            ForEach(message.corrections) { correction in
                VStack(alignment: .leading, spacing: 3) {
                    if !correction.original.isEmpty, !correction.corrected.isEmpty {
                        HStack(spacing: 6) {
                            Text(correction.original)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(correction.corrected)
                                .foregroundStyle(.primary)
                        }
                        .font(.footnote.weight(.medium))
                    } else if !correction.corrected.isEmpty {
                        Text(correction.corrected)
                            .font(.footnote.weight(.medium))
                    }
                    if !correction.note.isEmpty {
                        Text(correction.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    private var hintsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可以这样说")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(message.followUps.enumerated()), id: \.offset) { _, hint in
                Button {
                    onUseHint(hint)
                } label: {
                    Text(hint)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubbleView(
            message: ChatMessage(
                role: .tutor,
                text: "Nice! What size would you like?",
                translation: "好的！您想要什么尺寸？",
                corrections: [Correction(original: "i go to school yesterday", corrected: "I went to school yesterday", note: "过去的事要用过去式。")],
                followUps: ["试试这样说：for here or to go"]
            ),
            language: .english,
            showsTranslation: true,
            isSpeaking: false,
            onReplay: {},
            onUseHint: { _ in }
        )
        MessageBubbleView(
            message: ChatMessage(role: .learner, text: "I want a large latte."),
            language: .english,
            showsTranslation: true,
            isSpeaking: false,
            onReplay: {},
            onUseHint: { _ in }
        )
    }
    .padding()
}