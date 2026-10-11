//
//  SSEReader.swift
//  AIAssistant
//
//  极简 SSE（Server-Sent Events）解析器。
//  只做一件事：把 TCP 收到的字节流切成一个个 event。
//  注意：只在"空行"处分包再 decode UTF-8，避免半个汉字被截断。
//

import Foundation

struct SSEEvent {
    var name: String?
    var data: String

    /// 便捷取 JSON
    func json() -> [String: Any]? {
        guard let data = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }
}

final class SSEReader {

    private var buffer = Data()
    /// 防御：异常服务端可能一直不发空行，限制缓冲上限
    private let maxBuffer = 1024 * 1024

    private static let lf = Data([0x0A, 0x0A])          // \n\n
    private static let crlf = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    func append(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        var events: [SSEEvent] = []

        while true {
            let lfRange = buffer.range(of: Self.lf)
            let crlfRange = buffer.range(of: Self.crlf)

            var cut: Range<Data.Index>?
            if let a = lfRange, let b = crlfRange {
                cut = a.lowerBound <= b.lowerBound ? a : b
            } else {
                cut = lfRange ?? crlfRange
            }
            guard let separator = cut else { break }

            let blockData = buffer.subdata(in: 0..<separator.lowerBound)
            buffer.removeSubrange(0..<separator.upperBound)
            if let block = String(data: blockData, encoding: .utf8) {
                events.append(contentsOf: Self.parse(block: block))
            }
        }

        if buffer.count > maxBuffer { buffer.removeAll(keepingCapacity: true) }
        return events
    }

    /// 连接结束时把残留内容也解出来（少数服务端最后一条不带空行）
    func flush() -> [SSEEvent] {
        guard !buffer.isEmpty, let block = String(data: buffer, encoding: .utf8) else { return [] }
        buffer.removeAll(keepingCapacity: true)
        return Self.parse(block: block)
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private static func parse(block: String) -> [SSEEvent] {
        var name: String?
        var dataLines: [String] = []

        for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty { continue }
            if line.hasPrefix(":") { continue }  // 注释（心跳包）

            let field: String
            var value: String
            if let colon = line.firstIndex(of: ":") {
                field = String(line[line.startIndex..<colon])
                value = String(line[line.index(after: colon)...])
                if value.hasPrefix(" ") { value.removeFirst() }
            } else {
                field = line
                value = ""
            }

            switch field {
            case "event": name = value
            case "data": dataLines.append(value)
            default: break // id / retry 用不到
            }
        }

        guard !dataLines.isEmpty else { return [] }
        return [SSEEvent(name: name, data: dataLines.joined(separator: "\n"))]
    }
}
