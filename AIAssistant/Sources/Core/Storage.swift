//
//  Storage.swift
//  AIAssistant
//
//  会话存储：索引文件 + 每个会话一个 JSON，附件单独放 Attachments/。
//  列表页只读索引，聊天页只读当前会话 —— iPhone 5s 只有 1GB 内存，
//  不能一次性把所有历史都 decode 进内存。
//

import Foundation

final class ConversationStore {

    static let shared = ConversationStore()

    private let fileManager = FileManager.default
    private let indexFileName = "conversations.index.json"
    private let conversationFolder = "Conversations"
    private let attachmentFolder = "Attachments"

    /// 单会话最多保留多少条消息（避免文件无限膨胀）
    private let maxMessagesPerConversation = 200
    /// 最多保留多少条会话
    private let maxConversations = 100

    private(set) var summaries: [ConversationSummary] = []

    var documentsURL: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var attachmentsURL: URL {
        return documentsURL.appendingPathComponent(attachmentFolder, isDirectory: true)
    }

    private var conversationsURL: URL {
        return documentsURL.appendingPathComponent(conversationFolder, isDirectory: true)
    }

    private var indexURL: URL {
        return documentsURL.appendingPathComponent(indexFileName)
    }

    private init() {}

    // MARK: - 启动

    func prepare() {
        if #available(iOS 10.0, *) {
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                           ofItemAtPath: documentsURL.path)
        }
        ensureDirectories()
        loadIndex()
    }

    private func ensureDirectories() {
        for url in [attachmentsURL, conversationsURL] {
            if !fileManager.fileExists(atPath: url.path) {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([ConversationSummary].self, from: data) else {
            summaries = []
            return
        }
        summaries = list.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(summaries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - 会话读写

    func createConversation(providerId: String?) -> Conversation {
        var conversation = Conversation()
        conversation.providerId = providerId
        conversation.title = L10n.untitledChat
        save(conversation)
        return conversation
    }

    func loadConversation(id: String) -> Conversation? {
        let url = conversationsURL.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var conversation = try? decoder.decode(Conversation.self, from: data) else { return nil }
        // 会话恢复时清掉瞬时状态
        for index in conversation.messages.indices {
            conversation.messages[index].isStreaming = false
            conversation.messages[index].errorText = nil
        }
        return conversation
    }

    func save(_ conversation: Conversation) {
        var stored = conversation
        if stored.title.isEmpty || stored.title == L10n.untitledChat {
            stored.title = Self.makeTitle(from: conversation)
        }
        for index in stored.messages.indices {
            stored.messages[index].isStreaming = false
            stored.messages[index].errorText = nil
        }
        if stored.messages.count > maxMessagesPerConversation {
            stored.messages = Array(stored.messages.suffix(maxMessagesPerConversation))
        }
        stored.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(stored) {
            ensureDirectories()
            try? data.write(to: conversationsURL.appendingPathComponent("\(stored.id).json"), options: .atomic)
        }

        let summary = stored.summary
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        summaries.sort(by: { $0.updatedAt > $1.updatedAt })
        trimIfNeeded()
        saveIndex()
    }

    func delete(id: String) {
        try? fileManager.removeItem(at: conversationsURL.appendingPathComponent("\(id).json"))
        summaries.removeAll(where: { $0.id == id })
        saveIndex()
    }

    func deleteAll() {
        try? fileManager.removeItem(at: conversationsURL)
        try? fileManager.removeItem(at: attachmentsURL)
        summaries = []
        ensureDirectories()
        saveIndex()
        ImagePipeline.shared.clearCaches()
    }

    private func trimIfNeeded() {
        guard summaries.count > maxConversations else { return }
        let removed = summaries.suffix(summaries.count - maxConversations)
        for item in removed {
            try? fileManager.removeItem(at: conversationsURL.appendingPathComponent("\(item.id).json"))
        }
        summaries = Array(summaries.prefix(maxConversations))
    }

    private static func makeTitle(from conversation: Conversation) -> String {
        if let firstUser = conversation.messages.first(where: { $0.role == .user }) {
            let text = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(18)) }
            if let attachment = firstUser.attachments.first {
                switch attachment.kind {
                case .image: return "图片对话"
                case .video: return "视频对话"
                case .audio: return "语音对话"
                }
            }
        }
        return L10n.untitledChat
    }

    // MARK: - 附件

    func attachmentURL(relativePath: String) -> URL {
        return documentsURL.appendingPathComponent(relativePath)
    }

    /// 写入附件数据，返回相对路径
    @discardableResult
    func writeAttachment(data: Data, fileExtension ext: String) -> String {
        ensureDirectories()
        let name = "\(UUID().uuidString).\(ext)"
        let url = attachmentsURL.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return "\(attachmentFolder)/\(name)"
    }

    func totalAttachmentBytes() -> Int {
        guard let enumerator = fileManager.enumerator(at: attachmentsURL,
                                                     includingPropertiesForKeys: [.fileSizeKey],
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }

    /// 删掉没有被任何会话引用的孤儿附件（清理缓存用）
    func purgeOrphanAttachments() {
        var referenced = Set<String>()
        for summary in summaries {
            guard let conversation = loadConversation(id: summary.id) else { continue }
            for message in conversation.messages {
                for attachment in message.attachments {
                    referenced.insert(attachment.relativePath)
                    if let thumb = attachment.thumbnailRelativePath { referenced.insert(thumb) }
                    referenced.formUnion(attachment.frameRelativePaths)
                }
            }
        }
        guard let enumerator = fileManager.enumerator(at: attachmentsURL,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator {
            let relative = "\(attachmentFolder)/\(url.lastPathComponent)"
            if !referenced.contains(relative) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    func formattedStorageUsage() -> String {
        let bytes = totalAttachmentBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
