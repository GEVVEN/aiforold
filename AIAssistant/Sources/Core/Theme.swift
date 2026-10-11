//
//  Theme.swift
//  AIAssistant
//
//  自绘配色。刻意不用 UIColor.systemBackground / .label 之类的
//  动态色（iOS 13+），这样才能在 iOS 12 上跑，同时保证深色模式自己可控。
//

import UIKit

extension Notification.Name {
    static let appThemeDidChange = Notification.Name("app.themeDidChange")
    static let appSettingsDidChange = Notification.Name("app.settingsDidChange")
}

struct Palette {
    var background: UIColor
    var surface: UIColor
    var surfaceAlt: UIColor
    var bubbleUser: UIColor
    var bubbleUserText: UIColor
    var bubbleAssistant: UIColor
    var bubbleAssistantText: UIColor
    var primaryText: UIColor
    var secondaryText: UIColor
    var tertiaryText: UIColor
    var divider: UIColor
    var accent: UIColor
    var accentSoft: UIColor
    var danger: UIColor
    var codeBackground: UIColor
    var navBackground: UIColor
    var inputBackground: UIColor
    var isDark: Bool
}

enum Theme {

    static let accentHex = "#4C6FFF"

    private static let light = Palette(
        background: UIColor(hex: "#F5F6F8"),
        surface: UIColor(hex: "#FFFFFF"),
        surfaceAlt: UIColor(hex: "#EFF1F5"),
        bubbleUser: UIColor(hex: "#4C6FFF"),
        bubbleUserText: UIColor(hex: "#FFFFFF"),
        bubbleAssistant: UIColor(hex: "#FFFFFF"),
        bubbleAssistantText: UIColor(hex: "#1A1C1E"),
        primaryText: UIColor(hex: "#1A1C1E"),
        secondaryText: UIColor(hex: "#6B7280"),
        tertiaryText: UIColor(hex: "#9AA1AC"),
        divider: UIColor(hex: "#E3E6EB"),
        accent: UIColor(hex: "#4C6FFF"),
        accentSoft: UIColor(hex: "#E8EDFF"),
        danger: UIColor(hex: "#FF4D4F"),
        codeBackground: UIColor(hex: "#F0F1F4"),
        navBackground: UIColor(hex: "#FFFFFF"),
        inputBackground: UIColor(hex: "#FFFFFF"),
        isDark: false
    )

    private static let dark = Palette(
        background: UIColor(hex: "#121316"),
        surface: UIColor(hex: "#1C1E22"),
        surfaceAlt: UIColor(hex: "#23262B"),
        bubbleUser: UIColor(hex: "#3D5BD9"),
        bubbleUserText: UIColor(hex: "#FFFFFF"),
        bubbleAssistant: UIColor(hex: "#1C1E22"),
        bubbleAssistantText: UIColor(hex: "#ECEDEF"),
        primaryText: UIColor(hex: "#ECEDEF"),
        secondaryText: UIColor(hex: "#9DA3AD"),
        tertiaryText: UIColor(hex: "#6E747D"),
        divider: UIColor(hex: "#2C3036"),
        accent: UIColor(hex: "#6C8BFF"),
        accentSoft: UIColor(hex: "#262C44"),
        danger: UIColor(hex: "#FF6B6D"),
        codeBackground: UIColor(hex: "#22252A"),
        navBackground: UIColor(hex: "#181A1E"),
        inputBackground: UIColor(hex: "#1C1E22"),
        isDark: true
    )

    private(set) static var current: Palette = light
    private(set) static var mode: AppTheme = .system

    /// 跟随系统只在 iOS 13+ 有意义；iOS 12 一律按浅色处理。
    static func apply(_ theme: AppTheme) {
        mode = theme
        switch theme {
        case .light:
            current = light
        case .dark:
            current = dark
        case .system:
            if #available(iOS 13.0, *) {
                current = (UITraitCollection.current.userInterfaceStyle == .dark) ? dark : light
            } else {
                current = light
            }
        }
    }

    // MARK: 圆角 / 间距（4 英寸屏也够用）

    static let bubbleRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let hairline: CGFloat = 1 / UIScreen.main.scale

    static func isCompactWidth(_ width: CGFloat = UIScreen.main.bounds.width) -> Bool {
        return width <= 320  // iPhone 5/5s/SE1 竖屏宽度 320
    }

    // MARK: 字体

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static var body: UIFont { font(Theme.isCompactWidth() ? 15 : 16) }
    static var bodyBold: UIFont { font(Theme.isCompactWidth() ? 15 : 16, weight: .semibold) }
    static var caption: UIFont { font(12) }
    static var footnote: UIFont { font(13) }
    static var title: UIFont { font(17, weight: .semibold) }
    static var code: UIFont { UIFont(name: "Menlo", size: 13) ?? font(13) }
}

// MARK: - 便捷扩展

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            var expanded = ""
            for c in s { expanded.append(c); expanded.append(c) }
            s = expanded
        }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    func mix(with other: UIColor, ratio: CGFloat) -> UIColor {
        let t = max(0, min(1, ratio))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}

extension UIView {
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }

    func roundCorners(_ radius: CGFloat) {
        layer.cornerRadius = radius
        if #available(iOS 11.0, *) {
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                   .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        layer.masksToBounds = true
    }

    func addHairlineBottom(_ color: UIColor) {
        let line = UIView()
        line.backgroundColor = color
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: Theme.hairline)
        ])
    }
}

extension UIViewController {
    /// iOS 13 起 modal 默认是 pageSheet，统一强制全屏，避免 4 英寸屏上被裁。
    func presentFullScreen(_ vc: UIViewController, animated: Bool = true) {
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: animated, completion: nil)
    }

    func showAlert(title: String?, message: String?, actionTitle: String = L10n.ok) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    /// 跳系统设置（权限被拒时引导用户）
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

extension UIFont {
    func monospacedDigits() -> UIFont {
        if #available(iOS 9.0, *) {
            return UIFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        }
        return self
    }
}
