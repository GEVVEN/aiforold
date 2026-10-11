//
//  Settings.swift
//  AIAssistant
//
//  设置存储：UserDefaults 存 JSON，API Key 单独走 Keychain，
//  落盘的 JSON 里 Key 永远是空的。
//

import Foundation

final class SettingsStore {

    static let shared = SettingsStore()

    private let defaultsKey = "app.settings.v1"
    private(set) var settings: AppSettings

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        hydrateSecrets()
        // 老版本升级后可能有新增的内置服务
        if settings.providers.isEmpty {
            settings.providers = AppSettings.builtinProviders
            settings.activeProviderId = settings.providers[0].id
        }
        if settings.provider(id: settings.activeProviderId) == nil {
            settings.activeProviderId = settings.providers[0].id
        }
    }

    // MARK: - 读写

    var activeProvider: ProviderProfile {
        settings.activeProvider
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        persist()
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }

    func persist() {
        var copy = settings
        // Key 只在内存 / Keychain，不写进 UserDefaults
        for index in copy.providers.indices {
            copy.providers[index].apiKey = ""
        }
        copy.speech.apiKey = ""
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        storeSecrets()
    }

    // MARK: - Keychain 同步

    private func hydrateSecrets() {
        for index in settings.providers.indices {
            let id = settings.providers[index].id
            settings.providers[index].apiKey = Keychain.get(Keychain.providerKey(id)) ?? ""
        }
        settings.speech.apiKey = Keychain.get(Keychain.speechKey) ?? ""
    }

    private func storeSecrets() {
        for provider in settings.providers {
            Keychain.set(provider.apiKey, for: Keychain.providerKey(provider.id))
        }
        Keychain.set(settings.speech.apiKey, for: Keychain.speechKey)
    }

    // MARK: - 服务管理

    @discardableResult
    func upsertProvider(_ provider: ProviderProfile) -> ProviderProfile {
        var stored = provider
        update { s in
            if let index = s.providers.firstIndex(where: { $0.id == stored.id }) {
                s.providers[index] = stored
            } else {
                stored.id = UUID().uuidString
                s.providers.append(stored)
                s.activeProviderId = stored.id
            }
        }
        return stored
    }

    func deleteProvider(id: String) {
        guard settings.providers.count > 1 else {
            update { $0.providers = AppSettings.builtinProviders
                     $0.activeProviderId = AppSettings.builtinProviders[0].id }
            Keychain.remove(Keychain.providerKey(id))
            return
        }
        update { s in
            s.providers.removeAll(where: { $0.id == id })
            if s.activeProviderId == id, let first = s.providers.first {
                s.activeProviderId = first.id
            }
        }
        Keychain.remove(Keychain.providerKey(id))
    }

    func setActiveProvider(id: String) {
        update { $0.activeProviderId = id }
    }

    /// 按配置里的档位，把图片 / 视频参数写回（设置页改档位时调用）
    func applyQuality(_ quality: ImageSettings.Quality) {
        update { $0.image.quality = quality }
    }

    func clearProviderKey(id: String) {
        update { s in
            if let index = s.providers.firstIndex(where: { $0.id == id }) {
                s.providers[index].apiKey = ""
            }
        }
        Keychain.remove(Keychain.providerKey(id))
    }
}
