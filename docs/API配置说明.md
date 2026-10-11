# API 配置说明

设置入口：App 首页 → 右上角 **齿轮** → 「API 服务」。

App 里 API 地址由 **Base URL** + **对话路径** 拼出来，拼接规则是「宽进严出」：

- `Base URL` 末尾的 `/` 会被自动去掉；
- 如果 `Base URL` 已经以 `/v1` 结尾，而路径也是 `/v1/...`，不会重复拼成 `/v1/v1/...`；
- 所以下面表格里的两种写法都对：

```
Base URL: https://api.deepseek.com        路径: /v1/chat/completions
Base URL: https://api.deepseek.com/v1     路径: /chat/completions
```

---

## 一、常用服务商

| 服务商 | 接口类型 | Base URL | 对话路径 | 模型示例 | 图片输入 |
| --- | --- | --- | --- | --- | --- |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com` | `/v1/chat/completions` | `deepseek-chat`、`deepseek-reasoner` | 需换多模态模型 |
| OpenAI | OpenAI 兼容 | `https://api.openai.com` | `/v1/chat/completions` | `gpt-4o-mini`、`gpt-4o` | ✅ |
| Anthropic Claude | Anthropic Claude | `https://api.anthropic.com` | `/v1/messages` | `claude-3-5-sonnet-latest` | ✅ |
| 阿里通义（DashScope 兼容模式） | OpenAI 兼容 | `https://dashscope.aliyuncs.com/compatible-mode` | `/v1/chat/completions` | `qwen-vl-max`、`qwen-plus` | ✅（VL 系列） |
| Moonshot Kimi | OpenAI 兼容 | `https://api.moonshot.cn` | `/v1/chat/completions` | `moonshot-v1-8k` | 需视觉模型 |
| 智谱 GLM | OpenAI 兼容 | `https://open.bigmodel.cn/api/paas/v4` | `/chat/completions` | `glm-4v-flash` | ✅ |
| 硅基流动 | OpenAI 兼容 | `https://api.siliconflow.cn` | `/v1/chat/completions` | `Qwen/Qwen2.5-7B-Instruct` | 看具体模型 |
| Ollama（电脑上跑，手机连局域网） | OpenAI 兼容 | `http://192.168.1.20:11434` | `/v1/chat/completions` | `qwen2.5:7b` | 需 `llava` 之类 |
| LM Studio | OpenAI 兼容 | `http://192.168.1.20:1234` | `/v1/chat/completions` | 模型名照抄 LM Studio 界面 | 看模型 |
| one-api / new-api 网关 | OpenAI 兼容 | `https://你的网关域名` | `/v1/chat/completions` | 网关里配置的模型名 | 看上游 |

> ⚠️ 模型名一定要填**服务商文档里的准确名字**。填错会返回 404 或 `model_not_found`。

### Anthropic 的两个坑

1. `max_tokens` 是**必填**的，App 已经帮你带上（默认 2048，可在设置里改）。
2. 它要求 user / assistant 严格交替，App 会自动合并连续同角色的消息。

---

## 二、局域网自建服务（Ollama / LM Studio）

手机和电脑要在同一个 Wi-Fi 下，并且服务要监听 `0.0.0.0`：

```bash
# Ollama：允许局域网访问，然后拉一个模型
OLLAMA_HOST=0.0.0.0 ollama serve
ollama pull qwen2.5:7b
```

查看电脑的局域网 IP（Windows：`ipconfig`；macOS：`ipconfig getifaddr en0`），把 `http://192.168.x.x:11434` 填进 Base URL。

**注意**：App 里填 `127.0.0.1` 指的是**手机自己**，不是你的电脑。另外 `Info.plist` 已开启 `NSAllowsArbitraryLoads`，所以 `http://`（非 HTTPS）的局域网接口可以直接用；如果把它关掉，iOS 会拦住明文 HTTP。

---

## 三、语音转写（可选）

「按住说话」默认走 **iOS 系统听写**，iOS 12 上需要联网。想更准、更快，可以切到 **服务器转写**（设置 → 语音 → 识别方式）：

| 服务商 | Base URL | 路径 | 模型 |
| --- | --- | --- | --- |
| OpenAI Whisper | `https://api.openai.com` | `/v1/audio/transcriptions` | `whisper-1` |
| Groq | `https://api.groq.com/openai` | `/v1/audio/transcriptions` | `whisper-large-v3` |
| 硅基流动 | `https://api.siliconflow.cn` | `/v1/audio/transcriptions` | `FunAudioLLM/SenseVoiceSmall` |
| one-api 网关 | 你的网关地址 | `/v1/audio/transcriptions` | `whisper-1` |

录音格式固定为 `audio/m4a`（AAC 16kHz 单声道 32kbps）。如果服务商只认 wav/mp3，会返回 400，需要改成对应格式——目前代码里在 `Media/AudioRecorder.swift` 调整 `AVFormatIDKey` 即可。

---

## 四、自定义请求头

有些网关需要额外头（如版本号、组织标识）。设置页「自定义请求头」按每行一个 `Key: Value` 填：

```
X-Api-Version: 2024-01-01
OpenAI-Organization: org-xxxx
```

这些头会加在所有请求上（含流式请求）。`Authorization: Bearer <key>` 与 Anthropic 的 `x-api-key` 由 App 自动带上，不用手写。

---

## 五、常见报错对照

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| 「还没有填 API Key」 | Key 为空 | 填 Key；本地服务（127.0.0.1 / 192.168.x）可留空 |
| HTTP 401 / 403 | Key 错、欠费、IP 被限 | 换 Key 或检查服务商控制台 |
| HTTP 404 | 路径或模型名错 | 核对 Base URL + 路径；确认模型名 |
| HTTP 429 | 触发限流 | 等一会儿，或把「最大回复长度」调小 |
| 连不上服务器 | 域名被墙 / Wi-Fi 问题 | 换网络或用国内中转网关 |
| 返回内容无法解析 | 网关返回了非标准结构 | 换一家，或用 one-api 做统一转换 |
| 一直「正在输入…」后报错 | 服务端不支持流式 | 设置里关掉「流式输出」再试 |
| 中文乱码 | 极少数网关编码不规范 | 换网关；App 端已按 UTF-8 严格解析 |
| 图片发送后模型说看不到 | 模型不支持图片，或没开「支持图片输入」 | 换多模态模型，并在设置里打开开关 |

---

## 六、想再加一家新协议？

只要实现一个 `ChatProvider` 就够了，UI、会话、存储都不用动：

```swift
// Sources/Net/ChatProvider.swift
protocol ChatProvider {
    var profile: ProviderProfile { get }
    func makeRequest(messages: [ChatMessage]) throws -> URLRequest  // 组请求
    func parse(event: SSEEvent) -> [StreamDelta]                    // 解流式增量
    func parseCompletion(_ data: Data) throws -> ChatCompletion      // 解非流式响应
}
```

照着 `OpenAIProvider` 抄一份，改请求体字段和 SSE 取值路径，再在 `ChatProviderFactory.make(_:)` 里加一个分支即可。图片内容由 `MessagePreparer` 统一整理成「文本 + 图片」中间格式，你只需要把它渲染成对方的 JSON 结构。
