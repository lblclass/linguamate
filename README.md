# LinguaMate · 大模型外语口语陪练（iOS）

用大模型做**语音对话**练口语的原生 iOS App：语音输入 → 大模型角色扮演对话 → 语音朗读，
支持**英语 / 日语**，内置场景主题、语法纠正、中文翻译和对话记录。

- 技术栈：SwiftUI + Observation（iOS 17+）、Apple Speech（`SFSpeechRecognizer`）、
  `AVSpeechSynthesizer`、`URLSession` 流式 SSE、Keychain。
- 模型接入：任何兼容 OpenAI `POST /chat/completions` 的服务（OpenAI、DeepSeek、Moonshot、
  Ollama、LM Studio、自建网关…），流式输出，可在设置里改 Base URL / 模型 / Key。
- **离线演示模式**：不填 API Key 也能完整体验「说 → 回 → 朗读 → 纠正 → 记录」，方便先验证交互。

## 功能对照需求

| 需求 | 实现 |
| --- | --- |
| 用大模型进行外语对话 | `LLMClient` 流式请求 + `OpenAITutorEngine`，逐句朗读，边说边播 |
| 语音输入 | `SpeechRecognizer`：麦克风 + Apple 语音识别，优先设备端识别，静音自动断句 |
| 语音输出 | `SpeechSynthesizer`：按句合成，可选系统音色与语速，支持打断（barge-in） |
| 开启新对话 | 首页选场景即新建会话，`ConversationSession` 独立保存 |
| 设置对话主题（内置） | `TopicCatalog`：英语 10 个、日语 10 个场景，含角色设定、目标、开场白、关键句 |
| 英语 / 日语 | `SupportedLanguage` 统一驱动识别、朗读、提示词与主题 |
| （额外）语法纠正 | 回复带「小纠正」卡片：原句 → 改写 + 中文说明 |
| （额外）中文翻译 | 每条 AI 回复附中文译文，可开关 |
| （额外）对话记录 | 本地 JSON 持久化，可回看、继续对话、导出文本 |
| （额外）难度分级 | 入门 / 进阶 / 高阶，影响句长、语速与用词 |
| （额外）开口提示 | 每轮给出「可以这样说」的中文提示，可一键填入输入框 |

## 目录结构

```
LinguaMate/
├── LinguaMate.xcodeproj/          # 可直接用 Xcode 打开（含共享 scheme 与测试 target）
├── project.yml                    # 备选：XcodeGen 生成工程
├── LinguaMate/
│   ├── App/                       # 入口、AppState、会话控制器、设计系统
│   ├── Models/                    # 语言/难度/消息/会话/主题/设置
│   ├── Services/                  # 大模型、提示词、SSE、解析、语音、存储、Keychain
│   ├── Views/                     # 首页、主题选择、对话、气泡、记录、设置
│   ├── Resources/Assets.xcassets/ # App 图标（1024×1024，无 alpha）与主题色
│   ├── Info.plist                 # 麦克风 / 语音识别权限说明等
│   └── PrivacyInfo.xcprivacy      # 隐私清单（UserDefaults / 文件时间戳）
├── LinguaMateTests/               # 70 个 XCTest 用例（含真实模型回复回放）
└── Tools/                         # 生成工程、生成图标、协议交叉校验、静态校验、真实接口联调
```

## 快速开始（需要一台 Mac）

```bash
# 方式一：直接打开（推荐）
open LinguaMate.xcodeproj      # Xcode 15+，选择 iPhone 模拟器或真机 ⌘R

# 方式二：用 XcodeGen 重新生成工程
brew install xcodegen && xcodegen generate && open LinguaMate.xcodeproj
```

首次运行前请在 Xcode 的 **Signing & Capabilities** 里选择自己的 Team，
并把 `PRODUCT_BUNDLE_IDENTIFIER`（默认 `com.linguamate.app`）改成你自己的唯一标识。

### 设备兼容性

- **iPhone 11：已支持。** 工程最低系统版本为 iOS 17.0，iPhone 11 支持 iOS 17 / 18 / 26。
- iPhone 11 的屏幕为 6.1 英寸刘海屏（414×896 pt），当前 SwiftUI 布局会自动处理刘海和底部安全区，
  不需要单独写机型判断。
- 已在 iPhone 11 模拟器（iOS 18.4）验证首页布局，并完成 arm64 真机目标编译。
- 如果手机仍停留在 iOS 16，请先升级到 iOS 17 或更高版本；本工程使用了 iOS 17 的
  `@Observable` / `@Bindable`，没有做 iOS 16 兼容。

## 配置大模型

打开 App → **设置 → 大模型**：

1. 想先试交互：保持「离线演示模式」开启即可，完全不需要联网。
2. 接真实模型：关闭演示模式，填写 Base URL（如 `https://api.openai.com/v1`）、模型名
   （如 `gpt-4o-mini`），粘贴 API Key 后直接点「测试连接」。测试使用与实际对话相同的流式
   `/chat/completions` 请求；成功后会自动把 Key 写入 Keychain，你也可以先手动保存。
   Key 只写入本机 Keychain，不进 UserDefaults、不进日志、不随记录导出。

## 安装到 iPhone 的几种方式

1. **Xcode 直连真机（最容易）**：Mac + 数据线 + 免费 Apple ID。选中设备 ⌘R，
   首次需在 iPhone「设置 → 通用 → VPN与设备管理」信任开发者证书。免费账号签名 7 天有效，到期重连一次即可。
2. **TestFlight（要 99 美元/年开发者账号）**：Xcode → Product → Archive → Distribute App →
   App Store Connect，上传后在 TestFlight 里给自己或测试者安装，有效期 90 天。
3. **Windows 用户的折中方案**：用 GitHub Actions 的 macOS runner（或云端 Mac）执行
   `xcodebuild -scheme LinguaMate -configuration Release -destination generic/platform=iOS -archivePath build/LinguaMate.xcarchive archive`
   并导出 `LinguaMate.ipa`，再用 **AltStore / SideStore** 配免费 Apple ID 侧载到 iPhone。
4. **模拟器**：只想看界面，Xcode 里选任意 iPhone 模拟器 ⌘R 即可；模拟器没有真实麦克风时可用键盘输入。

App 内首屏建议顺序：选语言 → 选难度 → 点场景卡片 → 点麦克风说话（说完自动结束）→ 听 AI 回复。

## 验证情况

可以在没有 Mac 的机器上跑的部分都跑了（`Tools/` 下脚本）：

| 脚本 | 作用 | 本次结果 |
| --- | --- | --- |
| `node Tools/protocol_check.js` | 把 SSE 解码、回复解析、流式抽取三段算法逐行移植到 JS，用与 XCTest 相同的用例跑一遍 | **17/17 通过** |
| `node Tools/contract_check.js` | 用 App 真实的系统提示词调用一个真实 OpenAI 兼容接口（英/日各一次，含流式） | **16/16 通过**，真实回复已存档到 `LinguaMateTests/RunFixtures.swift` 供 XCTest 回放 |
| `node Tools/verify_project.js` | 工程完整性（对象引用、build phase、plist 权限键、隐私清单、图标 1024×1024 无 alpha、33 个 Swift 文件花括号配平/无 CRLF/无 tab、引用与磁盘文件一致） | **全部通过** |
| `node Tools/generate_project.js` | 从磁盘文件重新生成 `project.pbxproj` 与 scheme | 27 个 App 源文件 + 6 个测试文件 |

交叉校验过程中真的抓到并修掉了 5 个问题：解析器遇到缺失的结束标签时会把后续段落吞进朗读内容、
纠正行前导项目符号没被剥离、`trimQuotes` 未先裁空白、流式抽取在回复较短时过度保留字符、
以及一个源文件（`Models/Language.swift`）漏建导致类型缺失。

**本轮在 macOS / Xcode 16.3 上补跑的**：
① arm64 真机目标编译通过；② iPhone 11 模拟器（iOS 18.4）安装并启动成功，首页布局正常。

**仍未验证的**：实体 iPhone 11 上的麦克风识别、语音识别权限、TTS 音色和打断表现，
需要连接真机后执行 `LinguaMateTests`（70 个用例）并实际试跑。

## 隐私

录音只用于识别，识别结果优先在设备端完成；对话记录以 JSON 存在 App 私有目录；
只有你主动发送的对话内容会发往你自己配置的模型服务；API Key 存 Keychain，不随记录导出。

## 参考的开源实现与取舍

- **Apple Speech + AVSpeechSynthesizer 组合**（系统能力）：零依赖、离线可用、延迟低，
  因此识别与朗读优先用系统能力，只有「对话智能」交给大模型。
- **WhisperKit / whisper.cpp**：端侧 Whisper 识别质量更好、语种更全，但模型体积与首次加载成本高，
  这里留作后续可插拔的识别后端。
- **pipecat / LiveKit Agents**：语音 agent 的「ASR → LLM → TTS 流水线 + 可打断」设计，
  本项目的流式回复、逐句朗读、点麦克风即打断都是从这类实现借鉴的。
- **Apple Foundation Models（iOS 26+ 端侧模型）** 与 sherpa-onnx / Kokoro 类端侧 TTS：
  可让「全离线」版本成立，后续可作为 `TutorEngine` / `SpeechSynthesizer` 的另一种实现接入。
- 常见开源「AI 口语陪练」类 App 的通用做法：预设场景系统提示词 + 限制回复长度 + 温和纠错 +
  保存 transcript。本项目照此实现，并额外把「协议标签」做成可流式解析的紧凑格式，
  以便开口第一句就能朗读出来。
