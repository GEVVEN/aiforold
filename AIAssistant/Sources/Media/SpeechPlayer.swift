//
//  SpeechPlayer.swift
//  AIAssistant
//
//  朗读助手回复：用系统 AVSpeechSynthesizer，离线、免费、几乎不占内存。
//

import AVFoundation

final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = SpeechPlayer()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// 朗读结束 / 被打断时回调（主线程）
    var onFinish: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 太长就截断：老机型读几千字会卡，而且没人会听完
    private let maxCharacters = 800

    func speak(_ text: String, language: String = "zh-CN") {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        stop()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])

        let content = plain.count > maxCharacters ? String(plain.prefix(maxCharacters)) + "……" : plain
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        DispatchQueue.main.async { self.onFinish?() }
    }
}
