//
//  HTTPClient.swift
//  AIAssistant
//
//  URLSession 封装：普通请求 + 流式（SSE）请求。
//  流式部分自己实现 delegate，不依赖任何第三方网络库。
//

import Foundation

// MARK: - 错误

enum APIError: Error {
    case invalidURL
    case missingKey
    case emptyContent
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case cancelled

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .invalidURL: return "接口地址不正确"
        case .missingKey: return L10n.keyMissing
        case .emptyContent: return "内容为空"
        case .http(let status, let message):
            return message.isEmpty ? "服务端返回 \(status)" : "\(message)（HTTP \(status)）"
        case .network(let text): return text
        case .decoding(let text): return "返回内容无法解析：\(text)"
        case .cancelled: return L10n.stopped
        }
    }

    static func from(_ error: Error) -> APIError {
        if let apiError = error as? APIError { return apiError }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorNotConnectedToInternet:
                return .network("网络未连接")
            case NSURLErrorTimedOut:
                return .network("请求超时，请检查网络或把超时时间调大")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return .network("连不上服务器，请检查 Base URL")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return .network("HTTPS 证书校验失败")
            default:
                return .network(nsError.localizedDescription)
            }
        }
        return .network(nsError.localizedDescription)
    }
}

// MARK: - HTTP 客户端

final class HTTPClient {

    static let shared = HTTPClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if #available(iOS 11.0, *) {
            configuration.waitsForConnectivity = false
        }
        session = URLSession(configuration: configuration)
    }

    /// 普通（一次性）请求
    @discardableResult
    func send(_ request: URLRequest,
              completion: @escaping (Result<Data, APIError>) -> Void) -> URLSessionDataTask {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(APIError.from(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network("没有收到服务器响应")))
                return
            }
            let payload = data ?? Data()
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.http(status: http.statusCode,
                                          message: Self.errorMessage(from: payload))))
                return
            }
            completion(.success(payload))
        }
        task.resume()
        return task
    }

    /// 流式请求
    func stream(_ request: URLRequest,
                onEvent: @escaping (SSEEvent) -> Void,
                onFinish: @escaping (APIError?) -> Void) -> StreamingTask {
        let task = StreamingTask(request: request, onEvent: onEvent, onFinish: onFinish)
        task.start()
        return task
    }

    // MARK: - 错误信息提取

    /// 尽量从各家不同的错误 JSON 里挖出人话
    static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let type = error["type"] as? String { return type }
            }
            if let message = object["message"] as? String { return message }
            if let error = object["error"] as? String { return error }
            if let detail = object["detail"] as? String { return detail }
            if let choices = object["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(300))
        }
        return ""
    }
}

// MARK: - 流式任务

/// 一个流式请求 = 一个独立的 URLSession（delegate 只服务这一个请求），
/// 这样实现最简单、也最容易彻底释放。
final class StreamingTask: NSObject, URLSessionDataDelegate {

    private let request: URLRequest
    private let onEvent: (SSEEvent) -> Void
    private let onFinish: (APIError?) -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let reader = SSEReader()

    private var errorBody = Data()
    private var isErrorResponse = false
    private var finished = false
    private let lock = NSLock()

    init(request: URLRequest,
         onEvent: @escaping (SSEEvent) -> Void,
         onFinish: @escaping (APIError?) -> Void) {
        self.request = request
        self.onEvent = onEvent
        self.onFinish = onFinish
        super.init()
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        // 流式响应必须关掉缓存与超时限制
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 3
        if #available(iOS 11.0, *) {
            configuration.waitsForConnectivity = false
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        lock.lock()
        let alreadyDone = finished
        finished = true
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        if !alreadyDone {
            DispatchQueue.main.async { [weak self] in
                self?.onFinish(.cancelled)
            }
        }
    }

    private func finish(_ error: APIError?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        // 收尾：把残留的半条 event 也交给上层（取消时不要）
        if !(error?.isCancelled ?? false) {
            for event in reader.flush() { onEvent(event) }
        }
        session?.finishTasksAndInvalidate()
        session = nil
        onFinish(error)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            isErrorResponse = true
            errorBody.removeAll(keepingCapacity: true)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isErrorResponse {
            // 只保留开头这批错误信息：网关返回一大坨 HTML 时，既不 memmove 也不无限增长
            let limit = 256 * 1024
            if errorBody.count < limit {
                let room = limit - errorBody.count
                errorBody.append(room >= data.count ? data : data.prefix(room))
            }
            return
        }
        for event in reader.append(data) { onEvent(event) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isErrorResponse {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
            finish(.http(status: status, message: HTTPClient.errorMessage(from: errorBody)))
            return
        }
        if let error = error {
            finish(APIError.from(error))
            return
        }
        finish(nil)
    }
}
