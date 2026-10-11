//
//  AppDelegate.swift
//  AIAssistant
//
//  刻意不用 Scene（UIApplicationSceneManifest 需要 iOS 13+），
//  只用 AppDelegate 建窗口 —— 这样 iOS 12 和 iOS 17 行为完全一致。
//

import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 提前初始化设置（会从 Keychain 取回 API Key）
        _ = SettingsStore.shared
        Theme.apply(SettingsStore.shared.settings.theme)
        ConversationStore.shared.prepare()
        configureAppearance()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.current.background
        let root = ConversationListViewController()
        let navigation = RootNavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeChanged),
                                               name: .appThemeDidChange,
                                               object: nil)
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // iPhone 5s 上这个回调很容易触发，收到就把图片缓存全扔掉
        ImagePipeline.shared.clearCaches()
    }

    @objc private func themeChanged() {
        configureAppearance()
    }

    private func configureAppearance() {
        let palette = Theme.current
        let navigationBar = UINavigationBar.appearance()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = palette.navBackground
        navigationBar.tintColor = palette.accent
        navigationBar.titleTextAttributes = [
            .foregroundColor: palette.primaryText,
            .font: Theme.title
        ]
        if #available(iOS 11.0, *) {
            navigationBar.prefersLargeTitles = false
        }
        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: palette.accent], for: .normal)
    }
}

/// 只为了在 iOS 13+ 上响应"跟随系统深色模式"的切换
final class RootNavigationController: UINavigationController {

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard SettingsStore.shared.settings.theme == .system else { return }
        guard #available(iOS 13.0, *) else { return }
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            Theme.apply(.system)
            NotificationCenter.default.post(name: .appThemeDidChange, object: nil)
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.current.isDark ? .lightContent : .default
    }
}
