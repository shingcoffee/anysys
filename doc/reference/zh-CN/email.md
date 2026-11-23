---
title: "邮件"
summary: "平台级邮件凭证与租户模板；SMTP 使用类型化列，每个 API 厂商单独一个文件。"
---

## 概要

`FeatureModules::Email::Registration`（模块键 `email`）发送事务邮件和活动邮件。投递厂商是 `app/services/email/providers/` 下的 `Email::Providers` 子类：`smtp.rb`、`ses.rb`、`aliyun.rb`。新增 API 厂商就是这一个文件，并调用 `register!`。凭证留在 `Emails::Credential`。SMTP 是历史上的例外，仍使用类型化列（`host`、`port`、`username`、认证、TLS、域、DKIM）。SES 与阿里云把厂商字段放在 JSON `config` 里。加密列 `password` 存放 SMTP 密码或 API 密钥。

凭证是平台级的，每个厂商每个 mode 一行。租户不能按每次发送挑选厂商。`Email::CredentialResolver` 在调用过 `default!` 的厂商（SMTP）那一行处于 active 时优先用它，否则用该 mode 下第一条 active 凭证。

## 配置邮件投递

在 `/81721200/admin/maintenance/platform/module_settings/email/credentials` 保存目标供应商和模式的凭证，再为该模式**指派投递供应商**；每个模式只能启用一个已配齐的供应商。Rails 生产环境使用 `production`，其余使用 `sandbox`；应用模式不会代建厂商测试账户。为租户启用邮件模块也不会生成平台凭证。编辑时留空密钥字段会保留旧值。从租户邮件模板发送测试邮件，并核对厂商回执；入队或 `sent` 不等于已投递。

### SMTP（`smtp`）

1. 准备 SMTP 服务器或中继；`username` **必须是要用作发件人的、已获中继授权的邮箱地址**，应用直接以此作为邮件 From。填写 `host`、`port`、`username`、**密码**、HELO `domain`、`authentication`（`plain`、`login` 或 `cram_md5`），并按服务器要求启用 STARTTLS／SSL。即使中继允许匿名发送，本应用仍要求用户名和密码。按中继的 [SMTP 认证](https://www.postfix.org/SASL_README.html)与 [TLS](https://www.postfix.org/TLS_README.html)说明配置。
2. 如启用 DKIM，填写域名、选择器和私钥，并依 [RFC 6376](https://www.rfc-editor.org/rfc/rfc6376#section-3.6.2) 在 `<selector>._domainkey.<domain>` 发布表单显示的 TXT 公钥。核对 DNS 后发送测试模板。SMTP 没有投递回执 webhook，消息状态停在 `sent`。

### Amazon SES（`ses`）

1. 在所选 SES `region` [验证发件域名或地址](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html)，创建有 SES 发送权限的 IAM AccessKey。如 **AWS SES** 账户仍处于自身的发送沙箱，应[申请正式环境权限](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html)；Anysys 的 `sandbox` 标记不会改变 AWS 限制。填写 `access_key_id`、加密的**密码**字段（存放 Secret Access Key）、`region` 与已验证的 `from_email`。
2. 在同一 SES 地域建立 **Standard** SNS 主题，授权 SES `sns:Publish`，然后到 SES 身份的 **Notifications → Feedback notifications**，将**投递、退信、投诉**都指向该主题。将公开 HTTPS 地址 `https://<host>/email/webhooks/ses` 订阅到 SNS，**关闭原始消息投递**，并在 Anysys 填写 `sns_topic_arn`。SNS 会发送带 `Type`、`TopicArn`、`Signature` 和内嵌 `Message` 的签名 POST 信封；应用校验该信封并自动确认有效订阅。**不要**直接将 SES EventBridge 事件或原始 SNS 消息投递到此端点。参见 [SES 回执配置](https://docs.aws.amazon.com/ses/latest/dg/configure-sns-notifications.html)与 [SNS HTTP(S) 订阅](https://docs.aws.amazon.com/sns/latest/dg/sns-http-https-endpoint-as-subscriber.html)。
3. 从租户模板发送到实际邮箱；也可用 SES [邮箱模拟器](https://docs.aws.amazon.com/ses/latest/dg/send-an-email-from-console.html)测试成功、退信和投诉。表单未直观标注 `sns_topic_arn` 为必填，但供应商**就绪检查要求此项**。

### 阿里云邮件推送（`aliyun`）

1. 在选定地域开通[邮件推送](https://help.aliyun.com/zh/direct-mail/user-guide/overview)，为发信域名[配置并验证 DNS](https://help.aliyun.com/zh/direct-mail/user-guide/how-to-configure-sending-domain-names)，[创建与 `from_email` 一致的发信地址](https://help.aliyun.com/zh/direct-mail/user-guide/setup-sender-addresses)。取得可调用 [`SingleSendMail`](https://help.aliyun.com/zh/direct-mail/api-dm-2015-11-23-singlesendmail) 的 AccessKey。填写 `access_key_id`、加密的**密码**字段（存放 AccessKey Secret）、`region`、`from_email` 及可选的 `from_alias`；这里**不用**发信地址的 SMTP 密码。
2. 在 Anysys 设置 `webhook_secret`。按阿里云[邮件推送 EventBridge 事件分发](https://help.aliyun.com/zh/direct-mail/user-guide/set-up-eventbridge)说明启用事件分发，在发送地域筛选 `acs.dm` 的**投递成功与失败**事件。通过 HTTP 目标或中转服务把事件转发至 `POST https://<host>/email/webhooks/aliyun`，并附带 `Authorization: Basic <base64(aliyun:<webhook_secret>)>`，或使用 URL 编码后的 `?token=<webhook_secret>`。普通 EventBridge POST 会收到 403；仅在 Anysys 保存密钥不会认证回调。转发正文须保留 `data.env_id`、`data.rcpt` 和 `data.status`。旧版 MNS 通知也须经过带认证的转发路径。
3. 核对真实回调：`0` 已投递，`2`／`3` 抑制无效／垃圾邮件收件人，`4` 为不抑制的失败。其他反馈格式不作为投诉事件。当前 `SingleSendMail` 传输在预留额度／入队前及实际派发时，均以 `UNSUPPORTED_FEATURE` 拒绝 CC、BCC、自定义 Reply-To、CID／内联附件及活动一键退订邮件。该传输尚未实现活动一键退订头，活动应使用支持该能力的供应商。发送就绪不代表回执认证可用。

## 流程

```text
Emails::Activities::Send
        |  Email::Contracts::Send
        |  TemplateRenderer
        |  Email::CredentialResolver
        |  Emails::Suppression.suppressed? -> 状态 suppressed
        |  customer.with_lock + 每日上限
        v
Emails::Message 状态 queued
        |
        v
Emails::DeliverMessageJob
        |  Email::Providers.for(provider)#deliver
        |  SMTP -> Emails::DeliveryMailer.deliver_now，状态停在 sent
        |  SES / 阿里云 -> API，再等 webhook
        v
POST /email/webhooks/:provider
        |
        v
Emails::WebhooksController
        |  验证保留凭证，parse_events -> ReceiptInbox
        v
mark_delivered! / mark_bounced! / mark_complained!
        |
        v
事件要求 suppress 时 Emails::Suppression.record_global!
```

打开与点击是 `/email/track/:message_id/...` 上的 `Emails::TrackingController`。退订是 `/unsubscribe/:token` 上的 `Emails::UnsubscribesController`。这些路由是公开的。

## 实现

### 厂商

`Email::Providers::Base` 声明 `key`、`default_display_name`、`config_fields`、`configured?(credential)` 和 `delivery_mechanism`。`:none` 表示状态停在 `sent`（SMTP）。`:webhook` 表示厂商推送投递、退信和投诉。`uses_webhook_secret?` 对 webhook 厂商默认为 true。SES 返回 false，用 SNS 证书校验，不用 `webhook_secret`。实例方法 `deliver(message:)` 返回 `{ provider_message_id:, raw: }`，失败时抛出 `Email::Errors::ApiError` 或 `TransportError`。Webhook 厂商实现 `verify_webhook!(request)` 和 `parse_events(request)`，事件类型为 `:delivered`、`:bounced`、`:complained`。

`Email::Activities::SaveCredential` 按 `TYPED` 写入 SMTP 类型化列，其余字段进入 `config`。`password`、`dkim_private_key`、`webhook_secret` 留空时保留原密钥。`Email::Activities::AssignDelivery` 每个 mode 只激活一条凭证，并停用其余行。active 行必须通过 `configured?`。

`Emails::Credential` 仅在 `smtp?` 时校验 SMTP 字段，启用 DKIM 时相关字段必填。`Email::DkimSigner` 明确签署两个 List-Unsubscribe 头。`from_address` 对 SMTP 使用 username，对 API 使用 `config_value(:from_email)`，残留 SMTP 用户名不会覆盖 API 发件地址。

### 发送、模板、上限

`Emails::Activities::Send.call` 用 `Email::Contracts::Send` 校验，渲染 `Emails::Template`，解析凭证。`Emails::Suppression.suppressed?` 命中该租户和地址时，只记一条 suppressed 消息。每日上限在 `customer.with_lock` 内检查。上限来自 `FeatureModules::DailyCap` 读取客户分配上的 `daily_send_cap`，默认是 `Emails::Activities::Send::DEFAULT_DAILY_CAP`（1000）。平台所有者在该客户的 `/:cid/admin/maintenance/modules` 页面于邮件模块下设置非负的每日上限；客户在 `/:cid/admin/settings/modules/emails/daily_cap`（或 `/emails`）只能查看。新行状态为 `queued`，交给 `Emails::DeliverMessageJob`。幂等键重复时返回已有消息。

`Emails::DeliverMessageJob` 有条件领取到期 queued 邮件，租约 30 分钟，最多三次尝试；投递前重查模块、抑制及活动取消。确定 API 拒绝直接失败，传输失败释放后重试／恢复。领取防止常规重叠派发，但厂商接受后超时或租约过期仍不能保证恰好一次。

`Emails::Template` 按租户隔离并有版本（`Emails::TemplateVersion`、`Emails::TemplateContent`）。状态为 `draft`、`active`、`retired`。新建模板表单初始化为 `status: "active"`，因此“立即启用此模板”默认勾选；取消勾选则提交 `draft`。新建失败后重新显示提交时的状态。活动发送是 `Emails::SendActivities::SendActivity`，受众是 `Emails::Audience::List`。后续任务是 `Email::Cron::ReconcileMessages` 和 `Emails::SendActivities::Cron::ReconcileSendActivities`。

在 `/:cid/admin/settings/modules/emails/template_tokens`，**内置字段**列表和模板编辑器的字段选择器都通过 `Emails::TemplateToken#display_label`，按平台变量的 `source_key` 显示本地化名称，包括标签仍为 `Dispute.provider` 等旧格式的记录。未识别的内置字段会根据存储的标签显示易读的名称，不再一律显示相同的通用标题。内置字段列表默认收起，展开后显示只读变量及其取值来源：收件人账户或所属组织信息、生成的退订链接，或发送流程显式提供的数据。使用 `Emails::VariableContext.for(user:)` 的发送流程会提供收件人账户属性、客户属性和退订链接；其他平台字段须由 `vars` 提供，缺少可用值时留空。**自定义字段**按实体 ID 分组。各组默认收起，标题显示实体名称和字段数量；展开后显示变量名称、对应的实体字段，以及编辑／删除操作。实体已删除时显示本地化的“实体不可用”提示。没有自定义字段时仍直接显示空状态。

在 `/:cid/admin/settings/modules/emails/template_tokens/new`，**实体**选择器列出本租户或平台共享的已启用 Entity 定义。选择后列出尚未添加的结构字段，默认全部勾选，并以字段名称预填可编辑的显示名称。管理员可全选或清空选择，再一次提交至少一个字段。`Emails::TemplateTokens::Operation::BulkCreate` 校验实体权限、字段归属、重复选择和已存在的变量后，在事务中批量创建；提交无效时保留所选实体、勾选状态和名称。在 `/:cid/admin/settings/modules/emails/template_tokens/:id/edit`，表单按“实体→字段映射”的顺序展示单个字段及其显示名称。初次打开时保留自定义名称；切换实体时默认选择其首个可用字段并推荐字段名称，切换字段时也会推荐相应名称。下拉列表排除已被其他变量使用的字段，直接提交重复映射也会被拒绝。自定义实体字段可插入模板，但收件人与 EntityEntry 的关联尚未接入，发送时字段值会留空；两个表单均对此予以明确提示。

`FeatureModules::Email::Provisioner.call` 与 `.revoke` 均为空。启用不创建凭证，停用不删除模板。永久删除客户由归属感知的 `Customers::Purge` 处理，不能声称全部邮件表均由外键级联删除。见[客户](customers)。

交接合同是 `to`、`template_id`、`vars`，以及可选的 `cc`、`bcc`、`reply_to`、`idempotency_key`。输出是 `message_id` 和 `status`（`queued`、`sent` 或 `failed`）。见 [flowchart-runtime](flowchart-runtime)。

### 流程图步骤：send_template_email

`send_template_email` 步骤动作从流程图发送租户邮件模板。`templateId`（必填）引用 `email_templates` 来源（本客户已启用的模板），`to`（必填）是 ctx 路径，`vars` 把字面量键映射到字面量值，`cc`、`bcc`、`replyTo`、`idempotencyKey` 为可选表达式。步骤在 `Step.attempt("send_template_email.failed", Email::Errors::Error)` 内调用 `Emails::Gateway.send(customer: Customer.find_by(id: ctx[:customer_id]), …)`，并把消息 id 写入 `resultVar`（默认 `email_message_id`）。客户始终取自运行上下文，从不取自步骤输入。见 [流程图步骤动作](flowchart-step-actions)。

### Webhook

`POST /email/webhooks/:provider` 仅接受已注册 webhook 供应商。控制器验证全部保留凭证，包括已停用行。多个凭证共用密钥／主题时，`WebhookCredentialBinding` 按记录中的供应商／厂商消息 ID、凭证 ID／模式及收件信封逐项解析；SES 已认证的发件账户必须与配置的主题账户一致。全部事件解析完成后才写入回执／抑制名单。唯一验证身份传给 `Emails::ReceiptInbox.record!`；身份唯一但消息尚未关联时，回执持久保留，等待发送后／cron 重投。歧义事件返回 HTTP 409，不任意分配模式，也不采用请求中的模式提示。凭证身份唯一后，抑制可先于消息关联生效。不会猜测回填无 metadata 历史行或恢复已覆盖密钥。

### 四个面

| 面 | 路径 | 控制器 |
| --- | --- | --- |
| 条目 | `/:cid/admin/modules/emails/templates`、`/send_activities`、`/lists`、`/dashboard`，以及健康、报表、送达、互动、抑制名单 | `Admin::Modules::Emails::TemplatesController`、`TemplateVersionsController`、`SendActivitiesController`、`SendActivityDeliveriesController`、`SendActivityCancellationsController`、`ListsController`、`DashboardController`、`HealthController`、`ReportsController`、`DeliverabilityController`、`EngagementController`、`SuppressionsController`、`AttachmentsController` |
| 客户设置 | `/:cid/admin/settings/modules/emails`（含 `/daily_cap`）与 `/template_tokens` | `Admin::ModuleConfigsController` 只读展示 `daily_send_cap`；`Admin::Settings::Modules::Emails::TemplateTokensController` |
| 启用／停用及客户上限 | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`、`ModuleEnablementsController`；仅平台所有者可通过 `ModuleOwnerConfigurationsController` 写入 `daily_send_cap` |
| 平台设置 | `/:cid/admin/maintenance/platform/module_settings/email/credentials` | `Admin::Maintenance::Platform::Emails::CredentialsController`；共用窗格在 `ModuleSettingsController` |

模块键是 `email`。URL 段是 `emails`。

## 需要特别注意

### 路由审计：接收、发件箱、活动及内容不变量

`Emails::Quota.reserve` 是原始、事务及活动邮件共用的租户串行预留。幂等重放优先于可变校验／上限／供应商检查；空键归一为 nil，重复持久化竞争返回同一台账。每日用量跨消息类型排除 suppressed／failed；活动还检查滚动分钟额度，默认 60。单封定时邮件按接收日预留，不按实际投递日。

幂等查询绕过 Active Record 查询缓存，唯一索引竞争失败、回滚保存点后的查询亦如此。获胜记录必须在该保存点之外，且客户与幂等键完全一致。校验恢复仅接受 `idempotency_key` 的 `:taken` 错误，其他校验／索引失败继续抛出。投递到期时间采用数据库的微秒精度，队列调度比较以已保存的 UTC 时刻为准。

`Emails::MessageAdmission.validate!(credential:, attributes:)` 在配额／入队接收前检查未保存信封。活动 Build／start 使用 `validate_campaign!(template:, credential: nil)`，模板测试发送提供可控 UnsupportedMessage 提示。`Email::Providers::Base#supports_message?`／`#validate_message!` 与派发共用受保护的 `unsupported_features(message:)`。阿里云以 `UNSUPPORTED_FEATURE` 拒绝活动一键退订、CC／BCC／Reply-To 及内联 MIME，适配器仅实现 To 加 HTML／文本。厂商 API 的 Headers／BccAddress／ReplyAddress 尚未接入，因此拒绝活动接收，不承诺一键退订头。

queued 消息保存到期／入队／领取／尝试标记。`DeliveryHandoff` 加速入队，`Emails::Cron::RecoverMessages` 修复到期发件箱并重投回执，不提前使未来邮件失败。活动运行有独占租约、受限批次、持久化延后／进度、台账恢复／统计及可重试暂时分发错误。Build 校验启用的同租户模板及最多十个名单，原子保存父记录／关联。新鲜编辑／删除守卫协调调度领取，删除失败如实反馈。非终态发送活动仍引用模板时，不能修改主题、正文和编辑器类型；改名仍可保存。仅改名单元数据的 PATCH 保留省略类型／规则。

模板头提升原子应用标量及 Action Text 内容，每个版本写入检查模块启用。变量更新无效时，将提交的名称／实体／字段值与持久化变量分开保留；无效选项经转义显示，并以 HTTP 422 展示模型错误，不同步被拒绝的输入。实体权限及数组／哈希批量形状仍须校验；UUID 默认值可往返，重名标签按来源限定，不选择歧义项。主题／纯文本使用文本归一，HTML 使用 HTML 归一；自定义实体变量的收件人关联仍未实现。

选中的快照是一份完整定义，不与当前列做局部合并：缺失或为 null 的 `subject`、`body_html` 归一为空字符串，可选 `body_text` 保持 null，缺失或为 null 的编辑器类型使用结构默认值 `code`。应用图片快照时，Action Text 附件身份／元数据、embeds 关联及编译后的 CID HTML 一并恢复。作者 HTML 原样保留，不通过旧布局解包兼容逻辑裁剪。浏览器预览仅替换模板所属客户的 CID 图片；未归属或外租户文件保留 CID，不生成签名浏览器 URL。变量副标题采用目录当前的本地化编辑标签。紧凑表格行操作与仪表盘的可访问菜单分别限定范围。

生命周期迁移 `20261011173041` 会拒绝既有 queued 邮件：升级前须先解析或隔离其未决调度状态。旧主库台账无法区分立即投递与延后投递，生产 Solid Queue 又位于独立数据库。迁移不增加历史队列导入或旧信封运行时回退。签名退订载荷必须包含固定用户、邮箱及客户；不完整／无效载荷直接拒绝，不借用当前资料的地址或租户。

SMTP／SES 正文及退订头使用消息固定租户／地址。SES 内联附件使用 Mail 原始 MIME，保留信封 CC／BCC／Reply-To，在 SDK 验签前检查 SNS 信封／证书地址形状，按受影响收件人生成回执。公开令牌退订跳过会话 MFA。分析及活动 `RefreshStats.sent_count` 仅计入 `sent`／`delivered`／`bounced`／`complained`；pending、queued、failed、suppressed 分别统计。活动统计另提供 `materialized_count`、`pending_count`、`queued_count`、`failed_count`、`suppressed_count`。设备标题使用独立翻译键。邮件／回调 URL 共用 `APP_HOST`、`APP_PROTOCOL` 及可选 `APP_PORT`（开发默认 localhost／http／3000，生产要求主机且默认 HTTPS）。

邮件及短信凭证 CRUD 分别复用所属模块的事务性投递分配流程，停用同模式其他行。须保留未完成工作的历史凭证，记录 ID 不能恢复已覆盖密钥。见[短信](sms)、[后台任务](background-jobs)、[身份认证](authentication)。

:::note
供应商、接收／回执、活动、配额及变量／版本 API 已按源码记载。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。真实厂商、队列与浏览器结果仍在该套件之外。
:::

:::attention
`Emails::Audience::SegmentQuery.valid?(rules)` 在任一字段／运算符／值／组／连接无效时拒绝整棵树；历史畸形树不匹配用户，写入／预览拒绝无效输入。深度／节点／值限制为 12／500／4 KB，数值／日期／布尔类型严格，LIKE 通配符按字面处理。仅有意留空的根选择全部租户用户，全无效树不会扩大名单。阿里云在预留／入队前拒绝不支持功能，派发时再次检查。
:::

:::attention
新的 API 厂商是 `app/services/email/providers/` 下一个继承 `Email::Providers::Base` 并调用 `register!` 的文件。厂商字段放进 `config_fields`，从而写入 `Emails::Credential#config`。`Email::Providers::Smtp` 是例外：`config_fields` 为空，`Email::Activities::SaveCredential::TYPED` 写入 `host`、`port`、`username`、认证、TLS、域和 DKIM 列。不要为 SES 或阿里云加列。
:::

:::attention
`Emails::Credential` 没有 `customer_id`。`Email::CredentialResolver` 和 `Email::Activities::AssignDelivery` 把凭证当成全平台每个 mode 一个 active 厂商。`AssignDelivery` 会停用该 mode 下的其他行。租户侧唯一的发送设置是每日上限：`FeatureModules::DailyCap` 读取它，仅 `Admin::Maintenance::ModuleOwnerConfigurationsController` 能写入；`Admin::ModuleConfigsController` 排除该字段的更新。`FeatureModules::Email::Provisioner` 不创建凭证。
:::

:::attention
SMTP 没有 webhook。回执验证使用保留凭证身份，空厂商 ID 不会关联到 NULL-ID 消息。确认已认证但未关联的事件表示已持久接收，不表示消息投影完成。
:::

:::attention
`Emails::DeliverMessageJob` 会重试传输失败，因此可能投递两次。类注释写明 SMTP 和 API 调用都没有客户端幂等键，厂商已接受后若超时，重试会再发。`Emails::Activities::Send` 仍会在入队前用自己的 `idempotency_key` 去重。
:::

## 关键代码

```ruby
# app/services/email/providers/smtp.rb
def key                  = "smtp"
def default_display_name = "SMTP"
def delivery_mechanism   = :none

def config_fields = []

def configured?(credential)
  credential.host.present? && credential.username.present? && credential.password.present?
end
```

```ruby
# app/services/email/providers.rb
module Providers
  extend PluginRegistry.build(label: "email provider", dir: "app/services/email/providers")
end
```

```ruby
# app/models/emails/credential.rb
# SMTP (the standard protocol) keeps its typed columns (host/port/username/auth/ssl/starttls/
# domain/dkim_*); API vendors (SES, Aliyun, …) store their config in the JSON
# `config` blob.
```

```ruby
# app/services/emails/receipt_inbox.rb — after provider verification
Emails::ReceiptInbox.record!(credential: verified_credential, event: {
  type: :delivered, provider_message_id: vendor_id, email: recipient,
  suppress: false, raw: normalized_data
})
```

```ruby
# config/routes.rb
post "/email/webhooks/:provider",
     to: "emails/webhooks#create",
     as: :email_webhook,
     constraints: ->(req) {
        provider = req.path_info.match(%r{\A/email/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
       Email::Providers.keys.map(&:to_s).include?(provider)
     }
```
