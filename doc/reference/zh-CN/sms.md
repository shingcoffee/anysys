---
title: "短信"
summary: "定向营销活动与事务短信，以及已授权联系人、平台模板、节流发件箱派发和回执对账。"
---

## 概要

`FeatureModules::Sms::Registration`（模块键 `sms`）支持定向营销活动与事务短信。厂商是 `app/services/sms/adapters/` 下的 `Sms::Adapters` 子类：`aliyun.rb`（`delivery_mechanism` 为 `:poll`，并调用了 `default!`）和 `twilio.rb`（`:webhook`）。新厂商就是这一个文件，并调用 `register!`。共用密钥是 `Sms::Credential` 上的 `access_key_id` 和加密的 `access_key_secret`。厂商自己的非密钥配置（签名、地域、发送号、消息服务编号）在 JSON `config` 里。不为单个厂商写迁移。

`Sms::Template` 是平台级的。`provider_template_codes` 把每个适配器键映射到该厂商的模板编号；`purpose` 区分事务／营销用途，可选 `body_template` 保存审核内容的预览副本。租户数据包括联系人、仅追加授权证据、动态分群、活动、收件人台账与消息，以及该租户被允许看见的退订名单。消息台账同时充当事务性发件箱：接收时记录 `queued`，提交后由后台任务调用厂商。`sent` 表示 API 已接受，不表示运营商已送达。

完整的**受众 → 内容 → 发送时间 → 确认**流程、Twilio／Braze／Klaviyo／Mailchimp 官方参考及实现 API 见[短信受众与活动](sms-campaigns)。手动添加／实体同步不授予同意；保存与预览不发送，须单独确认并启动。

## 配置短信供应商

在 `/81721200/admin/maintenance/platform/module_settings/sms/credentials` 保存运行模式的凭证（Rails 生产环境用 `production`，其余用 `sandbox`），再为该模式**指派一个已配置的投递供应商**。应用的 Sandbox 模式不会自动采用厂商测试凭证。在 `/81721200/admin/maintenance/platform/module_settings/sms/templates` 创建**启用**的模板，填写选定供应商的模板编号与变量。为租户启用短信模块后，才能从其管理端发送。

启用发送任务前，须落实收件人对该用途的许可、获批发送方／模板、允许的目标地区及可用的退订通道。短信营销授权通过 `Sms::Contact` 的仅追加同意／撤回证据单独记录，新建或更换号码后为未知。记录同意不解除抑制，同步不导入授权。事务发送保留核心接收规则；号码未被阻止或符合号码规划，不代表允许发送。

### 阿里云短信（`aliyun`）

1. [开通短信服务](https://help.aliyun.com/zh/sms/getting-started/get-started-with-sms)，创建有短信 API 权限的 RAM AccessKey。发送中国境内短信时，按要求完成企业资质、实名登记，并申请通过审核的**签名**和**短信模板**。参见阿里云 [API 接入说明](https://help.aliyun.com/zh/sms/getting-started/use-sms-api)。
2. 填写 `access_key_id`、加密的 `access_key_secret`、已审核 `sign_name` 及 `region`（默认 `cn-hangzhou`），映射批准的 `SMS_...` 模板及变量。`QuerySendDetails` 现读取实际 `SmsSendDetailDTOs.SmsSendDetailDTO` 应答，畸形形状按 unknown 处理。无需登记阿里云短信 webhook。
3. 通过 `POST /:cid/admin/modules/sms/sends` 测试发送，检查消息记录和厂商控制台的投递记录。此适配器在 Anysys 中显示 `sent`／`unknown` **不等于**已确认投递；仅保存签名和模板也不能证明厂商已审核通过。

`QuerySendDetails.SendDate` 优先使用 `dispatch_started_at`，历史行回退至 `sent_at`，再回退至 `created_at`；先转为中国标准时间（`Asia/Shanghai`），再格式化日期。接收时间或午夜后收到应答，不会改变本次派发的查询日期。

### Twilio（`twilio`）

1. 准备可发短信的号码，建议建立带发送方的 [Messaging Service](https://www.twilio.com/docs/messaging/services)。获取 **Account SID** 和主 **Auth Token**。将 SID 填入 `access_key_id`，Auth Token 填入加密的 `access_key_secret`，并填写 `messaging_service_sid` 或可发短信的 `from` 号码。回调验签也使用该 Auth Token。
2. 在 [Twilio Content Template Builder](https://www.twilio.com/docs/content/create-templates-with-the-content-template-builder) 创建可发短信的模板，把其 `HX...` Content SID 填作平台模板的 Twilio 编号。应用模板变量须匹配 [ContentVariables 占位符](https://www.twilio.com/docs/content/send-templates-created-with-the-content-template-builder)（常见为 `"1"`、`"2"`）。
3. 将 `APP_HOST` 设为接收 Twilio 回调的公网主机。应用在每次发送时生成 `/sms/webhooks/twilio/delivery` 状态回调；还需单独在 Twilio 号码或 Messaging Service 中登记 `POST https://<host>/sms/webhooks/twilio/inbound`，以接收 STOP 回复。**检查实际生成的投递回调 URL：**本应用的生产环境设有 `force_ssl`，会生成 HTTPS；开发环境默认是 HTTP，除非另行配置路由 URL 协议。Twilio 会对**完整公网 URL** [签名请求](https://www.twilio.com/docs/usage/security)；公网协议、域名以及反向代理转发的协议必须与 Rails 请求 URL 一致。使用正式凭证和允许接收的号码验证模板投递与 STOP；Twilio [测试凭证不会产生状态回调，且测试短信不支持 `MessagingServiceSid`](https://www.twilio.com/docs/iam/test-credentials)。

## 流程

```text
Sms::Gateway.send
        |
        v
Sms::Activities::Send
        |  canonical request / tenant idempotency replay
        |  module / template / vars / marketing consent / opt-out / credential / quota
        v
Sms::Message queued (template snapshot + credential identity + expiry)
        |
        |  outermost commit -> Sms::DeliveryHandoff (best effort)
        |  Sms::RecoverMessagesJob -> repair missed/stale handoff
        v
Sms::DeliverMessageJob
        |  fenced preparation claim -> recheck expiry / module / permission / policy
        |  shared-account pacing -> persist only a due dispatch authorization
        |  persist dispatch_started_at -> adapter.send_message (one attempt)
        +-- API acceptance -> sent + vendor_message_id
        +-- proven rejection -> failed
        +-- ambiguous acceptance / attempted crash -> unknown (no resend)
        |
        +-- Sms::Cron::ReconcileMessages -> query_supported? -> adapter.query
        |
        +-- :webhook (Twilio)
              POST /sms/webhooks/:provider/delivery
              POST /sms/webhooks/:provider/inbound
                    |
                    v
              Sms::WebhooksController -> Sms::ReceiptInbox
                    |  delivery -> Sms::DeliveryProjection
                    |  verified opt-out -> Sms::OptOut.record_global!
```

`Admin::Modules::Sms::SendsController#create` 是管理端的 HTTP 交接。它为 URL 确定的当前客户调用 `Sms::Gateway.send`。模块停用后，新请求返回 404；真实幂等重放仍返回原台账行。

## 实现

### 受众与活动 HTTP 界面

短信模块入口打开**活动**。模块中心与侧栏对齐邮件模块：**活动**、**受众**（联系人、分群、退订名单三个页签）和**短信记录**。路由访问点从已注册路由生成，并使用本地化短信标签。新增控制器继承 `Admin::Modules::Sms::BaseController`，显式检查管理员／所有者权限与短信启用状态；联系人、分群、活动、收件人及同意证据均按 URL 指定客户查询，平台所有者跨租户浏览也遵循此范围。

分群删除委托 `Sms::Audience::DeleteSegment.call(customer:, actor:, segment:)`，草稿删除委托 `Sms::Campaigns::DeleteDraft.call(customer:, actor:, campaign:)`。这两个 `Sms::Result` API 负责租户／身份校验、客户优先加锁、最新依赖／状态检查及事务删除。草稿引用的分群或须保留的活动返回已有本地化 409 冲突；历史分群引用置空，但不修改冻结活动快照、联系人、证据或台账。平台短信目录在渲染时读取 `Registration.module_description`，使用成对的 `sms_campaign_http.registration.description` 翻译。完整 API 规则见[短信受众与活动](sms-campaigns)。

联系人可手动添加，或从受支持的普通实体手动同步，每批预览／执行最多 100 条，携带游标与固定上界。授权单独记录，换号重置为未知。动态规则无效即拒绝，匹配与可发送分别统计。活动采用字段／固定值／默认值映射及可选签名 `unsubscribe_url`；可先保存未完成草稿，再预览／确认已保存设置后启动。启动固定规则／内容／设置，执行开始原子捕获当前名单、联系人数据及解析变量（最多 10,000 人）。发送受免打扰、活动频次、接收容量、共享账户节流、租户额度和绝对截止时间约束；取消仅关闭未尝试任务。报告／CSV 从保留的收件人／消息台账推导。完整约定见[短信受众与活动](sms-campaigns)。

设 `S = /:customer_id/admin/modules/sms`。实体同步静态路由先于联系人 `/:id` 路由声明。

| 界面 | 路由 | Helper 前缀 `admin_modules_sms_` |
| --- | --- | --- |
| 联系人 | `S/contacts` 标准 CRUD；DELETE 归档 | `contacts`、`contact`、`new_contact`、`edit_contact` |
| 同意证据 | POST `S/contacts/:contact_id/consent_events`；仅追加 | `contact_consent_events` |
| 手动实体同步 | GET `S/contacts/entity_sync/new`；POST `.../preview`；POST `S/contacts/entity_sync` | `new_contacts_entity_sync`、`preview_contacts_entity_sync`、`contacts_entity_sync` |
| 动态分群 | `S/segments` 标准 CRUD；集合／成员 POST `preview` | `segments`、`segment`、`new_segment`、`edit_segment`、`preview_segments`、`preview_segment` |
| 活动草稿 | `S/campaigns` 标准 CRUD；集合／成员 POST `preview` | `campaigns`、`campaign`、`new_campaign`、`edit_campaign`、`preview_campaigns`、`preview_campaign` |
| 启动／取消 | POST `S/campaigns/:id/launch`；POST `.../cancel` | `launch_campaign`、`cancel_campaign` |
| 报告 | GET `S/campaigns/:campaign_id/report`，可带 `.csv` | `campaign_report` |

所有管理端 helper 的首个参数均为客户 ID。新分群通过 `POST S/segments/preview` 预览；已有分群通过 `POST S/segments/:id/preview` 预览，按 URL 租户查找记录。预览叠加提交值但不保存，保留原记录身份及提交的 `lock_version`；返回的保存按钮以 PATCH 更新原分群。校验失败时仍保留该身份和原始输入；保存旧版本仍返回冲突。成员 ID 不存在、格式无效或属于其他租户时返回 `404`，平台所有者也不例外，绝不回退为新分群。

`Sms::RequestAttributes` 生成规范输入，请求正文上限为 64 KiB。未知／受保护参数、非标量表单值、无效 ID／整数、畸形 JSON、重复对象键及非对象 JSON 字段均在业务写入前被拒绝。可选空 ID 转为 nil；无效／外租户 ID 绝不变成“全部联系人”。输入根及字段如下：

```text
sms_contact: phone, name, country_code, timezone, status, custom_attributes_json, lock_version
sms_consent_event: action, occurred_at, reference, statement, notes, event_key
sms_entity_sync: entity_id, phone_field, name_field, country_code, timezone,
                 attribute_map_json, after_entry_id, through_entry_id
sms_segment: name, description, segment_rules_json, lock_version
sms_campaign: name, template_id, segment_id, variable_map_json, send_timing,
              scheduled_local, timezone, quiet_hours_start, quiet_hours_end,
              frequency_window_hours, send_rate_per_minute, deadline_hours, lock_version
```

JSON 文本框转换为规范 `custom_attributes`、`attribute_map`、`segment_rules` 或 `variable_map` 对象。`Sms::FormValues` 在校验失败／预览时保留原始文本，GET 时从记录填充。同意发生时间必须含明确 ISO 8601 时区偏移；来源、操作者、号码和客户由同意服务确定。`scheduled_local` 格式为 `YYYY-MM-DDTHH:mm`，适配层按活动 IANA 时区转换为 UTC `scheduled_at`，拒绝夏令时缺失或重复时间。空计划时间可保留为未完成草稿。表单不能设置厂商、凭证、原始短信正文、同意投影、活动状态、快照、统计或租约。

活动预览使用相同字段，另接受根级 `preview_contact_id`，仅限本租户联系人。共用原生表单在保存时也提交此样本选项：仅作经过租户范围校验的只读元数据，绝不传入草稿持久化。Rails 提交字段 `commit` 为传输元数据，不属业务输入。启动仅接受根级 `lock_version` 和签名 `review_token`；取消不接受可编辑设置；归档接受根级 `lock_version`。控制器调用冻结的 `Sms::Contacts::*`、`Sms::Audience::*`、`Sms::Campaigns::*` 结果 API，预览与保存、短信接收各自独立。

HTML 保存／操作以 `303` 重定向至记录；校验失败以 `422` 重绘完整表单及选项；过期编辑／确认或非草稿修改返回 `409`。资源不存在／不可访问及短信停用返回 `404`。JSON 格式为 `{data: ...}` 或 `{error: {code:, errors: ...}}`：创建 `201`、更新／操作 `200`、启动 `202`。活动 JSON 不包含执行令牌和凭证快照。

列表提供当前页数组 `@records`、`@columns`、`@pagination`（`page/per_page/total/total_pages`）和 `@filters`；默认每页 25 行，上限 100。表单提供 `@form_values` 和 `@errors`。联系人详情另提供分页 `@consent_events`、当前 `@eligibility` 和 `@consent_form_values`；分群表单提供 `@catalog` 和 `@preview`。活动表单／确认页提供哈希选项 `@templates`（启用的平台营销模板）、`@segments`（租户分群）、`@contacts`（最多 20 行，包含指定样本）。实体同步提供 `@entities`、`@source_fields` 及有界 `@sync_result`。查询均在控制器／服务内完成。

报告以 `refresh: false` 调用 `Sms::Campaigns::Report`；GET／CSV 不持久更新统计，也不启动执行。筛选白名单为 `q/status/message_status/skip_reason/page/per_page/sort/dir`。CSV 按 ID 顺序每批 100 行输出全部匹配收件人，不受界面分页限制。固定列为 `campaign_id, recipient_id, contact_id, name, phone_e164, recipient_status, skip_reason, message_id, message_status, dispatch_started_at, sent_at, delivered_at, expires_at, failure_code, provider_segments`。表头本地化，时间使用 ISO 8601，公式前导文本加单引号转义；排除变量、原始应答、证据、签名令牌及凭证。

公开 `GET /sms/unsubscribes/:token` 与 `POST` 共用 `sms_unsubscribe_path(token)`。`Sms::UnsubscribesController` 仅为这两个操作跳过登录／MFA，保留浏览器 CSRF 验证。签名、用途、有效期及租户／联系人／号码解析由 `Sms::Campaigns::Unsubscribe` 完成，不采用查询参数。GET／HEAD 仅渲染 `{masked_phone:, already_unsubscribed:}`，不写入或入队；POST 幂等，无效／过期链接返回本地化 `404`。

`config/initializers/sms_unsubscribe_path_filtering.rb` 为短信退订路由扩展 Rails 的仅显示接口 `ActionDispatch::Request#filtered_path`，在输出 Rails `Started GET/HEAD/POST` 请求行及控制器埋点 `:path` **之前**，将完整能力令牌段替换为 `[FILTERED]`。保护范围包含格式后缀、挂载路径及经路由规范化的尾部／重复斜杠，同时保留 Rails 查询参数过滤。真实 `PATH_INFO`、URL、路径参数、路由匹配及签名令牌验证均不受影响；其他请求路径保持正常日志。现有 `:token` 参数过滤器另行遮蔽参数载荷中的退订／确认令牌，不能单独遮蔽 URL 路径内的令牌。

仅客户 `81721200` 的平台所有者可编辑模板 `purpose`（`transactional/marketing`）及可选 `body_template`，预览校验使用 `Sms::Contracts::TemplatePreview`；部分 PATCH 保留未提交的变量／厂商编号字段。平台凭证表单除厂商注册字段外，还接受通用 `sender_rate_per_second`：有限数值 `0 < rate <= 1`，经 `Sms::PlatformCredentialSave` 及现有凭证活动保存至 JSON `config`。无效速率保留在未保存的表单模型中，便于修正。`dispatch_next_at` 仅供运行时使用。

### Gateway 与 HTTP 约定

`Sms::Gateway.send(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil, provider: nil, expires_at: nil)` 返回 `Sms::Message`，通常为 `queued`；事务短信收件人被阻止时返回审计用的 `suppressed` 行。新接收营销模板须有同租户有效联系人、当前号码已同意且无抑制，否则抛出 `Sms::Errors::MarketingIneligible`（继承 `TemplateVarsInvalid`）。直接 Ruby、HTTP 及工作流调用均受此限制，派发再次检查固定的用途／联系人。真实幂等重放返回原消息，不再次发送。Ruby 的 `vars: nil` 归一为 `{}`。没有外层事务时，返回前该行已提交；位于调用方事务内时，该行参与同一事务，回滚会删除该行且不入队投递任务。`expires_at: nil` 表示从接收起有效一小时；可信 Ruby 调用方可传 `Time` 或 `ActiveSupport::TimeWithZone`。到期阻止尚未尝试的派发，不撤回已在途的投递。

`Sms::Gateway.send_campaign(customer:, recipient:, at: nil)` 是可信内部任务 API，返回 `Sms::Message`。它重新读取已持久化的同租户运行中活动／收件人，校验冻结内容／变量／资格，应用当前营销策略及额度，并以 `sms-campaign:<campaign_id>:recipient:<recipient_id>` 原子接收／关联该收件人的唯一消息。Run 可传入 `at:`；接收预留时间取该值与取得锁后采样的 `Time.current` 中较晚者，普通调用方省略此参数，幂等重放保留已有接收事实。采用启动时固定的模板及凭证身份，不接受调用方任意快照，也不按当前模板重新选择。无公开 HTTP 端点；调用方使用草稿、预览及启动界面。见[短信受众与活动](sms-campaigns)。

```ruby
message = Sms::Gateway.send(
  customer: customer,
  to: "+8613800138000",
  template_key: "verify_code",
  vars: { "code" => "1234" },
  idempotency_key: "verification-42"
)
```

`POST /:cid/admin/modules/sms/sends` 接收 `to`、`template_key`、可选对象 `vars`（省略或 null 时为 `{}`）及可选 `idempotency_key`。控制器在 Gateway 前应用 `Sms::SendStandards`；数组、字符串及其他畸形变量形状仍无效，不强制转成对象。省略／null 的键或通过限额的空白字符串归一为未提供。长度／编码检查先于空白归一，HTTP 还拒绝控制字符，因此超长空白或含换行的键返回 `422`。HTTP 不允许设置 `expires_at`，即使传 null 也无效。请求中的厂商／模式、发送方、原始正文和厂商凭证不传入 Gateway。角色与租户门禁先于接收逻辑执行。

```json
{
  "to": "+8613800138000",
  "template_key": "verify_code",
  "vars": { "code": "1234" },
  "idempotency_key": "verification-42"
}
```

| HTTP | 含义 |
| --- | --- |
| `202` | 返回行处于 `queued`，包括仍在排队的重放。 |
| `200` | 返回行处于其他状态，包括 `suppressed` 或重放的 `failed`／`unknown`／`expired`；须检查 `status`。 |
| `409` | `idempotency_conflict`：租户幂等键对应不同请求内容。 |
| `404` | 新请求的短信模块未启用。 |
| `422` | `invalid_request`：形状、号码、模板／变量、厂商映射无效、HTTP 到期值不受支持，或营销联系人／授权不合格。 |
| `429` | `rate_limited`（带 `window`）或 `daily_cap_exceeded`。 |
| `503` | `credentials_missing`。 |

响应包含 `message_id`、`status`、`vendor_message_id`、`failure_code`、`failure_message`（预置失败文案翻译，厂商文本按记录显示）及 ISO 8601 `expires_at`。入队接收不是回执，厂商结果稍后写入台账。控制器仍保留 `502 transport_error` 救援，但异步厂商失败通常更新消息，不改变已经结束的 HTTP 响应。

### 适配器与凭证

`Sms::Adapters::Base` 要求 `key`、`default_display_name`、`config_fields`、`configured?(credential)` 及 `send_message(to:, template:, template_params:)`，返回 `{ vendor_message_id:, raw: }`。默认 `delivery_mechanism` 是 `:poll`，但 `query_supported?` 默认为 false：实现 `query(message:)` 的适配器须显式启用查询能力。阿里云与 Twilio 均已启用；Twilio 使用官方 `twilio-ruby` SDK 的 Message fetch 弥补回调丢失。Webhook 适配器实现 `verify_webhook!`、`parse_delivery_receipt` 及表示已分类退订的 `parse_inbound`（`{ phone:, keyword: }`）。`rate_limit_windows` 默认同一号码每分钟 1 条、每小时 5 条、每天 10 条。

查询返回 `{ status:, raw: }`；投递解析返回含 `vendor_message_id`、`status`、`raw` 的数组。可选规范键为 `phone`、`provider_status`、`failure_code`、`failure_message`、`occurred_at`、`segments`；Twilio `account_sid` 等账户身份用于绑定原凭证。状态归一为 `:delivered`、`:failed` 或 `:unknown`，不要把 API 接受视为送达。

形似成功但畸形或有歧义的厂商应答抛出 `Sms::Errors::TransportError`，可选读取属性为 `vendor_message_id`、`payload`。Twilio 可保留畸形资源中通过语法校验的 SID，阿里云可保留有歧义 SendSms 应答中通过校验的 BizId。适配器以可用应答／审计哈希作为 `payload`，不据此假定接受。任务从部分结果或该错误取得可用 ID 及 raw／审计事实并记录 `unknown`；持久化后重新读取已记录身份，关联提前回执，保留的 ID 也可用于原凭证查询。ID 及原始事实均不证明接受或送达。缺少可用 ID 或持久化失败仍可能未决，歧义绝不授权再次发送。

创建／查询时，Twilio 保留本次调用的官方客户端，并在可用时读取 `client.http_client.last_response`，校验解析后的响应 JSON，不依赖 SDK 强制转换后的日期或错误代码。HTTP `201` 若有安全 SID，但 Message `status` 为数字、日期无效或 `error_code` 畸形，则抛出带该 SID 及选定审计事实的 `TransportError`；已尝试消息变为 `unknown`，不误报失败或退订。已认证回执或有效查询可在不重发的情况下补齐结果。仅保留 `AUDIT_FIELDS` 白名单字段，排除完整原始正文及额外消息内容／凭证回显字段。传输与验签仍由官方 SDK 处理，适配器不自行实现 HTTP 协议。

REST 异常响应使用独立约定：可选整数 `status` 须匹配 SDK 实际 HTTP 状态，范围为 `400..599`，不同于成功 Message 资源的字符串 `status`。对于发送尝试，有效 HTTP `400` 配合厂商代码 `21610` 表示已证实拒绝，记录 `failed` 并创建全局退订；代码 `21211` 记录 `failed`，不创建退订，而厂商代码缺失／仅为 HTTP 回退值、畸形响应及 HTTP `5xx` 仍属未决（`unknown`）。

`Sms::Credential` 每个厂商每个 mode 一行，没有 `customer_id`。状态 `active` 必须通过 `configured?`。`Sms::CredentialResolver` 在 `Sms::Adapters.default_key` 那条凭证为 active 时优先用它，否则用该 mode 的第一条 active 行。生产环境 mode 为 `production`，否则为 `sandbox`。`Sms::Activities::AssignDelivery` 每个 mode 只激活一条，并停用其余行；`Sms::Activities::SaveCredential` 通过 `AssignDelivery.persist` 保存平台表单，复用加锁事务，校验失败时回滚对其他凭证的停用。

未选到凭证时抛出 `Sms::Errors::CredentialsMissing`，使用调用时翻译的 `admin_modules.sms.errors.credentials_missing`；流程图的 `send_sms` 步骤经 `FlowchartRuntime::Step.fail` 以 `send_sms.credentials_missing` 报告。缺少凭证的消息不暴露内部模式／厂商选择细节。

`FeatureModules::Sms::Provisioner.call` 与 `.revoke` 返回 nil。凭证和模板不按租户创建。客户限额是 `FeatureModules::CustomerAssignment` 上的 `daily_send_cap`，默认 `Sms::Activities::Send::DEFAULT_DAILY_CAP`（1000），由 `FeatureModules::DailyCap` 读取。平台所有者在该客户的 `/:cid/admin/maintenance/modules` 页面于短信模块下设置非负上限；客户管理员在 `/:cid/admin/settings/modules/sms/daily_cap`（或 `/sms`）只能查看。

### 模板、发送、退订

`Sms::Template` 的 key 匹配 `\A[a-z0-9_]+\z`。状态为 `active` 和 `retired`。`provider_code` 读取 `provider_template_codes[provider]`。解析出的厂商没有该编号时，`Send` 抛出 `Sms::Errors::TemplateVarsInvalid`。

`Send` 将租户幂等键绑定到 SHA-256 规范请求指纹：E.164 收件人、模板键、按键排序的标量变量，以及显式请求的厂商、模式和到期时间（UTC，微秒精度）。解析后的默认值与自动计算的一小时到期值不参与指纹，因此真实重放不受模板停用、厂商重分配或模块停用影响。符号／字符串变量键及插入顺序统一处理；内容变化抛出 `Sms::Errors::IdempotencyConflict`（HTTP `409`）。可变前置条件之前、限额锁内及唯一索引竞争之后均检查重放。Ruby 与 HTTP 中通过限额的空白键归一为 nil，不标识重放。

内部、工作流与 HTTP 新发送均通过核心模块门禁。跨模板的手机号时间窗、租户每日预算及插入在 `Sms::Quota.synchronize`／`customer.with_lock` 内一同预留；SQLite 先写后读以取得写锁。suppressed 不消耗两类预算；每日计数还排除 failed／expired，手机号时间窗仅排除 suppressed。

接收时固定 `metadata.template_snapshot`（`key`、选定 `provider`、`provider_code`、`required_vars`、`vars`、`purpose`）及 `credential_id`／`credential_mode`；营销消息还关联类型化 `contact_id`，活动消息关联 `campaign_id`。派发从快照构造模板；后续模板修改／停用及投递重分配不会替换已接收载荷或改选凭证行。**这不是凭证密钥版本快照：**派发／查询／验签时仍读取保留行的当前密钥及发送号／签名／服务配置。编辑或删除该行可能影响未完成消息与回调验签，不承诺密钥轮换安全。

`Sms::OptOut` 没有 `TenantScoped`。已验证 STOP 写入 NULL 客户的全局抑制，租户行仅本地生效。`OptOutsController` 将实际有 `sent_at` 且非 suppressed 的消息号码传给 `visible_to_customer`；仅探测已抑制号码不能暴露全局退订元数据。

`Sms::WebhooksController` 为 API 控制器，已注册 poll 适配器返回 404。delivery／inbound 验证全部保留凭证，包括已停用行；请求提供的已签名 Twilio `AccountSid` 必须匹配候选账户。`WebhookCredentialBinding` 根据记录中的厂商消息 ID、凭证 ID／模式及已认证的投递收件人解析共用密钥的模式行。账户证明仍有歧义时，inbound STOP 可使用唯一的实际联系凭证记录。解析后的身份传给 `Sms::ReceiptInbox`；身份唯一的提前回执持久保留至关联，身份唯一的 STOP 可无消息匹配而全局生效。歧义未消除时，在回执／退订写入前返回 HTTP 409，不任意采用模式，也不接受请求中的模式提示。

上行退订的联系人取适配器归一后的 `From`，不是上行 `To`（平台发送方）。投递关联使用归一后的 `To`。旧投递事件未提供 `phone` 时可使用 raw `To`；控制器校验并归一为 E.164，在收件箱处理前复制到 `event[:phone]`。因此，即使仅一条凭证通过验签，仍执行收件人匹配。提供的联系人无效时，在回执／退订写入前返回 `400 invalid_request`；有效但不匹配的投递号码不写入该消息。缺少收件人数据与提供了无效值是不同情况。

Twilio 已签名的 `OptOutType=STOP` 是权威退订分类，正文为本地语言时也生效。无该分类时，识别 `STOP`、`STOPALL`、`UNSUBSCRIBE`、`CANCEL`、`END`、`QUIT`、`REVOKE`、`OPTOUT`。已签名的 START／HELP 分类及未分类的 START／HELP 正文均忽略。匹配的 Twilio 拒绝／回执代码 `21610` 为记录中的收件人创建全局抑制。没有自动全局解除或重新同意路径，上行回复不建立正向同意。Twilio 上行响应为无内容的 `<Response/>` XML，不生成回复消息。控制器在解析前拒绝已知 `Content-Length` 超过 64 KiB 的请求；流式限额由边缘服务执行。

### 号码与载荷标准

`Sms::PhoneNumber` 在维护中的 Phonelib 号码规划数据外加严格词法门禁。国际号码须以 `+` 或 `00` 开头；本地号码默认中国（`CN`）。空格、点、连字符及配对括号可作显示分隔符；拒绝说明文字、字母号码、分机、控制字符、畸形括号及无国际标记的国家代码前缀。输入最多 64 个 UTF-8 字节，输出为 E.164。应用自有辅助接口 `Sms::PhoneNumber.normalize(raw, country: "US")` 可选国家上下文；Gateway／HTTP 不提供国家覆盖。有效号码规划不证明号码已分配、可达或可接收短信。

`Sms::SendStandards` 是 `Sms::Contracts::Send` 与 `Sms::MessageAdmission` 使用的共用无 SQL 形状校验器。接收在规范复制、生成指纹或查询幂等键前限制载荷；可变模板／厂商前置条件仅用于新接收。限额按字节，不按字符数计算：

| 输入 | 限额 |
| --- | --- |
| 模板键 | UTF-8 字符串，`[a-z0-9_]+`，最多 128 字节。 |
| 幂等键 | 可选 UTF-8 字符串，最多 128 字节；有效空白字符串归一为未提供，HTTP 还拒绝含控制字符的键。 |
| 变量 | 对象，最多 64 个唯一字符串／符号键；每个非空 UTF-8 键最多 128 字节。 |
| 变量值 | 非空 UTF-8 字符串或有限整数／浮点数／十进制数；文本表示最多 1,024 字节。不接受嵌套对象／数组、布尔值或 null。 |
| 变量载荷 | JSON 最多 8,192 字节，包含键及转义开销。 |

提供的变量键须与启用模板的必需键完全一致，缺少或多余均失败。这些载荷限额不同于短信分段容量。

### 发件箱、派发与恢复

`ActiveRecord.after_all_transactions_commit` 仅在最外层提交后启动 `Sms::DeliveryHandoff`。`Sms::DeliverMessageJob` 入队尽力执行：失败时尽量清除加速标记，已提交的接收行仍有效。`Sms::RecoverMessagesJob` 按生产 `config/recurring.yml` 排期每五分钟扫描台账。`DeliveryHandoff::RECOVERY_AFTER` 是独立的五分钟入队标记阈值；`DeliveryDispatch::CLAIM_TTL` 是 30 分钟准备租约。这些是可恢复条件，不保证投递时限。

条件式领取令牌隔离准备阶段。入队遗漏或准备滞留后，恢复可重新入队尚未尝试的 queued 行；令牌被替换后，旧任务无法通过原子的 `DeliveryDispatch.start` 更新。调用厂商前，任务再次检查到期、模块启用及退订，再写入 `dispatch_started_at` 并增加 `delivery_attempts`。完成写入匹配这一不可变派发标记及原令牌或已清除的令牌，因此提前回执清除令牌后也不会重新开放尝试。尚未尝试而已到期的行变为 `expired`；模块停用或新增退订变为 `suppressed`。最终检查后的 STOP 仍可能与派发竞争。

`Sms::Campaigns::DeliveryPolicy` 还检查当前营销联系人／号码／授权，以及活动取消／失败／截止时间、免打扰及活动频次。使用同一保留凭证的所有发送共用 `Sms::DispatchLimiter` 与 `dispatch_next_at`，读取实时 `sender_rate_per_second`（默认 1，有限值 `0 < rate <= 1`）。未来的 `delivery_due_at` 延后交接／领取／开始／恢复，不产生尝试，也不重置到期时间。一分钟活动调度器与五分钟核心恢复分别修复到期任务；账户节流限制持久化开始，不保证运营商送达。见[短信受众与活动](sms-campaigns)和[后台任务](background-jobs)。

存在尝试标记后，任务及恢复路径均不再发送该载荷。已证实 API 拒绝变为 `failed`；超时、畸形接受应答或已尝试任务崩溃变为 `unknown`。恢复隔离崩溃时保留唯一尝试的令牌，允许其真实迟到应答补记厂商 ID，但不会让该行再次可领取。投递任务没有发送重试策略。

仅台账完成写入对语句／连接故障重试，每次状态转换最多尝试三次（`LEDGER_COMPLETION_ATTEMPTS`）。适配器调用及回执投影均位于该重试块之外。无法持久完成接受状态时，任务使用保留的 ID／raw 事实进行有界 unknown 写入。数据库更新成功但重新加载失败，不会倒退已保存状态；迟到接受可补齐缺少的接受事实，不覆盖运营商终态、原始回执或失败事实。耗尽台账写入尝试不允许重发，也不保证全部事实均已保存。

`Sms::Cron::ReconcileMessages` 每 15 分钟运行，重投回执，并对有厂商 ID、处于 `pending`／`sent`／`unknown` 且在两分钟宽限至三天最大年龄范围内的行查询支持该能力的适配器。查询资格及超龄判断均使用 `COALESCE(dispatch_started_at, sent_at, created_at)`：优先派发，历史行回退至接受／接收时间，不以新消息接收时间起算。更早的未决 pending／sent 变为 `unknown`，不标失败死信。queued 派发恢复独立处理。已认证的迟到送达可修复 `unknown` 或 `failed`；后续失败／unknown 不会倒退 `delivered`。到期仅阻止尚未尝试的发送。

| 状态 | 含义 |
| --- | --- |
| `queued` | 已接收的发件箱行，可能准备中或等待任务。 |
| `pending` | 历史状态，不是新发送默认值。 |
| `sent` | 厂商 API 接受了唯一一次尝试。 |
| `delivered` | 投递回执确认成功。 |
| `failed` | 已证实拒绝，或真实失败／未送达回执。 |
| `unknown` | 接受／送达未决，绝不意味着可重发。 |
| `suppressed` | 外部尝试前被阻止。 |
| `expired` | 外部尝试前超过截止时间。 |

`20261013000100_enhance_sms_delivery_lifecycle` 为增量迁移：新增到期、入队／领取／尝试列及发件箱索引，将新行默认状态改为 `queued`。不重置数据库，也不转换或补发既有 `pending` 行。见[后台任务](background-jobs)。

### 回执诊断、分段与日志

`Sms::DeliveryProjection` 将回调与查询的规范事实统一写入，提供收件人时须匹配记录中的 E.164 目标。厂商失败代码／文本写入台账。规范事件为 delivered 时，`delivered_at` 采用有效发生时间，缺少时采用处理时间。有值时，元数据保留 `provider_status`、正数实际 `provider_segments` 及 ISO 8601 `provider_occurred_at`，failed／unknown 事件也可记录。**厂商事件时间是诊断元数据，不是送达证明：**Twilio REST `date_updated` 是资源更新时间，仅有时间戳或分段数不意味着 `delivered`。Twilio 无时区且有歧义的运营商时间戳仅保留 raw，不擅自补时区；阿里云文档规定的时间按 `Asia/Shanghai` 解析。

`Sms::SegmentCalculator.call(text:, **limits)` 是针对**完整渲染正文**的纯函数参考计数器。GSM-7 默认字符占一个 septet，扩展字符占两个；非 GSM 文本按 UTF-16 代码单元计数（增补平面字符占两个）。默认单段／多段容量为 160／153 septet 及 70／67 UTF-16 单元。装段不拆开 GSM 转义序列或代理对，并支持容量覆盖。结果为 `encoding`、`units`、`segments`、`segment_units`：

```ruby
Sms::SegmentCalculator.call(text: "a" * 152 + "^" + "a" * 152)
# => { encoding: :gsm7, units: 306, segments: 3, segment_units: [152, 153, 1] }
Sms::SegmentCalculator.call(text: "😀" * 67)
# => { encoding: :utf16, units: 134, segments: 3, segment_units: [66, 66, 2] }
```

没有预览副本的模板不提供渲染正文，发送前估算未知，不可从编号／变量推算。活动预览可渲染所有者维护的可选 `body_template` 并估算样本，但该副本不作为原始正文发送，也不替代厂商实际分段。计数器及厂商分段元数据均不是计费报价。

参数日志过滤精确名称 `vars`、`to`、`From`、`To`、`Body`，包括嵌套 `vars[...]` 查询键；不泛化过滤所有含 `body`／`phone` 的名称。这保护请求日志，不处理已存载荷／原始回执。

`Sms::DeliverMessageJob` 自身的 `[sms.deliver]` 警告仅记录消息 ID 及错误类，不记录异常文本和厂商载荷。其 `sms.send` 观测事件包含结果、厂商及耗时；保留的应答／审计事实写入台账。

消息详情视图渲染 `Sms::Admin::MessageDetailsComponent`（`app/components/sms/admin/message_details_component.rb` 及 `.html.erb`）。响应式详情网格展示本地化状态说明、收件人、模板键、厂商、厂商 ID、派发开始、尝试次数、API 接受时间、送达时间、到期时间、厂商事件时间／状态及实际报告的分段数。有效时间使用语义化 `<time datetime="…">` 元素。缺少到期／分段时显示未知，其他事实缺失或厂商事件时间格式无效时显示未记录。失败代码／文本仅在 `failed` 时显示。仅展示变量名，**所有变量值均隐藏**；不渲染原始应答、模板快照或凭证密钥。已存载荷仍供后台处理，页面隐藏不等于删除数据。

### 四个面

| 面 | 路径 | 控制器 |
| --- | --- | --- |
| 条目 | `/:cid/admin/modules/sms/campaigns`、`/contacts`、`/segments`、`/messages`、`/opt_outs`，以及 `POST .../sends` | `Admin::Modules::Sms::*`；活动启动／取消／报告、授权与手动同步均为模块内嵌套操作 |
| 客户设置 | `/:cid/admin/settings/modules/sms`（含 `/daily_cap`） | `Admin::ModuleConfigsController` 只读展示 `daily_send_cap`，PATCH 排除该字段 |
| 启用／停用及客户上限 | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`、`ModuleEnablementsController`；仅平台所有者可通过 `ModuleOwnerConfigurationsController` 写入 `daily_send_cap` |
| 平台设置 | `/:cid/admin/maintenance/platform/module_settings/sms/credentials` 与 `/templates` | `Admin::Maintenance::Platform::Sms::CredentialsController`、`TemplatesController`；共用窗格在 `ModuleSettingsController` |

`MessagesController` 使用 `Sms::Message.for_current_customer`。注册类的 `entries_for("messages")` 是同一模型上的通用条目关系。侧栏路径是专用的 index。

模块交接输入是 `to`、`template_key`、可选 `vars`、`idempotency_key` 及可信 `expires_at`；输出为 `message_id` 和 `Sms::Message::STATUSES` 中的状态，包括 `queued`、`expired`。流程图用 `send_sms` 步骤动作发送短信，它取代了旧通知动作的短信通道。字段为 `templateKey`（可搜索的已启用平台短信模板引用）、`to`（默认 `model.phone`）、`vars`（字面量键映射到表达式值）及可选 `idempotencyKey`；消息 id 写入 `resultVar`（默认 `sms_message_id`）。步骤调用 `FlowchartRuntime::SmsDelivery.deliver`，经 `FlowchartRuntime::Sms.send_template` 与 Gateway 使用平台模板和凭证，并把 `Sms::Errors` 映射为 `send_sms.*` 失败代码（`suppressed`、`quota`、`credentials_missing`、`module_disabled`、`idempotency_conflict`、`marketing_ineligible`、`template_missing`、`api_error`、`invalid_number`、`provider_code_missing`、`invalid_vars`、`failed`）。返回的消息只要不是 `suppressed` 就算工作流成功，不代表已送达。短信结果／错误不触发其他通道。见[流程图运行时](flowchart-runtime)和[流程图步骤动作](flowchart-step-actions)。

## 需要特别注意

### 路由审计：预留及回执不变量

`Sms::ReceiptInbox.record!(credential:, event:, event_key: nil)` 接受已认证的规范 delivery／inbound 事件，按凭证及事件身份去重，raw 不参与身份。厂商 ID 记录后，恢复及对账重投 pending 回执。状态转换检查持久化状态，stale 轮询／失败／unknown 不能倒退 delivered。管理路由保留租户／用户门禁，核心模块门禁控制新接收，不隐藏真实重放。公开回调依赖厂商证明，不依赖浏览器会话。见[邮件](email)、[租户与角色](tenancy-and-roles)、[后台任务](background-jobs)。

短信幂等查询绕过 Active Record 查询缓存。真实唯一索引竞争失败、回滚持久化保存点后，服务重新读取同客户／同键的获胜记录，不再次调用厂商。获胜记录必须位于失败方保存点之外；在其内部插入的记录会按事务语义回滚。找不到对应租户／幂等键时，索引错误继续抛出，不返回其他客户的记录，也不伪报发送成功。

:::note
回执缺失、厂商 ID 丢失及超过查询窗口的消息可能持续未决。台账区分不确定与已证实失败；运行验证应针对配置账户实测回调验签、查询兜底及任务恢复。
:::

:::attention
新厂商是 `app/services/sms/adapters/` 下一个继承 `Sms::Adapters::Base` 并调用 `register!` 的文件。Webhook 路由约束读取 `Sms::Adapters.keys`。非密钥的厂商字段通过 `config_fields` 进入 `config`。`access_key_secret` 留在所有适配器共用的加密列上。`Sms::Adapters::Aliyun` 是 `:poll`，并且是 `default!` 适配器。`Sms::Adapters::Twilio` 是 `:webhook`。
:::

:::attention
`verified_adapters` 对非 webhook 适配器返回 404。只有保留凭证验证成功后才解析 delivery／inbound，回执写入前须解析原发送身份；active-only 选择仅用于新发送。
:::

:::attention
NULL 客户的全局退订抑制全部租户。可见性要求实际发送接触，接收阶段的 suppressed 行不足以获得权限。多次退订检查缩小竞争窗口，但无法撤回已在途的厂商操作。
:::

:::attention
`Sms::Activities::AssignDelivery` 让全平台每个 mode 只留下一条 active 的 `Sms::Credential`。`FeatureModules::Sms::Provisioner` 不会把凭证复制到客户上。本模块的租户设置是 `daily_send_cap`，由 `Sms::Quota` 在客户写锁内执行。`Sms::Activities::Send` 在真实重放后检查 `FeatureModules::Module.enabled?`；派发在唯一一次外部尝试前再次检查。
:::

## 关键代码

```ruby
# app/services/sms/adapters.rb
module Adapters
  extend PluginRegistry.build(label: "sms adapter", dir: "app/services/sms/adapters")
end
```

```ruby
# app/models/sms/opt_out.rb
def self.opted_out?(customer_id:, phone_e164:)
  phone = Sms::PhoneNumber.normalize(phone_e164)
  return false unless phone

  where(phone_e164: phone).where(customer_id: [nil, customer_id]).exists?
end

def self.record_global!(phone_e164:, provider: nil, reason: nil)
  upsert_row(customer_id: nil, phone_e164: phone_e164, provider: provider, reason: reason)
end
```

```ruby
# app/controllers/sms/webhooks_controller.rb
provider_class = Sms::Adapters.for(provider)
unless provider_class.delivery_mechanism == :webhook
  raise ArgumentError, "provider #{provider} has no webhook endpoint"
end
```

```ruby
# app/services/sms/activities/send.rb
if created && message.status == "queued"
  ActiveRecord.after_all_transactions_commit { DeliveryHandoff.call(message) }
end
```

```ruby
# config/routes.rb
post "/sms/webhooks/:provider/:kind",
     to: "sms/webhooks#create",
     as: :sms_webhook,
     constraints: ->(req) {
       provider = req.path_info.split("/")[3]
       Sms::Adapters.keys.map(&:to_s).include?(provider)
     }
```
