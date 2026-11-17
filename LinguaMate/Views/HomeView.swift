import SwiftUI

/// Landing screen: pick a language, pick a level, pick a scenario, start talking.
struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTopic: ConversationTopic?
    @State private var reviewingSession: ConversationSession?
    @State private var showsTopicPicker = false

    var body: some View {
        @Bindable var store = appState.settingsStore

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    languageSection(store: store)
                    topicSection
                    recentSection
                    footnote
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Theme.softGradient.ignoresSafeArea())
            .navigationTitle("LinguaMate")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showsTopicPicker) {
                TopicPickerView(language: appState.settings.language) { topic in
                    selectedTopic = topic
                }
            }
            .navigationDestination(item: $selectedTopic) { topic in
                ConversationView(appState: appState, topic: topic)
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

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🎧")
                    .font(.system(size: 34))
                Spacer()
                if appState.isDemoMode {
                    BadgePill(text: "演示模式 · 无需 API Key", color: .white)
                }
            }
            Text("用大模型练口语")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("语音输入 → 大模型对话 → 语音朗读，支持英语与日语")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.heroGradient)
        )
    }

    private func languageSection(store: AppSettingsStore) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 12) {
            Text("练什么语言")
                .font(.headline)

            Picker("语言", selection: $store.settings.language) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text("\(language.flag) \(language.displayName)").tag(language)
                }
            }
            .pickerStyle(.segmented)

            Text("难度")
                .font(.headline)
                .padding(.top, 4)

            Picker("难度", selection: $store.settings.level) {
                ForEach(ConversationLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(appState.settings.level.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("推荐场景")
                    .font(.headline)
                Spacer()
                Button("全部主题") { showsTopicPicker = true }
                    .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(featuredTopics.enumerated()), id: \.element.id) { _, topic in
                    TopicCard(topic: topic) {
                        selectedTopic = topic
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近的对话")
                .font(.headline)

            if recentSessions.isEmpty {
                Text("还没有对话记录，选一个场景开始吧。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                ForEach(recentSessions) { session in
                    Button {
                        reviewingSession = session
                    } label: {
                        HStack(spacing: 12) {
                            Text(session.topicEmoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.topicTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(session.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(session.summaryLine)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .cardStyle(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footnote: some View {
        Text("提示：点击麦克风开始说话，说完会自动结束；也可以直接用键盘输入。所有对话记录只保存在本机。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private var featuredTopics: [ConversationTopic] {
        Array(TopicCatalog.topics(for: appState.settings.language).prefix(6))
    }

    private var recentSessions: [ConversationSession] {
        Array(appState.sessionStore.sessions.prefix(3))
    }

    private func resolvedTopic(for session: ConversationSession) -> ConversationTopic {
        TopicCatalog.topic(id: session.topicID, language: session.language)
            ?? ConversationTopic(
                id: session.topicID,
                language: session.language,
                category: "自定义",
                title: session.topicTitle,
                emoji: session.topicEmoji,
                summary: "历史对话",
                role: "a friendly \(session.language.promptName) conversation partner",
                goal: "Continue the previous conversation naturally.",
                openingLine: session.language == .english ? "Let's continue where we left off." : "続きから話しましょう。",
                keyPhrases: []
            )
    }
}

/// Compact scenario tile.
struct TopicCard: View {
    let topic: ConversationTopic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(topic.emoji)
                    .font(.title2)
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(topic.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.languageColor(topic.language).opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environment(AppState())
}