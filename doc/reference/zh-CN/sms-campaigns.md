---
title: "短信受众与活动"
summary: "已授权联系人、手动实体同步、动态受众、审核模板个性化、确认后启动、有界派发及基于台账的报告。"
---

## 概要

短信活动工作区按**受众 → 内容 → 发送时间 → 确认**分步向导组织，与邮件发送活动一致。保存草稿和预览只提交当前字段，不会启动发送。租户管理员添加联系人、单独记录营销授权，选择动态分群或全部联系人，配置平台营销模板的个性化变量，保存草稿并确认后启动。执行开始时固定名单，发送前检查当前授权与派发限制，并保留收件人台账供报告和 CSV 导出使用。

本页按当前源码编写。`docs/plans/2026-10-13-sms-audience-campaigns.md` 是架构设计约定；存在差异时，以本页记载的实际实现为准。厂商配置、直接发送、回执处理及消息状态见[短信](sms)，任务配置见[后台任务](background-jobs)。

### 官方产品参考

| 参考 | 借鉴的交互模式 | Anysys 实现 |
| --- | --- | --- |
| [Twilio Messaging Services](https://www.twilio.com/docs/messaging/services) | 共用发送方配置、异步投递回调、有效期及退订处理 | 平台凭证、回执对账、共享账户节流与尝试前截止时间；API 受理与送达分别记录。 |
| [Klaviyo 短信活动](https://help.klaviyo.com/hc/en-us/articles/360040039971) | 明确同意、名单／分群、个性化预览、频次控制、免打扰及立即／定时发送 | 独立联系人及授权证据、动态分群、样本预览、按活动尝试计算的频次窗口及收件人本地免打扰时段。 |
| [Braze 短信活动创建](https://www.braze.com/docs/user_guide/message_building_by_channel/sms/campaign/create/) | 订阅筛选、个性化、发送控制、确认与报告；该链接跳转至当前 SMS／MMS／RCS 指南 | 区分受众匹配、授权和派发资格，并在最终尝试边界再次检查授权。 |
| [Mailchimp 营销短信](https://mailchimp.com/help/create-send-marketing-sms/) | 已订阅受众、合并字段／默认值、确认清单、发送时长、报告及取消剩余排队消息 | 字段／固定值／默认值映射、已保存草稿确认、绝对截止时间、有条件取消及收件人／消息报告。 |

这些是产品设计参考，不表示已接入 Klaviyo、Braze 或 Mailchimp，也不承诺功能对等。当前工作区通过既有阿里云／Twilio 适配器管理一次性短信活动；不提供上述产品的 MMS／RCS、会话收件箱、A/B 测试、周期活动、短链接／点击／转化追踪、CSV 联系人导入或公开订阅收集功能。

## 流程

```text
Manual contact / explicit Entity sync -> consent unknown
        |
        +-- append grant/revoke evidence -> current-phone consent projection
        v
Dynamic audience -> approved marketing template + safe variable mappings
        |
        v
Save draft -> preview/review saved settings -> signed review token
        |
        v
Launch -> freeze settings/content/rules/credential identity -> scheduled
        |
        |  one-minute SchedulerJob -> leased RunJob
        v
Execution start -> atomic recipient/contact/vars snapshot -> running
        |
        |  eligibility / quiet hours / admission rate / quotas / deadline
        v
Sms::Gateway.send_campaign -> one linked Sms::Message -> post-commit handoff
        |
        |  final permission/policy recheck + shared-account dispatch clock
        v
Sole external attempt -> API acceptance / rejection / unknown
        |
        +-- callbacks / queries -> delivery outcomes -> report / CSV
        +-- cancel -> close only remaining unattempted work
```

## 实现

### 租户模型与管理界面

活动域由五个租户模型承载：`Sms::Contact`、`Sms::ConsentEvent`、`Sms::Audience::Segment`、`Sms::Campaign`、`Sms::CampaignRecipient`。模板与凭证仍属平台级资源。模块入口打开活动。侧栏分为活动、受众（联系人、分群、退订名单页签）和短信记录。管理控制器继承 `Admin::Modules::Sms::BaseController`，要求管理员／所有者权限及短信启用，按 URL 客户解析记录；平台所有者跨租户浏览也遵循此范围。

`FeatureModules::Sms::Registration.module_description` 在调用时翻译 `sms_campaign_http.registration.description`，中文为“通过可扩展服务商发送定向短信活动与事务短信”。平台模块目录的短信卡片及搜索描述读取该注册访问器，因此已注册模块切换语言后也会更新文案，不持久写入或冻结显示翻译。

路由／访问授权目录分别标识八项受众／活动资源：联系人、同意记录、联系人同步、受众、活动、启动活动、取消群发及活动报告。`AccessPoints::SmsRouteLabels` 与 `Admin::Settings::Modules::Authentication::GrantRouteLabel` 共用翻译键，在单一短信上下文下生成各自独立的中英文名称，不使用通用资源标签。控制器主体键及动作／租户／角色校验不变。完整主体／动作矩阵见[访问授权](access-grants)。

设 `S = /:customer_id/admin/modules/sms`。联系人位于 `S/contacts`（DELETE 归档），证据通过 POST `S/contacts/:contact_id/consent_events` 追加，手动同步位于 `S/contacts/entity_sync`，动态受众位于 `S/segments`，草稿位于 `S/campaigns`。预览、启动（`S/campaigns/:id/launch`）、取消（`.../cancel`）使用独立 POST；GET `S/campaigns/:campaign_id/report[.csv]` 读取结果。完整输入根、helper、响应码及 CSV 列见[短信](sms)。

新分群通过 `POST S/segments/preview` 预览，对应 `admin_modules_sms_preview_segments_path(customer_id)`；已有分群使用 `POST S/segments/:id/preview`，对应 `admin_modules_sms_preview_segment_path(customer_id, segment)`。成员操作按 URL 租户查找记录，仅叠加提交值，不保存。成功及校验失败重绘均保留原记录身份、原始表单值及提交的 `lock_version`，返回的保存按钮以 PATCH 更新原记录，不创建重复分群。旧版本保存仍返回冲突；成员 ID 格式无效、不存在或属于其他租户时返回 `404`，平台所有者也不例外。

删除业务规则由服务负责，控制器仅校验 HTTP 载荷并按结果渲染／重定向：

| API | 输入 | 成功 `Sms::Result#value`／记录保留结果 |
| --- | --- | --- |
| `Sms::Audience::DeleteSegment.call` | `customer:, actor:, segment:` | 已删除分群；存在草稿引用时返回 `segment_in_use`（HTTP 409）。历史活动保留冻结受众／内容及台账，仅将 `segment_id` 置空。 |
| `Sms::Campaigns::DeleteDraft.call` | `customer:, actor:, campaign:` | 已删除的空、未启动草稿；非草稿状态、已有收件人、已记录启动或关联消息限制均返回 `not_draft`（HTTP 409）。 |

两者均返回 `Sms::Result`，重新校验已持久化、启用的管理员／所有者身份、记录类型及指定租户，按**客户 → 记录**加锁，再按租户范围重新读取数据库行并检查依赖／状态。平台所有者可在其他租户 URL 下操作，但不能将外租户记录用于错误的指定客户。记录已删除、句柄失效或伪造内存中的租户身份时返回 `not_found`，操作者无权访问时返回 `forbidden`。冲突文案复用两种语言已有的 `sms_campaign_http.errors.segment_in_use`／`.not_draft` 键。删除失败整笔回滚，不会部分置空引用；联系人和同意证据保留。

### 手动联系人与有界实体同步

联系人按租户内 E.164 号码唯一，已归档记录也占用该身份。手动创建填写号码、国家上下文（默认 `CN`）、可选姓名／IANA 时区及标量自定义属性对象。国家代码不决定时区。自定义属性最多 32 个键、总计 8 KiB；键匹配 `[a-z][a-z0-9_]{0,63}`，字符串最多 1,024 字节，值可为字符串、有限数值、布尔值或 null，不支持嵌套数组／对象。DELETE 归档并保留证据／历史；恢复须显式更新联系人状态。

`Sms::Contacts::SyncEntity.call(customer:, actor:, attributes:, preview: false)` 支持可访问、启用的普通实体，不遍历桥接关系，也不支持原生模型扩展。共享定义按当前客户通过 `resolved_current_version` 解析，条目始终使用 `EntityEntry.for_customer(customer.id)`。`Sms::EntitySources` 仅提供受支持的标量 schema 字段；必选电话字段的实际类型须为 `html_type: "tel"`，名称类似电话并不足够。数据从 `entry.data_json[field_slug]` 读取。

预览不写入，最多检查 `after_entry_id` 之后的 100 条，并返回上界 `through_entry_id`；每次执行 POST 按 ID 顺序处理最多 100 条，手动继续时携带上界、游标和映射。每次请求重新校验来源与映射。结果区分创建、更新、无变化、无效及冲突，不自动轮询或导入授权。

同步先按来源关联匹配，再按租户号码匹配。未关联来源的同号联系人可建立关联；身份冲突或已有不同来源均报告冲突，不合并。仅替换映射涉及的属性键，保留未映射键及归档状态。同号更新保留授权，换号重置授权。删除来源不会静默删除联系人；重放批次不会重复创建联系人或授予许可。

### 仅追加的授权与发送抑制

新建／手动／同步联系人均以 `consent_status: "unknown"` 开始。`Sms::Contacts::RecordConsent` 在锁定当前号码后追加管理员事件。记录同意须有凭证来源及收件人实际同意内容；撤回须有凭证来源，两者均可附备注。每段证据文本最多 1,024 字节，证据对象最多 4 KiB，`event_key` 最多 128 字节。发生时间须含明确 ISO 8601 时差，且不得为未来时间。客户、操作者、来源及号码由服务端确定。

`Sms::ConsentEvent` 持久化后只读，无编辑／删除路由。同键同事实重放返回原证据，同键不同事实返回冲突。当前号码的授权投影按记录插入顺序更新，`consent_changed_at` 取记录时间，不取补录的历史发生时间。更换号码会将投影重置为未知并清除该时间，即使新号码曾有历史同意也须重新记录；旧号码证据保留。

撤回及签名链接退订还会创建租户 `Sms::OptOut`。记录同意不会解除租户／全局抑制。已验证服务商 STOP 或 Twilio `21610` 创建全局抑制，并可为关联联系人追加 `provider_opt_out` 证据。发送资格直接读取抑制记录，不依赖逐一更新各租户联系人投影。START／HELP 不授予同意，也不解除阻止。已归档联系人无论是否同意均不可发送。

### 无效即拒绝的动态受众

`Sms::Audience::SegmentQuery` 使用已引用的 Arel 值及受控字段编译有界 AND／OR 分组 AST。连接按从左到右计算：`[A, B, C]` 配 `[AND, OR]` 表示 `((A AND B) OR C)`；嵌套组独立计算。有意设置的空根 `{}` 或空条件／连接组考虑本租户全部联系人。空嵌套组、未知字段／运算符／键、连接数量错误、转换无效或超限会使整棵树无效。保存／预览拒绝无效规则；查询已存无效规则返回 `.none`，活动开始前失败，绝不扩大受众。

规则上限为 32 KiB、深度 8、100 个节点及 1,024 字节字符串值。根字段为 `name`、`phone_e164`、`country_code`、`timezone`、`status`、`consent_status`、`source_kind`、`created_at`、`updated_at`。最多公开 128 个排序后的租户自定义键，以 `attributes.<key>` 表示，要求类型一致；混合类型排除，整数／浮点数归为同一数值类型。启动时固定引用属性的类型，缺失或类型不符均不匹配。日期时间比较须使用含时差的完整 ISO 8601 值。

匹配名单可包含已归档／未授权联系人。受众预览分别展示匹配、可发送及排除数；活动预览另检查个性化与活动频次窗口。免打扰延迟仍算合格联系人。选择受众外样本不会将其计入名单或授予许可。活动预览、启动及开始均限最多 10,000 个匹配联系人，预览最多五个样本。共用分群构建器使用短信字段目录，由宿主表单的原生 POST 操作预览。

### 模板用途、预览副本与变量

仅平台所有者维护 `Sms::Template#purpose`（默认 `transactional`，或 `marketing`）及可选 `body_template`。活动须选择启用的营销模板，并为解析出的发送账户配置厂商编号。副本最多 4 KiB，仅接受必需变量中的简单 `{{variable_name}}` 占位符。它是所有者维护的预览文本，不作为原始正文发给厂商，也不证明厂商已批准。没有副本时仅预览变量，段数未知；有副本时，`Sms::SegmentCalculator` 根据渲染样本估算，不作费用报价，也不保证厂商实际分段一致。

启动时 `variable_map` 键须与所选模板必需变量完全一致。字段映射包含 `source: "field"`、白名单字段及可选显式 `fallback`；固定值映射包含 `source: "literal"` 和 `value`。允许字段为 `name`、`phone_e164`、`country_code`、`timezone`、受控 `attributes.<key>` 及生成的 `unsubscribe_url`。缺失／null／空白字段使用默认值，无默认值则以 `personalization_missing` 跳过收件人，不隐式补姓名。字段布尔值转为字符串，固定值／默认值须为非空字符串或有限数值。上限为 64 个变量、128 字节键、1,024 字节解析值、8,192 字节解析载荷及 16 KiB 映射 JSON。不执行表达式、Liquid、ERB、Ruby 访问器或实体遍历。

`unsubscribe_url` 使用 Rails 签名绑定客户／联系人／冻结号码，有效期 365 天，按经过校验的规范 URL 配置生成。GET／HEAD `/sms/unsubscribes/:token` 仅显示掩码号码及确认表单；经 CSRF 保护的 POST 幂等追加撤回与租户抑制。联系人已换号时，链接仅撤回签名旧号码，不修改新号码授权。预览生成链接不写入或入队；无效／过期链接返回本地化 404。获批远程营销内容须实际包含有效退订方式，如映射链接或服务商回复说明；应用不会自动追加退订文字或缩短链接。

`config/initializers/sms_unsubscribe_path_filtering.rb` 仅针对短信退订路径扩展 `ActionDispatch::Request#filtered_path`，在**日志输出前**遮蔽能力令牌。Rails 的 `Started GET/HEAD/POST` 请求行及控制器埋点 `:path` 显示 `/sms/unsubscribes/[FILTERED]`，存在挂载前缀或查询参数时，保留前缀及经 Rails 过滤后的查询部分。匹配使用 Rails 路由规范化，覆盖尾部／重复斜杠及格式后缀。真实 URL、`PATH_INFO`、令牌路径参数及验签保持完整；其他短信及应用路径正常记录。现有 `:token` 参数过滤器另行遮蔽参数载荷，不能单独遮蔽 URL 路径内的能力令牌。

### 已保存草稿、确认及两个快照边界

`Sms::Campaigns::Save` 可保存未完成草稿：缺少模板、变量映射或定时时间会列为启动阻塞项，但提交的引用／形状及已填写设置仍须有效。`Preview` 将输入覆盖到未保存副本，只读评估，不调用厂商、不预留额度、不入队。仅已保存、无阻塞且预览设置与该草稿一致时，才能取得 15 分钟签名确认令牌。草稿详情评估已保存设置；表单中未保存的预览不会启动这些修改。

`Launch.call(customer:, actor:, campaign:, lock_version:, review_token:, at: Time.current)` 在锁内检查版本、设置／内容／规则／类型摘要及凭证身份，并重跑当前预览门禁。确认过期或已变化返回 `review_changed`（HTTP 409）。启动须满足短信启用、账户已配置、有效且启用的营销内容、完整映射、人数有界且有合格受众，以及未来定时日期。按活动 IANA 时区解析本地时间，拒绝夏令时不存在／有歧义的时间。

启动固定设置、模板／厂商编号／必需变量／用途／副本、变量映射、受众规则／引用类型及凭证 ID／模式，记录操作者与时间，计算绝对截止时间，并设为 `scheduled`，立即发送也先进入此状态；提交后尽力将调度器入队。启动后不能编辑设置或重新启动；匹配的重放仍指向同一次启动。凭证身份固定，但保留行的密钥、发送方配置及账户速率仍为实时基础设施配置。

首次执行时，`Run.snapshot_audience` 在客户／活动事务内按冻结规则查询当前租户联系人，每批读取 100 条，原子写入完整台账（最多 10,000 个匹配行）、联系人快照、解析变量及初始资格，并记录 `started_at`。初始不合格行立即跳过。实际实现为分批读写，不是 insert-select。回滚移除整个快照，恢复不会扩展已提交名单或重新计算个性化。开始前的联系人变化可影响名单；开始后的变化可阻止发送，但不替换冻结的目标／内容。之后补录同意或恢复联系人，不会将初始排除者加入本次发送。

### 排期、派发限制与取消

生产环境每分钟运行 `Sms::Campaigns::SchedulerJob`，每批扫描 100 行，分配／续用 15 分钟执行租约，修复丢失的继续执行或到期消息交接。`RunJob#perform(customer_id, campaign_id, run_token)` 恢复 `Current.customer`，`Run` 检查有效租约／令牌并续租，每次最多处理 100 个到期待处理收件人。独立的五分钟核心恢复及 15 分钟回执对账见[后台任务](background-jobs)。

Run 在取得客户／活动锁后、每个收件人的联系人／收件人锁后，以及完成／统计更新前，重新采样时间。有效时间取显式 `at` 与 `Time.current` 中较晚者，不能用调用入口时间掩盖等待锁期间的租约过期。每个写入阶段先校验当前令牌与租约，再以锁内时间延长仍有效的租约。租约已过期或令牌已替换时，不得创建受众、接收其他收件人，或完成／刷新活动。

每个收件人的资格、截止时间、到期时间及滚动接收窗口均采用最新锁内时间，因此同一批次中先前已接收的记录会计入下一收件人的 60 秒上限。内部 `Gateway.send_campaign` 可接收 Run 传入的可选 `at:`，并以该时间与其当前锁内时间中较晚者记录预留；普通调用方省略此参数。预留时间在持久化前确定，不在写入后另取时间；幂等重放保留既有接收事实。共享账户节流仍是独立的最终派发限制，不能替代更低的活动接收上限。

| 限制 | 实际规则 |
| --- | --- |
| 预定开始／截止时间 | 立即发送以启动时间起算，定时发送以所选 UTC 时刻起算。`expires_at = intended_start + deadline_hours`（1–168，默认 24），延迟不重置。初始快照前到期则活动失败；开始后到期关闭剩余未尝试任务。 |
| 免打扰 | 本地整点 0–23，包含开始、不含结束，起止不可相同；默认 21–09。优先使用联系人当前有效时区，否则采用冻结活动时区（默认 `Asia/Shanghai`）。仅能延迟至截止时间前。 |
| 活动频次 | 1–168 小时，默认 24。按同租户同号码其他活动的 `dispatch_started_at` 判断，未知结果的尝试也阻止发送。直接事务短信不计作活动频次事实，但仍受核心号码额度限制。 |
| 活动接收速率 | 每分钟 1–60 人，默认 60；按滚动 60 秒收件人 `admitted_at` 预留计数，跳过者不占额度。 |
| 共享账户节流 | `Sms::DispatchLimiter` 锁定保留凭证，使用实时 `config["sender_rate_per_second"]`（`0 < rate <= 1`，默认 1）。`dispatch_next_at` 串行授权所有使用该行的租户／活动／直接发送，只预留当前可开始的尝试，不成批预订未来时段。 |
| 租户／号码额度 | 既有每日预算及适配器号码窗口仍生效。活动可延迟至确定的重置时间，零日额度直接跳过；延迟达到截止时间则到期。 |

最终派发事务在记录唯一尝试前检查当前有效状态、准确号码、明确同意、退订、模块、活动取消／失败／截止时间、免打扰、频次及到期时间。延迟释放准备领取，不产生尝试；恢复不能绕过 `delivery_due_at`。涉及的记录按客户 → 活动 → 联系人 → 收件人 → 消息 → 凭证顺序加锁，提交后才调用网络。节流限制持久化派发授权，不保证运营商每秒送达量。预览时长采用活动接收与账户节流中较低的上限，共享流量及免打扰可延长实际时间。

`Cancel` 对待发送／发送中／已取消活动幂等。它使执行令牌失效，取消待处理收件人，并仅在没有 `dispatch_started_at` 时抑制已关联排队消息；消息关联与接收事实保留。取消与派发开始共用串行锁：尝试先获准则继续执行，回执仍可更新。不支持撤回厂商调用、暂停／恢复或重发未知结果。仅未启动草稿可删除，已启动活动及报告保留。

### 基于台账的报告与 CSV

`Sms::Campaigns::Report.call(customer:, campaign:, refresh: false)` 从收件人及关联的同租户消息推导结果。GET／CSV 不写统计或启动执行；`RefreshStats` 是写侧可重建缓存。匹配数取收件人行数，开始时可发送数取联系人快照，已接收表示存在消息关联，已尝试取 `dispatch_started_at`，API 受理取 `sent_at`。收件人 `pending/admitted/skipped/cancelled` 属执行状态，与消息投递状态不同；取消后仍可保留历史接收关联。

已尝试／API 受理是历史节点，delivered／failed／unknown／queued／suppressed／expired 是当前结果；计数重叠，不可相加。送达率为已送达 ÷ 已尝试，尚无尝试时未知。终止原因含跳过及已接收后被阻止／取消的行，当前延迟另行统计。仅汇总服务商报告的正数段数，并展示缺失数，不从预览推算，也不作为费用报价。

报告可按收件人／消息状态、原因及姓名／号码筛选。`Sms::CampaignReportCsv` 按 ID 顺序每批 100 行输出全部筛选结果，不受页面大小限制；表头本地化，时间为 ISO 8601，公式前导文本转义。内容包括联系人／目标、收件人／消息状态、尝试／受理／送达／到期、失败代码及服务商段数，不包含变量、原始响应、证据、签名令牌或凭证。

## 需要特别注意

:::attention
号码、实体条目、登录账户、分群匹配或未退订均不代表同意。通过直接 Gateway／HTTP／工作流路径新发营销模板，也须有同租户有效联系人、当前号码已同意且无抑制。`Sms::Errors::MarketingIneligible` 继承 `TemplateVarsInvalid`（直接 HTTP 返回 422）；派发再次检查固定的营销用途／联系人。事务模板保留核心模块／退订／额度规则。
:::

:::attention
预览与启动固定不同事实：确认令牌短期检查已保存设置，启动固定规则／内容，执行开始固定名单／联系人／变量。预览人数不保证为最终收件人数；已引用分群缺失或分群输入无效时，绝不回退至全部联系人，冻结规则无效则在接收前失败。
:::

:::note
`completed` 表示收件人派发编排结束：已接收消息均已跨过尝试边界，或被抑制／到期。`sent` 为服务商受理，不是送达；`unknown` 为未决，不表示可重试。完成／取消后回调及查询仍可更新报告，不通过重发已尝试载荷来消除歧义。应用截止时间无法撤回已在服务商／运营商队列中的消息。
:::

## 关键代码

### 手动同步与分群输入

以下值仅作输入示例，不表示已有种子记录或自动授予许可：

```json
{
  "entity_id": 42,
  "phone_field": "mobile",
  "name_field": "full_name",
  "country_code": "CN",
  "timezone": "Asia/Shanghai",
  "attribute_map": { "city": "city", "vip": "vip" },
  "after_entry_id": 0,
  "through_entry_id": 2500
}
```

```json
{
  "type": "group",
  "joins": ["AND"],
  "conditions": [
    { "field": "country_code", "operator": "equals", "value": "CN" },
    { "field": "attributes.vip", "operator": "equals", "value": true }
  ]
}
```

### 字段、固定值及默认值映射

使用所选模板实际必需键（Twilio 可使用数字键）；无变量模板使用 `{}`：

```json
{
  "name": { "source": "field", "field": "name", "fallback": "Customer" },
  "offer": { "source": "literal", "value": "20%" },
  "opt_out_url": { "source": "field", "field": "unsubscribe_url" }
}
```

### 可信活动接收与调度器

`Sms::Gateway.send_campaign(customer:, recipient:, at: nil)` 是内部任务 API，返回 `Sms::Message` 并使用核心短信异常类型，不返回 `Sms::Result`。它重新读取已持久化的同租户运行中活动／收件人，校验启动快照、开始时资格、目标及准确变量，再检查当前营销策略，并固定活动内容／凭证。不接受任意快照或原始正文，无公开 HTTP 端点。稳定身份 `sms-campaign:<campaign_id>:recipient:<recipient_id>` 修复同一消息关联；消息接收及关联位于同一事务，仅在最外层提交后入队。

```ruby
# app/services/sms/gateway.rb
def send_campaign(customer:, recipient:, at: nil)
  Sms::Activities::Send.call_campaign(customer: customer, recipient: recipient, at: at)
end
```

```yaml
# config/recurring.yml — production
sms_campaign_scheduler:
  class: "Sms::Campaigns::SchedulerJob"
  queue: default
  schedule: every minute
```
