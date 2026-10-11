//
//  L10n.swift
//  AIAssistant
//
//  文案集中管理（中文）。刻意不用 Localizable.strings：
//  少一次文件 IO，启动更快，也方便直接改。
//

import Foundation

enum L10n {

    // MARK: 通用
    static let appName = "AI 助手"
    static let ok = "好"
    static let cancel = "取消"
    static let save = "保存"
    static let delete = "删除"
    static let done = "完成"
    static let close = "关闭"
    static let edit = "编辑"
    static let copy = "复制"
    static let copied = "已复制"
    static let retry = "重试"
    static let loading = "处理中…"
    static let notConfigured = "未配置"
    static let test = "测试连接"
    static let optional = "选填"

    // MARK: 会话
    static let chatListTitle = "AI 助手"
    static let newChat = "新对话"
    static let untitledChat = "新对话"
    static let emptyChatList = "还没有对话\n点右上角 + 开始"
    static let emptyChatHint = "问我点什么吧，可以发文字、图片、视频或按住说话"
    static let clearHistory = "清空全部对话"
    static let clearHistoryConfirm = "将删除所有本地对话与附件，且不可恢复。"
    static let deleteChatConfirm = "删除这条对话？"
    static let storageUsage = "本地占用"

    // MARK: 输入
    static let inputPlaceholder = "发消息…"
    static let holdToTalk = "按住 说话"
    static let releaseToSend = "松开发送"
    static let slideUpToCancel = "上滑取消"
    static let releaseToCancel = "松开手指，取消发送"
    static let voiceTooShort = "说话时间太短"
    static let recording = "正在录音…"
    static let transcribing = "正在识别…"
    static let micPermissionDenied = "没有麦克风权限，请到 设置-隐私-麦克风 里打开"
    static let speechPermissionDenied = "没有语音识别权限，请到 设置-隐私-语音识别 里打开"
    static let cameraPermissionDenied = "没有相机权限，请到 设置-隐私-相机 里打开"
    static let photoPermissionDenied = "没有相册权限，请到 设置-隐私-照片 里打开"
    static let stopGenerating = "停止生成"
    static let stopped = "已停止"
    static let requestFailed = "请求失败"
    static let msgTooLong = "内容过长"
    static let busyGenerating = "正在生成回复，请稍候"
    static let emptyReply = "模型没有返回内容"
    static let goToSettings = "去设置"
    static let sourceUnavailable = "当前不可用"
    static let noCamera = "此设备没有可用相机"
    static let imageProcessFailed = "图片处理失败"
    static let recordStartFailed = "录音启动失败"
    static let speechNotRecognized = "没听清，请再说一次"
    static let previewUnavailable = "该附件无法预览"
    static let voiceDisabled = "语音输入已在设置里关闭"
    static let visionOffHint = "当前服务未开启图片输入，图片会以文字描述发送"
    static let voiceAutoSend = "识别后直接发送"

    // MARK: 附件
    static let attachTitle = "发送内容"
    static let attachCamera = "拍照"
    static let attachCameraVideo = "拍视频"
    static let attachPhotoLibrary = "从相册选择图片"
    static let attachVideoLibrary = "从相册选择视频"
    static let attachMaxReached = "最多添加 6 个附件"
    static let attachCompressing = "正在压缩图片…"
    static let attachProcessingVideo = "正在处理视频…"
    static let attachEmpty = "选择的内容为空"
    static let videoFramesNote = "以下是该视频按时间顺序抽取的关键帧"

    // MARK: 设置
    static let settingsTitle = "设置"
    static let sectionService = "API 服务"
    static let sectionModel = "模型与参数"
    static let sectionSpeech = "语音"
    static let sectionMedia = "图片与视频"
    static let sectionAppearance = "外观与性能"
    static let sectionAbout = "关于"
    static let currentService = "当前服务"
    static let addService = "添加服务"
    static let serviceName = "名称"
    static let serviceKind = "接口类型"
    static let baseURL = "Base URL"
    static let chatPath = "对话路径"
    static let apiKey = "API Key"
    static let apiKeyPlaceholder = "粘贴你的 Key（保存在系统钥匙串）"
    static let model = "模型"
    static let systemPrompt = "系统提示词"
    static let supportsVision = "支持图片输入（多模态）"
    static let streaming = "流式输出（打字机效果）"
    static let temperature = "温度"
    static let maxTokens = "最大回复长度"
    static let maxImages = "单次最多图片数"
    static let extraHeaders = "自定义请求头"
    static let extraHeadersHint = "每行一个，格式 Key: Value"
    static let testSending = "正在请求…"
    static let testSuccess = "连接成功"
    static let testFailed = "连接失败"
    static let speechEnabled = "语音输入"
    static let speechKind = "识别方式"
    static let speechModel = "转写模型"
    static let speechLanguage = "识别语言"
    static let speechMaxDuration = "最长录音时长"
    static let transcriberServer = "服务器转写（Whisper 接口）"
    static let transcriberApple = "iOS 系统听写"
    static let ttsEnabled = "朗读回复"
    static let imageQuality = "图片压缩"
    static let imageQualitySaver = "省流量"
    static let imageQualityStandard = "标准"
    static let imageQualityHigh = "高清"
    static let videoFrames = "视频抽帧数"
    static let performanceMode = "低配模式（iPhone 5s 推荐）"
    static let performanceModeHint = "减少动画与缓存，降低内存占用"
    static let theme = "主题"
    static let themeSystem = "跟随系统"
    static let themeLight = "浅色"
    static let themeDark = "深色"
    static let clearCaches = "清除图片缓存"
    static let cachesCleared = "已清除"
    static let version = "版本"
    static let aboutHint = "纯系统框架实现，无第三方依赖。所有对话与附件只存在本机。"
    static let fillRequired = "请先填写 Base URL 与模型名"
    static let keyMissing = "还没有填 API Key"
    static let providerDeletedHint = "已删除"

    // MARK: 服务商预设
    static let providerKindOpenAI = "OpenAI 兼容（DeepSeek/通义/Moonshot/Ollama…）"
    static let providerKindAnthropic = "Anthropic Claude"

    // MARK: 默认提示词
    static let defaultSystemPrompt = """
    你是一个中文 AI 助手，回答准确、简洁、口语化。
    当用户发来图片或视频时，先描述你看到的关键信息，再回答问题。
    不确定的内容要说明不确定，不要编造。
    """
}

// 让模型层能直接拿到这些文案（Models.swift 里用到了 L10n）
typealias L10nText = L10n
