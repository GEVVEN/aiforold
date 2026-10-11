//
//  AudioRecorder.swift
//  AIAssistant
//
//  录音：AAC / 16kHz / 单声道 / 32kbps。
//  为什么压这么狠？60 秒只有约 240KB，上传快、转写便宜，
//  iPhone 5s 也不至于在录音时掉帧。
//

import AVFoundation

final class AudioRecorder {

    static let shared = AudioRecorder()

    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?
    private var startedAt: Date?

    private init() {}

    var isRecording: Bool { recorder?.isRecording ?? false }

    var currentDuration: Double {
        guard let startedAt = startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    // MARK: - 权限

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    static var hasPermission: Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }

    // MARK: - 录音

    @discardableResult
    func start() -> URL? {
        stopSilently()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            return nil
        }

        let name = "voice-\(UUID().uuidString).m4a"
        let url = ConversationStore.shared.attachmentsURL.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else { return nil }
            self.recorder = recorder
            self.currentURL = url
            self.startedAt = Date()
            return url
        } catch {
            return nil
        }
    }

    /// 0...1 的音量，用来画波形
    func currentLevel() -> CGFloat {
        guard let recorder = recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)   // -160...0 dB
        let normalized = (power + 52) / 52
        return CGFloat(max(0.05, min(1, normalized)))
    }

    /// 结束并返回文件 + 时长
    func stop() -> (url: URL, duration: Double)? {
        guard let recorder = recorder, let url = currentURL else {
            stopSilently()
            return nil
        }
        let duration = currentDuration
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil
        deactivateSession()
        if FileManager.default.fileExists(atPath: url.path) {
            return (url, duration)
        }
        return nil
    }

    /// 取消：停止并删掉文件
    func cancel() {
        let url = currentURL
        stopSilently()
        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stopSilently() {
        recorder?.stop()
        recorder = nil
        startedAt = nil
        currentURL = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
