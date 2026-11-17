import SwiftUI

/// Past conversations: review, export, delete.
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var reviewingSession: ConversationSession?

    var body: some View {
        NavigationStack {
            Group {
                if appState.sessionStore.sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(appState.sessionStore.sessions) { session in
                            Button {
                                reviewingSession = session
                            } label: {
                                row(for: session)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    appState.sessionStore.delete(id: session.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                ShareLink(item: SessionExporter.plainText(for: session)) {
                                    Label("导出", systemImage: "square.and.arrow.up")
                                }
                                .tint(Theme.accent)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("对话记录")
            .toolbar {
                if !appState.sessionStore.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) {
                            appState.sessionStore.deleteAll()
                        }
                    }
                }
            }
            .navigationDestination(item: $reviewingSession) { session in
                ConversationView(
                    appState: appState,
                    topic: resolvedTopic(for: session),
                    existingSession: session
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有对话记录",
            systemImage: "text.bubble",
            description: Text("在「练习」里选一个场景开口说话，记录会自动保存在本机。")
        )
    }

    private func row(for session: ConversationSession) -> some View {
        HStack(spacing: 12) {
            Text(session.topicEmoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.topicTitle)
                        .font(.subheadline.weight(.semibold))
                    if session.isDemo {
                        BadgePill(text: "演示", color: .orange)
                    }
                }
                Text(session.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(session.summaryLine) · \(SessionExporter.dateString(session.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func resolvedTopic(for session: ConversationSession) -> ConversationTopic {
        TopicCatalog.topic(id: session.topicID, language: session.language)
            ?? ConversationTopic(
                id: session.topicID,
                language: session.language,
                category: "历史",
                title: session.topicTitle,
                emoji: session.topicEmoji,
                summary: "历史对话",
                role: "a friendly \(session.language.promptName) conversation partner",
                goal: "Continue the previous conversation naturally.",
                openingLine: "Let's continue.",
                keyPhrases: []
            )
    }
}

/// Turns a session into shareable text (pure function, unit tested).
enum SessionExporter {
    static func plainText(for session: ConversationSession) -> String {
        var lines: [String] = []
        lines.append("LinguaMate · \(session.topicTitle)")
        lines.append("\(session.language.displayName) · \(session.level.displayName) · \(dateString(session.startedAt))")
        lines.append("")
        for message in session.messages {
            let speaker = message.role == .tutor ? "AI" : "我"
            lines.append("\(speaker): \(message.text)")
            if let translation = message.translation, !translation.isEmpty {
                lines.append("   译文: \(translation)")
            }
            for correction in message.corrections where !correction.isEmpty {
                lines.append("   纠正: \(correction.original) -> \(correction.corrected) \(correction.note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    HistoryView()
        .environment(AppState())
}