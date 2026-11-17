import AVFoundation
import SwiftUI

/// Engine, speech, teaching and data settings.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var apiKeyDraft = ""
    @State private var connectionResult: String?
    @State private var connectionFailed = false
    @State private var isTesting = false
    @State private var showsClearAlert = false

    var body: some View {
        @Bindable var store = appState.settingsStore

        NavigationStack {
            Form {
                engineSection(store: store)
                speechSection(store: store)
                teachingSection(store: store)
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .task {
                apiKeyDraft = appState.apiKey
            }
            .alert("清空所有对话记录？", isPresented: $showsClearAlert) {
                Button("清空", role: .destructive) { appState.sessionStore.deleteAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("该操作不可撤销，记录只保存在本机。")
            }
        }
    }

    // MARK: - Sections

    private func engineSection(store: AppSettingsStore) -> some View {
        @Bindable var store = store

        return Section {
            Toggle("离线演示模式", isOn: $store.settings.useDemoEngine)
            if appState.settings.useDemoEngine {
                Text("关闭离线演示模式后，才能测试真实模型连接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("Base URL", text: $store.settings.baseURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            TextField("模型名称", text: $store.settings.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("API Key", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                appState.saveAPIKey(apiKeyDraft)
            } label: {
                Label("保存 API Key 到 Keychain", systemImage: "key.fill")
            }

            Button {
                Task { await runConnectionTest() }
            } label: {
                HStack {
                    Label("测试连接", systemImage: "bolt.horizontal.circle")
                    Spacer()
                    if isTesting { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isTesting || appState.settings.useDemoEngine)

            if let connectionResult {
                Text(connectionResult)
                    .font(.footnote)
                    .foregroundStyle(connectionFailed ? .red : .green)
            }

            if let message = appState.keychainMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("大模型")
        } footer: {
            Text("任何兼容 OpenAI /chat/completions 的服务都可以：OpenAI、DeepSeek、Moonshot、Ollama、LM Studio 等。API Key 只存在本机 Keychain，不会上传。")
        }
    }

    private func speechSection(store: AppSettingsStore) -> some View {
        @Bindable var store = store
        let voices = SpeechSynthesizer.availableVoices(for: appState.settings.language)

        return Section("语音") {
            Toggle("自动朗读 AI 回复", isOn: $store.settings.autoSpeakReplies)
            Toggle("说完后自动继续聆听", isOn: $store.settings.continueListeningAfterReply)

            VStack(alignment: .leading) {
                Text("语速 \(String(format: "%.2f", appState.settings.speechRate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Slider(value: $store.settings.speechRate, in: 0.3...0.65, step: 0.01)
            }

            Picker("音色", selection: voiceBinding) {
                Text("系统默认").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(voiceLabel(voice)).tag(voice.identifier)
                }
            }
        }
    }

    private func teachingSection(store: AppSettingsStore) -> some View {
        @Bindable var store = store

        return Section("教学") {
            Picker("默认语言", selection: $store.settings.language) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text("\(language.flag) \(language.displayName)").tag(language)
                }
            }
            Picker("默认难度", selection: $store.settings.level) {
                ForEach(ConversationLevel.allCases) { level in
                    Text("\(level.displayName) · \(level.detail)").tag(level)
                }
            }
            Toggle("显示中文翻译", isOn: $store.settings.showTranslation)
            Toggle("语法纠正", isOn: $store.settings.enableCorrections)
        }
    }

    private var dataSection: some View {
        Section("数据") {
            LabeledContent("对话记录", value: "\(appState.sessionStore.sessions.count) 段")
            LabeledContent("累计轮数", value: "\(appState.sessionStore.totalTurns) 轮")
            Button("清空所有记录", role: .destructive) {
                showsClearAlert = true
            }
            if let error = appState.sessionStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: AppInfo.version)
            LabeledContent("语音识别", value: "Apple Speech · 优先设备端")
            LabeledContent("隐私", value: "录音与记录仅保存在本机")
        }
    }

    // MARK: - Helpers

    private var voiceBinding: Binding<String> {
        Binding(
            get: { appState.settings.voiceIdentifiers[appState.settings.language.rawValue] ?? "" },
            set: { newValue in
                let key = appState.settings.language.rawValue
                appState.update { settings in
                    if newValue.isEmpty {
                        settings.voiceIdentifiers.removeValue(forKey: key)
                    } else {
                        settings.voiceIdentifiers[key] = newValue
                    }
                }
            }
        )
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) · \(voice.language)"
    }

    private func runConnectionTest() async {
        isTesting = true
        connectionResult = nil
        let result = await appState.testConnection(apiKeyOverride: apiKeyDraft)
        switch result {
        case .success(let message):
            connectionResult = message
            connectionFailed = false
            let trimmedDraft = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDraft.isEmpty, trimmedDraft != appState.apiKey {
                appState.saveAPIKey(trimmedDraft)
            }
        case .failure(let error):
            connectionResult = error.localizedDescription
            connectionFailed = true
        }
        isTesting = false
    }
}

enum AppInfo {
    static var version: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
