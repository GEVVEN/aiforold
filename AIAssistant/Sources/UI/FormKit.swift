//
//  FormKit.swift
//  AIAssistant
//
//  一个极小的声明式表单引擎（设置页 / 服务编辑页 / 语音设置页共用）。
//  这样几个设置页都只有"描述数据"的代码，不用重复写 tableView 数据源。
//

import UIKit

enum FormRowStyle {
    case normal
    case accent
    case destructive
}

enum FormRow {
    case text(title: String,
              value: String,
              placeholder: String,
              secure: Bool,
              keyboard: UIKeyboardType,
              autocapitalization: UITextAutocapitalizationType,
              onChange: (String) -> Void)
    case longText(title: String, value: String, placeholder: String, minHeight: CGFloat, onChange: (String) -> Void)
    case toggle(title: String, subtitle: String?, value: Bool, onChange: (Bool) -> Void)
    case detail(title: String, value: String, onTap: () -> Void)
    case action(title: String, style: FormRowStyle, onTap: () -> Void)
    case slider(title: String, value: Double, min: Double, max: Double, step: Double,
                format: (Double) -> String, onChange: (Double) -> Void)
    case note(text: String)
}

struct FormSection {
    var title: String?
    var footer: String?
    var rows: [FormRow]
}

class FormViewController: UITableViewController {

    /// 每次刷新都重新描述表单（读最新的模型值）
    var buildSections: (() -> [FormSection])?

    private var sections: [FormSection] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive
        registerCells()
        observeKeyboard()
        reloadForm()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        reloadForm()
    }

    func reloadForm() {
        sections = buildSections?() ?? []
        tableView.reloadData()
    }

    func applyTheme() {
        let palette = Theme.current
        view.backgroundColor = palette.background
        tableView.backgroundColor = palette.background
        tableView.separatorColor = palette.divider
        navigationController?.navigationBar.barTintColor = palette.navBackground
        navigationController?.navigationBar.tintColor = palette.accent
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: palette.primaryText]
        navigationController?.navigationBar.isTranslucent = false
        if #available(iOS 11.0, *) {
            navigationController?.navigationBar.prefersLargeTitles = false
        }
    }

    // MARK: - 键盘

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardHidden),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        tableView.contentInset.bottom = overlap
        tableView.scrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardHidden() {
        tableView.contentInset.bottom = 0
        tableView.scrollIndicatorInsets.bottom = 0
    }

    // MARK: - 私有

    private enum CellID {
        static let text = "FormTextFieldCell"
        static let longText = "FormLongTextCell"
        static let toggle = "FormSwitchCell"
        static let detail = "FormDetailCell"
        static let action = "FormActionCell"
        static let slider = "FormSliderCell"
        static let note = "FormNoteCell"
    }

    private func registerCells() {
        tableView.register(FormTextFieldCell.self, forCellReuseIdentifier: CellID.text)
        tableView.register(FormLongTextCell.self, forCellReuseIdentifier: CellID.longText)
        tableView.register(FormSwitchCell.self, forCellReuseIdentifier: CellID.toggle)
        tableView.register(FormDetailCell.self, forCellReuseIdentifier: CellID.detail)
        tableView.register(FormActionCell.self, forCellReuseIdentifier: CellID.action)
        tableView.register(FormSliderCell.self, forCellReuseIdentifier: CellID.slider)
        tableView.register(FormNoteCell.self, forCellReuseIdentifier: CellID.note)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footer
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = Theme.current.secondaryText
        header.contentView.backgroundColor = Theme.current.background
    }

    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.textColor = Theme.current.tertiaryText
        footer.contentView.backgroundColor = Theme.current.background
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let palette = Theme.current

        switch row {
        case .text(let title, let value, let placeholder, let secure, let keyboard, let autocapitalization, let onChange):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.text, for: indexPath) as! FormTextFieldCell
            cell.configure(title: title,
                           value: value,
                           placeholder: placeholder,
                           secure: secure,
                           keyboard: keyboard,
                           autocapitalization: autocapitalization,
                           onChange: onChange)
            cell.applyTheme(palette)
            return cell

        case .longText(let title, let value, let placeholder, let minHeight, let onChange):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.longText, for: indexPath) as! FormLongTextCell
            cell.configure(title: title,
                           value: value,
                           placeholder: placeholder,
                           minHeight: minHeight,
                           onChange: onChange)
            cell.applyTheme(palette)
            return cell

        case .toggle(let title, let subtitle, let value, let onChange):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.toggle, for: indexPath) as! FormSwitchCell
            cell.configure(title: title, subtitle: subtitle, value: value, onChange: onChange)
            cell.applyTheme(palette)
            return cell

        case .detail(let title, let value, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.detail, for: indexPath) as! FormDetailCell
            cell.configure(title: title, value: value)
            cell.applyTheme(palette)
            return cell

        case .action(let title, let style, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.action, for: indexPath) as! FormActionCell
            cell.configure(title: title, style: style)
            cell.applyTheme(palette)
            return cell

        case .slider(let title, let value, let minimum, let maximum, let step, let format, let onChange):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.slider, for: indexPath) as! FormSliderCell
            cell.configure(title: title,
                           value: value,
                           minimum: minimum,
                           maximum: maximum,
                           step: step,
                           format: format,
                           onChange: onChange)
            cell.applyTheme(palette)
            return cell

        case .note(let text):
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.note, for: indexPath) as! FormNoteCell
            cell.configure(text: text)
            cell.applyTheme(palette)
            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .detail(_, _, let onTap):
            view.endEditing(true)
            onTap()
        case .action(_, _, let onTap):
            view.endEditing(true)
            onTap()
        default:
            break
        }
    }
}

// MARK: - 单元格

final class FormTextFieldCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let textField = UITextField()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = Theme.caption
        titleLabel.numberOfLines = 1
        textField.font = Theme.body
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.clearButtonMode = .whileEditing
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String,
                   value: String,
                   placeholder: String,
                   secure: Bool,
                   keyboard: UIKeyboardType,
                   autocapitalization: UITextAutocapitalizationType,
                   onChange: @escaping (String) -> Void) {
        titleLabel.text = title
        self.onChange = onChange
        if textField.text != value { textField.text = value }
        textField.placeholder = placeholder
        textField.isSecureTextEntry = secure
        textField.keyboardType = keyboard
        textField.autocapitalizationType = autocapitalization
        textField.returnKeyType = .done
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.secondaryText
        textField.textColor = palette.primaryText
        textField.tintColor = palette.accent
        textField.attributedPlaceholder = NSAttributedString(
            string: textField.placeholder ?? "",
            attributes: [.foregroundColor: palette.tertiaryText])
    }

    @objc private func editingChanged() {
        onChange?(textField.text ?? "")
    }
}

final class FormLongTextCell: UITableViewCell, UITextViewDelegate {

    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private var onChange: ((String) -> Void)?
    private var heightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = Theme.caption

        textView.font = Theme.body
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.font = Theme.body
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.roundCorners(8)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)
        container.addSubview(placeholderLabel)

        let stack = UIStackView(arrangedSubviews: [titleLabel, container])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        heightConstraint = container.heightAnchor.constraint(equalToConstant: 96)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            heightConstraint!,

            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            textView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 2),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String,
                   value: String,
                   placeholder: String,
                   minHeight: CGFloat,
                   onChange: @escaping (String) -> Void) {
        titleLabel.text = title
        if textView.text != value { textView.text = value }
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !value.isEmpty
        heightConstraint?.constant = minHeight
        self.onChange = onChange
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.secondaryText
        textView.textColor = palette.primaryText
        textView.tintColor = palette.accent
        placeholderLabel.textColor = palette.tertiaryText
        if let container = textView.superview {
            container.backgroundColor = palette.surfaceAlt
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        onChange?(textView.text ?? "")
    }
}

final class FormSwitchCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = Theme.body
        titleLabel.numberOfLines = 0
        subtitleLabel.font = Theme.caption
        subtitleLabel.numberOfLines = 0
        toggle.addTarget(self, action: #selector(switched), for: .valueChanged)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [textStack, toggle])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String?, value: Bool, onChange: @escaping (Bool) -> Void) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle ?? "").isEmpty
        toggle.isOn = value
        self.onChange = onChange
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.primaryText
        subtitleLabel.textColor = palette.tertiaryText
        toggle.onTintColor = palette.accent
    }

    @objc private func switched() {
        onChange?(toggle.isOn)
    }
}

final class FormDetailCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        titleLabel.font = Theme.body
        valueLabel.font = Theme.footnote
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        chevron.contentMode = .scaleAspectFit

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.primaryText
        valueLabel.textColor = palette.secondaryText
        chevron.image = Icon.chevronRight.image(size: 14, color: palette.tertiaryText)
        tintColor = palette.accent
    }
}

final class FormActionCell: UITableViewCell {

    private let titleLabel = UILabel()
    private var style: FormRowStyle = .accent

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        titleLabel.font = Theme.body
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -13)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, style: FormRowStyle) {
        titleLabel.text = title
        self.style = style
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        switch style {
        case .normal: titleLabel.textColor = palette.primaryText
        case .accent: titleLabel.textColor = palette.accent
        case .destructive: titleLabel.textColor = palette.danger
        }
    }
}

final class FormSliderCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var onChange: ((Double) -> Void)?
    private var format: ((Double) -> String)?
    private var step: Double = 0.1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = Theme.body
        valueLabel.font = Theme.caption.monospacedDigits()
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        headerStack.axis = .horizontal
        headerStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [headerStack, slider])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String,
                   value: Double,
                   minimum: Double,
                   maximum: Double,
                   step: Double,
                   format: @escaping (Double) -> String,
                   onChange: @escaping (Double) -> Void) {
        titleLabel.text = title
        slider.minimumValue = Float(minimum)
        slider.maximumValue = Float(maximum)
        slider.value = Float(value)
        valueLabel.text = format(value)
        self.step = step
        self.format = format
        self.onChange = onChange
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        titleLabel.textColor = palette.primaryText
        valueLabel.textColor = palette.secondaryText
        slider.minimumTrackTintColor = palette.accent
        slider.maximumTrackTintColor = palette.surfaceAlt
        slider.thumbTintColor = palette.accent
    }

    @objc private func sliderChanged() {
        if step > 0 {
            let rounded = (Double(slider.value) / step).rounded() * step
            slider.value = Float(rounded)
        }
        let value = Double(slider.value)
        // 就地更新数值标签：不 reload 表单，避免打断拖动
        valueLabel.text = format?(value)
        onChange?(value)
    }
}

final class FormNoteCell: UITableViewCell {

    private let textLabel2 = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textLabel2.font = Theme.caption
        textLabel2.numberOfLines = 0
        textLabel2.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textLabel2)
        NSLayoutConstraint.activate([
            textLabel2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textLabel2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textLabel2.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textLabel2.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String) {
        textLabel2.text = text
    }

    func applyTheme(_ palette: Palette) {
        backgroundColor = palette.surface
        textLabel2.textColor = palette.tertiaryText
    }
}
