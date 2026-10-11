//
//  Models.swift
//  AIAssistant
//
//  全局数据模型。全部使用 struct + Codable，方便落盘 / 读取，
//  避免引入任何第三方序列化库（iPhone 5s 上省内存、省启动时间）。
//

import Foundation

// MARK: - 消息

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

enum AttachmentKind: String, Codable {
    /// 图片（相册、拍照）
    case image
    /// 视频（相册、拍摄）—— 发送时抽帧为多张图片 + 可选音轨转写
    case video
    /// 语音（录音后转写为文字，原始音频仅本地保留）
    case audio
}

struct Attachment: Codable, Equatable {
    var id: String = UUID().uuidString
    var kind: AttachmentKind
    /// 相对 Documents 的路径，例如 "Attachments/xxx.jpg"
    var relativePath: String
    /// 缩略图相对路径（可空）
    var thumbnailRelativePath: String? = nil
    /// 视频抽出的关键帧（相对路径数组）
    var frameRelativePaths: [String] = []
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var durationSeconds: Double = 0
    /// 语音转写 / 视频音轨转写结果
    var transcript: String? = nil
    var byteSize: Int = 0

    var isVisual: Bool { kind == .image || kind == .video }

    /// 给模型看的一行摘要（放在文本里，帮助模型理解"这是什么"）
    var summaryLine: String {
        switch kind {
        case .image:
            return "[图片 \(pixelWidth)×\(pixelHeight)]"
        case .video:
            let secs = String(format: "%.1f", durationSeconds)
            return "[视频 \(secs) 秒，共提取 \(frameRelativePaths.count) 帧画面]"
        case .audio:
            return "[语音]"
        }
    }
}

struct ChatMessage: Codable, Equatable {
    var id: String = UUID().uuidString
    var role: MessageRole
    var text: String
    var attachments: [Attachment] = []
    var createdAt: Date = Date()
    var modelName: String? = nil
    /// 思维链（DeepSeek-R1 / Claude thinking 之类），仅展示用
    var reasoningText: String? = nil
    /// 仅用于内存态：正在流式输出
    var isStreaming: Bool = false
    /// 仅用于内存态：出错信息
    var errorText: String? = nil

    static func user(text: String, attachments: [Attachment] = []) -> ChatMessage {
        ChatMessage(role: .user, text: text, attachments: attachments)
    }

    static func assistant(text: String = "", streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, isStreaming: streaming)
    }
}

// MARK: - 会话

/// 会话摘要：列表页只加载这个，避免把全部历史都读进内存。
struct ConversationSummary: Codable, Equatable {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var preview: String
}

struct Conversation: Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerId: String?

    var summary: ConversationSummary {
        let lastUser = messages.last(where: { $0.role == .user })
        let lastAny = messages.last
        var preview = lastAny?.text ?? ""
        if preview.isEmpty, let att = lastAny?.attachments.first {
            preview = att.summaryLine
        }
        if let lu = lastUser, lu.id == lastAny?.id, !lu.attachments.isEmpty {
            preview = lu.attachments.map { $0.summaryLine }.joined() + " " + preview
        }
        preview = preview.replacingOccurrences(of: "\n", with: " ")
        return ConversationSummary(id: id,
                                   title: title,
                                   createdAt: createdAt,
                                   updatedAt: updatedAt,
                                   messageCount: messages.count,
                                   preview: String(preview.prefix(60)))
    }
}

// MARK: - API 服务配置

enum ProviderKind: String, Codable, CaseIterable {
    /// OpenAI 格式：DeepSeek / OpenAI / Moonshot / 通义 / 硅基流动 / Ollama / one-api …
    case openAICompatible
    /// Anthropic Claude Messages API 格式
    case anthropic

    var displayName: String {
        switch self {
        case .openAICompatible: return L10n.providerKindOpenAI
        case .anthropic: return L10n.providerKindAnthropic
        }
    }

    var defaultChatPath: String {
        switch self {
        case .openAICompatible: return "/v1/chat/completions"
        case .anthropic: return "/v1/messages"
        }
    }

    var shortBadge: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容"
        case .anthropic: return "Claude"
        }
    }
}

struct ProviderProfile: Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "DeepSeek"
    var kind: ProviderKind = .openAICompatible
    /// 例如 https://api.deepseek.com （不要带结尾斜杠）
    var baseURL: String = "https://api.deepseek.com"
    /// 例如 /v1/chat/completions
    var chatPath: String = ProviderKind.openAICompatible.defaultChatPath
    /// Key 只存在 Keychain，这里始终为空字符串
    var apiKey: String = ""
    var model: String = "deepseek-chat"
    var systemPrompt: String = L10n.defaultSystemPrompt
    var extraHeaders: [String: String] = [:]
    var supportsVision: Bool = true
    var streaming: Bool = true
    /// 发送图片时的 detail（auto / low / high），由图片压缩档位同步过来
    var imageDetail: String = "auto"
    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    /// 单次请求最多带几张图（5s 上建议 2~4）
    var maxImages: Int = 4

    var chatURL: URL? {
        Self.composeURL(base: baseURL, path: chatPath)
    }

    /// 宽进严出地拼 URL：baseURL 里已经带了 /v1 时不再重复添加。
    static func composeURL(base: String, path: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else { return nil }
        while b.hasSuffix("/") { b.removeLast() }
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return URL(string: b) }
        if !p.hasPrefix("/") { p = "/" + p }
        if b.hasSuffix("/v1"), p.hasPrefix("/v1/") {
            p = String(p.dropFirst(3))
        }
        return URL(string: b + p)
    }
}

// MARK: - 语音设置

enum TranscriberKind: String, Codable, CaseIterable {
    /// 走 OpenAI 兼容的 /v1/audio/transcriptions（Whisper 类服务）
    case openAICompatible
    /// 走 iOS 系统听写（iOS 12 上需要联网，由苹果服务器识别）
    case appleSpeech

    var displayName: String {
        switch self {
        case .openAICompatible: return L10n.transcriberServer
        case .appleSpeech: return L10n.transcriberApple
        }
    }
}

struct SpeechSettings: Codable, Equatable {
    var enabled: Bool = true
    var kind: TranscriberKind = .appleSpeech
    var baseURL: String = "https://api.openai.com"
    var path: String = "/v1/audio/transcriptions"
    /// Key 存 Keychain，这里始终为空
    var apiKey: String = ""
    var model: String = "whisper-1"
    /// 空字符串表示自动
    var language: String = "zh"
    /// 录音上限（秒）
    var maxDuration: Double = 60
    /// 识别出文字后直接发送
    var autoSendVoice: Bool = true

    var transcribeURL: URL? {
        ProviderProfile.composeURL(base: baseURL, path: path)
    }
}

// MARK: - 图片 / 视频 / 性能

struct ImageSettings: Codable, Equatable {
    /// 发送前把长边压到这个像素数
    var maxEdge: Int = 1024
    var jpegQuality: Double = 0.62
    /// OpenAI 的 detail 字段
    var detail: String = "auto"

    enum Quality: Int, CaseIterable {
        case saver = 0    // 省流量
        case standard = 1 // 标准
        case high = 2     // 高清

        var title: String {
            switch self {
            case .saver: return L10n.imageQualitySaver
            case .standard: return L10n.imageQualityStandard
            case .high: return L10n.imageQualityHigh
            }
        }

        var maxEdge: Int {
            switch self {
            case .saver: return 832
            case .standard: return 1024
            case .high: return 1440
            }
        }

        var jpegQuality: Double {
            switch self {
            case .saver: return 0.55
            case .standard: return 0.62
            case .high: return 0.75
            }
        }
    }

    var quality: Quality {
        get {
            if maxEdge <= 832 { return .saver }
            if maxEdge <= 1024 { return .standard }
            return .high
        }
        set {
            maxEdge = newValue.maxEdge
            jpegQuality = newValue.jpegQuality
        }
    }
}

enum AppTheme: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return L10n.themeSystem
        case .light: return L10n.themeLight
        case .dark: return L10n.themeDark
        }
    }
}

struct AppSettings: Codable, Equatable {
    var providers: [ProviderProfile] = AppSettings.builtinProviders
    var activeProviderId: String = AppSettings.builtinProviders[0].id
    var speech: SpeechSettings = SpeechSettings()
    var image: ImageSettings = ImageSettings()
    /// 视频发送时抽取多少帧（越多越耗流量/内存）
    var videoFrameCount: Int = 3
    /// 是否朗读助手回复（离线 TTS，不消耗接口额度）
    var ttsEnabled: Bool = false
    /// 低配机型模式：关掉多余动画、缩小缓存
    var performanceMode: Bool = true
    var theme: AppTheme = .system

    static var builtinProviders: [ProviderProfile] {
        var deepseek = ProviderProfile()
        deepseek.name = "DeepSeek"
        deepseek.baseURL = "https://api.deepseek.com"
        deepseek.chatPath = "/v1/chat/completions"
        deepseek.model = "deepseek-chat"
        deepseek.supportsVision = false

        var openai = ProviderProfile()
        openai.id = "builtin-openai"
        openai.name = "OpenAI"
        openai.baseURL = "https://api.openai.com"
        openai.chatPath = "/v1/chat/completions"
        openai.model = "gpt-4o-mini"

        var claude = ProviderProfile()
        claude.id = "builtin-claude"
        claude.name = "Claude"
        claude.kind = .anthropic
        claude.baseURL = "https://api.anthropic.com"
        claude.chatPath = ProviderKind.anthropic.defaultChatPath
        claude.model = "claude-3-5-sonnet-latest"

        var ollama = ProviderProfile()
        ollama.id = "builtin-ollama"
        ollama.name = "Ollama 本地"
        ollama.baseURL = "http://127.0.0.1:11434"
        ollama.chatPath = "/v1/chat/completions"
        ollama.model = "qwen2.5:7b"

        return [deepseek, openai, claude, ollama]
    }

    static var `default`: AppSettings { AppSettings() }

    func provider(id: String) -> ProviderProfile? {
        providers.first(where: { $0.id == id })
    }

    var activeProvider: ProviderProfile {
        provider(id: activeProviderId) ?? providers.first ?? AppSettings.builtinProviders[0]
    }
}
