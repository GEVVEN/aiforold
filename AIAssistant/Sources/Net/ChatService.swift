//
//  ChatService.swift
//  AIAssistant
//
//  一次对话请求的完整生命周期：组装 → 发送 → 流式回调 → 收尾 / 取消。
//  所有回调都在主线程，UI 层不用再 dispatch。
//

import Foundation

final class ChatService {

    static let shared = ChatService()

    private var streamingTask: StreamingTask?
    private var plainTask: URLSessionDataTask?
    /// 每次请求一个 token，避免旧请求的迟到回调污染新对话
    private var requestToken = UUID()
    private(set) var completions = 0
    /// 当前请求的收尾回调：用户点「停止生成」时要用它通知界面收尾
    private var activeFinish: ((APIError?) -> Void)?
    private(set) var isBusy = false

    private init() {}

    // MARK: - 发送

    func send(messages: [ChatMessage],
              profile: ProviderProfile,
              onDelta: @escaping (StreamDelta) -> Void,
              onFinish: @escaping (APIError?) -> Void) {

        cancel(silently: true)

        let token = UUID()
        requestToken = token
        isBusy = true
        activeFinish = onFinish

        var working = profile
        working.imageDetail = SettingsStore.shared.settings.image.detail
        let provider = ChatProviderFactory.make(working)

        // 图片 base64 是磁盘 IO，放后台拼请求
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let request: URLRequest
            do {
                request = try provider.makeRequest(messages: messages)
            } catch let error as APIError {
                DispatchQueue.main.async { self.finish(token: token, error: error, onFinish: onFinish) }
                return
            } catch {
                DispatchQueue.main.async {
                    self.finish(token: token, error: APIError.from(error), onFinish: onFinish)
                }
                return
            }

            guard self.isCurrent(token) else { return }
            DispatchQueue.main.async {
                guard self.isCurrent(token) else { return }
                if working.streaming {
                    self.startStreaming(provider: provider, request: request, token: token,
                                        onDelta: onDelta, onFinish: onFinish)
                } else {
                    self.startPlain(provider: provider, request: request, token: token,
                                    onDelta: onDelta, onFinish: onFinish)
                }
            }
        }
    }

    private func startStreaming(provider: ChatProvider,
                                request: URLRequest,
                                token: UUID,
                                onDelta: @escaping (StreamDelta) -> Void,
                                onFinish: @escaping (APIError?) -> Void) {
        streamingTask = HTTPClient.shared.stream(request, onEvent: { [weak self] event in
            guard let self = self, self.isCurrent(token) else { return }
            let deltas = provider.parse(event: event)
            guard !deltas.isEmpty else { return }
            DispatchQueue.main.async {
                guard self.isCurrent(token) else { return }
                for delta in deltas {
                    if delta.kind == .failure {
                        self.finish(token: token,
                                    error: .http(status: 200, message: delta.value),
                                    onFinish: onFinish)
                        return
                    }
                    onDelta(delta)
                }
            }
        }, onFinish: { [weak self] error in
            guard let self = self else { return }
            self.finish(token: token, error: error, onFinish: onFinish)
        })
    }

    private func startPlain(provider: ChatProvider,
                            request: URLRequest,
                            token: UUID,
                            onDelta: @escaping (StreamDelta) -> Void,
                            onFinish: @escaping (APIError?) -> Void) {
        plainTask = HTTPClient.shared.send(request) { [weak self] result in
            guard let self = self, self.isCurrent(token) else { return }
            switch result {
            case .failure(let error):
                self.finish(token: token, error: error, onFinish: onFinish)
            case .success(let data):
                do {
                    let completion = try provider.parseCompletion(data)
                    DispatchQueue.main.async {
                        guard self.isCurrent(token) else { return }
                        if let reasoning = completion.reasoning, !reasoning.isEmpty {
                            onDelta(.reasoning(reasoning))
                        }
                        if !completion.text.isEmpty { onDelta(.text(completion.text)) }
                        self.finish(token: token, error: nil, onFinish: onFinish)
                    }
                } catch let error as APIError {
                    self.finish(token: token, error: error, onFinish: onFinish)
                } catch {
                    self.finish(token: token, error: APIError.from(error), onFinish: onFinish)
                }
            }
        }
    }

    // MARK: - 取消

    /// silently = true 用于「内部换请求」，不通知旧请求的收尾回调
    func cancel(silently: Bool = false) {
        let finish = activeFinish
        activeFinish = nil

        requestToken = UUID()
        streamingTask?.cancel()
        streamingTask = nil
        plainTask?.cancel()
        plainTask = nil
        isBusy = false

        if !silently, let finish = finish {
            // 用户主动停止：必须让界面收尾（否则会一直显示"正在输入"）
            if Thread.isMainThread {
                finish(.cancelled)
            } else {
                DispatchQueue.main.async { finish(.cancelled) }
            }
        }
        if !silently { completions += 1 }
    }

    // MARK: - 内部

    private func isCurrent(_ token: UUID) -> Bool { token == requestToken }

    private func finish(token: UUID, error: APIError?, onFinish: @escaping (APIError?) -> Void) {
        guard isCurrent(token) else { return }
        requestToken = UUID()
        streamingTask = nil
        plainTask = nil
        isBusy = false
        activeFinish = nil
        completions += 1
        let callback = onFinish
        if Thread.isMainThread {
            callback(error)
        } else {
            DispatchQueue.main.async { callback(error) }
        }
    }

    // MARK: - 测试连接

    /// 设置页「测试连接」：只发一句最短的话，验证配置是否可用。
    func test(profile: ProviderProfile, completion: @escaping (Result<String, APIError>) -> Void) {
        var probe = profile
        probe.streaming = false
        probe.temperature = 0
        probe.maxTokens = 32
        probe.systemPrompt = "你是连通性测试助手，只用一句话回答。"

        let message = ChatMessage.user(text: "你好，请回复：连接正常")
        var collected = ""

        send(messages: [message], profile: probe, onDelta: { delta in
            if delta.kind == .text { collected += delta.value }
        }, onFinish: { error in
            if let error = error, !error.isCancelled {
                completion(.failure(error))
            } else if collected.isEmpty {
                completion(.failure(.emptyContent))
            } else {
                completion(.success(collected))
            }
        })
    }
}
