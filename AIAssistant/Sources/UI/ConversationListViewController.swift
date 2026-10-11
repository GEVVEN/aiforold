//
//  ConversationListViewController.swift
//  AIAssistant
//
//  会话列表（App 首页）。只读索引文件，不加载任何历史消息，
//  所以哪怕有上百条对话，进入这里也是瞬间的事。
//

import UIKit

final class ConversationListViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateLabel = UILabel()
    private let headerContainer = UIView()
    private let providerChip = UIView()
    private let providerDot = UIView()
    private let providerLabel = UILabel()
    private let chipChevron = UIImageView()

    private var summaries: [ConversationSummary] = []

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigation()
        setupTable()
        setupHeader()
        setupEmptyState()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeChanged),
                                               name: .appThemeDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: .appSettingsDidChange,
                                               object: nil)
        applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        applyTheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 搭建

    private func setupNavigation() {
        title = L10n.appName
        navigationItem.largeTitleDisplayMode = .never

        let gear = UIBarButtonItem(image: Icon.gear.barButtonImage(), style: .plain,
                                   target: self, action: #selector(openSettings))
        let plus = UIBarButtonItem(image: Icon.plus.barButtonImage(), style: .plain,
                                   target: self, action: #selector(startNewChat))
        navigationItem.rightBarButtonItems = [plus, gear]
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
    }

    private func setupHeader() {
        let width = UIScreen.main.bounds.width
        headerContainer.frame = CGRect(x: 0, y: 0, width: width, height: 50)
        headerContainer.autoresizingMask = [.flexibleWidth]

        providerChip.frame = CGRect(x: 12, y: 6, width: width - 24, height: 38)
        providerChip.autoresizingMask = [.flexibleWidth]
        providerChip.roundCorners(10)
        providerChip.isUserInteractionEnabled = true
        providerChip.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                action: #selector(openSettings)))
        headerContainer.addSubview(providerChip)

        providerDot.frame = CGRect(x: 12, y: 16, width: 6, height: 6)
        providerDot.roundCorners(3)
        providerChip.addSubview(providerDot)

        providerLabel.frame = CGRect(x: 26, y: 0, width: providerChip.bounds.width - 60, height: 38)
        providerLabel.autoresizingMask = [.flexibleWidth]
        providerLabel.font = Theme.footnote
        providerChip.addSubview(providerLabel)

        chipChevron.frame = CGRect(x: providerChip.bounds.width - 26, y: 12, width: 14, height: 14)
        chipChevron.autoresizingMask = [.flexibleLeftMargin]
        chipChevron.contentMode = .scaleAspectFit
        providerChip.addSubview(chipChevron)

        tableView.tableHeaderView = headerContainer
        updateHeader()
    }

    private func setupEmptyState() {
        emptyStateLabel.text = L10n.emptyChatList
        emptyStateLabel.font = Theme.footnote
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7)
        ])
    }

    // MARK: - 数据

    private func reload() {
        summaries = ConversationStore.shared.summaries
        tableView.reloadData()
        emptyStateLabel.isHidden = !summaries.isEmpty
        updateHeader()
    }

    private func updateHeader() {
        let settings = SettingsStore.shared.settings
        let provider = settings.activeProvider
        let hasKey = !provider.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        let host = URL(string: provider.baseURL)?.host ?? provider.baseURL
        let isLocal = host == "127.0.0.1" || host == "localhost" || host.hasPrefix("192.168.")

        if hasKey || isLocal {
            providerLabel.text = "\(provider.name) · \(provider.model)"
            providerDot.backgroundColor = Theme.current.accent
            providerLabel.textColor = Theme.current.secondaryText
        } else {
            providerLabel.text = "还没填 API Key，点这里去设置"
            providerDot.backgroundColor = Theme.current.danger
            providerLabel.textColor = Theme.current.danger
        }
        chipChevron.image = Icon.chevronRight.image(size: 14, color: Theme.current.tertiaryText)
    }

    // MARK: - 主题

    @objc private func applyTheme() {
        let palette = Theme.current
        view.backgroundColor = palette.background
        tableView.backgroundColor = palette.background
        tableView.separatorColor = palette.divider
        emptyStateLabel.textColor = palette.tertiaryText
        providerChip.backgroundColor = palette.surface
        navigationController?.navigationBar.barTintColor = palette.navBackground
        navigationController?.navigationBar.tintColor = palette.accent
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: palette.primaryText]
        navigationController?.navigationBar.isTranslucent = false
        navigationItem.rightBarButtonItems?.first?.image = Icon.plus.barButtonImage(color: palette.accent)
        navigationItem.rightBarButtonItems?.last?.image = Icon.gear.barButtonImage(color: palette.accent)
        updateHeader()
        tableView.reloadData()
    }

    @objc private func themeChanged() { applyTheme() }
    @objc private func settingsChanged() { updateHeader() }

    // MARK: - 动作

    @objc private func startNewChat() {
        let chat = ChatViewController(conversationId: nil)
        navigationController?.pushViewController(chat, animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    private func openConversation(_ id: String) {
        let chat = ChatViewController(conversationId: id)
        navigationController?.pushViewController(chat, animated: true)
    }
}

// MARK: - 列表

extension ConversationListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return summaries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier,
                                                 for: indexPath) as! ConversationCell
        cell.configure(with: summaries[indexPath.row])
        cell.applyTheme(Theme.current)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openConversation(summaries[indexPath.row].id)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: L10n.delete) { [weak self] _, _, completion in
            guard let self = self else { return }
            let summary = self.summaries[indexPath.row]
            ConversationStore.shared.delete(id: summary.id)
            self.summaries.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.emptyStateLabel.isHidden = !self.summaries.isEmpty
            completion(true)
        }
        delete.backgroundColor = Theme.current.danger
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - 会话单元格

final class ConversationCell: UITableViewCell {

    static let reuseIdentifier = "ConversationCell"

    private let avatarView = UIView()
    private let avatarIcon = UIImageView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        avatarView.roundCorners(10)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarIcon.contentMode = .center
        avatarIcon.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(avatarIcon)
        contentView.addSubview(avatarView)

        titleLabel.font = Theme.bodyBold
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        previewLabel.font = Theme.caption
        previewLabel.numberOfLines = 1
        previewLabel.lineBreakMode = .byTruncatingTail

        dateLabel.font = Theme.caption.monospacedDigits()
        dateLabel.textAlignment = .right
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, previewLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let rowStack = UIStackView(arrangedSubviews: [textStack, dateLabel])
        rowStack.axis = .horizontal
        rowStack.spacing = 8
        rowStack.alignment = .center
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            avatarIcon.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarIcon.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            avatarIcon.widthAnchor.constraint(equalToConstant: 20),
            avatarIcon.heightAnchor.constraint(equalToConstant: 20),

            rowStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with summary: ConversationSummary) {
        titleLabel.text = summary.title.isEmpty ? L10n.untitledChat : summary.title
        previewLabel.text = summary.preview.isEmpty ? "\(summary.messageCount) 条消息" : summary.preview
        dateLabel.text = Self.relativeTime(summary.updatedAt)
        avatarIcon.image = Icon.sparkle.image(size: 18, color: Theme.current.accent)
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.primaryText
        previewLabel.textColor = palette.secondaryText
        dateLabel.textColor = palette.tertiaryText
        avatarView.backgroundColor = palette.accentSoft
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return timeFormatter.string(from: date) }
        if interval < 86400 * 2 { return "昨天" }
        return dayFormatter.string(from: date)
    }
}
