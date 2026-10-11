//
//  RecordOverlayView.swift
//  AIAssistant
//
//  "按住说话"的浮层：中间一张卡片 + 5 根波形柱。
//  波形完全靠改 frame 驱动（20Hz），不用 CoreAnimation 的复杂动画，
//  iPhone 5s 上只有 6 个视图在动，几乎不占性能。
//

import UIKit

final class RecordOverlayView: UIView {

    private let card = UIView()
    private let barContainer = UIView()
    private let bars: [UIView] = (0..<5).map { _ in UIView() }
    private let titleLabel = UILabel()
    private let timerLabel = UILabel()
    private var lastLevels: [CGFloat] = Array(repeating: 0.1, count: 5)

    private static let barWidth: CGFloat = 5
    private static let barSpacing: CGFloat = 6
    private static let barAreaHeight: CGFloat = 34
    private static var barsTotalWidth: CGFloat {
        return CGFloat(5) * barWidth + 4 * barSpacing
    }

    private(set) var isCancelMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.18)
        alpha = 0
        isUserInteractionEnabled = false

        card.translatesAutoresizingMaskIntoConstraints = false
        card.roundCorners(20)
        addSubview(card)

        // 波形柱故意不用 Auto Layout：每 0.05s 改一次 constraint.constant 会
        // 反复触发整窗布局，A7 上不划算。这里用一个固定高度的容器 + 手写 frame。
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        addBars()

        titleLabel.font = Theme.font(15, weight: .medium)
        titleLabel.textColor = UIColor.white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        timerLabel.font = Theme.font(13).monospacedDigits()
        timerLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        timerLabel.textAlignment = .center
        timerLabel.text = "0:00"

        let stack = UIStackView(arrangedSubviews: [barContainer, titleLabel, timerLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 168),
            card.heightAnchor.constraint(equalToConstant: 152),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
            barContainer.heightAnchor.constraint(equalToConstant: Self.barAreaHeight),
            barContainer.widthAnchor.constraint(equalToConstant: Self.barsTotalWidth)
        ])

        setCancelMode(false)
    }

    private func addBars() {
        for bar in bars {
            bar.backgroundColor = UIColor.white
            bar.roundCorners(2.5)
            barContainer.addSubview(bar)
        }
    }

    // MARK: - 显示 / 隐藏

    func show(in window: UIView) {
        frame = window.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if superview == nil { window.addSubview(self) }
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
    }

    func hide() {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }

    // MARK: - 更新

    func update(level: CGFloat, seconds: Double) {
        timerLabel.text = format(seconds)

        // 波形往前跑：丢掉最旧的采样，压入最新音量
        lastLevels.removeFirst()
        lastLevels.append(max(0, min(1, level)))
        layoutBars()
    }

    private func layoutBars() {
        let area = barContainer.bounds
        guard area.width > 0 else { return }
        var x = (area.width - Self.barsTotalWidth) / 2
        for (index, bar) in bars.enumerated() {
            let height = max(6, min(Self.barAreaHeight, 6 + lastLevels[index] * 28))
            bar.frame = CGRect(x: x,
                               y: (area.height - height) / 2,
                               width: Self.barWidth,
                               height: height)
            x += Self.barWidth + Self.barSpacing
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutBars()
    }

    func setCancelMode(_ cancel: Bool) {
        isCancelMode = cancel
        card.backgroundColor = cancel
            ? UIColor(hex: "#D8453F").withAlphaComponent(0.96)
            : UIColor(hex: "#2A2D33").withAlphaComponent(0.94)
        titleLabel.text = cancel ? L10n.releaseToCancel : L10n.slideUpToCancel
        for bar in bars { bar.backgroundColor = UIColor.white }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
