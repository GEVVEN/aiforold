//
//  ImagePipeline.swift
//  AIAssistant
//
//  图片处理管线。iPhone 5s 只有 1GB 内存，所以：
//    * 一律用 ImageIO（CGImageSource）做"解码即缩放"，绝不先把 8MP 原图整个解码；
//    * 缩略图 / base64 都进 NSCache 且设了上限；
//    * 落盘的永远是压缩后的小图，附件目录不会失控。
//

import UIKit
import ImageIO
import CoreGraphics

final class ImagePipeline {

    static let shared = ImagePipeline()

    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 8 * 1024 * 1024   // 8MB 封顶
        return cache
    }()

    private let base64Cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 24
        cache.totalCostLimit = 12 * 1024 * 1024  // base64 是原始字节的 1.33 倍
        return cache
    }()

    private init() {}

    // MARK: - 从相册 / 拍照得到的 UIImage

    /// 压缩 + 落盘，返回可直接挂到消息上的附件
    func processPickedImage(_ image: UIImage, settings: ImageSettings) -> Attachment? {
        let maxEdge = CGFloat(max(320, settings.maxEdge))
        let resized = Self.resize(image: image, maxEdge: maxEdge)
        guard let jpeg = Self.jpegData(from: resized, quality: settings.jpegQuality) else { return nil }
        return store(jpeg: jpeg, pixelSize: resized.size, kind: .image, duration: 0)
    }

    /// 从相册拿到的原始文件（推荐：内存占用最低）
    func processPickedImageData(_ data: Data, settings: ImageSettings) -> Attachment? {
        let maxEdge = CGFloat(max(320, settings.maxEdge))
        guard let jpeg = Self.downscaledJPEG(from: data, maxEdge: maxEdge, quality: settings.jpegQuality),
              let size = Self.pixelSize(of: jpeg) else { return nil }
        return store(jpeg: jpeg, pixelSize: size, kind: .image, duration: 0)
    }

    /// 视频抽帧用：CGImage → 压缩 JPEG → 落盘
    func storeFrame(_ cgImage: CGImage,
                    maxEdge: CGFloat,
                    quality: CGFloat,
                    attachmentKind: AttachmentKind = .image) -> Attachment? {
        let pixel = CGSize(width: cgImage.width, height: cgImage.height)
        let needsScale = max(pixel.width, pixel.height) > maxEdge
        let jpeg: Data?
        if needsScale {
            jpeg = Self.downscaledJPEG(from: cgImage, maxEdge: maxEdge, quality: quality)
        } else {
            jpeg = Self.jpegData(from: cgImage, quality: quality)
        }
        guard let finalJPEG = jpeg, let size = Self.pixelSize(of: finalJPEG) else { return nil }
        return store(jpeg: finalJPEG, pixelSize: size, kind: attachmentKind, duration: 0)
    }

    // MARK: - 落盘

    private func store(jpeg: Data, pixelSize: CGSize, kind: AttachmentKind, duration: Double) -> Attachment? {
        let relativePath = ConversationStore.shared.writeAttachment(data: jpeg, fileExtension: "jpg")
        let thumbData = Self.downscaledJPEG(from: jpeg, maxEdge: 240, quality: 0.5)
        var thumbPath: String?
        if let thumbData = thumbData {
            thumbPath = ConversationStore.shared.writeAttachment(data: thumbData, fileExtension: "jpg")
        }
        var attachment = Attachment(kind: kind, relativePath: relativePath)
        attachment.thumbnailRelativePath = thumbPath
        attachment.pixelWidth = Int(pixelSize.width.rounded())
        attachment.pixelHeight = Int(pixelSize.height.rounded())
        attachment.durationSeconds = duration
        attachment.byteSize = jpeg.count
        return attachment
    }

    // MARK: - base64（发给模型用）

    func base64(for attachment: Attachment) -> (mime: String, data: String)? {
        return base64(relativePath: attachment.relativePath)
    }

    func base64ForFrame(relativePath: String) -> (mime: String, data: String)? {
        return base64(relativePath: relativePath)
    }

    private func base64(relativePath: String) -> (mime: String, data: String)? {
        let key = relativePath as NSString
        if let cached = base64Cache.object(forKey: key) {
            return (mime(for: relativePath), cached as String)
        }
        let url = ConversationStore.shared.attachmentURL(relativePath: relativePath)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let encoded = data.base64EncodedString()
        base64Cache.setObject(encoded as NSString, forKey: key, cost: encoded.utf8.count)
        return (mime(for: relativePath), encoded)
    }

    private func mime(for path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".heic") { return "image/heic" }
        return "image/jpeg"
    }

    // MARK: - 读取（展示用）

    func thumbnail(for attachment: Attachment) -> UIImage? {
        let path = attachment.thumbnailRelativePath ?? attachment.relativePath
        return image(relativePath: path, maxPixelSize: 240)
    }

    func image(relativePath: String, maxPixelSize: CGFloat) -> UIImage? {
        let key = "\(relativePath)#\(Int(maxPixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = ConversationStore.shared.attachmentURL(relativePath: relativePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        let cost = cgImage.bytesPerRow * cgImage.height
        thumbnailCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 后台线程取缩略图，主线程回调（列表滚动时用）
    func asyncThumbnail(for attachment: Attachment, completion: @escaping (UIImage?) -> Void) {
        let path = attachment.thumbnailRelativePath ?? attachment.relativePath
        let key = "\(path)#240" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = self?.image(relativePath: path, maxPixelSize: 240)
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - 缓存

    func clearCaches() {
        thumbnailCache.removeAllObjects()
        base64Cache.removeAllObjects()
        Icon.clearCache()
    }

    // MARK: - 纯函数式的缩放工具

    /// 等比缩放到长边不超过 maxEdge
    static func resize(image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }

        let ratio = maxEdge / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        if #available(iOS 11.0, *) { format.preferredRange = .standard }
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func jpegData(from image: UIImage, quality: CGFloat) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }

    /// CGImage → JPEG（不经过 UIImage）
    static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 用 ImageIO 直接解出缩略图并编码成 JPEG —— 峰值内存只跟目标尺寸有关
    static func downscaledJPEG(from data: Data, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downscaledJPEG(source: source, maxEdge: maxEdge, quality: quality)
    }

    static func downscaledJPEG(from cgImage: CGImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(CGFloat(cgImage.width), CGFloat(cgImage.height))
        guard longest > maxEdge else { return jpegData(from: cgImage, quality: quality) }

        // 直接用 CGContext 缩放，避免"先编一张 quality=1.0 的大 JPEG 再解码回来"这种双倍开销
        let ratio = maxEdge / longest
        let width = max(1, Int((CGFloat(cgImage.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * ratio).rounded()))
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return jpegData(from: scaled, quality: quality)
    }

    private static func downscaledJPEG(source: CGImageSource, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        // "public.jpeg" 字面量等价于 kUTTypeJPEG，避免 iOS 14 的 deprecation 告警
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func pixelSize(of jpegData: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
