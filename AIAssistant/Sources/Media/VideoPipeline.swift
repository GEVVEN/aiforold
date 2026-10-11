//
//  VideoPipeline.swift
//  AIAssistant
//
//  "发视频"在现实里做不到：主流大模型 API 都不收视频文件。
//  所以这里的做法是（也就是客户端豆包类的做法）：
//    1. 按时间轴均匀抽 N 张关键帧 → 当作多张图片发给多模态模型；
//    2. 如果服务支持，再把音轨导出并转写成文字一起发过去。
//  好处：流量可控、老机型内存可控，而且模型能同时"看到画面 + 听到说话"。
//

import AVFoundation
import UIKit
import CoreMedia

final class VideoPipeline {

    static let shared = VideoPipeline()

    struct Processed {
        var attachment: Attachment
        /// 导出出来的音轨（可空），交给语音识别去转文字
        var audioURL: URL?
    }

    private let workQueue = DispatchQueue(label: "app.video.pipeline", qos: .userInitiated)

    private init() {}

    // MARK: - 抽帧

    func process(videoURL: URL,
                 frameCount: Int,
                 settings: ImageSettings,
                 completion: @escaping (Swift.Result<Processed, APIError>) -> Void) {

        workQueue.async {
            let asset = AVURLAsset(url: videoURL, options: nil)
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration.isFinite, duration > 0.05 else {
                DispatchQueue.main.async { completion(.failure(.network("这个视频读不出时长"))) }
                return
            }

            let count = max(1, min(frameCount, 6))
            let maxEdge = CGFloat(settings.maxEdge)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxEdge, height: maxEdge)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

            var times: [NSValue] = []
            for index in 0..<count {
                let seconds = duration * (Double(index) + 0.5) / Double(count)
                times.append(NSValue(time: CMTime(seconds: seconds, preferredTimescale: 600)))
            }

            let lock = NSLock()
            var frames = [Int: CGImage]()
            var remaining = count
            var firstError: Error?

            generator.generateCGImagesAsynchronously(forTimes: times) { requested, image, _, result, error in
                lock.lock()
                if result == .succeeded, let image = image {
                    let seconds = CMTimeGetSeconds(requested)
                    let index = max(0, min(count - 1, Int((seconds / duration * Double(count)) - 0.5 + 0.0001)))
                    frames[index] = image
                } else if error != nil || result == .failed {
                    firstError = firstError ?? error
                }
                remaining -= 1
                let done = remaining <= 0
                lock.unlock()

                guard done else { return }
                self.finishFrames(frames: frames,
                                  count: count,
                                  duration: duration,
                                  maxEdge: maxEdge,
                                  quality: settings.jpegQuality,
                                  asset: asset,
                                  error: firstError,
                                  completion: completion)
            }
        }
    }

    private func finishFrames(frames: [Int: CGImage],
                              count: Int,
                              duration: Double,
                              maxEdge: CGFloat,
                              quality: CGFloat,
                              asset: AVAsset,
                              error: Error?,
                              completion: @escaping (Swift.Result<Processed, APIError>) -> Void) {
        workQueue.async {
            let ordered = (0..<count).compactMap { frames[$0] }
            guard !ordered.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(.network(error?.localizedDescription ?? "视频抽帧失败")))
                }
                return
            }

            var framePaths: [String] = []
            var thumbnailPath: String?
            var previewSize = CGSize.zero

            for (index, cgImage) in ordered.enumerated() {
                guard let frame = ImagePipeline.shared.storeFrame(cgImage,
                                                                 maxEdge: maxEdge,
                                                                 quality: quality) else { continue }
                framePaths.append(frame.relativePath)
                if index == ordered.count / 2 {
                    thumbnailPath = frame.thumbnailRelativePath ?? frame.relativePath
                    previewSize = CGSize(width: frame.pixelWidth, height: frame.pixelHeight)
                }
            }

            guard !framePaths.isEmpty else {
                DispatchQueue.main.async { completion(.failure(.network("视频抽帧失败"))) }
                return
            }

            var attachment = Attachment(kind: .video, relativePath: framePaths[0])
            attachment.frameRelativePaths = framePaths
            attachment.thumbnailRelativePath = thumbnailPath ?? framePaths[0]
            attachment.pixelWidth = Int(previewSize.width)
            attachment.pixelHeight = Int(previewSize.height)
            attachment.durationSeconds = duration
            attachment.byteSize = framePaths.reduce(0) { partial, path in
                let url = ConversationStore.shared.attachmentURL(relativePath: path)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return partial + size
            }

            self.exportAudio(from: asset) { audioURL in
                DispatchQueue.main.async {
                    completion(.success(Processed(attachment: attachment, audioURL: audioURL)))
                }
            }
        }
    }

    // MARK: - 音轨导出

    func exportAudio(from asset: AVAsset, completion: @escaping (URL?) -> Void) {
        guard !asset.tracks(withMediaType: .audio).isEmpty else {
            completion(nil)
            return
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil)
            return
        }
        let name = "voice-\(UUID().uuidString).m4a"
        let url = ConversationStore.shared.attachmentsURL.appendingPathComponent(name)
        session.outputURL = url
        session.outputFileType = .m4a
        session.exportAsynchronously {
            if session.status == .completed {
                completion(url)
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(nil)
            }
        }
    }
}
