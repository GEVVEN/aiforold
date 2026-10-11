//
//  ImageViewerViewController.swift
//  AIAssistant
//
//  全屏看图：支持缩放、左右滑动切换、保存到相册。
//  视频附件在这里展示的是"抽取出来的关键帧"，每帧标上序号，
//  让用户知道发出去的到底是哪几帧。
//

import UIKit
import Photos

final class ImageViewerViewController: UIViewController {

    private struct Page {
        var relativePath: String
        var caption: String
    }

    private let pages: [Page]
    private var index: Int

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let pageLabel = UILabel()
    private let captionLabel = UILabel()

    // MARK: - 初始化

    init(attachments: [Attachment], startIndex: Int) {
        var pages: [Page] = []
        for attachment in attachments {
            if attachment.kind == .video {
                let total = attachment.frameRelativePaths.count
                for (frameIndex, path) in attachment.frameRelativePaths.enumerated() {
                    pages.append(Page(relativePath: path,
                                      caption: "视频关键帧 \(frameIndex + 1)/\(max(total, 1)) · \(Self.durationText(attachment.durationSeconds))"))
                }
            } else {
                pages.append(Page(relativePath: attachment.relativePath,
                                  caption: "\(attachment.pixelWidth)×\(attachment.pixelHeight)"))
            }
        }
        self.pages = pages
        self.index = max(0, min(startIndex, max(0, pages.count - 1)))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)

        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissSelf)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        let left = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:)))
        left.direction = .left
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:)))
        right.direction = .right
        view.addGestureRecognizer(left)
        view.addGestureRecognizer(right)

        closeButton.setImage(Icon.close.image(size: 20, color: .white), for: .normal)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.roundCorners(16)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        saveButton.setImage(Icon.doc.image(size: 18, color: .white), for: .normal)
        saveButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        saveButton.roundCorners(16)
        saveButton.addTarget(self, action: #selector(saveCurrent), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)

        pageLabel.font = Theme.caption.monospacedDigits()
        pageLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        pageLabel.textAlignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageLabel)

        captionLabel.font = Theme.caption
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captionLabel)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            saveButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            saveButton.widthAnchor.constraint(equalToConstant: 32),
            saveButton.heightAnchor.constraint(equalToConstant: 32),

            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageLabel.bottomAnchor.constraint(equalTo: captionLabel.topAnchor, constant: -4),

            captionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            captionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            captionLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -26)
        ])

        load()
    }

    private func load() {
        guard !pages.isEmpty else {
            captionLabel.text = "没有可显示的图片"
            return
        }
        let page = pages[index]
        scrollView.setZoomScale(1, animated: false)
        imageView.frame = scrollView.bounds
        let maxPixel = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
        imageView.image = ImagePipeline.shared.image(relativePath: page.relativePath, maxPixelSize: maxPixel)
        pageLabel.text = pages.count > 1 ? "\(index + 1) / \(pages.count)" : nil
        captionLabel.text = page.caption
        saveButton.isHidden = imageView.image == nil
    }

    // MARK: - 交互

    @objc private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func swipe(_ gesture: UISwipeGestureRecognizer) {
        guard pages.count > 1 else { return }
        if gesture.direction == .left {
            index = min(index + 1, pages.count - 1)
        } else {
            index = max(index - 1, 0)
        }
        load()
    }

    @objc private func toggleZoom() {
        let zoomed = scrollView.zoomScale > 1.01
        scrollView.setZoomScale(zoomed ? 1 : 2, animated: true)
    }

    @objc private func saveCurrent() {
        guard let image = imageView.image else { return }
        if #available(iOS 14.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    guard status == .authorized || status == .limited else {
                        Toast.error("没有相册写入权限")
                        return
                    }
                    self.writeToAlbum(image)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard status == .authorized else {
                        Toast.error("没有相册写入权限")
                        return
                    }
                    self.writeToAlbum(image)
                }
            }
        }
    }

    private func writeToAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if error == nil {
            Toast.show("已保存到相册")
        } else {
            Toast.error("保存失败")
        }
    }

    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension ImageViewerViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
