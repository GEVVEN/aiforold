//
//  SettingsViewController.swift
//  AIAssistant
//
//  设置页：换 API（DeepSeek / OpenAI / Claude / 通义 / Ollama / one-api 任意兼容网关）、
//  改模型与参数、配语音转写、图片压缩、主题与性能。
//  表单由 FormKit 声明式渲染，这里只描述"有哪些项"。
//
//  写入策略：文本框改动先落到内存 working 副本，0.8 秒无输入后再落盘
//  （避免每敲一个字符就写一次 Keychain）；开关 / 选择类立即落盘。
//

import UIKit

final class SettingsViewController: FormViewController {

    /// 服务或参数变化后通知聊天页刷新标题
    var onProviderChanged: (() -> Void)?

    private var workingProvider = SettingsStore.shared.activeProvider
    private var workingSpeech = SettingsStore.shared.settings.speech
    private var persistTimer: Timer?
    private var didSetup = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        title = L10n.settingsTitle
        super.viewDidLoad()
        buildSections = { [weak self] in self?.makeSections() ?? [] }
        reloadForm()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushPersist()
    }

    deinit {
        persistTimer?.invalidate()
    }

    // MARK: - 落盘

    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.flushPersist()
        }
    }

    private func flushPersist() {
        persistTimer?.invalidate()
        persistTimer = nil

        let provider = workingProvider
        let speech = workingSpeech
        var activeId = provider.id

        SettingsStore.shared.update { settings in
            if let index = settings.providers.firstIndex(where: { $0.id == provider.id }) {
                settings.providers[index] = provider
            } else {
                var copy = provider
                if copy.id.isEmpty { copy.id = UUID().uuidString }
                settings.providers.append(copy)
                activeId = copy.id
            }
            settings.providers = settings.providers.filter { !$0.id.isEmpty }
            settings.speech = speech
            settings.activeProviderId = activeId
        }
        workingProvider = SettingsStore.shared.settings.activeProvider
        workingSpeech = SettingsStore.shared.settings.speech
        onProviderChanged?()
    }

    // MARK: - 表单

    private func makeSections() -> [FormSection] {
        var sections: [FormSection] = []
        sections.append(serviceSection())
        sections.append(providerSection())
        sections.append(modelSection())
        sections.append(speechSection())
        sections.append(mediaSection())
        sections.append(appearanceSection())
        sections.append(aboutSection())
        return sections
    }

    // MARK: API 服务

    private func serviceSection() -> FormSection {
        let activeId = SettingsStore.shared.settings.activeProviderId
        var rows: [FormRow] = []

        for provider in SettingsStore.shared.settings.providers {
            let isActive = provider.id == activeId
            let title = isActive ? "\(provider.name)（使用中）" : provider.name
            let value = provider.model.isEmpty ? L10n.notConfigured : provider.model
            rows.append(.detail(title: title, value: value, onTap: { [weak self] in
                self?.selectProvider(id: provider.id)
            }))
        }

        rows.append(.action(title: "＋ " + L10n.addService, style: .accent, onTap: { [weak self] in
            self?.addProvider()
        }))

        return FormSection(title: L10n.sectionService,
                           footer: "点选即可切换当前服务；想改参数，先切到它，再到下面修改。",
                           rows: rows)
    }

    private func selectProvider(id: String) {
        flushPersist()
        SettingsStore.shared.setActiveProvider(id: id)
        workingProvider = SettingsStore.shared.activeProvider
        reloadForm()
        onProviderChanged?()
    }

    private func addProvider() {
        flushPersist()
        var provider = AppSettings.builtinProviders[0]
        provider.id = UUID().uuidString
        provider.name = "新服务"
        provider.apiKey = ""
        SettingsStore.shared.upsertProvider(provider)
        SettingsStore.shared.setActiveProvider(id: provider.id)
        workingProvider = SettingsStore.shared.activeProvider
        reloadForm()
        onProviderChanged?()
    }

    // MARK: 当前服务参数

    private func providerSection() -> FormSection {
        var rows: [FormRow] = []

        rows.append(.text(title: L10n.serviceName,
                          value: workingProvider.name,
                          placeholder: "例如 Kimi / 本地 Ollama",
                          secure: false,
                          keyboard: .default,
                          autocapitalization: .none,
                          onChange: { [weak self] value in
                              self?.workingProvider.name = value
                              self?.schedulePersist()
                          }))

        rows.append(.detail(title: L10n.serviceKind,
                            value: workingProvider.kind.displayName,
                            onTap: { [weak self] in self?.chooseKind() }))

        rows.append(.text(title: L10n.baseURL,
                          value: workingProvider.baseURL,
                          placeholder: "https://api.deepseek.com",
                          secure: false,
                          keyboard: .URL,
                          autocapitalization: .none,
                          onChange: { [weak self] value in
                              self?.workingProvider.baseURL = value.trimmingCharacters(in: .whitespaces)
                              self?.schedulePersist()
                          }))

        rows.append(.text(title: L10n.chatPath,
                          value: workingProvider.chatPath,
                          placeholder: workingProvider.kind.defaultChatPath,
                          secure: false,
                          keyboard: .URL,
                          autocapitalization: .none,
                          onChange: { [weak self] value in
                              self?.workingProvider.chatPath = value.trimmingCharacters(in: .whitespaces)
                              self?.schedulePersist()
                          }))

        rows.append(.text(title: L10n.apiKey,
                          value: workingProvider.apiKey,
                          placeholder: L10n.apiKeyPlaceholder,
                          secure: true,
                          keyboard: .default,
                          autocapitalization: .none,
                          onChange: { [weak self] value in
                              self?.workingProvider.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                              self?.schedulePersist()
                          }))

        rows.append(.text(title: L10n.model,
                          value: workingProvider.model,
                          placeholder: "deepseek-chat / gpt-4o-mini / qwen2.5:7b",
                          secure: false,
                          keyboard: .default,
                          autocapitalization: .none,
                          onChange: { [weak self] value in
                              self?.workingProvider.model = value.trimmingCharacters(in: .whitespaces)
                              self?.schedulePersist()
                          }))

        rows.append(.longText(title: L10n.systemPrompt,
                              value: workingProvider.systemPrompt,
                              placeholder: L10n.defaultSystemPrompt,
                              minHeight: 96,
                              onChange: { [weak self] value in
                                  self?.workingProvider.systemPrompt = value
                                  self?.schedulePersist()
                              }))

        rows.append(.longText(title: L10n.extraHeaders,
                              value: Self.headersText(workingProvider.extraHeaders),
                              placeholder: "X-Api-Version: 2024-01-01",
                              minHeight: 66,
                              onChange: { [weak self] value in
                                  self?.workingProvider.extraHeaders = Self.parseHeaders(value)
                                  self?.schedulePersist()
                              }))

        if workingProvider.apiKey.trimmingCharacters(in: .whitespaces).isEmpty,
           !workingProvider.baseURL.contains("127.0.0.1"),
           !workingProvider.baseURL.contains("localhost") {
            rows.append(.note(text: "提示：还没填 API Key，填好后点下面的「测试连接」验证一下。"))
        }

        rows.append(.action(title: L10n.test, style: .accent, onTap: { [weak self] in
            self?.testConnection()
        }))

        if SettingsStore.shared.settings.providers.count > 1 {
            rows.append(.action(title: "删除当前服务", style: .destructive, onTap: { [weak self] in
                self?.deleteCurrentProvider()
            }))
        }

        return FormSection(title: "当前服务：\(workingProvider.name)",
                           footer: "Base URL 直接填到域名即可；如果服务商要求 /v1 前缀，这里也支持。",
                           rows: rows)
    }

    private func chooseKind() {
        let sheet = UIAlertController(title: L10n.serviceKind, message: nil, preferredStyle: .actionSheet)
        for kind in ProviderKind.allCases {
            sheet.addAction(UIAlertAction(title: kind.displayName, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                let previousDefault = self.workingProvider.kind.defaultChatPath
                self.workingProvider.kind = kind
                if self.workingProvider.chatPath.isEmpty || self.workingProvider.chatPath == previousDefault {
                    self.workingProvider.chatPath = kind.defaultChatPath
                }
                self.flushPersist()
                self.reloadForm()
            }))
        }
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private func deleteCurrentProvider() {
        let alert = UIAlertController(title: "删除当前服务？",
                                      message: workingProvider.name,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak self] _ in
            guard let self = self else { return }
            SettingsStore.shared.deleteProvider(id: self.workingProvider.id)
            self.workingProvider = SettingsStore.shared.activeProvider
            self.reloadForm()
            self.onProviderChanged?()
        }))
        present(alert, animated: true, completion: nil)
    }

    private func testConnection() {
        persistTimer?.invalidate()
        persistTimer = nil
        view.endEditing(true)

        // 用一份临时配置测试，不污染当前设置
        var probe = workingProvider
        if probe.model.isEmpty { probe.model = "deepseek-chat" }
        Toast.show(L10n.testSending)
        ChatService.shared.test(profile: probe) { [weak self] result in
            switch result {
            case .success(let text):
                let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.showAlert(title: L10n.testSuccess,
                                message: preview.isEmpty ? "服务正常响应" : preview)
            case .failure(let error):
                self?.showAlert(title: L10n.testFailed, message: error.message)
            }
        }
    }

    // MARK: 模型参数

    private func modelSection() -> FormSection {
        var rows: [FormRow] = []

        rows.append(.toggle(title: L10n.supportsVision,
                            subtitle: "关闭后不再上传图片，只发文字描述",
                            value: workingProvider.supportsVision,
                            onChange: { [weak self] value in
                                self?.workingProvider.supportsVision = value
                                self?.flushPersist()
                                self?.reloadForm()
                            }))

        rows.append(.toggle(title: L10n.streaming,
                            subtitle: "关闭则等全部生成完再显示",
                            value: workingProvider.streaming,
                            onChange: { [weak self] value in
                                self?.workingProvider.streaming = value
                                self?.flushPersist()
                            }))

        rows.append(.slider(title: L10n.temperature,
                            value: workingProvider.temperature,
                            min: 0,
                            max: 2,
                            step: 0.1,
                            format: { String(format: "%.1f", $0) },
                            onChange: { [weak self] value in
                                self?.workingProvider.temperature = value
                                self?.schedulePersist()
                            }))

        rows.append(.slider(title: L10n.maxTokens,
                            value: Double(workingProvider.maxTokens),
                            min: 256,
                            max: 8192,
                            step: 256,
                            format: { "\(Int($0))" },
                            onChange: { [weak self] value in
                                self?.workingProvider.maxTokens = Int(value)
                                self?.schedulePersist()
                            }))

        rows.append(.slider(title: L10n.maxImages,
                            value: Double(workingProvider.maxImages),
                            min: 1,
                            max: 6,
                            step: 1,
                            format: { "\(Int($0)) 张" },
                            onChange: { [weak self] value in
                                self?.workingProvider.maxImages = Int(value)
                                self?.schedulePersist()
                            }))

        return FormSection(title: L10n.sectionModel,
                           footer: "不同服务商支持的参数不完全一样，报错就先把 max_tokens 调小试试。",
                           rows: rows)
    }

    // MARK: 语音

    private func speechSection() -> FormSection {
        var rows: [FormRow] = []

        rows.append(.toggle(title: L10n.speechEnabled,
                            subtitle: "关掉后输入栏不再显示「按住说话」",
                            value: workingSpeech.enabled,
                            onChange: { [weak self] value in
                                self?.workingSpeech.enabled = value
                                self?.flushPersist()
                                self?.reloadForm()
                            }))

        rows.append(.detail(title: L10n.speechKind,
                            value: workingSpeech.kind.displayName,
                            onTap: { [weak self] in self?.chooseTranscriber() }))

        rows.append(.toggle(title: L10n.voiceAutoSend,
                            subtitle: "识别完直接发出，不用再点发送",
                            value: workingSpeech.autoSendVoice,
                            onChange: { [weak self] value in
                                self?.workingSpeech.autoSendVoice = value
                                self?.flushPersist()
                            }))

        if workingSpeech.kind == .openAICompatible {
            rows.append(.text(title: "转写 Base URL",
                              value: workingSpeech.baseURL,
                              placeholder: "https://api.openai.com",
                              secure: false,
                              keyboard: .URL,
                              autocapitalization: .none,
                              onChange: { [weak self] value in
                                  self?.workingSpeech.baseURL = value.trimmingCharacters(in: .whitespaces)
                                  self?.schedulePersist()
                              }))
            rows.append(.text(title: "转写路径",
                              value: workingSpeech.path,
                              placeholder: "/v1/audio/transcriptions",
                              secure: false,
                              keyboard: .URL,
                              autocapitalization: .none,
                              onChange: { [weak self] value in
                                  self?.workingSpeech.path = value.trimmingCharacters(in: .whitespaces)
                                  self?.schedulePersist()
                              }))
            rows.append(.text(title: "转写 API Key",
                              value: workingSpeech.apiKey,
                              placeholder: L10n.apiKeyPlaceholder,
                              secure: true,
                              keyboard: .default,
                              autocapitalization: .none,
                              onChange: { [weak self] value in
                                  self?.workingSpeech.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                  self?.schedulePersist()
                              }))
            rows.append(.text(title: L10n.speechModel,
                              value: workingSpeech.model,
                              placeholder: "whisper-1",
                              secure: false,
                              keyboard: .default,
                              autocapitalization: .none,
                              onChange: { [weak self] value in
                                  self?.workingSpeech.model = value.trimmingCharacters(in: .whitespaces)
                                  self?.schedulePersist()
                              }))
        }

        rows.append(.detail(title: L10n.speechLanguage,
                            value: Self.languageTitle(workingSpeech.language),
                            onTap: { [weak self] in self?.chooseLanguage() }))

        rows.append(.slider(title: L10n.speechMaxDuration,
                            value: workingSpeech.maxDuration,
                            min: 10,
                            max: 180,
                            step: 10,
                            format: { "\(Int($0)) 秒" },
                            onChange: { [weak self] value in
                                self?.workingSpeech.maxDuration = value
                                self?.schedulePersist()
                            }))

        return FormSection(title: L10n.sectionSpeech,
                           footer: "iOS 12 的系统听写必须联网；如果识别不稳，建议切到服务器转写（Whisper 类接口）。",
                           rows: rows)
    }

    private func chooseTranscriber() {
        let sheet = UIAlertController(title: L10n.speechKind, message: nil, preferredStyle: .actionSheet)
        for kind in TranscriberKind.allCases {
            sheet.addAction(UIAlertAction(title: kind.displayName, style: .default, handler: { [weak self] _ in
                self?.workingSpeech.kind = kind
                self?.flushPersist()
                self?.reloadForm()
            }))
        }
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private func chooseLanguage() {
        let options: [(String, String)] = [("zh", "中文"), ("en", "English"), ("", "自动检测")]
        let sheet = UIAlertController(title: L10n.speechLanguage, message: nil, preferredStyle: .actionSheet)
        for (value, title) in options {
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.workingSpeech.language = value
                self?.flushPersist()
                self?.reloadForm()
            }))
        }
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private static func languageTitle(_ value: String) -> String {
        switch value {
        case "": return "自动检测"
        case "zh": return "中文"
        case "en": return "English"
        default: return value
        }
    }

    // MARK: 图片与视频

    private func mediaSection() -> FormSection {
        let settings = SettingsStore.shared.settings
        var rows: [FormRow] = []

        rows.append(.detail(title: L10n.imageQuality,
                            value: settings.image.quality.title,
                            onTap: { [weak self] in self?.chooseQuality() }))

        rows.append(.slider(title: L10n.videoFrames,
                            value: Double(settings.videoFrameCount),
                            min: 1,
                            max: 6,
                            step: 1,
                            format: { "\(Int($0)) 帧" },
                            onChange: { value in
                                SettingsStore.shared.update { $0.videoFrameCount = Int(value) }
                            }))

        rows.append(.action(title: L10n.clearCaches, style: .normal, onTap: { [weak self] in
            ImagePipeline.shared.clearCaches()
            ConversationStore.shared.purgeOrphanAttachments()
            Toast.show(L10n.cachesCleared)
            self?.reloadForm()
        }))

        return FormSection(title: L10n.sectionMedia,
                           footer: "iPhone 5s 建议保持「省流量」：图片长边 832px，视频只抽 3 帧。",
                           rows: rows)
    }

    private func chooseQuality() {
        let sheet = UIAlertController(title: L10n.imageQuality, message: nil, preferredStyle: .actionSheet)
        for quality in ImageSettings.Quality.allCases {
            let title = "\(quality.title)（长边 \(quality.maxEdge)px）"
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                SettingsStore.shared.applyQuality(quality)
                self?.reloadForm()
            }))
        }
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    // MARK: 外观与性能

    private func appearanceSection() -> FormSection {
        let settings = SettingsStore.shared.settings
        var rows: [FormRow] = []

        rows.append(.detail(title: L10n.theme,
                            value: settings.theme.title,
                            onTap: { [weak self] in self?.chooseTheme() }))

        rows.append(.toggle(title: L10n.performanceMode,
                            subtitle: L10n.performanceModeHint,
                            value: settings.performanceMode,
                            onChange: { value in
                                SettingsStore.shared.update { $0.performanceMode = value }
                            }))

        rows.append(.toggle(title: L10n.ttsEnabled,
                            subtitle: "用系统语音朗读回复，离线、不花额度",
                            value: settings.ttsEnabled,
                            onChange: { value in
                                SettingsStore.shared.update { $0.ttsEnabled = value }
                                if !value { SpeechPlayer.shared.stop() }
                            }))

        return FormSection(title: L10n.sectionAppearance, footer: nil, rows: rows)
    }

    private func chooseTheme() {
        let sheet = UIAlertController(title: L10n.theme, message: nil, preferredStyle: .actionSheet)
        for theme in AppTheme.allCases {
            sheet.addAction(UIAlertAction(title: theme.title, style: .default, handler: { [weak self] _ in
                SettingsStore.shared.update { $0.theme = theme }
                Theme.apply(theme)
                NotificationCenter.default.post(name: .appThemeDidChange, object: nil)
                self?.applyTheme()
                self?.reloadForm()
            }))
        }
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    // MARK: 关于

    private func aboutSection() -> FormSection {
        var rows: [FormRow] = []

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        rows.append(.detail(title: L10n.version, value: "\(version) (\(build))", onTap: {}))

        rows.append(.detail(title: L10n.storageUsage,
                            value: ConversationStore.shared.formattedStorageUsage(),
                            onTap: {}))

        rows.append(.note(text: L10n.aboutHint))

        rows.append(.action(title: L10n.clearHistory, style: .destructive, onTap: { [weak self] in
            self?.confirmClearAll()
        }))

        return FormSection(title: L10n.sectionAbout, footer: nil, rows: rows)
    }

    private func confirmClearAll() {
        let alert = UIAlertController(title: L10n.clearHistory,
                                      message: L10n.clearHistoryConfirm,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak self] _ in
            ConversationStore.shared.deleteAll()
            Toast.show(L10n.done)
            self?.reloadForm()
        }))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - 工具

    private func presentSheet(_ sheet: UIAlertController) {
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true, completion: nil)
    }

    private static func headersText(_ headers: [String: String]) -> String {
        return headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { result[key] = value }
        }
        return result
    }
}
