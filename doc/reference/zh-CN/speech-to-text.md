---
title: "语音转文字"
summary: "听写上传由 AI 助手当前的语音供应商转写；语音转文字没有自己的功能模块注册。"
---

## 概要

语音转文字不是 `FeatureModules` 注册。没有 `FeatureModules::SpeechToText` 类，也没有独立的模块键。`app/services/speech_to_text/` 校验上传、保存短命的 `SpeechToText::Clip`，并调用当前持有转写任务的 `AiAssistant::Providers` 子类。租户开关是 `FeatureModules::Module.enabled?(key: "ai_assistant")`。时长来自该模块的分配（`language`、`max_duration_seconds`），由 `SpeechToText::DurationPolicy` 读取。客户管理员可在设置中选择语言、查看录音时长上限；平台所有者在该客户的「维护／模块」下修改上限。参见 [ai-assistant](ai-assistant) 和 [module-framework](module-framework)。

两个调用方入队同一个活动。Cookie 组件提交到 `Admin::Modules::AiAssistant::TranscriptionsController`。桌面客户端提交到 `Admin::Assistant::TranscriptionsController`，之后轮询 `show`。两者都包含 `SpeechToText::TranscriptionEnqueueing`。供应商调用发生在 `SpeechToText::TranscribeJob`，不在 Puma 请求线程上。

## 流程

```text
DictateFieldComponent  或  桌面端麦克风
        |
        v
SpeechToText::TranscriptionEnqueueing#create
        |
        v
SpeechToText::Activities::EnqueueTranscription
        |  合同、时长、模块、供应商、限流
        |  SpeechToText::Clip（挂上音频，status pending）
        v
SpeechToText::TranscribeJob
        |
        v
SpeechToText::Activities::Transcribe
        |  AiAssistant::ProviderSettings.active_for(:transcribe)
        |  provider.transcribe
        v
destination「field」     -> Turbo 替换 SpeechToText::ResultComponent
destination「assistant」 -> AiAssistant::Activities::SendMessage
        |
        v
clip.audio.purge（持久化终态之后）
桌面端轮询：SpeechToText::Activities::ShowTranscription
之后：SpeechToText::PruneClipsJob 删除该行
```

## 实现

`EnqueueTranscription` 共用助手模块／供应商／限流检查，校验声明上传类型／大小、字段 ID 及归一目的地。客户端时长／字节上限仅为初步守卫，不是时长证明。`SpeechToText::AudioProbe` 在入队或付费调用前用 FFmpeg 解码实际音频，按单声道 8kHz 有符号 16 位 PCM 字节计算租户时长上限；仅允许本地 file／pipe 协议，解码限时 30 秒。缺少解码器返回 503 `audio_probe_unavailable`，无效音频为 422 `invalid_audio`，超时长为 `too_long`。请求主机及 worker 均须安装 FFmpeg，可用 `STT_FFMPEG_PATH` 指定程序。

`DurationPolicy::MODULE_KEY` 是 `"ai_assistant"`。默认上限 60 秒。绝对上限 120 秒。`SpeechToText::DictateFieldComponent` 读同一策略，浏览器展示的上限就是服务器执行的上限。写在 clip 上的语言是请求值，否则是分配里的 `language`，否则是 `"auto"`。

`Clip` 的目的地是 `"field"` 和 `"assistant"`。`normalize_destination` 对其他值返回 `"field"`，因此未知值只会填入调用方自己的输入框，不会发进助手线程。Cookie 控制器传递组件声明的目的地。桌面控制器把 `dictation_destination` 固定为 `DESTINATION_ASSISTANT`，把 `field_dom_id` 固定为 `"desktop"`，并通过 `Oauth::BearerAuthenticatable` 拒绝 Cookie 会话。参见 [authentication](authentication)。

`Transcribe` 原子领取 pending→processing，重查模块／供应商，转写并路由后持久化 succeeded／failed。助手片段使用入队时授权的 `conversation_id` 及 `SendMessage` 幂等键 `speech_to_text:clip:<id>`；已删除／外来会话不能将音频转入新线程。字段片段为签名用户流保留文本，助手片段在聊天交接后清空文本。重复 worker／终态重跑无操作。仅持久化终态后清除音频，持久化故障保留音频。`ShowTranscription` 限定片段／客户／用户。`PruneClipsJob` 将五分钟未更新的 pending／processing 标失败并广播，清除终态音频，自 updated_at 保留终态行 15 分钟。生产排期仍为每日 4:45，并非每五分钟。

清理前先将终态行的 `updated_at` 保存为局部变量 `finished_at`，因为 Active Storage 移除附件会更新片段时间戳。删除依据捕获的终态时间，不使用 `created_at`，也不使用清除音频后变化的时间戳。创建较早但刚完成的片段继续保留；终态已超过 15 分钟的片段，即使仍有音频附件也会删除。恰好 15 分钟时继续保留。这里的 `finished_at` 是局部变量，不是新增数据库列。

供应商在 `AiAssistant::Providers` 下，不在 `app/services/speech_to_text/` 下。能转写的类：`OpenaiWhisper`（`ruby-openai`，`default!` 供应商）、`AwsTranscribe`（ffmpeg 转为 PCM 后的 HTTP/2 流）、`Aliyun`（闪识，令牌经 `Vendor::AliyunRpc`）、`AwsBedrock`（Converse 的音频内容块；其他容器经 ffmpeg 转为 wav）。`Deepseek`、`Qwen`、`Cursor` 把 `supports_transcribe?` 设为 false，它们的 `#transcribe` 返回 `configuration_error`。`UpdateProviderSettings` 不会把这三者指派给转写任务。只做转写的供应商，其 `#chat` 仍是 `Providers::Base`，返回 `configuration_error`。

## 需要特别注意

### 浏览器录音验证

`spec/e2e/speech_to_text_mic.app.spec.js` 使用现有 `chromium-media` 项目的
麦克风权限和模拟采集设备，由 Chromium 的实际 `MediaRecorder` 录音。测试等待
实际 `speech-to-text` Stimulus 控制器及 Action Cable 已确认的面板流订阅，
点击麦克风、核对录音状态，等待录音时长
达标后点击停止，并断言正常上传返回 202。应用通过 `AudioProbe` 解码音频，再经
本地 HTTP SDK 供应商转写。`helpers/speech_runtime.js` 核对供应商收到的准确
multipart 音频字节数／SHA-256、可见转写文本、该测试独立持有的准确会话、正数解码时长、
持久化的 `succeeded` 终态及已清除的音频。就绪和时长轮询不调用应用动作方法。
`Clip` 没有时长列；辅助程序监听原生录音器的 `dataavailable` 事件，正常请求获准后
使用实际 `AudioProbe` 重新检测这些字节。供应商 SHA-256 匹配证明同一音频实际通过
SDK 传输，即使 Chromium 网络检查器省略 multipart 文件内容也可验证。
测试复用已准备好的准确数据库；现有服务器上的四 worker 命令见
`spec/e2e/README.md`。

2026 年 10 月 12 日，这组五用例复测以四 worker 全部通过：5/5，零重试、跳过或
不稳定用例；供应商辅助测试通过 4/4。实际录音片段 4 解码时长 1.32 秒，13,932
字节及 SHA-256 与供应商一致，进入固定会话 17，持久化为 `succeeded` 并清除音频。
转写文本在浏览器可见，并经数据库核对。证据：
`/tmp/opencode/assistant-audio-followup/results-final.json` 及 `summary.md`。

### 路由审计：入队确认及会话绑定

`EnqueueTranscription.call(..., conversation_id:)` 在保存 assistant 片段前要求自有会话。拒绝／抛错入队产生失败片段及 503 `enqueue_failed`，不误返回 202。`BroadcastResult` 将已提交终态与流投递错误分开。语音交接迁移增加会话／processing 状态及开始时间。

:::attention
两套 HTTP 调用均允许／传入 `conversation_id`，助手上传要求会话属于认证客户／用户。`DictateFieldComponent(conversation_id:)` 挂载所选线程，`speech-to-text` 在麦克风权限提示前固定 ID；`ai-assistant:conversationChanged` 仅更新下一次录音，不改变已缓冲片段。桌面上传显式发送所选 ID，轮询返回 id／status／conversation_id／error_code，仅成功的自有字段片段返回原转写文本，助手文本由固定聊天消费。已创建持久片段的入队失败响应包含 clip_id。见 [AI 助手](ai-assistant)、[OAuth](oauth)、[后台任务](background-jobs)。
:::

:::note
2026 年 10 月 11 日，AI／实体定义／语音转文字／LLM 定向测试在 `storage/ai_verify.sqlite3`、结构版本 `20261011190000` 上通过：1,666 个用例，零失败。语音测试实际解码 FFmpeg 生成的压缩音频，并覆盖线程绑定、入队拒绝、终态／重复处理、广播回退及清除音频前的保留期判断。结构加载到隔离测试数据库；该操作不执行仅修改数据的历史付款回填。实际厂商与浏览器流程不在本次范围内。证据见 `docs/audits/2026-10-11-ai-stt-targeted-verification.md`。
:::

:::attention
语音转文字没有在 `FeatureModules` 里注册。`SpeechToText::Activities::Transcribe` 和 `SpeechToText::DurationPolicy` 都以 `ai_assistant` 为键。关掉该模块后，入队返回 403，进行中的任务记为 `disabled`。听写没有单独的启用行。
:::

:::attention
`SpeechToText::Activities::EnqueueTranscription` 不调用供应商。只有 `SpeechToText::Activities::Transcribe` 打开音频并调用 `provider.transcribe`。`Admin::Modules::AiAssistant::TranscriptionsController` 在任务入队后返回 202 和 `clip_id`。
:::

:::attention
`SpeechToText::Clip.normalize_destination` 失败即落到 `"field"`。`Admin::Assistant::TranscriptionsController` 不信任请求体里的目的地：它始终设置 `DESTINATION_ASSISTANT`。字段 clip 不会调用 `AiAssistant::Activities::SendMessage`。
:::

:::attention
先持久化终态，再清除音频。processing／pending 持久化失败保留音频供排期恢复；轮询读取持久状态，不按 blob 是否存在判断。清理保留期使用清除音频前捕获的终态 `updated_at`。
:::

## 关键代码

```ruby
# app/services/speech_to_text/activities/enqueue_transcription.rb
def call
  failure = preflight_failure
  return failure if failure

  clip = create_clip!
  job = SpeechToText::TranscribeJob.perform_later(clip.id)
  return enqueue_failure(clip) unless job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)
  success_result(clip)
end
```

```ruby
# app/services/speech_to_text/activities/transcribe.rb
def transcribe_clip
  unless FeatureModules::Module.enabled?(key: "ai_assistant", customer_id: clip.customer_id)
    return failed("disabled")
  end

  settings = AiAssistant::ProviderSettings.active_for(:transcribe)
  return failed("disabled") unless settings
  return failed("generic_error") unless clip.audio.attached?

  result = clip.audio.open do |file|
    settings.provider_class.new(settings: settings).transcribe(
      io: file,
      filename: clip.audio.filename.to_s,
      content_type: clip.audio.content_type,
      language: clip.language
    )
  end
  map_outcome(result)
end
```

```ruby
# app/models/speech_to_text/clip.rb
def self.normalize_destination(value)
  candidate = value.to_s.strip
  DESTINATIONS.include?(candidate) ? candidate : DEFAULT_DESTINATION
end
```

```ruby
# app/services/speech_to_text/duration_policy.rb
MODULE_KEY            = "ai_assistant"
DEFAULT_MAX_DURATION  = 60
ABSOLUTE_MAX_DURATION = 120
```
