//
//  ChatMessageCell.swift
//  AIAssistant
//
//  聊天气泡。为了让 iPhone 5s 也能流畅滚动，这里做了几件事：
//    * 气泡内部用一个纵向 UIStackView，隐藏项自动折叠，不用手写一堆动态约束；
//    * 约束只建一次，配置阶段只改颜色 / 文本 / isHidden；
//    * 图片走缩略图缓存，并用 token 防止 cell 复用串图；
//    * 流式输出时不做 Markdown 排版（纯文本 + 光标），只在完成时排版一次。
//

import UIKit

final class ChatMessageCell: UITableViewCell {

    static let reuseIdentifier = "ChatMessageCell"

    var onTapMedia: ((Int) -> Void)?
    var onRetry: (() -> Void)?
    var onSpeak: (() -> Void)?

    private let avatarView = UIView()
    private let avatarIcon = UIImageView()
    private let bubbleView = UIView()
    private let contentStack = UIStackView()
    private let textLabel = UILabel()
    private let typingView = TypingDotsView()
    private let mediaStack = UIStackView()
    private let thumbs: [AttachmentThumbView] = (0..<3).map { _ in AttachmentThumbView() }
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let errorRow = UIStackView()

    private var userLeading: NSLayoutConstraint?
    private var userTrailing: NSLayoutConstraint?
    private var assistantLeading: NSLayoutConstraint?
    private var assistantTrailing: NSLayoutConstraint?
    private var userWidthLimit: NSLayoutConstraint?
    private var assistantWidthLimit: NSLayoutConstraint?
    private var thumbWidthConstraints: [NSLayoutConstraint] = []
    private var thumbHeightConstraints: [NSLayoutConstraint] = []

    private var isUser = false
    private(set) var message: ChatMessage?
    private var plainText = ""

    // MARK: - 初始化

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarView.roundCorners(14)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarIcon.contentMode = .center
        avatarIcon.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(avatarIcon)
        contentView.addSubview(avatarView)

        bubbleView.roundCorners(Theme.bubbleRadius)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        textLabel.numberOfLines = 0
        typingView.isHidden = true

        mediaStack.axis = .horizontal
        mediaStack.spacing = 6
        mediaStack.alignment = .leading
        mediaStack.isHidden = true
        for thumb in thumbs { mediaStack.addArrangedSubview(thumb) }

        errorLabel.font = Theme.caption
        errorLabel.numberOfLines = 0
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        retryButton.titleLabel?.font = Theme.caption
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.setContentHuggingPriority(.required, for: .horizontal)
        retryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        retryButton.roundCorners(6)

        errorRow.axis = .horizontal
        errorRow.spacing = 8
        errorRow.alignment = .center
        errorRow.isHidden = true
        errorRow.addArrangedSubview(errorLabel)
        errorRow.addArrangedSubview(retryButton)

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textLabel)
        contentStack.addArrangedSubview(typingView)
        contentStack.addArrangedSubview(mediaStack)
        contentStack.addArrangedSubview(errorRow)
        bubbleView.addSubview(contentStack)

        let compact = Theme.isCompactWidth()
        let thumbSize: CGFloat = compact ? 74 : 88

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 28),
            avatarView.heightAnchor.constraint(equalToConstant: 28),

            avatarIcon.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarIcon.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            avatarIcon.widthAnchor.constraint(equalToConstant: 18),
            avatarIcon.heightAnchor.constraint(equalToConstant: 18),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),

            typingView.heightAnchor.constraint(equalToConstant: 18)
        ])

        for thumb in thumbs {
            thumb.translatesAutoresizingMaskIntoConstraints = false
            // 注意：优先级 999 而不是 1000。
            // 原因有两个：① 3 张缩略图的必需宽度在小屏上会和气泡最大宽度冲突；
            // ② UIStackView 隐藏 arrangedSubview 时会把尺寸压到 0，必需约束会打架。
            let width = thumb.widthAnchor.constraint(equalToConstant: thumbSize)
            let height = thumb.heightAnchor.constraint(equalToConstant: thumbSize)
            width.priority = .init(999)
            height.priority = .init(999)
            width.isActive = true
            height.isActive = true
            thumbWidthConstraints.append(width)
            thumbHeightConstraints.append(height)
            thumb.onTap = { [weak self, weak thumb] in
                guard let self = self, let thumb = thumb else { return }
                let index = self.thumbs.firstIndex(of: thumb) ?? 0
                self.onTapMedia?(index)
            }
        }

        // 用户 / 助手 两套左右约束，配置时切换
        userTrailing = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        userLeading = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor,
                                                          constant: 44)
        assistantLeading = bubbleView.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8)
        assistantTrailing = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                                 constant: -12)
        userWidthLimit = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor,
                                                          multiplier: 0.76)
        assistantWidthLimit = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor,
                                                                multiplier: 0.82)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        bubbleView.addGestureRecognizer(longPress)
        bubbleView.isUserInteractionEnabled = true
    }

    // MARK: - 配置

    func configure(with message: ChatMessage, streaming: Bool) {
        self.message = message
        self.isUser = message.role == .user

        let palette = Theme.current
        bubbleView.backgroundColor = isUser ? palette.bubbleUser : palette.bubbleAssistant
        avatarView.isHidden = isUser
        avatarView.backgroundColor = palette.accentSoft
        avatarIcon.image = Icon.sparkle.image(size: 16, color: palette.accent)

        let style = isUser ? MarkdownStyle.userBubble : MarkdownStyle.chatBubble
        let hasText = !message.text.isEmpty
        let hasReasoning = (message.reasoningText?.isEmpty == false)

        // 文本（流式时纯文本 + 光标，省掉反复排版）
        if hasText || hasReasoning {
            textLabel.isHidden = false
            if streaming {
                textLabel.attributedText = NSAttributedString(string: message.text + " ▍",
                                                              attributes: Self.plainAttributes(style))
            } else if hasReasoning && !hasText {
                textLabel.attributedText = MarkdownLite.render("思考过程：\n" + (message.reasoningText ?? ""),
                                                               style: MarkdownStyle.captionStyle(palette))
            } else if hasReasoning {
                let combined = NSMutableAttributedString()
                combined.append(MarkdownLite.render("思考过程：\n" + (message.reasoningText ?? ""),
                                                    style: MarkdownStyle.captionStyle(palette)))
                combined.append(NSAttributedString(string: "\n\n"))
                combined.append(MarkdownLite.render(message.text, style: style))
                textLabel.attributedText = combined
            } else {
                textLabel.attributedText = MarkdownLite.render(message.text, style: style)
            }
            plainText = message.text.isEmpty ? (message.reasoningText ?? "") : message.text
        } else {
            textLabel.attributedText = nil
            textLabel.isHidden = true
            plainText = ""
        }

        // 等待首个字时的"三个点"
        typingView.isHidden = !(streaming && !hasText)

        // 附件
        let visual = message.attachments.filter { $0.isVisual }
        let visible = Array(visual.prefix(thumbs.count))
        mediaStack.isHidden = visible.isEmpty
        for (index, thumb) in thumbs.enumerated() {
            if index < visible.count {
                thumb.isHidden = false
                thumb.configure(attachment: visible[index])
            } else {
                thumb.prepareForReuse()
                thumb.isHidden = true
            }
        }

        // 错误 / 重试
        let hasError = (message.errorText?.isEmpty == false)
        errorRow.isHidden = !hasError
        if let errorText = message.errorText, hasError {
            errorLabel.text = errorText
            errorLabel.textColor = palette.danger
            retryButton.setTitle(L10n.retry, for: .normal)
            retryButton.setTitleColor(palette.accent, for: .normal)
            retryButton.backgroundColor = palette.accentSoft
        }

        // 左右切换
        userLeading?.isActive = false
        userTrailing?.isActive = false
        assistantLeading?.isActive = false
        assistantTrailing?.isActive = false
        userWidthLimit?.isActive = false
        assistantWidthLimit?.isActive = false

        if isUser {
            userLeading?.isActive = true
            userTrailing?.isActive = true
            userWidthLimit?.isActive = true
        } else {
            assistantLeading?.isActive = true
            assistantTrailing?.isActive = true
            assistantWidthLimit?.isActive = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTapMedia = nil
        onRetry = nil
        onSpeak = nil
        message = nil
        textLabel.attributedText = nil
        errorLabel.text = nil
        errorRow.isHidden = true
        mediaStack.isHidden = true
        typingView.isHidden = true
        for thumb in thumbs { thumb.prepareForReuse() }
    }

    private static func plainAttributes(_ style: MarkdownStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [
            .font: style.baseFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraph
        ]
    }

    // MARK: - 长按菜单（iOS 12 的 UIMenuController 方案）

    override var canBecomeFirstResponder: Bool { true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copyText) { return !plainText.isEmpty }
        if action == #selector(speakText) { return !plainText.isEmpty && !isUser }
        return false
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, message != nil else { return }
        becomeFirstResponder()
        let menu = UIMenuController.shared
        menu.setTargetRect(bubbleView.bounds, in: bubbleView)
        menu.setMenuVisible(true, animated: true)
    }

    @objc private func copyText() {
        UIPasteboard.general.string = plainText
        Toast.show(L10n.copied)
    }

    @objc private func speakText() {
        onSpeak?()
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}

extension MarkdownStyle {
    static func captionStyle(_ palette: Palette) -> MarkdownStyle {
        MarkdownStyle(baseFont: Theme.caption,
                      textColor: palette.secondaryText,
                      secondaryColor: palette.tertiaryText,
                      codeFont: Theme.code,
                      codeBackground: palette.codeBackground,
                      accent: palette.accent,
                      isDark: palette.isDark)
    }
}

// MARK: - 附件缩略图

final class AttachmentThumbView: UIView {

    private let imageView = UIImageView()
    private let overlay = UIView()
    private let playIcon = UIImageView()
    private let durationLabel = UILabel()
    private var token = UUID()

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        roundCorners(10)
        clipsToBounds = true
        backgroundColor = Theme.current.surfaceAlt

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        imageView.pinEdges(to: self)

        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isHidden = true
        addSubview(overlay)
        overlay.pinEdges(to: self)

        playIcon.contentMode = .center
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.isHidden = true
        addSubview(playIcon)

        durationLabel.font = Theme.font(10).monospacedDigits()
        durationLabel.textColor = .white
        durationLabel.textAlignment = .center
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        durationLabel.roundCorners(4)
        durationLabel.clipsToBounds = true
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.isHidden = true
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            playIcon.widthAnchor.constraint(equalToConstant: 26),
            playIcon.heightAnchor.constraint(equalToConstant: 26),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            durationLabel.heightAnchor.constraint(equalToConstant: 14),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(attachment: Attachment) {
        let currentToken = UUID()
        token = currentToken

        imageView.image = nil
        let isVideo = attachment.kind == .video
        overlay.isHidden = !isVideo
        playIcon.isHidden = !isVideo
        durationLabel.isHidden = !isVideo
        if isVideo {
            playIcon.image = Icon.play.image(size: 22, color: .white)
            durationLabel.text = Self.format(attachment.durationSeconds)
        }

        ImagePipeline.shared.asyncThumbnail(for: attachment) { [weak self] image in
            guard let self = self, self.token == currentToken else { return }
            self.imageView.image = image
        }
    }

    func prepareForReuse() {
        token = UUID()
        imageView.image = nil
        overlay.isHidden = true
        playIcon.isHidden = true
        durationLabel.isHidden = true
    }

    @objc private func tapped() {
        onTap?()
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 { return String(format: "%d:%02d", total / 60, total % 60) }
        return "\(total)s"
    }
}

// MARK: - "正在输入"的小圆点

final class TypingDotsView: UIView {

    private let dots: [UIView] = (0..<3).map { _ in UIView() }
    private var timer: Timer?
    private var step = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: dots)
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        for dot in dots {
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.roundCorners(3.5)
            dot.alpha = 0.35
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopAnimating() }
    }

    override var isHidden: Bool {
        didSet {
            if isHidden { stopAnimating() } else { startAnimating() }
        }
    }

    func startAnimating() {
        guard timer == nil else { return }
        let color = Theme.current.secondaryText
        for dot in dots { dot.backgroundColor = color }
        // 0.36s 一跳，比逐帧动画省电得多
        timer = Timer.scheduledTimer(withTimeInterval: 0.36, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.step = (self.step + 1) % 3
            for (index, dot) in self.dots.enumerated() {
                dot.alpha = index == self.step ? 1.0 : 0.35
            }
        }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        for dot in dots { dot.alpha = 0.35 }
    }
}
