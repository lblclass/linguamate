import SwiftUI

/// Full topic list with search, grouped by category.
struct TopicPickerView: View {
    let language: SupportedLanguage
    let onSelect: (ConversationTopic) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    Section(category) {
                        ForEach(topics(in: category)) { topic in
                            Button {
                                onSelect(topic)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(topic.emoji)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(topic.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(topic.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索场景")
            .navigationTitle("全部主题 · \(language.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var allTopics: [ConversationTopic] {
        TopicCatalog.topics(for: language)
    }

    private var filteredTopics: [ConversationTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTopics }
        return allTopics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(trimmed)
                || topic.summary.localizedCaseInsensitiveContains(trimmed)
                || topic.category.localizedCaseInsensitiveContains(trimmed)
                || topic.keyPhrases.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var filteredCategories: [String] {
        var seen: [String] = []
        for topic in filteredTopics where !seen.contains(topic.category) {
            seen.append(topic.category)
        }
        return seen
    }

    private func topics(in category: String) -> [ConversationTopic] {
        filteredTopics.filter { $0.category == category }
    }
}

#Preview {
    TopicPickerView(language: .japanese) { _ in }
}