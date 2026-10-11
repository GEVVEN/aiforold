//
//  Toast.swift
//  AIAssistant
//
//  轻量提示，替代 MBProgressHUD（少一个依赖，也少几 MB 内存）。
//

import UIKit

enum Toast {

    private static var current: UIView?

    static func show(_ text: String, duration: TimeInterval = 1.8) {
        guard !text.isEmpty else { return }
        guard let window = keyWindow() else { return }

        current?.removeFromSuperview()

        let container = UIView()
        container.backgroundColor = Theme.current.isDark
            ? UIColor(hex: "#2A2D33")
            : UIColor(hex: "#1F2226")
        container.alpha = 0
        container.roundCorners(10)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.textColor = UIColor.white
        label.font = Theme.footnote
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        window.addSubview(container)
        current = container

        let maxWidth = min(window.bounds.width - 64, 320)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            container.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: window.bottomAnchor, constant: -110)
        ])

        UIView.animate(withDuration: 0.18, animations: {
            container.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: duration, options: [], animations: {
                container.alpha = 0
            }, completion: { _ in
                container.removeFromSuperview()
                if current === container { current = nil }
            })
        })
    }

    static func error(_ text: String) {
        show(text, duration: 2.6)
    }

    private static func keyWindow() -> UIWindow? {
        if let window = UIApplication.shared.delegate?.window, let window = window { return window }
        for window in UIApplication.shared.windows where window.isKeyWindow { return window }
        return UIApplication.shared.windows.first
    }
}
