//
//  SpeechRecognizer.swift
//  AIAssistant
//
//  系统听写（Speech.framework）。iOS 12 上没有"离线听写"
//  （requiresOnDeviceRecognition 是 iOS 13+），所以这条路需要联网。
//  正因为如此，App 默认两种方式都留着：设置里可以切到服务器转写。
//

import Foundation
import Speech

final class AppleSpeechTranscriber {

    static let shared = AppleSpeechTranscriber()

    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechURLRecognitionRequest?
    private var completed = false

    private init() {}

    // MARK: - 权限

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    // MARK: - 转写

    /// 把录音文件交给系统听写；onPartial 会多次回调（在后台线程）
    func transcribe(fileURL: URL,
                    language: String,
                    onPartial: ((String) -> Void)? = nil,
                    completion: @escaping (Swift.Result<String, APIError>) -> Void) {

        cancel()
        completed = false

        let locale = Self.locale(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            completion(.failure(.network("系统听写当前不可用（需要联网或换服务器转写）")))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *) {
            // iPhone 5s / iOS 12 没有离线模型，这里保持 false
            request.requiresOnDeviceRecognition = false
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, !self.completed else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty { onPartial?(text) }
                if result.isFinal {
                    self.completed = true
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        completion(.failure(.emptyContent))
                    } else {
                        completion(.success(trimmed))
                    }
                    self.cleanup()
                    return
                }
            }

            if let error = error {
                let nsError = error as NSError
                // 216/203：没听清就结束了，属于正常情况
                if nsError.code == 216 || nsError.code == 203 {
                    self.completed = true
                    completion(.failure(.emptyContent))
                } else {
                    self.completed = true
                    completion(.failure(.network("听写失败：\(nsError.localizedDescription)")))
                }
                self.cleanup()
            }
        }
    }

    func cancel() {
        completed = true
        task?.cancel()
        task = nil
        request = nil
    }

    private func cleanup() {
        task = nil
        request = nil
    }

    private static func locale(for language: String) -> Locale {
        let value = language.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "", "auto": return Locale(identifier: "zh-CN")
        case "zh", "zh-cn", "zh-hans", "cmn": return Locale(identifier: "zh-CN")
        case "zh-tw", "zh-hant": return Locale(identifier: "zh-TW")
        case "en", "en-us": return Locale(identifier: "en-US")
        default: return Locale(identifier: value)
        }
    }
}
