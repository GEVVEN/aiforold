//
//  ChatProvider.swift
//  AIAssistant
//
//  把「对话」翻译成各家 API 的请求体。目前支持两大类：
//    1. OpenAI 兼容（DeepSeek / OpenAI / 通义 / Moonshot / 硅基流动 / Ollama / one-api …）
//    2. Anthropic Claude Messages API
//  新增一家只要再加一个 Provider 实现即可，UI 与网络层都不用动。
//

import Foundation

// MARK: - 流式增量

enum StreamDeltaKind {
    case text
    case reasoning
    case done
    case failure
    case ignored
}

struct StreamDelta {
    var kind: StreamDeltaKind
    var value: String = ""

    static func text(_ value: String) -> StreamDelta { StreamDelta(kind: .text, value: value) }
    static func reasoning(_ value: String) -> StreamDelta { StreamDelta(kind: .reasoning, value: value) }
    static let done = StreamDelta(kind: .done)
    static func failure(_ value: String) -> StreamDelta { StreamDelta(kind: .failure, value: value) }
}

/// 非流式响应的解析结果
struct ChatCompletion {
    var text: String
    var reasoning: String?
    var model: String?
}

// MARK: - 请求内容中间表示

enum ContentPart {
    case text(String)
    case image(base64: String, mime: String, detail: String)
}

struct PreparedMessage {
    var role: MessageRole
    var parts: [ContentPart]

    var textOnly: String {
        parts.compactMap { part -> String? in
            if case .text(let value) = part { return value }
            return nil
        }.joined(separator: "\n")
    }

    var hasImage: Bool {
        parts.contains { if case .image = $0 { return true } else { return false } }
    }
}

/// 把内存里的 ChatMessage 整理成「文本 + 图片」的中间格式。
/// 视频会以关键帧的形式作为图片输入，音轨转写结果拼进文本。
enum MessagePreparer {

    static func prepare(_ messages: [ChatMessage],
                        profile: ProviderProfile,
                        imageDetail: String = "auto") -> [PreparedMessage] {
        var result: [PreparedMessage] = []
        var imageBudget = max(0, profile.maxImages)

        for message in messages {
            if message.role == .system { continue }  // 系统提示词单独走 system 字段

            var parts: [ContentPart] = []
            var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var notes: [String] = []
            var images: [ContentPart] = []

            let visualAttachments = message.attachments.filter { $0.isVisual }

            for attachment in message.attachments {
                switch attachment.kind {
                case .image:
                    if profile.supportsVision, imageBudget > 0,
                       let encoded = ImagePipeline.shared.base64(for: attachment) {
                        images.append(.image(base64: encoded.data,
                                             mime: encoded.mime,
                                             detail: imageDetail))
                        imageBudget -= 1
                    }
                    notes.append(attachment.summaryLine)
                case .video:
                    notes.append(attachment.summaryLine)
                    if let transcript = attachment.transcript, !transcript.isEmpty {
                        notes.append("视频里的语音内容：「\(transcript)」")
                    }
                    if profile.supportsVision, imageBudget > 0, !attachment.frameRelativePaths.isEmpty {
                        notes.append(L10n.videoFramesNote)
                        for path in attachment.frameRelativePaths {
                            guard imageBudget > 0 else { break }
                            if let encoded = ImagePipeline.shared.base64ForFrame(relativePath: path) {
                                images.append(.image(base64: encoded.data, mime: encoded.mime, detail: imageDetail))
                                imageBudget -= 1
                            }
                        }
                    }
                case .audio:
                    if let transcript = attachment.transcript, !transcript.isEmpty {
                        notes.append(transcript)
                    } else {
                        notes.append(attachment.summaryLine)
                    }
                }
            }

            if !visualAttachments.isEmpty, !profile.supportsVision {
                notes.append("（当前服务未开启图片输入，以上内容仅以文字描述告知）")
            }

            if !notes.isEmpty {
                let noteText = notes.joined(separator: "\n")
                text = text.isEmpty ? noteText : text + "\n" + noteText
            }

            if !text.isEmpty { parts.append(.text(text)) }
            parts.append(contentsOf: images)

            // 空消息会被服务端拒绝，兜个底
            if parts.isEmpty { parts.append(.text("（空）")) }
            result.append(PreparedMessage(role: message.role, parts: parts))
        }

        return result
    }

    /// Anthropic 要求 user / assistant 严格交替，这里合并同角色的连续消息
    static func mergeConsecutiveRoles(_ messages: [PreparedMessage]) -> [PreparedMessage] {
        var merged: [PreparedMessage] = []
        for message in messages {
            if var last = merged.last, last.role == message.role {
                last.parts.append(contentsOf: message.parts)
                merged[merged.count - 1] = last
            } else {
                merged.append(message)
            }
        }
        // 首条必须是 user
        while let first = merged.first, first.role != .user {
            merged.removeFirst()
        }
        return merged
    }
}

// MARK: - 协议

protocol ChatProvider {
    var profile: ProviderProfile { get }
    func makeRequest(messages: [ChatMessage]) throws -> URLRequest
    func parse(event: SSEEvent) -> [StreamDelta]
    func parseCompletion(_ data: Data) throws -> ChatCompletion
}

extension ChatProvider {
    /// 本地服务（Ollama / LM Studio）通常不需要 Key
    var allowsEmptyKey: Bool {
        let host = URL(string: profile.baseURL)?.host ?? ""
        return host == "127.0.0.1" || host == "localhost" || host.hasPrefix("192.168.")
            || host.hasPrefix("10.") || host.hasSuffix(".local")
    }

    func commonHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "text/event-stream, application/json"
        ]
        for (key, value) in profile.extraHeaders { headers[key] = value }
        return headers
    }

    func baseRequest() throws -> URLRequest {
        guard let url = profile.chatURL else { throw APIError.invalidURL }
        if profile.apiKey.trimmingCharacters(in: .whitespaces).isEmpty, !allowsEmptyKey {
            throw APIError.missingKey
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in commonHeaders() { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }
}

// MARK: - OpenAI 兼容

struct OpenAIProvider: ChatProvider {

    let profile: ProviderProfile

    func makeRequest(messages: [ChatMessage]) throws -> URLRequest {
        var request = try baseRequest()
        if !profile.apiKey.isEmpty {
            request.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let prepared = MessagePreparer.prepare(messages, profile: profile, imageDetail: profile.imageDetail)
        var body: [String: Any] = [
            "model": profile.model,
            "messages": prepared.map { Self.render($0) },
            "stream": profile.streaming
        ]
        if !profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["messages"] = [["role": "system", "content": profile.systemPrompt]]
                + (body["messages"] as? [[String: Any]] ?? [])
        }
        if profile.maxTokens > 0 { body["max_tokens"] = profile.maxTokens }
        if profile.temperature >= 0 { body["temperature"] = profile.temperature }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private static func render(_ message: PreparedMessage) -> [String: Any] {
        let images = message.parts.compactMap { part -> [String: Any]? in
            guard case .image(let base64, let mime, let detail) = part else { return nil }
            return [
                "type": "image_url",
                "image_url": ["url": "data:\(mime);base64,\(base64)", "detail": detail]
            ]
        }
        let text = message.textOnly

        // 没有图片就用最朴素的字符串格式，兼容性最好（很多国产网关只认这个）
        if images.isEmpty {
            return ["role": message.role.rawValue, "content": text]
        }
        var content: [[String: Any]] = []
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        content.append(contentsOf: images)
        return ["role": message.role.rawValue, "content": content]
    }

    func parse(event: SSEEvent) -> [StreamDelta] {
        let trimmed = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed == "[DONE]" { return [.done] }
        guard let json = event.json() else { return [] }

        if let error = Self.errorMessage(in: json) { return [.failure(error)] }

        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            return []
        }
        var deltas: [StreamDelta] = []
        if let delta = first["delta"] as? [String: Any] {
            if let reasoning = Self.string(delta["reasoning_content"]) ?? Self.string(delta["reasoning"]) {
                deltas.append(.reasoning(reasoning))
            }
            if let content = Self.contentString(delta["content"]), !content.isEmpty {
                deltas.append(.text(content))
            }
        }
        if let text = Self.string(first["text"]), !text.isEmpty {
            deltas.append(.text(text))
        }
        if let message = first["message"] as? [String: Any],
           let content = Self.contentString(message["content"]), !content.isEmpty {
            deltas.append(.text(content))
        }
        if let finish = Self.string(first["finish_reason"]), !finish.isEmpty {
            deltas.append(.done)
        }
        return deltas
    }

    func parseCompletion(_ data: Data) throws -> ChatCompletion {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw APIError.decoding("不是合法 JSON")
        }
        if let error = Self.errorMessage(in: json) { throw APIError.http(status: 200, message: error) }
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            throw APIError.decoding("缺少 choices 字段")
        }
        if let message = first["message"] as? [String: Any] {
            let text = Self.contentString(message["content"]) ?? ""
            let reasoning = Self.string(message["reasoning_content"]) ?? Self.string(message["reasoning"])
            return ChatCompletion(text: text,
                                  reasoning: reasoning,
                                  model: Self.string(json["model"]))
        }
        if let text = Self.string(first["text"]) {
            return ChatCompletion(text: text, reasoning: nil, model: Self.string(json["model"]))
        }
        throw APIError.decoding("没有找到回复内容")
    }

    // MARK: 小工具

    static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// content 可能是字符串，也可能是 [{type:text,text:...}] 数组
    static func contentString(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let array = value as? [[String: Any]] {
            let pieces = array.compactMap { item -> String? in
                if let text = item["text"] as? String { return text }
                return nil
            }
            return pieces.isEmpty ? nil : pieces.joined()
        }
        return nil
    }

    static func errorMessage(in json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["type"] as? String) ?? "服务端返回错误"
        }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        if let message = json["message"] as? String,
           json["choices"] == nil, json["content"] == nil, !message.isEmpty {
            return message
        }
        return nil
    }
}

// MARK: - Anthropic Claude

struct AnthropicProvider: ChatProvider {

    let profile: ProviderProfile

    func makeRequest(messages: [ChatMessage]) throws -> URLRequest {
        var request = try baseRequest()
        if !profile.apiKey.isEmpty {
            request.setValue(profile.apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prepared = MessagePreparer.mergeConsecutiveRoles(
            MessagePreparer.prepare(messages, profile: profile, imageDetail: profile.imageDetail))

        var body: [String: Any] = [
            "model": profile.model,
            "max_tokens": profile.maxTokens > 0 ? profile.maxTokens : 2048,
            "stream": profile.streaming,
            "messages": prepared.map { Self.render($0) }
        ]
        if !profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["system"] = profile.systemPrompt
        }
        if profile.temperature >= 0 { body["temperature"] = min(1.0, profile.temperature) }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private static func render(_ message: PreparedMessage) -> [String: Any] {
        var blocks: [[String: Any]] = []
        let text = message.textOnly
        if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
        if message.role == .user {
            for part in message.parts {
                guard case .image(let base64, let mime, _) = part else { continue }
                blocks.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": mime, "data": base64]
                ])
            }
        }
        if blocks.isEmpty { blocks.append(["type": "text", "text": "（空）"]) }
        return ["role": message.role.rawValue, "content": blocks]
    }

    func parse(event: SSEEvent) -> [StreamDelta] {
        let trimmed = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let json = event.json() else { return [] }

        let type = (json["type"] as? String) ?? event.name ?? ""
        switch type {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            let deltaType = (delta["type"] as? String) ?? ""
            if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String {
                return [.reasoning(thinking)]
            }
            if let text = delta["text"] as? String, !text.isEmpty { return [.text(text)] }
            return []
        case "message_stop", "message_end":
            return [.done]
        case "error":
            let error = json["error"] as? [String: Any]
            return [.failure((error?["message"] as? String) ?? "服务端返回错误")]
        case "message_delta":
            if let delta = json["delta"] as? [String: Any],
               let stop = delta["stop_reason"] as? String, !stop.isEmpty {
                return [.done]
            }
            return []
        default:
            return []
        }
    }

    func parseCompletion(_ data: Data) throws -> ChatCompletion {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw APIError.decoding("不是合法 JSON")
        }
        if let error = json["error"] as? [String: Any] {
            throw APIError.http(status: 200, message: (error["message"] as? String) ?? "服务端返回错误")
        }
        guard let blocks = json["content"] as? [[String: Any]] else {
            throw APIError.decoding("缺少 content 字段")
        }
        var text = ""
        var reasoning: String?
        for block in blocks {
            let type = block["type"] as? String
            if type == "text", let piece = block["text"] as? String { text += piece }
            if type == "thinking", let piece = block["thinking"] as? String { reasoning = (reasoning ?? "") + piece }
        }
        guard !text.isEmpty || reasoning != nil else { throw APIError.emptyContent }
        return ChatCompletion(text: text, reasoning: reasoning, model: json["model"] as? String)
    }
}

// MARK: - 工厂

enum ChatProviderFactory {
    static func make(_ profile: ProviderProfile) -> ChatProvider {
        switch profile.kind {
        case .openAICompatible: return OpenAIProvider(profile: profile)
        case .anthropic: return AnthropicProvider(profile: profile)
        }
    }
}
