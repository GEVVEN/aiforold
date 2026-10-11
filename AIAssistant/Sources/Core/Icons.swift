//
//  Icons.swift
//  AIAssistant
//
//  全部图标用 Core Graphics 现画，不依赖 SF Symbols（iOS 13+）、
//  也不带任何图片资源。好处：
//    1) iOS 12 上可用；
//    2) 包体极小、内存占用极低（iPhone 5s 友好）；
//    3) 颜色随主题走，不用准备两套切图。
//

import UIKit

enum Icon: String, CaseIterable {
    case plus, mic, send, stop, camera, video, photo, gear
    case back, chevronRight, chevronDown, trash, close, check, refresh
    case copy, speaker, sparkle, play, keyboard, key, link, warning, more, doc

    func image(size: CGFloat = 24, color: UIColor = Theme.current.primaryText) -> UIImage {
        let key = "\(rawValue)-\(Int(size))-\(color.rgbaKey)" as NSString
        if let cached = Icon.cache.object(forKey: key) { return cached }
        let image = Icon.draw(self, size: size, color: color)
        Icon.cache.setObject(image, forKey: key)
        return image
    }

    func barButtonImage(color: UIColor = Theme.current.primaryText) -> UIImage {
        image(size: 22, color: color)
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func clearCache() { cache.removeAllObjects() }

    // MARK: - 绘制

    private static func draw(_ icon: Icon, size: CGFloat, color: UIColor) -> UIImage {
        let scale = UIScreen.main.scale
        // 逻辑坐标固定 24x24，再按需要缩放，保证小尺寸下线条依然清晰
        let canvas: CGFloat = 24
        let target = CGSize(width: size, height: size)
        UIGraphicsBeginImageContextWithOptions(target, false, scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }

        ctx.scaleBy(x: size / canvas, y: size / canvas)
        color.setStroke()
        color.setFill()
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch icon {
        case .plus:
            line(ctx, [CGPoint(x: 12, y: 5.5), CGPoint(x: 12, y: 18.5)])
            line(ctx, [CGPoint(x: 5.5, y: 12), CGPoint(x: 18.5, y: 12)])

        case .close:
            line(ctx, [CGPoint(x: 6.5, y: 6.5), CGPoint(x: 17.5, y: 17.5)])
            line(ctx, [CGPoint(x: 17.5, y: 6.5), CGPoint(x: 6.5, y: 17.5)])

        case .check:
            line(ctx, [CGPoint(x: 5, y: 12.5), CGPoint(x: 10, y: 17.5), CGPoint(x: 19, y: 7)])

        case .back:
            line(ctx, [CGPoint(x: 14.5, y: 5), CGPoint(x: 8, y: 12), CGPoint(x: 14.5, y: 19)])

        case .chevronRight:
            line(ctx, [CGPoint(x: 9.5, y: 5), CGPoint(x: 16, y: 12), CGPoint(x: 9.5, y: 19)])

        case .chevronDown:
            line(ctx, [CGPoint(x: 5, y: 9.5), CGPoint(x: 12, y: 16), CGPoint(x: 19, y: 9.5)])

        case .mic:
            // 话筒头
            let mic = UIBezierPath(roundedRect: CGRect(x: 9.2, y: 3.2, width: 5.6, height: 10.4),
                                   cornerRadius: 2.8)
            mic.lineWidth = 1.8
            mic.stroke()
            // 支架
            let stand = UIBezierPath()
            stand.move(to: CGPoint(x: 5.8, y: 11.4))
            stand.addArc(withCenter: CGPoint(x: 12, y: 11.4), radius: 6.2,
                         startAngle: 0, endAngle: .pi, clockwise: false)
            stand.lineWidth = 1.8
            stand.stroke()
            line(ctx, [CGPoint(x: 12, y: 17.6), CGPoint(x: 12, y: 20.4)])
            line(ctx, [CGPoint(x: 8.6, y: 20.6), CGPoint(x: 15.4, y: 20.6)])

        case .send:
            // 纸飞机
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 3.5, y: 11.2))
            path.addLine(to: CGPoint(x: 20.5, y: 4.2))
            path.addLine(to: CGPoint(x: 14.6, y: 20.5))
            path.addLine(to: CGPoint(x: 11.6, y: 13.6))
            path.close()
            path.lineWidth = 1.8
            path.lineJoinStyle = .round
            path.stroke()
            line(ctx, [CGPoint(x: 11.6, y: 13.6), CGPoint(x: 20.5, y: 4.2)])

        case .stop:
            let rect = UIBezierPath(roundedRect: CGRect(x: 7.5, y: 7.5, width: 9, height: 9), cornerRadius: 2)
            rect.fill()

        case .camera:
            let body = UIBezierPath(roundedRect: CGRect(x: 3.2, y: 7.2, width: 17.6, height: 12.6), cornerRadius: 3)
            body.lineWidth = 1.8
            body.stroke()
            // 顶部取景凸起
            let bump = UIBezierPath()
            bump.move(to: CGPoint(x: 8.6, y: 7.2))
            bump.addLine(to: CGPoint(x: 9.8, y: 4.6))
            bump.addLine(to: CGPoint(x: 14.2, y: 4.6))
            bump.addLine(to: CGPoint(x: 15.4, y: 7.2))
            bump.lineWidth = 1.8
            bump.stroke()
            let lens = UIBezierPath(arcCenter: CGPoint(x: 12, y: 13.4), radius: 3.4,
                                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
            lens.lineWidth = 1.8
            lens.stroke()

        case .video:
            let body = UIBezierPath(roundedRect: CGRect(x: 3.2, y: 7, width: 12.4, height: 10), cornerRadius: 2.6)
            body.lineWidth = 1.8
            body.stroke()
            let lens = UIBezierPath()
            lens.move(to: CGPoint(x: 16.4, y: 10.2))
            lens.addLine(to: CGPoint(x: 20.8, y: 7.6))
            lens.addLine(to: CGPoint(x: 20.8, y: 16.4))
            lens.addLine(to: CGPoint(x: 16.4, y: 13.8))
            lens.close()
            lens.lineWidth = 1.8
            lens.stroke()

        case .photo:
            let frame = UIBezierPath(roundedRect: CGRect(x: 3.4, y: 5.2, width: 17.2, height: 13.6), cornerRadius: 2.6)
            frame.lineWidth = 1.8
            frame.stroke()
            let hill = UIBezierPath()
            hill.move(to: CGPoint(x: 6, y: 16.6))
            hill.addLine(to: CGPoint(x: 10.6, y: 11.4))
            hill.addLine(to: CGPoint(x: 13.6, y: 14.6))
            hill.addLine(to: CGPoint(x: 16, y: 12.4))
            hill.addLine(to: CGPoint(x: 18.6, y: 16.6))
            hill.lineWidth = 1.8
            hill.stroke()
            let sun = UIBezierPath(arcCenter: CGPoint(x: 8.6, y: 9), radius: 1.5,
                                   startAngle: 0, endAngle: .pi * 2, clockwise: true)
            sun.fill()

        case .gear:
            let ring = UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: 3.6,
                                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ring.lineWidth = 1.8
            ring.stroke()
            for index in 0..<8 {
                let angle = CGFloat(index) * (.pi / 4)
                let inner: CGFloat = 6.6
                let outer: CGFloat = 9.4
                let p1 = CGPoint(x: 12 + cos(angle) * inner, y: 12 + sin(angle) * inner)
                let p2 = CGPoint(x: 12 + cos(angle) * outer, y: 12 + sin(angle) * outer)
                line(ctx, [p1, p2])
            }

        case .trash:
            line(ctx, [CGPoint(x: 4.5, y: 7), CGPoint(x: 19.5, y: 7)])
            let lid = UIBezierPath()
            lid.move(to: CGPoint(x: 9.5, y: 7))
            lid.addLine(to: CGPoint(x: 10.2, y: 4.4))
            lid.addLine(to: CGPoint(x: 13.8, y: 4.4))
            lid.addLine(to: CGPoint(x: 14.5, y: 7))
            lid.lineWidth = 1.8
            lid.stroke()
            let body = UIBezierPath()
            body.move(to: CGPoint(x: 6.4, y: 7))
            body.addLine(to: CGPoint(x: 7.4, y: 20))
            body.addLine(to: CGPoint(x: 16.6, y: 20))
            body.addLine(to: CGPoint(x: 17.6, y: 7))
            body.lineWidth = 1.8
            body.stroke()
            line(ctx, [CGPoint(x: 10.4, y: 10), CGPoint(x: 10.8, y: 17)])
            line(ctx, [CGPoint(x: 13.6, y: 10), CGPoint(x: 13.2, y: 17)])

        case .refresh:
            let arc = UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: 7.2,
                                   startAngle: -.pi / 3, endAngle: .pi * 1.35, clockwise: true)
            arc.lineWidth = 1.8
            arc.stroke()
            let head = UIBezierPath()
            head.move(to: CGPoint(x: 16.4, y: 2.6))
            head.addLine(to: CGPoint(x: 18.9, y: 7.3))
            head.addLine(to: CGPoint(x: 13.7, y: 8.1))
            head.lineWidth = 1.8
            head.lineJoinStyle = .round
            head.stroke()

        case .copy:
            let back = UIBezierPath(roundedRect: CGRect(x: 4.4, y: 3.6, width: 12, height: 12), cornerRadius: 2.6)
            back.lineWidth = 1.8
            back.stroke()
            let front = UIBezierPath(roundedRect: CGRect(x: 8.4, y: 8.4, width: 11.2, height: 11.2), cornerRadius: 2.6)
            front.lineWidth = 1.8
            front.stroke()

        case .speaker:
            let body = UIBezierPath()
            body.move(to: CGPoint(x: 4, y: 9.4))
            body.addLine(to: CGPoint(x: 7.6, y: 9.4))
            body.addLine(to: CGPoint(x: 12, y: 5.2))
            body.addLine(to: CGPoint(x: 12, y: 18.8))
            body.addLine(to: CGPoint(x: 7.6, y: 14.6))
            body.addLine(to: CGPoint(x: 4, y: 14.6))
            body.close()
            body.lineWidth = 1.8
            body.lineJoinStyle = .round
            body.stroke()
            let wave1 = UIBezierPath(arcCenter: CGPoint(x: 12.6, y: 12), radius: 4.2,
                                     startAngle: -.pi / 3.2, endAngle: .pi / 3.2, clockwise: true)
            wave1.lineWidth = 1.6
            wave1.stroke()
            let wave2 = UIBezierPath(arcCenter: CGPoint(x: 12.6, y: 12), radius: 7,
                                     startAngle: -.pi / 3.6, endAngle: .pi / 3.6, clockwise: true)
            wave2.lineWidth = 1.6
            wave2.stroke()

        case .sparkle:
            // 四角星：AI 头像
            let star = UIBezierPath()
            star.move(to: CGPoint(x: 12, y: 2.6))
            star.addQuadCurve(to: CGPoint(x: 21.4, y: 12), controlPoint: CGPoint(x: 13.4, y: 10.6))
            star.addQuadCurve(to: CGPoint(x: 12, y: 21.4), controlPoint: CGPoint(x: 13.4, y: 13.4))
            star.addQuadCurve(to: CGPoint(x: 2.6, y: 12), controlPoint: CGPoint(x: 10.6, y: 13.4))
            star.addQuadCurve(to: CGPoint(x: 12, y: 2.6), controlPoint: CGPoint(x: 10.6, y: 10.6))
            star.close()
            star.fill()

        case .play:
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: 8.4, y: 5.4))
            tri.addLine(to: CGPoint(x: 19, y: 12))
            tri.addLine(to: CGPoint(x: 8.4, y: 18.6))
            tri.close()
            tri.fill()

        case .keyboard:
            let frame = UIBezierPath(roundedRect: CGRect(x: 2.6, y: 6, width: 18.8, height: 12), cornerRadius: 2.6)
            frame.lineWidth = 1.7
            frame.stroke()
            for row in 0..<2 {
                for col in 0..<4 {
                    let x = 5.4 + CGFloat(col) * 3.9
                    let y = 9.4 + CGFloat(row) * 3.4
                    let dot = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 2.1, height: 2.1), cornerRadius: 0.6)
                    dot.fill()
                }
            }
            line(ctx, [CGPoint(x: 7.4, y: 15.6), CGPoint(x: 16.6, y: 15.6)])

        case .key:
            let ring = UIBezierPath(arcCenter: CGPoint(x: 8.4, y: 8.4), radius: 4.2,
                                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ring.lineWidth = 1.8
            ring.stroke()
            line(ctx, [CGPoint(x: 11.5, y: 11.5), CGPoint(x: 19.6, y: 19.6)])
            line(ctx, [CGPoint(x: 15.4, y: 15.4), CGPoint(x: 17.6, y: 13.2)])

        case .link:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 9.6, y: 14.4))
            path.addLine(to: CGPoint(x: 14.4, y: 9.6))
            path.lineWidth = 1.8
            path.stroke()
            let a = UIBezierPath(arcCenter: CGPoint(x: 8.2, y: 15.8), radius: 3.4,
                                 startAngle: .pi * 0.25, endAngle: .pi * 1.4, clockwise: true)
            a.lineWidth = 1.8
            a.stroke()
            let b = UIBezierPath(arcCenter: CGPoint(x: 15.8, y: 8.2), radius: 3.4,
                                 startAngle: .pi * 1.25, endAngle: .pi * 2.4, clockwise: true)
            b.lineWidth = 1.8
            b.stroke()

        case .warning:
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: 12, y: 3.6))
            tri.addLine(to: CGPoint(x: 21.4, y: 19.6))
            tri.addLine(to: CGPoint(x: 2.6, y: 19.6))
            tri.close()
            tri.lineWidth = 1.8
            tri.lineJoinStyle = .round
            tri.stroke()
            line(ctx, [CGPoint(x: 12, y: 9.6), CGPoint(x: 12, y: 14)])
            let dot = UIBezierPath(arcCenter: CGPoint(x: 12, y: 16.8), radius: 0.9,
                                   startAngle: 0, endAngle: .pi * 2, clockwise: true)
            dot.fill()

        case .more:
            for x in [6.6, 12.0, 17.4] {
                let dot = UIBezierPath(arcCenter: CGPoint(x: CGFloat(x), y: 12), radius: 1.5,
                                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
                dot.fill()
            }

        case .doc:
            let frame = UIBezierPath()
            frame.move(to: CGPoint(x: 6, y: 3.4))
            frame.addLine(to: CGPoint(x: 14, y: 3.4))
            frame.addLine(to: CGPoint(x: 18, y: 7.4))
            frame.addLine(to: CGPoint(x: 18, y: 20.6))
            frame.addLine(to: CGPoint(x: 6, y: 20.6))
            frame.close()
            frame.lineWidth = 1.8
            frame.lineJoinStyle = .round
            frame.stroke()
            line(ctx, [CGPoint(x: 8.6, y: 12), CGPoint(x: 15.4, y: 12)])
            line(ctx, [CGPoint(x: 8.6, y: 16), CGPoint(x: 13.4, y: 16)])
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    private static func line(_ ctx: CGContext, _ points: [CGPoint]) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

extension UIColor {
    var rgbaKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.2f-%.2f-%.2f-%.2f", r, g, b, a)
    }
}
