//
//  MarkdownLite.swift
//  AIAssistant
//
//  自己写一个"够用就好"的 Markdown 渲染（标题 / 粗体 / 斜体 / 行内代码 /
//  代码块 / 列表 / 引用 / 链接）。
//  为什么不用第三方库？渲染一次几十毫秒、几 MB 内存，在 iPhone 5s 上都是负担。
//  另外流式输出时（每秒改十几次）不调用这里，直接用纯文本，避免反复排版。
//

import UIKit

struct MarkdownStyle {
    var baseFont: UIFont
    var textColor: UIColor
    var secondaryColor: UIColor
    var codeFont: UIFont
    var codeBackground: UIColor
    var accent: UIColor
    var isDark: Bool

    static var chatBubble: MarkdownStyle {
        MarkdownStyle(baseFont: Theme.body,
                      textColor: Theme.current.bubbleAssistantText,
                      secondaryColor: Theme.current.secondaryText,
                      codeFont: Theme.code,
                      codeBackground: Theme.current.codeBackground,
                      accent: Theme.current.accent,
                      isDark: Theme.current.isDark)
    }

    static var userBubble: MarkdownStyle {
        MarkdownStyle(baseFont: Theme.body,
                      textColor: Theme.current.bubbleUserText,
                      secondaryColor: Theme.current.bubbleUserText.withAlphaComponent(0.75),
                      codeFont: Theme.code,
                      codeBackground: UIColor.white.withAlphaComponent(0.16),
                      accent: UIColor.white,
                      isDark: Theme.current.isDark)
    }
}

enum MarkdownLite {

    /// 单次渲染的字符上限：超长内容直接截断，避免 5s 卡住
    private static let maxCharacters = 12000

    static func render(_ markdown: String, style: MarkdownStyle) -> NSAttributedString {
        var text = markdown
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)) + "\n…（内容过长，已截断显示）"
        }

        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 6
        paragraph.lineBreakMode = .byWordWrapping

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: style.baseFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraph
        ]

        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBuffer: [String] = []

        func flushCode() {
            guard !codeBuffer.isEmpty else { return }
            let joined = codeBuffer.joined(separator: "\n")
            let codeParagraph = NSMutableParagraphStyle()
            codeParagraph.lineSpacing = 2
            codeParagraph.paragraphSpacing = 6
            codeParagraph.firstLineHeadIndent = 6
            codeParagraph.headIndent = 6
            let attributes: [NSAttributedString.Key: Any] = [
                .font: style.codeFont,
                .foregroundColor: style.textColor,
                .backgroundColor: style.codeBackground,
                .paragraphStyle: codeParagraph
            ]
            result.append(NSAttributedString(string: joined + "\n", attributes: attributes))
            codeBuffer.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    flushCode()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBuffer.append(line)
                continue
            }

            if trimmed.isEmpty {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                continue
            }

            // 标题
            if let heading = headingLevel(of: trimmed) {
                let size: CGFloat = heading == 1 ? 19 : (heading == 2 ? 17 : 15.5)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: Theme.font(size, weight: .semibold),
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraph
                ]
                let content = String(trimmed.dropFirst(heading)).trimmingCharacters(in: .whitespaces)
                appendInline(content, to: result, attributes: attributes, style: style)
                result.append(NSAttributedString(string: "\n", attributes: attributes))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                var attributes = baseAttributes
                attributes[.foregroundColor] = style.secondaryColor
                result.append(NSAttributedString(string: "▏", attributes: [
                    .font: style.baseFont,
                    .foregroundColor: style.accent,
                    .paragraphStyle: paragraph
                ]))
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                appendInline(content, to: result, attributes: attributes, style: style)
                result.append(NSAttributedString(string: "\n", attributes: attributes))
                continue
            }

            // 列表
            if let bullet = listMarker(of: trimmed) {
                let content = String(trimmed.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
                result.append(NSAttributedString(string: "  • ", attributes: baseAttributes))
                appendInline(content, to: result, attributes: baseAttributes, style: style)
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
                continue
            }

            appendInline(line, to: result, attributes: baseAttributes, style: style)
            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
        }

        if inCodeBlock { flushCode() }

        // 去掉最后一个换行，避免气泡底部多一行空白
        if result.length > 0 {
            let last = result.attributedSubstring(from: NSRange(location: result.length - 1, length: 1)).string
            if last == "\n" {
                result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
            }
        }
        return result
    }

    /// 纯文本（用于朗读、复制）
    static func plain(_ markdown: String) -> String {
        return markdown
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
    }

    // MARK: - 私有

    private static func headingLevel(of line: String) -> Int? {
        var count = 0
        for character in line {
            if character == "#" { count += 1 } else { break }
        }
        guard count > 0, count <= 4, line.count > count else { return nil }
        let next = line[line.index(line.startIndex, offsetBy: count)]
        return next == " " ? count : nil
    }

    private static func listMarker(of line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.prefix(2))
        }
        // 1. 2. 3.
        var digits = ""
        for character in line {
            if character.isNumber, digits.count < 3 { digits.append(character) } else { break }
        }
        if !digits.isEmpty, line.hasPrefix(digits + ". ") {
            return digits + ". "
        }
        return nil
    }

    /// 行内样式：**粗体**、*斜体*、`代码`、[链接](url)、裸 URL
    private static func appendInline(_ text: String,
                                     to result: NSMutableAttributedString,
                                     attributes: [NSAttributedString.Key: Any],
                                     style: MarkdownStyle) {
        var index = text.startIndex
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            result.append(NSAttributedString(string: plain, attributes: attributes))
            plain.removeAll(keepingCapacity: true)
        }

        while index < text.endIndex {
            let character = text[index]

            if character == "*", matches(text, at: index, "**") {
                if let end = findClosing(text, marker: "**", from: text.index(index, offsetBy: 2)) {
                    flushPlain()
                    var bold = attributes
                    let font = (attributes[.font] as? UIFont) ?? style.baseFont
                    bold[.font] = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
                    let content = String(text[text.index(index, offsetBy: 2)..<end])
                    result.append(NSAttributedString(string: content, attributes: bold))
                    index = text.index(end, offsetBy: 2)
                    continue
                }
            }

            if character == "`" {
                if let end = text[text.index(after: index)...].firstIndex(of: "`") {
                    flushPlain()
                    var codeAttributes = attributes
                    codeAttributes[.font] = style.codeFont
                    codeAttributes[.backgroundColor] = style.codeBackground
                    let content = String(text[text.index(after: index)..<end])
                    result.append(NSAttributedString(string: content, attributes: codeAttributes))
                    index = text.index(after: end)
                    continue
                }
            }

            if character == "[" {
                if let close = text[index...].firstIndex(of: "]"),
                   text.index(after: close) < text.endIndex,
                   text[text.index(after: close)] == "(",
                   let urlEnd = text[text.index(close, offsetBy: 2)...].firstIndex(of: ")") {
                    flushPlain()
                    var linkAttributes = attributes
                    linkAttributes[.foregroundColor] = style.accent
                    linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    let label = String(text[text.index(after: index)..<close])
                    result.append(NSAttributedString(string: label.isEmpty ? "链接" : label,
                                                     attributes: linkAttributes))
                    index = text.index(after: urlEnd)
                    continue
                }
            }

            if matches(text, at: index, "http://") || matches(text, at: index, "https://") {
                var end = text.endIndex
                var cursor = index
                while cursor < text.endIndex {
                    let c = text[cursor]
                    if c == " " || c == "\n" || c == "）" || c == ")" { end = cursor; break }
                    cursor = text.index(after: cursor)
                }
                let url = String(text[index..<end])
                if url.count > 8 {
                    flushPlain()
                    var linkAttributes = attributes
                    linkAttributes[.foregroundColor] = style.accent
                    linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    result.append(NSAttributedString(string: url, attributes: linkAttributes))
                    index = end
                    continue
                }
            }

            if character == "*" || character == "_" {
                let marker = String(character)
                if let end = findClosing(text, marker: marker, from: text.index(after: index)) {
                    flushPlain()
                    var italic = attributes
                    let font = (attributes[.font] as? UIFont) ?? style.baseFont
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                        italic[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
                    }
                    let content = String(text[text.index(after: index)..<end])
                    result.append(NSAttributedString(string: content, attributes: italic))
                    index = text.index(after: end)
                    continue
                }
            }

            plain.append(character)
            index = text.index(after: index)
        }

        flushPlain()
    }

    private static func findClosing(_ text: String, marker: String, from start: String.Index) -> String.Index? {
        guard start < text.endIndex else { return nil }
        var index = start
        while index < text.endIndex {
            if matches(text, at: index, marker) { return index }
            index = text.index(after: index)
        }
        return nil
    }

    /// 不生成子串的前缀比较（避免 O(n²) 的内存分配）
    private static func matches(_ text: String, at index: String.Index, _ pattern: String) -> Bool {
        var cursor = index
        for character in pattern {
            guard cursor < text.endIndex, text[cursor] == character else { return false }
            cursor = text.index(after: cursor)
        }
        return true
    }
}
