//
//  ChatViewController.swift
//  AIAssistant
//
//  聊天主界面。负责：
//    * 消息列表（列表 / 气泡 / 附件缩略图）
//    * 发送文字 / 图片 / 视频 / 语音，流式接收回复
//    * 按住说话（含上滑取消）、拍照 / 相册 / 拍视频
//    * 键盘避让、滚动到底、长按复制、朗读
//
//  性能取舍（iPhone 5s 1GB 内存 / A7 双核）：
//    * 流式输出用 0.12s 节流刷新，且期间只渲染纯文本；
//    * 图片一律走缩略图缓存，发送前先压到长边 1024（可调）；
//    * 录音 16kHz / 32kbps，视频只抽 3 帧。
//

import UIKit
import AVFoundation
import Photos

final class ChatViewController: UIViewController {

    // MARK: - 状态

    private var conversation: Conversation
    private let isNewConversation: Bool

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = ComposerView()
    private let emptyStateLabel = UILabel()
    private let scrollToBottomButton = UIButton(type: .system)
    private let recordOverlay = RecordOverlayView()
    private var composerBottom: NSLayoutConstraint!

    private var streamBuffer = ""
    private var reasoningBuffer = ""
    private var flushTimer: Timer?
    private var recordTimer: Timer?
    private var streamingMessageID: String?
    private var isVoicePressActive = false
    private var keyboardOverlap: CGFloat = 0
    private var isNearBottom = true
    /// 自己维护"正在批量更新"的状态：不依赖 UITableView 上不保证公开的 isUpdating
    private var isBatchUpdatingTable = false

    // MARK: - 初始化

    init(conversationId: String?) {
        if let id = conversationId, let loaded = ConversationStore.shared.loadConversation(id: id) {
            conversation = loaded
            isNewConversation = false
        } else {
            conversation = Conversation()
            isNewConversation = true
        }
        super.init(nibName: nil, bundle: nil)
        if conversation.providerId == nil {
            conversation.providerId = SettingsStore.shared.settings.activeProviderId
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        flushTimer?.invalidate()
        recordTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigation()
        setupTable()
        setupComposer()
        setupEmptyState()
        setupScrollButton()
        observeNotifications()
        applyTheme()
        updateEmptyState()
        // 进来就在底部
        DispatchQueue.main.async { [weak self] in
            self?.scrollToBottom(animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SpeechPlayer.shared.stop()
        if isMovingFromParent || isBeingDismissed {
            // 走之前把流式结果收尾，避免历史里留下一条空回复
            finalizeStreamingBeforeLeaving()
            ChatService.shared.cancel(silently: true)
        }
    }

    private func finalizeStreamingBeforeLeaving() {
        guard let id = streamingMessageID,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text = streamBuffer
        if !reasoningBuffer.isEmpty {
            conversation.messages[index].reasoningText = reasoningBuffer
        }
        conversation.messages[index].isStreaming = false
        if conversation.messages[index].text.isEmpty && conversation.messages[index].reasoningText == nil {
            conversation.messages.remove(at: index)
        } else {
            // 半截回复不能当成完整回答存进历史：标记出来，回来还能点「重试」
            conversation.messages[index].errorText = APIError.cancelled.message
        }
        streamingMessageID = nil
        flushTimer?.invalidate()
        flushTimer = nil
        composer.isGenerating = false
        persist()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        composer.setBottomInset(keyboardOverlap > 0 ? 8 : 8 + view.safeAreaInsets.bottom)
    }

    // MARK: - 界面搭建

    private func setupNavigation() {
        navigationItem.title = conversation.title
        let gear = UIBarButtonItem(image: Icon.gear.barButtonImage(), style: .plain,
                                   target: self, action: #selector(openSettings))
        navigationItem.rightBarButtonItem = gear
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Theme.current.background
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 96
        tableView.rowHeight = UITableView.automaticDimension
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.addSubview(tableView)
    }

    private func setupComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        view.addSubview(composer)

        composerBottom = composer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottom,

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyStateLabel.text = L10n.emptyChatHint
        emptyStateLabel.font = Theme.footnote
        emptyStateLabel.textColor = Theme.current.tertiaryText
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(emptyStateLabel, aboveSubview: tableView)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7)
        ])
    }

    private func setupScrollButton() {
        scrollToBottomButton.setImage(Icon.chevronDown.image(size: 18, color: Theme.current.secondaryText),
                                      for: .normal)
        scrollToBottomButton.backgroundColor = Theme.current.surface
        scrollToBottomButton.roundCorners(16)
        scrollToBottomButton.layer.borderWidth = Theme.hairline
        scrollToBottomButton.layer.borderColor = Theme.current.divider.cgColor
        scrollToBottomButton.alpha = 0
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomTapped), for: .touchUpInside)
        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollToBottomButton)
        NSLayoutConstraint.activate([
            scrollToBottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -12),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 32),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeChanged),
                                               name: .appThemeDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: .appSettingsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    @objc private func applyTheme() {
        let palette = Theme.current
        view.backgroundColor = palette.background
        tableView.backgroundColor = palette.background
        emptyStateLabel.textColor = palette.tertiaryText
        scrollToBottomButton.backgroundColor = palette.surface
        scrollToBottomButton.layer.borderColor = palette.divider.cgColor
        scrollToBottomButton.setImage(Icon.chevronDown.image(size: 18, color: palette.secondaryText), for: .normal)
        navigationItem.rightBarButtonItem?.image = Icon.gear.barButtonImage(color: palette.accent)
        composer.applyTheme()
        tableView.reloadData()
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    @objc private func settingsChanged() {
        // 切换服务后，把新模型名提示到输入框占位里
        navigationItem.title = conversation.title
    }

    // MARK: - 键盘

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        guard abs(overlap - keyboardOverlap) > 0.5 else { return }
        keyboardOverlap = overlap
        composerBottom.constant = -overlap
        // 键盘弹起时不需要再给 Home Indicator 留位，否则会多出一段空隙
        composer.setBottomInset(overlap > 0 ? 8 : 8 + view.safeAreaInsets.bottom)
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
        if isNearBottom { scrollToBottom(animated: true) }
    }

    @objc private func keyboardWillHide() {
        keyboardOverlap = 0
        composerBottom.constant = 0
        composer.setBottomInset(8 + view.safeAreaInsets.bottom)
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - 滚动

    private func scrollToBottom(animated: Bool) {
        let rows = tableView.numberOfRows(inSection: 0)
        guard rows > 0 else { return }
        let indexPath = IndexPath(row: rows - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    @objc private func scrollToBottomTapped() {
        isNearBottom = true
        scrollToBottom(animated: true)
    }

    private func updateScrollButton() {
        let target: CGFloat = isNearBottom ? 0 : 1
        guard abs(scrollToBottomButton.alpha - target) > 0.01 else { return }
        UIView.animate(withDuration: 0.15) {
            self.scrollToBottomButton.alpha = target
        }
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !conversation.messages.isEmpty
    }

    // MARK: - 发送

    private func sendCurrentInput() {
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = composer.attachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard !ChatService.shared.isBusy else {
            Toast.show(L10n.busyGenerating)
            return
        }

        let provider = SettingsStore.shared.activeProvider
        if !provider.supportsVision, attachments.contains(where: { $0.isVisual }) {
            Toast.show(L10n.visionOffHint)
        }

        let userMessage = ChatMessage.user(text: text, attachments: attachments)
        var assistant = ChatMessage.assistant(streaming: true)
        assistant.modelName = provider.model

        conversation.messages.append(userMessage)
        conversation.messages.append(assistant)
        conversation.providerId = provider.id
        streamingMessageID = assistant.id
        streamBuffer = ""
        reasoningBuffer = ""

        composer.clearInput()
        composer.removeAllAttachments()
        composer.isGenerating = true

        persist()
        updateEmptyState()
        tableView.reloadData()
        scrollToBottom(animated: true)
        startFlushTimer()

        let payload = conversation.messages.filter { $0.id != assistant.id }
        ChatService.shared.send(messages: payload, profile: provider, onDelta: { [weak self] delta in
            self?.handle(delta: delta)
        }, onFinish: { [weak self] error in
            self?.finishStreaming(error: error)
        })
    }

    private func handle(delta: StreamDelta) {
        switch delta.kind {
        case .text:
            streamBuffer += delta.value
        case .reasoning:
            reasoningBuffer += delta.value
        case .done:
            break
        case .failure:
            break
        case .ignored:
            break
        }
    }

    private func startFlushTimer() {
        flushTimer?.invalidate()
        // 5s / A7：0.25s 刷新一次已经足够"打字机"观感，布局次数只有 0.1s 方案的 40%
        let interval: TimeInterval = SettingsStore.shared.settings.performanceMode ? 0.25 : 0.12
        flushTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.applyStreamBuffer()
        }
    }

    /// 把缓冲区里的增量合入消息并刷新"正在输出的那一个" cell
    private func applyStreamBuffer() {
        guard let id = streamingMessageID,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }

        let newText = streamBuffer
        let newReasoning = reasoningBuffer
        guard conversation.messages[index].text != newText
            || conversation.messages[index].reasoningText != newReasoning else { return }

        conversation.messages[index].text = newText
        if !newReasoning.isEmpty {
            conversation.messages[index].reasoningText = newReasoning
        }

        let indexPath = IndexPath(row: index, section: 0)

        // 正在输出的 cell 不在屏幕上：整行刷新一次就够（此时用户没在看它）
        guard let cell = tableView.cellForRow(at: indexPath) as? ChatMessageCell else {
            if !isBatchUpdatingTable {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
            if isNearBottom { scrollToBottom(animated: false) }
            return
        }

        cell.configure(with: conversation.messages[index], streaming: true)

        // 让自适应高度重新计算。每次刷新都必须量一次，
        // 否则气泡高度会落后于文字，出现"文字被裁掉"的观感；
        // 代价用更稀的刷新频率（低配模式 0.25s）来平衡。
        if !isBatchUpdatingTable {
            isBatchUpdatingTable = true
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
            isBatchUpdatingTable = false
        }
        if isNearBottom { scrollToBottom(animated: false) }
    }

    private func finishStreaming(error: APIError?) {
        flushTimer?.invalidate()
        flushTimer = nil
        composer.isGenerating = false

        guard let id = streamingMessageID,
              let index = conversation.messages.firstIndex(where: { $0.id == id }) else {
            streamingMessageID = nil
            return
        }
        streamingMessageID = nil

        conversation.messages[index].text = streamBuffer
        if !reasoningBuffer.isEmpty {
            conversation.messages[index].reasoningText = reasoningBuffer
        }
        conversation.messages[index].isStreaming = false

        if let error = error {
            if error.isCancelled {
                if conversation.messages[index].text.isEmpty && conversation.messages[index].reasoningText == nil {
                    conversation.messages.remove(at: index)
                }
            } else {
                conversation.messages[index].errorText = error.message
                Toast.error(error.message)
            }
        } else if conversation.messages[index].text.isEmpty
                    && (conversation.messages[index].reasoningText?.isEmpty ?? true) {
            conversation.messages[index].errorText = L10n.emptyReply
        }

        persist()
        tableView.reloadData()
        if isNearBottom { scrollToBottom(animated: true) }

        if error == nil, SettingsStore.shared.settings.ttsEnabled {
            let content = conversation.messages.first(where: { $0.id == id })?.text ?? ""
            let spoken = conversation.messages.first(where: { $0.id == id })?.reasoningText ?? ""
            SpeechPlayer.shared.speak(MarkdownLite.plain(content.isEmpty ? spoken : content))
        }
    }

    private func persist() {
        ConversationStore.shared.save(conversation)
        if !isNewConversation || !conversation.messages.isEmpty {
            navigationItem.title = conversation.title
        }
    }

    // MARK: - 重试

    private func retryMessage(at indexPath: IndexPath) {
        guard indexPath.row < conversation.messages.count,
              conversation.messages[indexPath.row].role == .assistant else { return }
        guard !ChatService.shared.isBusy else { return }

        // 找到这条回复之前最近的用户消息
        var userIndex: Int?
        var cursor = indexPath.row - 1
        while cursor >= 0 {
            if conversation.messages[cursor].role == .user {
                userIndex = cursor
                break
            }
            cursor -= 1
        }
        guard let lastUserIndex = userIndex else { return }

        conversation.messages.removeSubrange((lastUserIndex + 1)...indexPath.row)

        let provider = SettingsStore.shared.activeProvider
        var assistant = ChatMessage.assistant(streaming: true)
        assistant.modelName = provider.model
        conversation.messages.append(assistant)
        streamingMessageID = assistant.id
        streamBuffer = ""
        reasoningBuffer = ""

        composer.isGenerating = true
        tableView.reloadData()
        scrollToBottom(animated: true)
        startFlushTimer()

        let payload = Array(conversation.messages.prefix(lastUserIndex + 1))
        ChatService.shared.send(messages: payload, profile: provider, onDelta: { [weak self] delta in
            self?.handle(delta: delta)
        }, onFinish: { [weak self] error in
            self?.finishStreaming(error: error)
        })
    }

    // MARK: - 附件

    private func presentAttachmentSheet() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.attachCamera, style: .default, handler: { [weak self] _ in
            self?.presentCamera(mediaType: "public.image")
        }))
        sheet.addAction(UIAlertAction(title: L10n.attachCameraVideo, style: .default, handler: { [weak self] _ in
            self?.presentCamera(mediaType: "public.movie")
        }))
        sheet.addAction(UIAlertAction(title: L10n.attachPhotoLibrary, style: .default, handler: { [weak self] _ in
            self?.presentLibrary(mediaType: "public.image")
        }))
        sheet.addAction(UIAlertAction(title: L10n.attachVideoLibrary, style: .default, handler: { [weak self] _ in
            self?.presentLibrary(mediaType: "public.movie")
        }))
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))

        if Theme.isCompactWidth() == false, let popover = sheet.popoverPresentationController {
            popover.sourceView = composer
            popover.sourceRect = composer.bounds
        }
        present(sheet, animated: true, completion: nil)
    }

    private func presentCamera(mediaType: String) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            Toast.show(L10n.noCamera)
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showPicker(source: .camera, mediaType: mediaType)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.showPicker(source: .camera, mediaType: mediaType)
                    } else {
                        self?.alertPermission(L10n.cameraPermissionDenied)
                    }
                }
            }
        default:
            alertPermission(L10n.cameraPermissionDenied)
        }
    }

    private func presentLibrary(mediaType: String) {
        let status: PHAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        if isLibraryAuthorized(status) {
            showPicker(source: .photoLibrary, mediaType: mediaType)
            return
        }

        if status == .notDetermined {
            let handler: (PHAuthorizationStatus) -> Void = { [weak self] newStatus in
                DispatchQueue.main.async {
                    if self?.isLibraryAuthorized(newStatus) == true {
                        self?.showPicker(source: .photoLibrary, mediaType: mediaType)
                    } else {
                        self?.alertPermission(L10n.photoPermissionDenied)
                    }
                }
            }
            if #available(iOS 14.0, *) {
                PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
            } else {
                PHPhotoLibrary.requestAuthorization(handler)
            }
            return
        }

        alertPermission(L10n.photoPermissionDenied)
    }

    /// .limited（iOS 14 的"选中的照片"）也要放行，且必须用 #available 包住
    private func isLibraryAuthorized(_ status: PHAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 14.0, *), status == .limited { return true }
        return false
    }

    private func showPicker(source: UIImagePickerController.SourceType, mediaType: String) {
        guard UIImagePickerController.isSourceTypeAvailable(source) else {
            Toast.show(L10n.sourceUnavailable)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.mediaTypes = [mediaType]
        picker.allowsEditing = false
        picker.delegate = self
        if source == .camera, mediaType == "public.movie" {
            picker.videoQuality = .typeMedium   // 5s 存储 / 上传都省一点
            picker.cameraCaptureMode = .video
        }
        presentFullScreen(picker)
    }

    private func alertPermission(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.goToSettings, style: .default, handler: { [weak self] _ in
            self?.openSystemSettings()
        }))
        present(alert, animated: true, completion: nil)
    }

    private func processImage(_ image: UIImage) {
        let settings = SettingsStore.shared.settings.image
        Toast.show(L10n.attachCompressing)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 先把 UIImage 转成 JPEG 数据，再交给 ImageIO 做"解码即缩放"：
            // 这样不会出现"全尺寸位图 + 全尺寸绘制上下文"同时在内存里的情况。
            let attachment: Attachment?
            if let data = ImagePipeline.jpegData(from: image, quality: 0.95) {
                attachment = ImagePipeline.shared.processPickedImageData(data, settings: settings)
                    ?? ImagePipeline.shared.processPickedImage(image, settings: settings)
            } else {
                attachment = ImagePipeline.shared.processPickedImage(image, settings: settings)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let attachment = attachment {
                    self.composer.addAttachment(attachment)
                } else {
                    Toast.error(L10n.imageProcessFailed)
                }
            }
        }
    }

    /// 相册/相机给的是文件 URL 时，读盘也放到后台，别在主线程读几 MB
    private func processImageFile(_ url: URL) {
        Toast.show(L10n.attachCompressing)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data {
                    self.processImageData(data)
                } else {
                    Toast.error(L10n.imageProcessFailed)
                }
            }
        }
    }

    private func processImageData(_ data: Data) {
        let settings = SettingsStore.shared.settings.image
        Toast.show(L10n.attachCompressing)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let attachment = ImagePipeline.shared.processPickedImageData(data, settings: settings)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let attachment = attachment {
                    self.composer.addAttachment(attachment)
                } else {
                    Toast.error(L10n.imageProcessFailed)
                }
            }
        }
    }

    private func processVideo(_ url: URL) {
        let settings = SettingsStore.shared.settings.image
        let frameCount = SettingsStore.shared.settings.videoFrameCount
        Toast.show(L10n.attachProcessingVideo)
        VideoPipeline.shared.process(videoURL: url, frameCount: frameCount, settings: settings) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                Toast.error(error.message)
            case .success(let processed):
                var attachment = processed.attachment
                if let audioURL = processed.audioURL,
                   SettingsStore.shared.settings.speech.enabled {
                    self.transcribeVoice(url: audioURL) { text in
                        if let text = text, !text.isEmpty {
                            attachment.transcript = text
                        }
                        try? FileManager.default.removeItem(at: audioURL)
                        self.composer.addAttachment(attachment)
                    }
                } else {
                    self.composer.addAttachment(attachment)
                }
            }
        }
    }

    // MARK: - 语音

    private func beginRecording() {
        guard AudioRecorder.shared.start() != nil else {
            Toast.error(L10n.recordStartFailed)
            return
        }
        recordOverlay.show(in: view)
        recordOverlay.setCancelMode(false)
        recordTimer?.invalidate()
        recordTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let level = AudioRecorder.shared.currentLevel()
            let seconds = AudioRecorder.shared.currentDuration
            self.recordOverlay.update(level: level, seconds: seconds)
            if seconds >= SettingsStore.shared.settings.speech.maxDuration {
                self.finishRecording(cancelled: false)
            }
        }
    }

    private func stopRecordTimer() {
        recordTimer?.invalidate()
        recordTimer = nil
    }

    private func finishRecording(cancelled: Bool) {
        stopRecordTimer()
        recordOverlay.hide()
        guard let result = AudioRecorder.shared.stop() else { return }
        if cancelled {
            try? FileManager.default.removeItem(at: result.url)
            return
        }
        guard result.duration >= 0.6 else {
            try? FileManager.default.removeItem(at: result.url)
            Toast.show(L10n.voiceTooShort)
            return
        }

        Toast.show(L10n.transcribing)
        transcribeVoice(url: result.url) { [weak self] text in
            guard let self = self else { return }
            defer { try? FileManager.default.removeItem(at: result.url) }
            guard let text = text, !text.isEmpty else {
                Toast.error(L10n.speechNotRecognized)
                return
            }
            self.composer.appendText(text)
            if SettingsStore.shared.settings.speech.autoSendVoice {
                self.sendCurrentInput()
            }
        }
    }

    private func transcribeVoice(url: URL, completion: @escaping (String?) -> Void) {
        let speech = SettingsStore.shared.settings.speech
        if speech.kind == .openAICompatible {
            TranscriptionService.shared.transcribe(fileURL: url, settings: speech) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text): completion(text)
                    case .failure(let error):
                        Toast.error(error.message)
                        completion(nil)
                    }
                }
            }
        } else {
            AppleSpeechTranscriber.shared.transcribe(fileURL: url, language: speech.language) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text): completion(text)
                    case .failure(let error):
                        if !error.isCancelled { Toast.error(error.message) }
                        completion(nil)
                    }
                }
            }
        }
    }

    // MARK: - 设置

    @objc private func openSettings() {
        let settings = SettingsViewController()
        settings.onProviderChanged = { [weak self] in
            self?.navigationItem.title = self?.conversation.title
        }
        navigationController?.pushViewController(settings, animated: true)
    }

    /// 注意：不能加 @objc —— 参数是 Swift 数组 [Attachment]，无法在 Objective-C 里表示
    private func openImage(_ attachments: [Attachment], index: Int) {
        guard !attachments.isEmpty else { return }
        let viewer = ImageViewerViewController(attachments: attachments, startIndex: index)
        presentFullScreen(viewer)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ChatViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversation.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseIdentifier,
                                                 for: indexPath) as! ChatMessageCell
        let message = conversation.messages[indexPath.row]
        cell.configure(with: message, streaming: message.isStreaming)
        cell.onTapMedia = { [weak self] index in
            guard let self = self else { return }
            let visual = message.attachments.filter { $0.isVisual }
            self.openImage(visual, index: index)
        }
        cell.onRetry = { [weak self] in
            self?.retryMessage(at: indexPath)
        }
        cell.onSpeak = { [weak self] in
            guard let self = self else { return }
            let text = message.text.isEmpty ? (message.reasoningText ?? "") : message.text
            SpeechPlayer.shared.speak(MarkdownLite.plain(text))
        }
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distance = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        let near = distance < 80
        if near != isNearBottom {
            isNearBottom = near
            updateScrollButton()
        }
    }
}

// MARK: - ComposerViewDelegate

extension ChatViewController: ComposerViewDelegate {

    func composerDidTapAttach(_ composer: ComposerView) {
        presentAttachmentSheet()
    }

    func composerDidTapSend(_ composer: ComposerView) {
        sendCurrentInput()
    }

    func composerDidTapStop(_ composer: ComposerView) {
        ChatService.shared.cancel()
        Toast.show(L10n.stopped)
        // cancel 会走到 finishStreaming，这里不用重复收尾
    }

    func composerDidChangeHeight(_ composer: ComposerView) {
        UIView.animate(withDuration: 0.15) {
            self.view.layoutIfNeeded()
        }
        if isNearBottom { scrollToBottom(animated: false) }
    }

    func composerDidRemoveAttachment(_ composer: ComposerView, at index: Int) {
        guard index < composer.attachments.count else { return }
        var items = composer.attachments
        items.remove(at: index)
        composer.setAttachments(items)
    }

    func composerDidTapAttachment(_ composer: ComposerView, at index: Int) {
        let items = composer.attachments
        guard index < items.count else { return }
        let target = items[index]
        guard target.isVisual else {
            Toast.show(L10n.previewUnavailable)
            return
        }
        let visual = items.filter { $0.isVisual }
        let visualIndex = visual.firstIndex(where: { $0.id == target.id }) ?? 0
        openImage(visual, index: visualIndex)
    }

    func composerVoiceDidBegin(_ composer: ComposerView) {
        let speech = SettingsStore.shared.settings.speech
        guard speech.enabled else {
            Toast.show(L10n.voiceDisabled)
            return
        }
        isVoicePressActive = true
        AudioRecorder.requestPermission { [weak self] granted in
            guard let self = self, self.isVoicePressActive else { return }
            guard granted else {
                Toast.error(L10n.micPermissionDenied)
                return
            }
            self.beginRecording()
        }
    }

    func composerVoiceDidMove(_ composer: ComposerView, translationY: CGFloat) {
        guard recordTimer != nil else { return }
        recordOverlay.setCancelMode(translationY < -55)
    }

    func composerVoiceDidEnd(_ composer: ComposerView, cancelled: Bool) {
        isVoicePressActive = false
        guard recordTimer != nil else {
            // 还没开始录音（例如权限弹窗中松手）
            AudioRecorder.shared.cancel()
            recordOverlay.hide()
            return
        }
        finishRecording(cancelled: cancelled)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true, completion: nil)

        if let mediaURL = info[.mediaURL] as? URL {
            processVideo(mediaURL)
            return
        }
        // 相册图片优先用原始文件（后台读盘 + 解码即缩放，内存最省）
        if let imageURL = info[.imageURL] as? URL {
            processImageFile(imageURL)
            return
        }
        if let image = info[.originalImage] as? UIImage {
            processImage(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
