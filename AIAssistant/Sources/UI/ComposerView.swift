//
//  ComposerView.swift
//  AIAssistant
//
//  底部输入栏（对标豆包的输入条）：
//      [ + ]  [ 输入框 / 按住说话 ]  [ 发送 ]
//  输入框右侧有一个"键盘 / 语音"切换按钮；
//  附件以横向缩略图条展示，带删除角标和体积提示（省流量，5s 用户很在意）。
//
//  布局全部交给两个 UIStackView（根纵向栈 + 输入行横向栈），
//  这样"附件区隐藏时自动收起"是免费的，不用手写一堆动态约束。
//

import UIKit

protocol ComposerViewDelegate: AnyObject {
    func composerDidTapAttach(_ composer: ComposerView)
    func composerDidTapSend(_ composer: ComposerView)
    func composerDidTapStop(_ composer: ComposerView)
    func composerDidChangeHeight(_ composer: ComposerView)
    func composerVoiceDidBegin(_ composer: ComposerView)
    /// translationY: 手指向上为负值
    func composerVoiceDidMove(_ composer: ComposerView, translationY: CGFloat)
    func composerVoiceDidEnd(_ composer: ComposerView, cancelled: Bool)
    func composerDidRemoveAttachment(_ composer: ComposerView, at index: Int)
    func composerDidTapAttachment(_ composer: ComposerView, at index: Int)
}

final class ComposerView: UIView {

    weak var delegate: ComposerViewDelegate?

    private let rootStack = UIStackView()
    private let inputRow = UIStackView()
    private let attachButton = UIButton(type: .system)
    private let inputContainer = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let modeButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let voiceBar = UIView()
    private let voiceLabel = UILabel()

    private let attachmentSection = UIStackView()
    private let attachmentInfoLabel = UILabel()
    private let attachmentScrollView = UIScrollView()
    private let attachmentStack = UIStackView()

    private var inputHeightConstraint: NSLayoutConstraint?
    private var rootBottomConstraint: NSLayoutConstraint?

    private(set) var attachments: [Attachment] = []
    private var isVoiceMode = false
    private var isCancellingVoice = false

    private let cancelThreshold: CGFloat = 55
    private let minInputHeight: CGFloat
    private let maxInputHeight: CGFloat

    // MARK: - 初始化

    override init(frame: CGRect) {
        let compact = Theme.isCompactWidth()
        minInputHeight = compact ? 32 : 34
        maxInputHeight = compact ? 88 : 104
        super.init(frame: frame)
        setup(compact: compact)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup(compact: Bool) {
        let attachSize: CGFloat = compact ? 34 : 36
        let sendSize: CGFloat = compact ? 38 : 42

        backgroundColor = Theme.current.inputBackground

        let topLine = UIView()
        topLine.backgroundColor = Theme.current.divider
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topLine)

        // 附件区
        attachmentInfoLabel.font = Theme.caption
        attachmentInfoLabel.textColor = Theme.current.secondaryText

        attachmentStack.axis = .horizontal
        attachmentStack.spacing = 8
        attachmentStack.alignment = .center
        attachmentStack.translatesAutoresizingMaskIntoConstraints = false

        attachmentScrollView.showsHorizontalScrollIndicator = false
        attachmentScrollView.alwaysBounceHorizontal = true
        attachmentScrollView.translatesAutoresizingMaskIntoConstraints = false
        attachmentScrollView.addSubview(attachmentStack)

        attachmentSection.axis = .vertical
        attachmentSection.spacing = 6
        attachmentSection.alignment = .fill
        attachmentSection.isHidden = true
        attachmentSection.addArrangedSubview(attachmentInfoLabel)
        attachmentSection.addArrangedSubview(attachmentScrollView)

        // 输入框
        inputContainer.backgroundColor = Theme.current.surfaceAlt
        inputContainer.roundCorners(minInputHeight / 2)
        inputContainer.layer.borderWidth = Theme.hairline
        inputContainer.layer.borderColor = Theme.current.divider.cgColor

        textView.font = Theme.body
        textView.textColor = Theme.current.primaryText
        textView.tintColor = Theme.current.accent
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = L10n.inputPlaceholder
        placeholderLabel.font = Theme.body
        placeholderLabel.textColor = Theme.current.tertiaryText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        modeButton.addTarget(self, action: #selector(toggleVoiceMode), for: .touchUpInside)
        modeButton.translatesAutoresizingMaskIntoConstraints = false

        voiceBar.isHidden = true
        voiceBar.translatesAutoresizingMaskIntoConstraints = false
        voiceLabel.text = L10n.holdToTalk
        voiceLabel.font = Theme.body
        voiceLabel.textAlignment = .center
        voiceLabel.translatesAutoresizingMaskIntoConstraints = false
        voiceBar.addSubview(voiceLabel)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(voicePressed(_:)))
        press.minimumPressDuration = 0.12
        press.allowableMovement = .greatestFiniteMagnitude
        voiceBar.addGestureRecognizer(press)
        voiceBar.isUserInteractionEnabled = true

        inputContainer.addSubview(textView)
        inputContainer.addSubview(placeholderLabel)
        inputContainer.addSubview(modeButton)
        inputContainer.addSubview(voiceBar)

        // 按钮
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.roundCorners(sendSize / 2)

        inputRow.axis = .horizontal
        inputRow.spacing = 6
        inputRow.alignment = .center
        inputRow.addArrangedSubview(attachButton)
        inputRow.addArrangedSubview(inputContainer)
        inputRow.addArrangedSubview(sendButton)

        rootStack.axis = .vertical
        rootStack.spacing = 8
        rootStack.alignment = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(attachmentSection)
        rootStack.addArrangedSubview(inputRow)
        addSubview(rootStack)

        inputHeightConstraint = inputContainer.heightAnchor.constraint(equalToConstant: minInputHeight)
        rootBottomConstraint = rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: Theme.hairline),

            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            rootBottomConstraint!,

            attachButton.widthAnchor.constraint(equalToConstant: attachSize),
            attachButton.heightAnchor.constraint(equalToConstant: attachSize),
            sendButton.widthAnchor.constraint(equalToConstant: sendSize),
            sendButton.heightAnchor.constraint(equalToConstant: sendSize),

            inputHeightConstraint!,
            inputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: minInputHeight),
            inputContainer.heightAnchor.constraint(lessThanOrEqualToConstant: maxInputHeight),

            textView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: modeButton.leadingAnchor, constant: -2),
            textView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 1),
            textView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -1),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 4),
            placeholderLabel.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeButton.leadingAnchor, constant: -2),

            modeButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -6),
            modeButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 26),
            modeButton.heightAnchor.constraint(equalToConstant: 26),

            voiceBar.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 6),
            voiceBar.trailingAnchor.constraint(equalTo: modeButton.leadingAnchor, constant: -4),
            voiceBar.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 2),
            voiceBar.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -2),

            voiceLabel.centerXAnchor.constraint(equalTo: voiceBar.centerXAnchor),
            voiceLabel.centerYAnchor.constraint(equalTo: voiceBar.centerYAnchor),

            attachmentStack.leadingAnchor.constraint(equalTo: attachmentScrollView.leadingAnchor),
            attachmentStack.trailingAnchor.constraint(equalTo: attachmentScrollView.trailingAnchor),
            attachmentStack.topAnchor.constraint(equalTo: attachmentScrollView.topAnchor),
            attachmentStack.bottomAnchor.constraint(equalTo: attachmentScrollView.bottomAnchor),
            attachmentScrollView.heightAnchor.constraint(equalToConstant: 66)
        ])

        attachButton.accessibilityLabel = L10n.attachTitle
        updateSendButtonState()
        applyTheme()
    }

    // MARK: - 主题

    func applyTheme() {
        let palette = Theme.current
        backgroundColor = palette.inputBackground
        inputContainer.backgroundColor = palette.surfaceAlt
        inputContainer.layer.borderColor = palette.divider.cgColor
        textView.textColor = palette.primaryText
        textView.tintColor = palette.accent
        placeholderLabel.textColor = palette.tertiaryText
        voiceLabel.textColor = palette.primaryText
        attachmentInfoLabel.textColor = palette.secondaryText
        attachButton.setImage(Icon.plus.image(size: 21, color: palette.secondaryText), for: .normal)
        updateModeButtonIcon()
        updateSendButtonState()
    }

    // MARK: - 对外接口

    var text: String { textView.text ?? "" }

    /// 底部留白（全面屏设备上要给 Home Indicator 让位）
    func setBottomInset(_ inset: CGFloat) {
        rootBottomConstraint?.constant = -max(8, inset)
    }

    var isGenerating: Bool = false {
        didSet { updateSendButtonState() }
    }

    func clearInput() {
        textView.text = ""
        updatePlaceholder()
        updateInputHeight(force: true)
        updateSendButtonState()
    }

    /// 语音识别结果回填
    func appendText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = self.text
        textView.text = existing.isEmpty ? trimmed : existing + trimmed
        updatePlaceholder()
        updateInputHeight(force: true)
        updateSendButtonState()
    }

    func setAttachments(_ items: [Attachment]) {
        attachments = items
        rebuildAttachmentStrip()
        updateSendButtonState()
    }

    func addAttachment(_ attachment: Attachment) {
        guard attachments.count < 6 else {
            Toast.show(L10n.attachMaxReached)
            return
        }
        attachments.append(attachment)
        rebuildAttachmentStrip()
        updateSendButtonState()
    }

    func removeAllAttachments() {
        attachments.removeAll()
        rebuildAttachmentStrip()
        updateSendButtonState()
    }

    func focusInput() {
        if isVoiceMode { setVoiceMode(false) }
        textView.becomeFirstResponder()
    }

    func resignInput() {
        textView.resignFirstResponder()
    }

    func setVoiceMode(_ enabled: Bool) {
        isVoiceMode = enabled
        textView.isHidden = enabled
        voiceBar.isHidden = !enabled
        updatePlaceholder()
        updateModeButtonIcon()
        if enabled {
            textView.resignFirstResponder()
        } else {
            textView.becomeFirstResponder()
        }
        updateSendButtonState()
    }

    // MARK: - 按钮

    @objc private func attachTapped() {
        delegate?.composerDidTapAttach(self)
    }

    @objc private func toggleVoiceMode() {
        setVoiceMode(!isVoiceMode)
    }

    @objc private func sendTapped() {
        if isGenerating {
            delegate?.composerDidTapStop(self)
            return
        }
        guard !text.isEmpty || !attachments.isEmpty else { return }
        delegate?.composerDidTapSend(self)
    }

    private func updateModeButtonIcon() {
        let icon: Icon = isVoiceMode ? .keyboard : .mic
        modeButton.setImage(icon.image(size: 20, color: Theme.current.secondaryText), for: .normal)
    }

    private func updateSendButtonState() {
        let canSend = !text.isEmpty || !attachments.isEmpty
        let palette = Theme.current
        if isGenerating {
            sendButton.setImage(Icon.stop.image(size: 18, color: .white), for: .normal)
            sendButton.backgroundColor = palette.danger
            sendButton.isEnabled = true
        } else {
            sendButton.setImage(Icon.send.image(size: 19, color: .white), for: .normal)
            sendButton.backgroundColor = canSend ? palette.accent : palette.surfaceAlt
            sendButton.isEnabled = canSend
        }
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty || isVoiceMode
    }

    // MARK: - 按住说话

    @objc private func voicePressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isCancellingVoice = false
            voiceBar.backgroundColor = Theme.current.accentSoft
            delegate?.composerVoiceDidBegin(self)
        case .changed:
            let translationY = gesture.location(in: voiceBar).y - voiceBar.bounds.midY
            let cancelled = translationY < -cancelThreshold
            if cancelled != isCancellingVoice {
                isCancellingVoice = cancelled
                voiceBar.backgroundColor = cancelled
                    ? Theme.current.danger.withAlphaComponent(0.18)
                    : Theme.current.accentSoft
            }
            delegate?.composerVoiceDidMove(self, translationY: translationY)
        case .ended, .cancelled, .failed:
            voiceBar.backgroundColor = .clear
            delegate?.composerVoiceDidEnd(self, cancelled: isCancellingVoice)
            isCancellingVoice = false
        default:
            break
        }
    }

    // MARK: - 输入框高度

    private func updateInputHeight(force: Bool = false) {
        guard let constraint = inputHeightConstraint else { return }
        let width = textView.bounds.width
        guard width > 0 else { return }
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let desired = size.height + 2
        textView.isScrollEnabled = desired > maxInputHeight
        let target = max(minInputHeight, min(maxInputHeight, desired))
        if force || abs(constraint.constant - target) > 0.5 {
            constraint.constant = target
            delegate?.composerDidChangeHeight(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateInputHeight()
    }

    // MARK: - 附件缩略图条

    private func rebuildAttachmentStrip() {
        attachmentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let hasItems = !attachments.isEmpty
        attachmentSection.isHidden = !hasItems
        guard hasItems else {
            delegate?.composerDidChangeHeight(self)
            return
        }

        let totalBytes = attachments.reduce(0) { $0 + $1.byteSize }
        attachmentInfoLabel.text = "已选 \(attachments.count) 项 · \(Self.sizeText(totalBytes))"

        for (index, attachment) in attachments.enumerated() {
            let chip = AttachmentChipView()
            chip.configure(attachment: attachment)
            chip.onDelete = { [weak self] in
                guard let self = self else { return }
                self.delegate?.composerDidRemoveAttachment(self, at: index)
            }
            chip.onTap = { [weak self] in
                guard let self = self else { return }
                self.delegate?.composerDidTapAttachment(self, at: index)
            }
            attachmentStack.addArrangedSubview(chip)
        }
        delegate?.composerDidChangeHeight(self)
    }

    private static func sizeText(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 KB" }
        if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - UITextViewDelegate

extension ComposerView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholder()
        updateSendButtonState()
        updateInputHeight()
    }
}

// MARK: - 附件小卡片

final class AttachmentChipView: UIView {

    private let imageView = UIImageView()
    private let deleteButton = UIButton(type: .system)
    private let playIcon = UIImageView()
    private var token = UUID()

    var onDelete: (() -> Void)?
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.current.surfaceAlt

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.roundCorners(10)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        playIcon.image = Icon.play.image(size: 16, color: .white)
        playIcon.isHidden = true
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playIcon)

        deleteButton.setImage(Icon.close.image(size: 11, color: .white), for: .normal)
        deleteButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        deleteButton.roundCorners(9)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56),
            heightAnchor.constraint(equalToConstant: 56),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            playIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            playIcon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            playIcon.widthAnchor.constraint(equalToConstant: 16),
            playIcon.heightAnchor.constraint(equalToConstant: 16),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 5),
            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: -5),
            deleteButton.widthAnchor.constraint(equalToConstant: 18),
            deleteButton.heightAnchor.constraint(equalToConstant: 18)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(attachment: Attachment) {
        let current = UUID()
        token = current
        playIcon.isHidden = attachment.kind != .video
        imageView.image = nil
        ImagePipeline.shared.asyncThumbnail(for: attachment) { [weak self] image in
            guard let self = self, self.token == current else { return }
            self.imageView.image = image
        }
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    @objc private func tapped() {
        onTap?()
    }
}
