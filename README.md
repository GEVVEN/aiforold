# AI 助手 · 可换 API 的 iOS 客户端（iOS 12+ / iPhone 5s 友好）

一个**纯 UIKit、零第三方依赖**的 iPhone AI 助手 App。功能对标手机版豆包：文字对话、发图片、发视频、按住说话、语音朗读、会话历史、深色模式，**API 可以随便换**（DeepSeek / OpenAI / Claude / 通义 / Moonshot / 硅基流动 / Ollama / one-api 网关都行），Key 存在系统钥匙串里。

- 最低系统：**iOS 12.0**（iPhone 5s、iPhone 6、iPad Air 1 这一代都还能装）
- 目标机型：**iPhone 5s（A7 双核 / 1GB 内存 / 4 英寸屏）**，专门做了低配优化
- 工程形态：完整可编译的 Xcode 工程（`AIAssistant.xcodeproj`），另有 GitHub Actions 云打包脚本
- 依赖：**无**。没有 CocoaPods / SPM / Carthage，没有 SwiftUI，没有 Swift 并发

> ⚠️ 先说实话：**IPA 必须用 macOS 上的 Xcode 签名打包**，Windows 本机做不到。
> 所以这里给了两条可落地的路径：① GitHub Actions 免费云打包出 `.ipa`；② Windows 用 Sideloadly / AltStore 用你自己的 Apple ID 签名安装。
> 详见 [docs/构建与安装.md](docs/构建与安装.md)。

---

## 一、功能清单

| 能力 | 实现方式 | 说明 |
| --- | --- | --- |
| 文字对话 | `URLSession` + SSE 流式解析 | 打字机效果，可随时「停止生成」 |
| 换 API | 设置页可视化配置，支持多个服务随意切换 | OpenAI 兼容协议 + Anthropic 协议两种适配器 |
| 发图片 | 相册 / **直接拍照** | 发送前按档位压缩（省流量 / 标准 / 高清） |
| 发视频 | 相册选 / **直接拍** | 均匀抽 1–6 帧当图片发给多模态模型，音轨可转写成文字一起发 |
| 语音发送 | 按住说话，上滑取消 | 两条识别路线：iOS 系统听写 / 服务器 Whisper 接口 |
| 语音朗读 | `AVSpeechSynthesizer` | 离线、免费、不消耗接口额度 |
| 会话历史 | 索引 + 单会话 JSON | 列表只读索引，进聊天才加载消息，省内存 |
| 长按复制 | `UIMenuController` | iOS 12 原生交互 |
| 深色模式 | 自绘配色 | 「跟随系统 / 浅色 / 深色」三选一 |
| 图片查看 | 全屏缩放、左右切换、保存到相册 | 视频附件在这里按「第 N/M 帧」展示 |
| 低配模式 | 关动画、压更狠、缓存更小 | 默认开启，为 5s 准备 |

**为什么视频不是直接上传视频文件？** 因为主流大模型 API（OpenAI / Anthropic / DeepSeek / 通义 …）目前都不接受视频输入。业界通行做法就是「抽关键帧 + 音轨转写」，本项目按这个思路实现：抽帧数量、压缩档位都能在设置里调。

---

## 二、源码结构

```
AIAssistant/
├── AIAssistant.xcodeproj/            # Xcode 工程（由脚本生成，别手改）
│   └── xcshareddata/xcschemes/       # 共享 scheme
├── AIAssistant/
│   ├── Info.plist                    # 权限说明 + 允许局域网 HTTP 接口
│   ├── LaunchScreen.storyboard       # 启动图（iOS 12 用 storyboard，不用 iOS 14 的 UILaunchScreen）
│   ├── Assets.xcassets/AppIcon.appiconset/   # 全套 App 图标（脚本生成）
│   └── Sources/
│       ├── App/AppDelegate.swift
│       ├── Core/       Models · Settings · Storage · Keychain · Theme · Icons · L10n
│       ├── Net/        HTTPClient · SSEReader · ChatProvider · ChatService · TranscriptionService
│       ├── Media/      ImagePipeline · VideoPipeline · AudioRecorder · SpeechRecognizer · SpeechPlayer
│       ├── Text/       MarkdownLite
│       └── UI/         ChatViewController · ConversationListViewController · SettingsViewController
│                       · ChatMessageCell · ComposerView · FormKit · RecordOverlayView · Toast · ImageViewer
├── docs/
│   ├── API配置说明.md                # 各家服务怎么填、报错怎么排
│   └── 构建与安装.md                  # 三种拿到 ipa 的路径（含 Windows 自签）
├── tools/
│   ├── generate_pbxproj.py           # 生成 Xcode 工程文件（增删源文件后重跑）
│   ├── make_icon.py                  # 生成全套 App 图标
│   └── check_ios12.py                # 静态自检：iOS 12 兼容性 / 括号配对 / 文案一致性 / 工程配置
└── .github/workflows/build-ipa.yml   # 云端打包出未签名 ipa
```

---

## 三、怎么拿到能装的 ipa

### 路线 A：Windows 用户推荐（免费、不用 Mac）

1. 把整个 `AIAssistant` 目录推到你的 GitHub 仓库（公开或私有都行）。
2. 进仓库 **Actions → Build unsigned IPA → Run workflow**，等 3–5 分钟。
3. 在运行结果页最下面下载 **AIAssistant-unsigned-ipa**。
4. Windows 装 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/)，用你自己的 Apple ID 对 ipa 签名并安装（iPhone 需先用数据线连到电脑并信任）。
5. iPhone 上：**设置 → 通用 → 描述文件与设备管理**，信任你的开发者证书，然后就能打开 App。

### 路线 B：有 Mac

1. 双击 `AIAssistant.xcodeproj`。
2. **Signing & Capabilities** 里把 Bundle Identifier 改成你自己的（例如 `com.你的名字.aiassistant`），Team 选你的 Apple ID。
3. 选中真机 → Run。或 **Product → Archive → Distribute App → Ad Hoc/Development** 导出 ipa。

### 路线 C：想要长期不过期

免费 Apple ID 签出来的 App **7 天后失效**（需重新签一次，AltStore 能自动续）。想长期用，用付费开发者账号（$99/年）签名，证书有效 1 年。

---

## 四、第一次使用必须配置 API

打开 App → 右上角齿轮 → 填这几项（以 DeepSeek 为例）：

| 字段 | 值 |
| --- | --- |
| 接口类型 | OpenAI 兼容 |
| Base URL | `https://api.deepseek.com` |
| 对话路径 | `/v1/chat/completions` |
| 模型 | `deepseek-chat`（要发图片就填 `deepseek-vl` 之类的多模态模型，并打开「支持图片输入」） |
| API Key | 你自己的 Key（只存本机钥匙串，不会进备份文件） |

填完点 **测试连接**，成功会有弹窗提示。更多服务商的填法见 [docs/API配置说明.md](docs/API配置说明.md)。

---

## 五、为 iPhone 5s 做的优化（以及为什么这样写）

| 优化点 | 具体做法 |
| --- | --- |
| 内存 | 图片一律走 `ImageIO` 的「解码即缩放」（`CGImageSourceCreateThumbnailAtIndex`），**从不把 8MP 原图整个解码**；缩略图 / base64 都进带容量上限的 `NSCache`；收到内存警告立即清缓存 |
| 启动 | 没有 storyboard 主界面（全代码建视图），没有第三方库初始化，没有 Scene 生命周期 |
| 滚动 | 自定义 cell + `UITableViewAutomaticDimension`，约束只建一次、配置阶段只改文本与颜色；缩略图用 token 防复用串图 |
| 流式输出 | 0.16s 节流合批刷新，且**流式期间只渲染纯文本**（不做 Markdown 排版），结束后才排版一次 |
| 网络 | 单会话并发上限 3，超时可配；`stream_options` 等非通用字段一律不发 |
| 录音 | AAC 16kHz / 单声道 / 32kbps，60 秒只有约 240KB |
| 视频 | 默认只抽 3 帧，每帧长边 ≤ 832px（省流量档） |
| 动画 | 只有波形、Toast、键盘三类轻动画；低配模式下刷新更保守 |
| 图标 | 全部用 Core Graphics 现画（`Icons.swift`），不带图片资源，iOS 12 也能用（不用 SF Symbols） |

---

## 六、自检（不需要 Xcode / macOS）

```bash
python3 tools/generate_pbxproj.py --check   # 工程与源码是否一致
python3 tools/check_ios12.py                # iOS12 兼容性 / 括号配对 / 文案引用 / 工程配置
```

> Windows 上把 `python3` 换成 `python` 即可。

`check_ios12.py` 会拦住这些坑：`UIImage(systemName:)`、`UIColor.systemBackground`、`insetGrouped`、`UINavigationBarAppearance`、`UIScene`、`PHPicker`、`UTType`、SwiftUI、Combine、Swift 并发、`AttributedString` 等等（已用 `#available` 包住的只提示不报错）。

改完源文件（新增 / 删除 `.swift`）记得重跑：

```bash
python3 tools/generate_pbxproj.py           # 重新生成工程文件并刷新 scheme
```

图标想换配色就改 `tools/make_icon.py` 顶部的两个颜色常量再跑一次。

---

## 七、已知限制

- 通过免费 Apple ID 自签的 App **7 天过期**，需要重新签（AltStore 可自动续期）。
- 部分地区/网络下 `api.deepseek.com` 等域名可能连不上，属网络问题，会明确提示「连不上服务器」。
- 系统听写（Speech.framework）在 iOS 12 上**必须联网**，且单次识别有长度限制；想更稳请切到服务器转写。
- 视频只发关键帧，模型看到的是几张静态画面，不是连续动作。
- 工程按 iPhone 竖屏设计，iPad 能跑但布局就是放大版。
- `Info.plist` 里开了 `NSAllowsArbitraryLoads`，是为了让局域网自建接口（Ollama / LM Studio / one-api）能用。**如果要上架 App Store，请删掉这一段**，或改成只放行你自己的域名。
- 本项目是个人使用向的客户端，不含任何账号体系、云同步和内容审核。

## 八、免责声明

请遵守你所使用 API 服务商的条款与当地法律法规；API Key、对话内容都在你自己的设备和你选择的服务商之间流动，作者不收集任何数据。
