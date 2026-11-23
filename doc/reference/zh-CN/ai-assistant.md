---
title: "AI 助手"
summary: "管理端会话、流式回复、工具调用、实体／表单／流程自动启用、后台子系统构建，以及 ruby_llm 封装前的平台供应商设置。"
---

## 概要

AI 助手是功能模块 `ai_assistant`。`FeatureModules::AiAssistant::Registration` 负责注册，入口为 `/:customer_id/admin/assistant`；客户设置中可修改回复语言（`auto`、`en`、`zh-CN`），听写时长上限只读。开通与关闭都不做数据准备。模块是否启用，由 [speech-to-text](speech-to-text) 读取；听写本身不是第二个功能模块。

一条线程是 `AiAssistant::Conversation`，属于一个客户和一个用户。每一轮是 `AiAssistant::Message`。每次回复对应一行 `AiAssistant::Generation`，由后台任务写完。请求线程只保存用户消息并入队。供应商 HTTP 只在 `AiAssistant::ReplyJob` 里发生。

对话补全走 `Llm`，这是 `ruby_llm` gem 的应用层封装。调用方不构造 `RubyLLM::Chat`。Whisper 转写留在 `AiAssistant::Providers::OpenaiWhisper` 里的 `ruby-openai`。Cursor Cloud Agents 留在 `AiAssistant::Providers::Cursor` 里的 `OutboundHttp`。平台凭证和两个任务开关在 `AiAssistant::ProviderSettings` 上，编辑地址是 `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings`。

## 配置 AI 与语音转写供应商

在 `/81721200/admin/maintenance/platform/module_settings/ai_assistant/settings` 编辑所需供应商，按其**实际凭证标签**填写密钥（API 密钥、AWS Secret Access Key 或阿里云 Access Key Secret），并运行**连接测试**。按钮会将探测任务入队；应等待结果，不能把立即返回当作测试通过。再通过**更换提供商**分别为**实体/流程图生成**和**音频转写**指派**已配齐**的供应商；保存密钥或连接测试通过都不会自动指派任务。在 `/:cid/admin/maintenance/modules` 为客户启用 `ai_assistant`；平台所有者也在此为该客户设置正整数 `max_duration_seconds` 录音时长上限。客户在 `/:cid/admin/settings/modules/ai_assistant` 可修改语言，但只能查看时长上限；伪造设置请求也不能更改。听写属于同一模块，没有独立开关。应分别测试实际聊天回复和有语音的音频：连接探针对语音供应商发送静音，对多数仅生成供应商发送文本，而 Cursor 只列出模型，无法验证全部模型与模态。

| 供应商／任务 | 厂商侧准备与 Anysys 字段 | 验证要点／接入限制 |
| --- | --- | --- |
| **OpenAI / Whisper**（`openai_whisper`）：两项 | [创建可计费的 OpenAI API 项目和密钥](https://developers.openai.com/api/docs/quickstart)；填写 **API Key**、可选的 **Organization**、音频 **Model**（`whisper-1`）及 **Chat model**（`gpt-4o-mini`）。参见 [OpenAI 语音转文字](https://developers.openai.com/api/docs/guides/speech-to-text)。 | 连接探针只转写静音，**不测试**聊天模型权限；另用真实语音和聊天回复验证。 |
| **DeepSeek**（`deepseek`）：生成 | [创建 DeepSeek API 密钥](https://platform.deepseek.com/api_keys)；填写 **API Key** 和 **Chat model**。应用默认 `deepseek-chat`，但**当前公布的[模型列表](https://api-docs.deepseek.com/quick_start/pricing)已不包含它**（列出 `deepseek-flash`／`deepseek-v4-pro`）；应选择并实测列表中的模型，不要依赖默认值。 | 不支持语音转写。 |
| **通义千问／Model Studio**（`qwen`）：生成 | 开通[阿里云百炼并创建 API 密钥](https://www.alibabacloud.com/help/en/model-studio/first-api-call-to-qwen)；填写 **API Key** 和 **Chat model**（默认 `qwen-plus`）。须选择**中国（北京）**地域的密钥和模型。 | Anysys 固定请求 `https://dashscope.aliyuncs.com/compatible-mode/v1`；表单不能切换到其他[地域](https://www.alibabacloud.com/help/en/model-studio/regions)。厂商推荐工作空间专属域名；旧 DashScope 域名从 2026 年 9 月 30 日起不再增加新功能。不支持语音转写。 |
| **AWS Bedrock**（`aws_bedrock`）：生成，可选语音 | 为 IAM 密钥授予 `bedrock:InvokeModel`，流式生成还需 `bedrock:InvokeModelWithResponseStream`；核对所选地域的[模型访问权限](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)。填写 **Access Key ID**、**Secret Access Key**（存入共用 `api_key` 列）、**Region**、**Chat model** 及音频 **Model**。 | 默认的 `amazon.nova-lite-v1:0` [不支持音频输入](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-lite.html)。音频 **Model** 必须支持通过 **Converse** 接口传递 `audio` 内容块；即使是 [Nova 2 Sonic](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-sonic.html) 一类语音模型，如使用不同 API，也不适用。连接测试向 **Chat model** 发送文本，不验证音频 **Model**。 |
| **AWS Transcribe**（`aws_transcribe`）：语音 | 依 [AWS 流式转写配置](https://docs.aws.amazon.com/transcribe/latest/dg/streaming-setting-up.html)，在所选地域为 IAM 密钥授权 `transcribe:StartStreamTranscription`。填写 **Access Key ID**、**Secret Access Key**（存入 `api_key`）和 **Region**（默认 `us-east-1`）；在后台任务机器上安装 `ffmpeg` 以转码上传音频。 | 使用 HTTP/2 流式接口；自动语言识别只选 `en-US`／`zh-CN`。不支持生成。 |
| **阿里云智能语音**（`aliyun`）：语音 | 开通[智能语音交互](https://www.alibabacloud.com/help/en/isi/getting-started/start-here)，创建授权 RAM AccessKey 和[语音项目](https://www.alibabacloud.com/help/en/isi/getting-started/manage-projects)。填写 **Access Key ID**、**Access Key Secret**（存入 `api_key`）、项目 **App Key** 及 **Region**（默认 `cn-shanghai`）。 | 适配器自行获取[访问令牌](https://www.alibabacloud.com/help/en/isi/getting-started/use-http-or-https-to-obtain-an-access-token)，但即使修改 Region，令牌主机／地域仍固定上海；语言由阿里云项目决定。不支持生成。 |
| **Cursor Cloud Agents**（`cursor`）：生成 | 创建 [Cursor API 密钥](https://cursor.com/docs/api)，填写 **API Key**，可从 `GET /v1/models` 选择 **Chat model**。 | 创建现读取 `agent.id` 与 `run.id`，轮询该精确 run，不使用可变 latestRunId。FINISHED 读取结果，ERROR／CANCELLED／EXPIRED 失败，轮询有时限。模型列表探测仍不等于真实回复测试；仅转发最后五张附件图片，不转写语音。 |

上传格式、时长、后台任务以及成功转写的含义见[语音转文字](speech-to-text)。

流程图名称只在 `FlowchartVisibility.allowed?` 为真时进入提及、目录工具和流程图轮次。该判断等于 `platform_owner?`。流程图输出契约（`FlowchartDefinitions::StructureSchema`）及其调色板由 `CodeGenerators::ActionCatalog.export` 生成，步骤动作与字段名不会与已移植生成器脱节。用 `bin/rails ai_assistant:flowchart_schema` 重新生成已提交的快照。参见 [flowchart-builder](flowchart-builder)。

助手以工具方式调用[操作 API](operations-api) 来创建和修改实体结构：`get_entity` 读取，`create_entity` 创建并立即生效，`update_entity` 修改且一律等待管理员处理：点击**应用更改**批准方案，或点击**放弃**撤回。无效调用返回带类型的违规项，由模型自行修正、向用户提问或说明原因。模型最终回复的文本不会写入任何数据。遇到只能由管理员决定的事项时，模型以问题卡片提问（结构化的 `questions`，建议答案已预选）；代管理员做出的重要决定，以 `assumptions` 列在回复下方。

通过 `/:customer_id/admin/assistant`（包括 `/81721200/admin/assistant`）新生成的资源可直接使用：实体与关联桥接立即处于有效状态，新建流程图通过校验后自动上线，生成的表单 `Page` 按列默认值上线（管理员开，会员与公开关）。更新或复用已有记录时保留其生命周期状态。参见[实体构建器](entity-builder)、[流程图构建器](flowchart-builder)及[页面构建器](page-builder)。

租户开启 `website` 模块后，助手还能搭建 [网站构建器](website-builder) 的页面。管理员描述业务；缺少关键信息时，模型以 `clarify` 问题卡片提问；`apply_website` 文档写入草稿状态的 `WebsitePage`。会话中上传的图片按内容放进图片字段，并复制到租户的网站媒体中。

## 流程

```text
POST /:cid/admin/modules/ai_assistant/messages
  或 POST /:cid/admin/assistant/messages（桌面端 Bearer）
        |
        v
AiAssistant::Activities::SendMessage
        |  用户消息 + AiAssistant::Generation（queued）
        v
AiAssistant::Assistant::GenerationHandoff
        |
        v
AiAssistant::ReplyJob
        |
        v
AiAssistant::Activities::Reply
        |  ExecutionPolicy，然后 ProviderClient#chat
        |  Llm.complete -> RubyLLM.context（走 ruby_llm 的生成供应商）
        |  原生工具调用 -> Tools::Session
        |    操作 -> Operations::Activities::Execute
        v
AiAssistant::Assistant::TurnProcessor
        |  Loop（JSON「tool」文档，最多 8 步）-> 同一个 Tools::Session
        |  Websites::Assistant::Processor
        |    意图为 apply_website；取代下面两步
        |  ReplyEnvelope（意图 chat 或 clarify）
        |    实体结果取自本轮的操作结果
        |  FlowchartDefinitions::Assistant::Processor
        |    仅当 FlowchartVisibility.allowed?(user)
        v
AiAssistant::Stream
        |  Turbo 流名称 [:ai_assistant, customer_id, user_id, conversation_id]
        v
管理端助手面板
```

单纯的决定跳过供应商补全。`AiAssistant::Assistant::PendingConfirmation.consume` 按所有语言的词表识别单纯同意（「确认」「yes」）与单纯拒绝（「算了」「no」），且只处理这句回复直接回应的提案：即它之前最近一条已完成的助手消息，前提是该消息不带问题卡片。**应用更改**按钮发送同样的同意语，并附带 `proposal_message_id`，把它固定到所属消息，因此中间问过别的问题后仍能应用。批准操作提案时，对其挂起的调用记录运行 `Operations::Activities::Confirm`；流程图提案以 `confirmed: true` 重放存储的文档。单纯拒绝使提案退役。**放弃**提交到 `POST /:cid/admin/modules/ai_assistant/messages/:id/discard_proposal`，退役提案且不消耗轮次。

## 实现

`SendMessage` 校验契约／模块／供应商，按客户／用户原子命中突发（15 秒 5 次）及持续（每小时 30 次）窗口。在同一会话锁内插入轮次、记录活动并安装 generation，保留顺序及 40 轮上限。之后入队，失败会创建带 `enqueue_failed` 的终态失败助手消息并清空 generation 指针。轮询 pending 仅取当前有效 generation，不按末尾用户消息推断。

桌面轮询仅有未回复的用户消息时，返回 `pending_reply: false`。安装 queued／running 当前 generation 后为 true；generation 进入终态后为 false，即使用户消息仍在。轮询不会按消息顺序推断 worker 是否运行。

`Reply` 领取这一代，运行 `ExecutionPolicy`（代、会话、用户消息的客户一致；用户是该客户的有效管理员或平台所有者；模块已开；`ProviderSettings.active_for(:generation)` 有结果），然后调用供应商。`ProviderClient` 统计这一轮里的每一次补全，包括工具循环和修复往返，到 `AiAssistant::Limits::MAX_VENDOR_CALLS`（12）即停。只有 `supports_streaming?` 为真时才转发 `on_chunk`。`DeltaPump` 合并 token（新增 24 个字符或间隔 120 毫秒），取消后停止推送。`Stream` 替换同一个草稿节点，重试的任务不会再叠一个气泡。

`TurnProcessor` 对供应商文本运行 `Loop`。带 `tool` 键的 JSON 对象由 `AiAssistant::Assistant::Tools::Session` 执行，然后再次调用模型，上限是 `Loop::MAX_STEPS`（8）。没有 `tool` 的文档原样通过。最终文本须能解析为 `ReplyEnvelope`：`{"intent": "chat", "reply": "…"}`，或意图为 `clarify` 的同样结构；纯文本视为闲聊。其他文档一律以提取失败消息结束这一轮。信封还可带 `questions` 与 `assumptions`。`AiAssistant::Assistant::Questions` 清洗二者，从不让这一轮失败：最多 `MAX_QUESTIONS`（5）个问题，类型为 `single`、`multiple` 或 `text`，每题 2–`MAX_OPTIONS`（8）个选项，默认值对齐到所给选项，长文本截断，编号 `q1…qN`；假设最多 `MAX_ASSUMPTIONS`（5）条。只要留下问题，意图即变为 `clarify`；此时 `reply` 为空则回退为 `questions.intro`。`Finalizer` 在已完成的轮次中把两份列表存入助手消息的 `metadata["questions"]` 与 `metadata["assumptions"]`。实体结果取自本轮的操作结果，而非文本：实体写入成功时，`created`、`updated`、`bridges` 中的名称附加到回复末尾；有挂起提案时追加审阅提示。流程图处理器仅在查看者被允许看见流程图，且实体结果为 `complete`、没有挂起提案，并且已经应用了变更或意图是闲聊时运行。其回复附加在实体回复之后；但若流程图这一步同样以 `chat` 意图结束（既未保存也未提案），实体回复已作答，流程图回复即被丢弃，以免重复。查看者无权看见流程图时，流程图提案会使这一轮失败。

`apply_website` 最终文档跳过实体／流程图步骤。`TurnProcessor` 开启 `:website`，调用 `Websites::Assistant::Processor` 并返回 `website_result`。模块关闭为 `website.module_disabled`；其余按需开通，校验最多五页、每页十二分区。类型／props 使用 SectionKit／SectionFields，链接指向已有／同文档 slug，页面 slug 唯一。DocumentRepair 使用 `website_repair`，最多两轮。

GenerationWriteGuard 包含开通及文档写入。`PageShortcuts::Collisions.with_customer_lock` 提供文档保存点，按 ID 锁定租户／站点页面，在锁内重查 generation 及草稿资格。`Undo.snapshot` 深复制最新写前状态，再调用 `SavePage(..., structure_editable: true)`；任一失败整份回滚。新页未发布，写入时检查首页，修改保留首页身份。Finalizer 记录新增／修改，并固定首个含本地站点媒体的写入页，否则最后一页。ArtifactPaneComponent 使用既有内嵌预览／编辑路由，显示持久发布状态，模块关闭时隐藏网站产物。

Finalizer 在 `metadata["website_undo"]["pages"]` 保存新增／修改 Undo 条目及 SHA-256 指纹。已提交效果在取消、失败或被替代后仍保留于带来源回复。网站启用时，消息按钮提交到 `POST /:cid/admin/modules/ai_assistant/messages/:id/undo`；UndoWebsiteReply 通过 Conversation.owned_by 限定记录并要求模块启用。

撤销先锁会话，再进入共用客户边界，重载／锁消息并按 ID 读取页面；修改前检查当前来源、发布及指纹。同一事务删除新增页，经 SavePage 恢复标题／slug／导航／分区并标 undone_at。页面缺失／发布／变更、恢复／slug 冲突或删除存活页面所需首页均拒绝。RecordNotUnique／StatementTimeout 返回重试提示。控制器用 Turbo Stream 重绘，拒绝为行内 422。提交后消息／产物广播失败只记录日志，不回滚工作，PromptBuilder 在历史添加 UNDONE_NOTE。

`Prompt::Composer` 的实体大纲带有五个网站分区，模块关闭时都不输出。`WebsiteSectionKit` 是由 `SectionKit` 与 `SectionFields` 生成的分区表；`WebsiteContract` 是 `apply_website` 文档格式；`WebsiteAuthoring` 说明何时追问、如何写文案、如何放置图片；`WebsiteCatalog` 列出页面及其状态、固定页面的分区，以及其他草稿页的分区（上限 `WebsiteCatalog::DRAFT_BUDGET`，12,000 个字符）；`WebsiteImages` 是上传清单。

用户消息里的每张图片以 `upload:<ActiveStorage::Attachment id>` 标识（`Websites::Assistant::Uploads`）。`PromptBuilder` 在用户轮次末尾附上一行清单（标记、文件名、方向、尺寸），并按整轮回放最新几轮的图片，上限为 `PromptBuilder::MAX_REPLAYED_IMAGES`（16）张、`MAX_REPLAYED_BYTES`（20 MB）。每条消息最多 `Attachments::MAX_FILES`（8）张图片，单张不超过 `MAX_BYTES`（5 MB），合计不超过 `MAX_TOTAL_BYTES`（20 MB），因此最新一轮图片总能放进一次供应商请求；输入框在上传前按同样的限制检查。图片字段只接受本会话的标记、租户站点已在用的 URL，或留空；留空由 `Websites::Skeletons.decorate_sections` 填入图库照片。写入时，`Websites::Activities::ImportMedia` 把引用到的 blob 复制到租户网站媒体（同一 blob 只复制一次），标记换成 `/:customer_id/site/media/:signed_id`。聊天附件始终保持原样。副本由 `Websites::ImageFit.rendition` 在导入时一次生成：长边已达 1920 像素的照片与 GIF 逐字节复制；更小的 JPEG、PNG、WebP 经 `image_processing` 按比例放大，向 1920 像素靠拢，最多 4 倍，并轻微锐化。整个过程不缩小、不裁切、不拉伸。图片库无法读取的文件按原样复制。处理后端由 `config.active_storage.variant_processor` 决定：优先 libvips，主机未装 libvips 时用 ImageMagick（`config/initializers/active_storage_image_processor.rb`）；Active Storage 也靠同一设置记录图片宽高。站点按原字节发送副本。分区用 `Websites::FittedPhotoComponent` 渲染这些导入照片（`ImageFit.fitted?`）：以 `object-contain` 完整显示照片，背后用同一张照片的模糊副本铺满画幅，主体不会被裁掉。其他媒体仍用 `object-cover`。文档保存失败或保存时抛出异常，本次复制出的副本都会被清除。只有导入副本的 URL 仍出现在租户某个页面上时，上传才算已放置（`ImportMedia.placed_source_ids`）；管理员之后移除的照片会再次提示放置。文档漏放已上传的图片时，处理器先发一次修复提示；之后照常写入，并在回复中列出未放置的文件名。

`Tools::Session` 实现 `list_catalog`、`generate_page`、`verify_artifact` 及所有已注册的操作。`list_catalog` 以操作词汇返回租户的非桥接实体（`EntityDefinitions::Api::Mapper#from_entity`，含 `version`），并在 `processing` 下为每位管理员附上租户自己的表单处理（`FlowchartDefinitions::Catalog`）。装了 `GenerationWriteGuard` 时，`generate_page` 的写入经过它。`supports_native_tools?` 的供应商还会收到 `ListCatalog`、`GeneratePageTool`、`VerifyArtifactTool`，以及每个 `available?` 为真的操作对应的一个 `Tools::OperationTool`。它们都是 `RubyLLM::Tool`，`execute` 回到同一个 session；`OperationTool` 的名称取操作键，描述取 `summary`，参数取投影后的契约。不支持原生工具的供应商从提示词分区 `Prompt::Sections::OperationTools` 获得同样的操作：其中列出每份投影契约，以及由 `Loop` 执行的 `{"tool": "<name>", "arguments": {…}}` 约定。`Llm` 把原生工具调用限制在 `Llm::MAX_TOOL_CALLS`（8），超出则抛出 `Llm::ToolLimitExceeded`。

两条工具路径都进入 `Session#dispatch_operation`。它以通道 `assistant`、会话用户为执行者，带上会话与 generation、幂等键 `gen-<generation id>-<operation key>-<input digest>`，以及包裹 `GenerationWriteGuard` 的 `around_write`，运行 `Operations::Activities::Execute`。模型收到 `Outcome#to_tool_payload`，含 `next_step`；调用被拒绝时另带 `attempts_remaining`。`Prompt::Sections::OperationTools`（`documents/operation_tools.md`）要求模型：更新前先调用 `get_entity`，并把返回的 `version` 作为 `expected_version`；`create_entity` 只用于新名称；每轮把所有变更合并为一次 `update_entity` 调用。遇到 `fix_payload` 时发送完整的修正调用，不向管理员提及错误；遇到 `ask_user` 时返回 `clarify`，每项一个问题，违规项给出的候选作为选项；遇到 `refresh` 时重新调用 `get_entity` 再重建；遇到 `blocked` 时说明原因后停止。挂起更新的回复不再提其他问题，管理员对它回答「是」或「否」便不会有歧义。

`Tools::Session::MAX_ATTEMPTS`（3）限制自我纠错：每个操作每轮最多被拒三次。成功的调用不计入，`get_entity` 读取和挂起的 `update_entity` 都不占次数。被拒三次后，下一次调用直接返回 `attempts.exhausted`（`blocked`），不再执行。本轮第一个 `confirmation_required` 结果成为 `pending_proposal`：`{"kind": "operation", "operation", "invocation_id", "customer_id", "plan"}`。此后同一轮再调用任何 `confirmation: :always` 的操作，都直接返回 `proposal.already_pending`（`blocked`），不会取代已有提案。

`ReplyWriter` 把提案存进助手消息的 `metadata["pending_confirmation"]`。同一事务中，`PendingConfirmation.retire_open!` 把线程里更早的待确认提案移到 `superseded_proposal`，并用 `Operations::Activities::Confirm.supersede!` 把对应的挂起记录标为 `superseded`。面板展示方案及**应用更改**、**放弃**、**我要调整**三个按钮。`PendingConfirmation.consume` 先把回复归为单纯同意或单纯拒绝；带问号的回复不算，带附加要求的回复交给模型。随后在会话锁内确定目标：固定目标 `metadata["confirms_message_id"]`（仅用于同意，由 `SendMessage` 按 `proposal_message_id` 写入）须指向本会话中仍待确认的已完成助手消息；手动输入的回复以最近一条已完成助手消息为目标，且仅当该消息待确认、不带 `questions` 时才生效。固定目标已不再待确认，或手动输入的同意／拒绝紧跟在已定局的提案（`applied_proposal`、`declined_proposal` 或 `superseded_proposal`，例如重新生成确认轮次，或点击**放弃**后再回复「确认」）之后时，回复 `proposal_not_pending`，不调用供应商，也不写入。批准时锁定客户，核对调用记录仍处于 `awaiting_confirmation` 且属于本客户、本会话，再调用 `TurnProcessor#apply_operation_proposal`，以会话用户为批准人运行 `Confirm`。`succeeded` 列出更新的实体与桥接，并把提案移到 `applied_proposal`；`conflict` 回复该实体在提案后已发生变化，请管理员重新提出；其他状态使这一轮失败。批准未能应用、且 `Confirm` 已为调用记录定局（`conflict`、`invalid` 或 `failed`）时，`consume` 改把提案移到 `superseded_proposal`。拒绝时把提案移到 `declined_proposal`，用 `Confirm.decline!(invocation, actor:)` 把本客户、本会话中仍待确认的调用记录标为 `declined`，并回复 `plan.declined`。各路径都在释放锁后重新广播该提案消息，面板随即不再提供按钮。挂起的 `operation_invocations` 记录保存方案与快照，之后写入 `confirmed_by_id`、`confirmed_at`（记录定局者，无论批准还是放弃）及最终状态。

`AiAssistant::Activities::DiscardProposal` 承载**放弃**按钮。它只经 `AiAssistant::Conversation.owned_by(customer:, user:)` 找到消息（否则 404），在会话锁内运行 `PendingConfirmation.decline!`；没有待确认提案时返回 422 `proposal_not_pending`。它不消耗轮次、不调用供应商、不追加消息；控制器把该消息重绘为已放弃。生成进行中也可执行：会话锁使其与 `consume` 串行，且从不取消 generation。

两个提示词分区把这些告诉模型。`Prompt::Sections::Clarifying`（`documents/clarifying.md`，位于 `OperationTools` 之后）说明何时提问——无法确定名称或用途、组织特有的选项列表、两种差异很大的设计、访客依赖的事实——如何提问（一轮问完，每题给出建议的 `default`），以及何时列出 `assumptions`。`Prompt::Sections::PendingProposal`（`documents/pending_proposal.md`，位于 `EntityFocus` 之后）展示仍有效的挂起变更集：调整时重发一份完整的变更集；隔了几轮才用文字同意时，原样重新提交，再次呈现方案。`Prompt::Context#pending_operation_proposal` 仅在 `operation` 提案的调用记录与 id、客户、会话都匹配且处于 `awaiting_confirmation` 时返回 `{ "operation", "input" }`；输入超过 `PendingProposal::MAX_INPUT_CHARS`（8,000）时以一句说明代替。`PromptBuilder` 在回放的助手轮次后附加说明：问过的问题、列出的假设，以及提案状态（`PENDING_NOTE`、`APPLIED_NOTE`、`DECLINED_NOTE` 或 `SUPERSEDED_NOTE`）。

`AiAssistant::ClarifyingQuestionsComponent` 渲染问题卡片。`ai_assistant_questions_controller.js` 把回答拼成一条普通消息——每个问题后接回答，未答为「无偏好」——再由 `ai_assistant_controller.js#answerQuestions` 经常规发送路径提交。卡片只在最新一条消息上可作答（`AssistantPanelComponent#questions_active?`；单独渲染时检查之后是否已有消息），任一次成功发送后就地关闭。`MessageComponent` 在气泡下方列出 `assumptions`。`AiAssistant::ReplyJob` 与 `Cron::ReconcileGenerations` 在 `AiAssistant::Locale.for(user:, customer:)` 下运行——先取用户界面语言，再取租户默认语言，而非模块的 `language` 设置——因此广播气泡和服务端写入的句子使用管理员的语言；`Tools::Session#call` 把工具结果固定为 `I18n.default_locale`，模型读到的内容不随之变化。

`AiAssistant::Providers` 加载 `app/services/ai_assistant/providers`。`OpenaiWhisper` 调用 `register!` 和 `default!`。会流式输出并接受原生工具的生成供应商：`openai_whisper`（`Llm` 供应商 `:openai`）、`deepseek`（`:deepseek`）、`qwen`（`Llm` 供应商 `:openai`，基址为 DashScope）、`aws_bedrock`（`:bedrock`）。`cursor` 通过 Cloud Agents 生成，忽略 `on_chunk`，不做转写。`aws_transcribe` 和 `aliyun` 只做转写；`#chat` 留在基类的失败关闭结果上。`ProviderSettings` 每个供应商一行。`transcribe_active` 与 `generation_active` 是部分唯一索引：`activate_for!` 清掉其他行的同一标记。`active_for` 只在 `configured?` 为真时返回该行。

`Mentions` 用租户自己的实体名解析 `@`；流程图名只对 `FlowchartVisibility` 允许的查看者解析。`ListMentions` 用同一份名单给输入框菜单。`Prompt::Sections::EntityPlatform` 在查看者未被允许时去掉流程图能力那一条。`Prompt::Sections::FlowchartCatalog` 在未被允许时不输出。流程图提示词大纲只由流程图处理器使用，其他查看者不会被 `TurnProcessor` 带进那一步；子系统构建的 `AuthorProcessing` 也会使用（见下文）。

`AiAssistant::ReconcileGenerationsJob` 每 15 分钟运行一次，把停滞的代标为超时（`running` 超过 30 分钟，`queued` 超过 10 分钟）。

Cookie 会话的输入框是 `Admin::Modules::AiAssistant::MessagesController`。桌面客户端用 `Admin::Assistant::MessagesController`，它包含 `Oauth::BearerAuthenticatable`，并拒绝 Cookie 会话。参见 [authentication](authentication)。

### 资源自动上线

`EntityDefinitions::Persist` 保留实体枚举的 `active` 默认值；关联桥接显式设为有效状态。实体没有单独的上线标记。实体更新仍须经过操作批准流程。

`FlowchartDefinitions::Persist::Writer#create!` 将图配置赋给尚未保存的租户自有候选记录，先运行 `FlowchartInputOutputValidator`，再把深复制的配置交给独立内存记录上的 `FlowchartServerValidator`。服务端校验器会修改输入，因此其副本从不保存。缺失输入引脚及严重级别为 `error` 的服务端问题，将翻译后的消息放入 `Persist::Result#errors`；警告不阻止上线。只有有效候选才设为 `status: :launched`，并保存编译后的 Activity 与首个版本。上线校验失败不留下流程图或版本，而是进入处理器既有的有限修复流程（最多两次）。保存返回 false 时如实返回错误；回调未提供错误时使用 `apply_errors.flowchart_save_failed` 兜底。`Writer#update!` 保留原有状态及确认要求。

显式 `generate_page` 调用，以及 `Finalizer` 在实体创建成功／批准更新后自动生成表单，均调用 `AiAssistant::Assistant::GeneratePage`。封装在 `Page.transaction(requires_new: true)` 内运行 `Pages::Activities::CreateFromEntityVersion(shared: false)` 并调用 `Page#launch!`。新行沿用列默认值（仅管理员）。创建／重建、页面版本、受众与上线共用该保存点。失败结果回滚；`ActiveRecord::RecordInvalid` 或 `RecordNotSaved` 返回 `ok: false`、`skipped: :launch_failed`，通过 `apply_page_skipped` 给出已翻译的校验原因（无原因时使用 `apply_errors.page_launch_failed`），不返回页面或已创建名称。表单失败不会撤销操作已完成的实体写入。

遇到 `:page_exists` 时，封装仅复用客户与实体版本精确匹配的页面，不更改上线状态或受众。底层 Activity 的手动构建器行为不变。工具／最终处理器生成仍在既有 generation 写入守卫内，对话中的流程图轮次仍仅限所有者；子系统构建会为租户管理员编写表单处理（见下文）。所有写入均为客户自有资源；共享全局资源的上线／受众仍要求平台资源路径。提示词文档与 `GeneratePageTool` 描述表单自动策略；网站营销页面保留独立的草稿／发布契约。

回复会附上本轮生成的表单链接。`Finalizer` 汇总自身 `GeneratePage` 结果与本轮 `generate_page` 工具效果中的页面（仅限同一客户，按 id 去重），再剔除被其中其他页面实体通过 `associations` 关联为目标的实体表单——主实体表单已收集关联记录。例如：一轮同时生成 Student 与 Course，且 Student 关联 Course，则只链接 Student 表单；若本轮只有被关联实体的表单，则仍链接该表单。`documents/entity_authoring.md` 规定业务域中唯一的人员实体为主实体：`Prompt::Sections::EntityCapabilities` 列出人员基础模型（`Authentication::User`）时，它扩展该模型、在 `create_entity` 中排第一、承载本次调用的全部关联，且不重复声明该节列出的继承列。硬性部分由 `SemanticValidator` 强制（见[操作 API](operations-api)）。已上线且对 `:admin` 可见的页面写入 `metadata["page_links"]`（`[{ "id", "name" }]`）。`AiAssistant::MessageComponent#page_links` 在渲染时按 `customer_id` 重新读取：已删除、已下线或属于其他租户的表单不再显示，已重命名的表单显示当前名称。每个表单渲染为一张卡片，链接到 `admin_page_form_path`（`/:customer_id/admin/pages/:page_id/form`），带 `target="_blank"` 与 `rel="noopener noreferrer"`。文案位于 `ai_assistant.assistant.page_links.*`。

回复正文由 `AiAssistant::Assistant::Markdown.compose(prose, notes)` 与 `.paragraphs(*parts)` 组装：先是正文，随后以项目符号列表列出平台附注（`apply_created`、`apply_bridges`、`apply_flowchart_created`、`apply_page_created`、`apply_page_skipped`、`verify.failed` 等）；没有正文且仅一条附注时保持为普通句子。实体回复与流程图回复各成一段。`Markdown.render` 对每个空行分隔的块逐行处理：句子后接 `- ` 或 `1. ` 条目时渲染为段落加列表，`#`–`######` 标题行渲染为加粗段落。

### 子系统构建

模型在某一轮建好实体后，由构建在后台补全该业务域。模型调用 `start_subsystem_build`（见[操作 API](operations-api)），传入 `list_journey_options` 给出的流程键和管理员描述的表单处理。操作保存一条 `AiAssistant::SubsystemBuild`（`ai_assistant_subsystem_builds`：`customer_id`、`conversation_id`、`user_id`、`status`、`stage`，以及 JSON 列 `blueprint`、`questions`、`answers`、`results`），并入队 `AiAssistant::SubsystemBuildJob`。部分唯一索引保证每个对话至多一条 `running` 或 `waiting_for_answers` 的构建。`Prompt::Sections::SubsystemBuilds`（`documents/subsystem_builds.md`）和 `Prompt::Sections::PageProcessing` 向每位管理员说明这一能力。

对话当前的 generation 仍在进行时，`SubsystemBuildJob` 在 `GENERATION_WAIT`（5 秒）后重新入队自己。随后设置 `Current.customer` 和管理员的语言（`AiAssistant::Locale.for`），调用 `AiAssistant::Subsystems::Build`。`Build` 再次检查用户（已启用，且为平台所有者或该客户的管理员）、模块和生成供应商，然后从保存的 `stage` 起依次执行各阶段：

| 阶段 | 内容 |
| --- | --- |
| `journeys` | 在客户锁内为每个尚无流程的键调用 `Journeys::Activities::Generate`；已有流程则复用。 |
| `processing` | `Subsystems::AuthorProcessing` 经 `FlowchartDefinitions::Assistant::Processor` 为每项需求写一个流程图，使用独立的 `ProviderClient`（预算 `NEED_BUDGET`，4 次调用），以 `documents/subsystem_processing.md` 为指令。 |
| `binding` | `Pages::Activities::BindFlowchart` 把写好的流程图设到对应页面上：该流程中需求受众的 `page_steps[page_index]`，并核对需求的实体。 |
| `launch` | `Journeys::Activities::Launch`；页面仍在等待处理的流程，以及注册关闭时的 `public` 流程除外。 |
| `report` | `Subsystems::Report` 发出一条助手消息：流程已发布、原已上线、留作草稿或失败；表单处理已设置、待配置、未设置、未纳入或失败；以及预检提示。 |

每次写入都以构建仍在运行为条件（`update_all`，条件为 `status` 等于 `running`），每处理完一项即保存结果。因此已取消的构建会在下一项前停止，重跑时跳过已完成的部分。意外错误以 `build.unexpected` 使构建失败，已建成的内容保留。

**筛查。**`Subsystems::Screen` 以 `screen:` 传给 `Processor`，其错误与校验器错误一并进入修复循环。步骤不得填写密钥（`api_call.authToken` 或 `authPassword`、`send_chat_message.signingSecret`、`send_webhook.secretExpression`，或类似凭证的请求头）。步骤配置中的每个网址或邮箱字面量都必须逐字出现在管理员本人的某条消息中（`role: "user"`）；组件面板默认值不受此限。`AuthorProcessing` 在首次写入前检查地址，发现问题即提问而不修复。经修复移除的密钥会列为待配置，以组件面板标签命名。

**提问与回答。**需求缺少某个值时，模型以 `clarify` 回复并附 `questions`，或由构建提出 `build.value_question`。`Build` 汇总各项需求的问题，置为 `waiting_for_answers`，并发出带 `metadata["questions"]` 的 `build.questions_intro`，照常显示问题卡片。构建等待期间，`Activities::Reply` 中的 `Subsystems::Answer.consume` 把下一条消息当作回答，先于 `PendingConfirmation` 和任何供应商调用。它保存 `{message_id, questions}`，将构建置回运行，重新入队任务，并回复 `answers.received`。构建运行期间发来的消息得到 `answers.running`。运行中的构建闲置 30 分钟（`SubsystemBuild::MAX_RUNNING_AGE`）即判为停滞并失败，该消息按常规处理。每项需求的指令附带最近三轮回答。收到一轮回答后仍在提问的需求不予纳入，并在汇报中列出尚缺的信息。

**取消与显示。**构建消息带 `metadata["subsystem_build"] = {"id"}`，发起构建的那条回复也带（`Tools::Session#record_subsystem_build`、`Finalizer`）。`MessageComponent` 重新读取构建，显示状态徽标；构建进行中时还显示**取消构建**，提交到 `POST /:cid/admin/modules/ai_assistant/messages/:id/cancel_build`。`Activities::CancelSubsystemBuild` 只能经调用者本人对话中的消息找到构建（否则 404），构建结束后返回 422 `cancel.not_active`。构建每次发消息或被取消时，之前的构建消息都会重新广播。

**租户措辞。**构建和 `set_page_processing` 对租户管理员开放，因此相关文字只说“表单处理”，从不说“流程图”。编写失败时显示 `build.processing_unwritten`，而非流程图轮次的消息；绑定被拒时显示 `BindFlowchart` 的 `reasons`；指令要求模型在问题、`needs_setup` 和回复中都不用这个词。平台所有者看到的是详细消息。

## 需要特别注意

### 本地浏览器测试契约与就绪判定

`spec/e2e/` 的助手应用测试通过实际 SDK HTTP／SSE 传输访问仅监听回环地址的
测试供应商。`helpers/provider_backend.js` 通过严格核对数据库路径的 Rails
runner 导出已解析的 `create_entity`、`update_entity`、`get_entity` 契约（词表槽位
按平台客户解析）及流程图契约。`support/provider_server.rb` 以 RubyLLM 的 OpenAI
格式返回原生 `tool_calls`（流式与非流式均可），收到工具结果后再回复 `chat` 信封。
序列化前，它用 `JSONSchemer` 按导出的操作契约校验每组工具调用参数，测试供应商
因此发不出实际工具会拒绝的调用。无效测试回复返回 422，不放宽应用校验。
指令识别同时接受 `system` 与 RubyLLM 默认的 OpenAI `developer` 角色；流程图
后续轮次返回对应的有效 chat 文档。

浏览器交互等待当前挂载节点上的实际 Stimulus 控制器，覆盖 Turbo 重新挂载。
提及输入还等待实际服务端候选请求完成。测试不注入候选，也不调用应用动作方法；
写入使用各测试独立持有的会话与实体。现有服务器上的四 worker 复测命令见
`spec/e2e/README.md`。写入／录音测试还等待面板两个 Turbo 流来源的 `connected`
属性；该属性仅在 Action Cable 确认订阅后设置。

2026 年 10 月 12 日，这组助手／实体／提及／麦克风复测以四 worker 全部通过：
5/5，零重试、跳过或不稳定用例；Node／Ruby 供应商测试通过 4/4。复用
`storage/browser_audit_final.sqlite3`，应用端口 3001，供应商端口 3012。证据位于
`/tmp/opencode/assistant-audio-followup/`（`results-final.json`、`browser-final.log`、
`helpers-final-2.log`、`summary.md`）。

### 路由审计：生成预算、确认及已提交效果

会话创建／当前查找按用户串行，重查容量／空线程守卫。`SendMessage(..., idempotency_key:)` 在消耗限流前复用会话内轮次，转写使用稳定片段键。`ProviderClient` 为原生工具提供 `before_request`／`before_tool_call`。`Llm::CompletionBoundary` 仅在该 chat 实例统计真实 RubyLLM 请求，包含递归；请求／工具前重查取消／替代。厂商请求、原生工具、JSON 循环及单操作被拒次数上限分别生效。

实体批准应用的是挂起的 `OperationInvocation`，而非模型新写的文档，且只能在挂起它的会话中进行。**放弃**（`discard_proposal`）受同一管理端守卫保护，经 `Conversation.owned_by` 查找消息，从不消耗轮次。**应用更改**会消耗一轮，因此会话用完 40 轮后只剩**放弃**可用。`Operations::Activities::Confirm` 重新校验存储的输入，再在同一客户锁内核对每个实体 `current_line_head_version_id` 的快照并写入，并发编辑因此返回 `conflict`，不会被覆盖。`create_entity` 从不挂起，批准只能应用审阅过的更新。已提交网站效果的被替代回复保存 cancelled 来源／撤销消息，不改替代 generation 指针／产物。

操作输入可以省略属性标识：`EntityDefinitions::Api::Mapper` 由名称生成；显式的无效标识则以契约 pattern 或 `attribute.reserved_slug` 失败。实体和生成页面的配额测试先将额度接受到订阅快照，再修改目录；调高／调低均不改写已接受额度。尚未配置默认方案时，账单提供有限 Starter 回退：50 个页面、25 个实体、5 个成员。见[实体构建器](entity-builder)、[操作 API](operations-api)及[账单](billing)。

网站导入及公开服务执行实际字节光栅／租户／媒体策略。AI 草稿重查及写前状态取得与锁定文档写入共用边界，Undo 使用最新锁定来源及页面指纹。助手听写 HTTP／组件／Stimulus 已在录音前传入并固定所选自有会话，切换线程不转移缓冲片段。见[网站构建器](website-builder)、[语音转文字](speech-to-text)、[实体构建器](entity-builder)。

:::note
2026 年 10 月 11 日，AI／实体定义／语音转文字／LLM 定向测试、桌面／组件语音请求及网站写入／撤销测试在 `storage/ai_verify.sqlite3`、结构版本 `20261011190000` 上通过：1,666 个用例，零失败。包括先前全套报告中产生 37 个 AI／语音失败的全部八个文件，以及相邻回归测试。权限与确认快照使用实际持久化的测试数据，不以桩结果替代快照。供应商传输按需模拟。2026-10-12 后续并行 RSpec 通过 **25,266 个示例，0 个失败**。两次运行均不认证实际厂商或浏览器流程。定向测试的完整命令与证据见 `docs/audits/2026-10-11-ai-stt-targeted-verification.md`。
:::

:::attention
`AiAssistant::Activities::Reply` 和 `AiAssistant::Assistant::ProviderClient#chat` 跑在 `AiAssistant::ReplyJob` 上。`SendMessage` 和控制器不得构造 `RubyLLM::Chat`、`OpenAI::Client` 或供应商 HTTP 客户端。走 ruby_llm 的供应商，对话入口是 `Llm.complete`。
:::

:::attention
`FlowchartVisibility.allowed?` 是流程图提及、对话流程图轮次和流程图提案的门闩。`AiAssistant::Assistant::Mentions.kinds_for`、`Prompt::Context#flowchart_visible?`、`Prompt::Sections::EntityPlatform`、`Prompt::Sections::FlowchartCatalog` 和 `TurnProcessor#flowchart_visible?` 都调用它。只有 `Authentication::User#platform_owner?` 为真。租户管理员拿不到流程图目录文本、流程图提及候选，也不会进入对话中的 `FlowchartDefinitions::Assistant::Processor` 轮次。但他们可通过 `set_page_processing`、`list_catalog` 的 `processing` 和子系统构建使用表单处理，相关文字都不出现“flowchart”；构建会在后台替他们运行处理器。
:::

:::attention
`AiAssistant::ProviderSettings.active_for` 失败即关闭。打了 `generation_active` 或 `transcribe_active` 但 `configured?` 为假的行，视同没有供应商。`UpdateProviderSettings.validate_assignees` 拒绝未实现 `supports_generation?` 的生成指派，也拒绝把 `supports_transcribe?` 设为 false 的转写指派。每个标记最多一行持有。
:::

:::attention
`AiAssistant::Assistant::ProviderClient` 把这一轮的每次供应商补全都计入 `AiAssistant::Limits::MAX_VENDOR_CALLS`。`Llm` 另外把原生工具调用停在 `MAX_TOOL_CALLS`。`Loop::MAX_STEPS` 是 JSON 工具往返的上限。`Tools::Session::MAX_ATTEMPTS` 限制每轮每个操作的被拒次数，超出后以 `attempts.exhausted` 回应下一次调用。用尽供应商调用预算时结果为 `outcome: :budget_exceeded`，回复正文是预算文案，不是通用故障文案。
:::

:::attention
模型永远无法批准或放弃提案。只有**应用更改**（固定到所属消息）、**放弃**，或直接回应该提案的单纯「是／否」才可以；之后有过任何助手回复再说「确认」，会交给模型处理，因而不会应用几轮之前提出的方案。附带新要求的回复同样交回模型。线程最多只有一个待确认提案：挂起新提案会取代旧的调用记录，`Confirm` 定局却未应用的批准也会让其提案退役。
:::

:::attention
`AiAssistant::Stream` 的名称带有 `customer_id` 和 `user_id`。会话查找走 `AiAssistant::Conversation.resolve` / `owned_by`，会拒绝别人的 id。`ExecutionPolicy` 拒绝消息、会话、客户对不上的代，也拒绝成员角色。
:::

:::attention
助手从不发布网站营销页面。`Websites::Assistant::Processor` 给新页面写入 `published: false`；`page_id` 指向已发布页面、其他站点的页面或不存在的页面时一律拒绝；不改 `Website` 设置、主题，也不动现有首页。`Websites::Assistant::Uploads` 只在本会话、本客户的用户消息中解析标记；`ImportMedia` 拒绝带有其他 `customer_id` 的 blob。模型自行编造的图片 URL 按校验错误处理。
:::

## 关键代码

```ruby
# app/services/ai_assistant/assistant/loop.rb
def call
  current = parse(@text)
  return success(@text) unless tool?(current)

  messages = nil
  MAX_STEPS.times do
    messages ||= PromptBuilder.call(conversation: @conversation, mode: :entity)
    result = @tool_session.call(current["tool"], current["arguments"])
    messages += [
      { role: "assistant", content: current.to_json },
      { role: "user", content: { "tool_result" => result }.to_json }
    ]
    reply = @chat.call(messages)
    return Result.new(outcome: :provider_failure) unless reply.is_a?(Hash) &&
                                                          reply[:outcome] == :success

    text = reply[:text].to_s
    current = parse(text) || { "intent" => "chat", "reply" => text }
    return success(current.to_json) unless tool?(current)
  end
  Result.new(outcome: :max_steps)
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def run_website(text)
  @progress.start(:website)
  website_result = Websites::Assistant::Processor.call(
    text: text, customer: @customer, conversation: @conversation, chat: @chat, write_guard: @write_guard
  )
  result(website_result.body, website_result.status, entity_result: nil, website_result: website_result)
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def flowchart_follow_on?(entity_result)
  return false unless flowchart_visible?

  entity_result.status == "complete" &&
    entity_result.proposal.blank? &&
    (entity_result.applied || entity_result.intent == ReplyEnvelope::Intent::CHAT)
end
```

```ruby
# app/services/ai_assistant/assistant/tools/session.rb
if @failures[key] >= MAX_ATTEMPTS
  return tool_payload(
    Operations::Outcome.invalid(
      operation: key,
      violations: [
        Operations::Violation.new(code: "attempts.exhausted", resolution: "blocked")
      ]
    ),
    attempts_remaining: 0
  )
end

outcome = execute_operation(key, args)
record_operation(outcome)
return tool_payload(outcome) if outcome.ok?

@failures[key] += 1
tool_payload(outcome, attempts_remaining: MAX_ATTEMPTS - @failures[key])
```

```ruby
# app/services/ai_assistant/assistant/pending_confirmation.rb
def typed_target(conversation, user_message)
  message = locked_complete_assistant_messages(conversation, user_message).order(id: :desc).first
  return if message.nil?
  return if pending_proposal?(message) && questions?(message)
  return message if pending_proposal?(message)
  return :not_pending if settled_proposal?(message)

  nil
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def flowchart_visible?
  FlowchartVisibility.allowed?(@conversation.user)
end
```

```ruby
# app/services/llm.rb
def run_chat
  ctx = RubyLLM.context { |config| apply_provider_config(config) }
  chat = ctx.chat(model: @model, provider: ruby_llm_provider, assume_model_exists: true)
  seed(chat)
  apply_options(chat)
  chat.instance_variable_set(:@anysys_before_request, method(:reserve_request!))
  chat.singleton_class.prepend(CompletionBoundary)
  cap_tool_calls(chat)
  return chat.complete unless @on_chunk

  chat.complete { |chunk| emit(chunk) }
end
```

```ruby
# app/models/ai_assistant/provider_settings.rb
def self.active_for(job)
  column = job_column(job)
  row = where(column => true).first
  row if row&.configured?
end
```
