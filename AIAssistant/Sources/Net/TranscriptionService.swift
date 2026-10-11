//
//  TranscriptionService.swift
//  AIAssistant
//
//  语音转文字：把录音文件 POST 到 OpenAI 兼容的 /v1/audio/transcriptions
//  （Whisper / 通义 / 硅基流动 / one-api 都支持）。
//  走这个接口的好处：iOS 12 上也能用中文识别，且识别质量比系统听写好。
//

import Foundation

final class TranscriptionService {

    static let shared = TranscriptionService()

    private init() {}

    @discardableResult
    func transcribe(fileURL: URL,
                    settings: SpeechSettings,
                    completion: @escaping (Result<String, APIError>) -> Void) -> URLSessionDataTask? {

        guard let url = settings.transcribeURL else {
            completion(.failure(.invalidURL))
            return nil
        }
        if settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            let host = url.host ?? ""
            let isLocal = host == "127.0.0.1" || host == "localhost" || host.hasPrefix("192.168.")
            if !isLocal {
                completion(.failure(.missingKey))
                return nil
            }
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            completion(.failure(.network("读取录音文件失败")))
            return nil
        }

        let boundary = "----AIAssistantBoundary\(UUID().uuidString.prefix(8))"
        var fields: [(String, String)] = [
            ("model", settings.model.isEmpty ? "whisper-1" : settings.model),
            ("response_format", "json")
        ]
        if !settings.language.isEmpty { fields.append(("language", settings.language)) }

        var body = Data()
        for (name, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        return HTTPClient.shared.send(request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                if let text = Self.parseText(from: data), !text.isEmpty {
                    completion(.success(text))
                } else {
                    completion(.failure(.decoding("没有识别出文字")))
                }
            }
        }
    }

    private static func parseText(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let text = json["text"] as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let result = json["result"] as? String { return result }
            if let error = json["error"] as? [String: Any], error["message"] is String { return nil }
        }
        // 少数服务端直接返回纯文本
        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("{") { return trimmed }
        }
        return nil
    }
}

extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
