---
title: "后台任务"
summary: "生产环境的 Active Job 使用 Solid Queue，Solid Cache 与 Solid Cable 各用自己的 SQLite 数据库。"
---

## 概要

生产环境把 `config.active_job.queue_adapter` 设为 `:solid_queue`，并把 Solid Queue 指到 `queue` 数据库。Solid Cache 是 `config.cache_store = :solid_cache_store`，使用 `cache` 数据库。Solid Cable 是生产环境的 Action Cable 适配器，使用 `cable` 数据库。任务是 `app/jobs` 下的 `ApplicationJob` 子类。周期任务写在 `config/recurring.yml`。本应用没有 Sidekiq 配置。

开发环境没有设置队列适配器，因此 Active Job 的 railtie 使用 `:async`。开发环境缓存是 `:memory_store`，Cable 是 `async`。测试环境使用 `:test` 适配器与 `:null_store`。

## 流程

```text
perform_later / wait_until
        |
        v
Active Job
        |
        +-- production -> :solid_queue
        |                 database.yml  queue: storage/production_queue.sqlite3
        |                 进程：bin/jobs，或在设置了 SOLID_QUEUE_IN_PUMA 时由 Puma 插件启动
        |                 周期：config/recurring.yml 的 production:
        |
        +-- development -> :async（development.rb 未设置适配器）
        +-- test        -> :test

Solid Cache（production） -> 数据库 cache
Solid Cable（production） -> 数据库 cable，轮询 0.1 秒，保留 1 天
```

## 实现

`config/queue.yml` 有一个 dispatcher（`polling_interval: 1`，`batch_size: 500`）和一个 worker 池，队列为 `"*"`，3 个线程，进程数取 `JOB_CONCURRENCY`（默认 1），`polling_interval: 0.1`。development、test、production 共用这一段。`config/puma.rb` 只在 `ENV["SOLID_QUEUE_IN_PUMA"]` 有值时加载 `plugin :solid_queue`。`bin/jobs` 启动环境并执行 `SolidQueue::Cli.start`。生产 Docker 镜像设置 `SOLID_QUEUE_IN_PUMA=true`，由 Web 容器加载该插件；见 [Docker 镜像](docker-image)。

`config/database.yml` 的 production 有四个 SQLite 库：`primary`（`storage/production.sqlite3`）、`cache`（`storage/production_cache.sqlite3`，迁移目录 `db/cache_migrate`）、`queue`（`storage/production_queue.sqlite3`，`db/queue_migrate`）、`cable`（`storage/production_cable.sqlite3`，`db/cable_migrate`）。开发环境只有一个文件 `storage/development.sqlite3`。`config/environments/production.rb` 设置 `config.solid_queue.connects_to = { database: { writing: :queue } }`。`config/cache.yml` 的 production 设置 `database: cache`，`max_size` 为 256 MB。`config/cable.yml` 的 production 设置 `adapter: solid_cable`，`connects_to: { database: { writing: cable } }`，`polling_interval: 0.1.seconds`，`message_retention: 1.day`。

`ApplicationJob` 继承 `ActiveJob::Base`。该文件里的死锁 `retry_on` 与反序列化 `discard_on` 都是注释。具体任务都 `queue_as :default`。例子：

- `Billing::DailyBillingJob` 运行 ReconcileCollections、RenewSubscriptions、CollectDueInvoices、Dunning、TrialEndingNotices、RevokePaymentMethods、DispatchNotices，分别救援并隔离 Current。`Billing::CollectionMaintenanceJob` 每 15 分钟执行对账／撤销／通知派发。
- `Payments::ChargeDueSubscriptionsJob`、`Payments::RedriveWebhookEventsJob`、`Payments::DailyMaintenanceJob` 是支付周期任务。`Payments::ProcessWebhookEventJob` 对 `StandardError` 使用 `wait: :polynomially_longer`，最多 `ATTEMPTS`（5）次，然后把 webhook 事件标为 `failed`。
- `Emails::DeliverMessageJob` 最多重试 3 次，然后 `mark_failed!`。`Emails::SendActivities::SchedulerJob` 与 `ReconcileSendActivitiesJob` 是发送活动的周期任务。`Emails::ReconcileMessagesJob` 核对投递状态。
- `Sms::Campaigns::SchedulerJob` 每分钟领取／修复到期活动任务；`Sms::Campaigns::RunJob` 一次性捕获受众，按有界批次处理收件人。`Sms::DeliverMessageJob` 派发共用发件箱，不重试发送；`Sms::RecoverMessagesJob` 修复交接／准备并隔离已尝试崩溃。`Sms::ReconcileMessagesJob` 重投回执并查询投递状态。
- `AiAssistant::ReconcileGenerationsJob`、`SpeechToText::PruneClipsJob` 是其余周期类。`AiAssistant::ReplyJob` 与 `SpeechToText::TranscribeJob` 由请求触发。
- `Notifications::BroadcastAnnouncementJob.schedule` 排期开始推送，`ExpireAnnouncementJob` 排期精确结束刷新，并检查最新状态／结束时间。见[公告](announcements)。

`config/recurring.yml` 的 `production:` 在每小时第 12 分钟执行 `SolidQueue::Job.clear_finished_in_batches`；邮件及短信活动调度每分钟一次；短信恢复每五分钟一次；邮件、短信与 AI 的核对每 15 分钟一次；账单收款维护每 15 分钟一次，日常账单每天 3 点；支付扣款在第 5 分钟；支付 webhook 重放在第 20 分钟；支付维护在 4 点；语音片段清理在 4 点 45 分。该文件的 `development:` 是注释。文件自己的注释说明，若要在本地跑账单周期，用 `bin/rails runner` 执行 `Billing::DailyBillingJob.perform_now`。

### 短信发件箱生命周期

`Sms::Gateway.send` 在主库记录 `queued`，默认一小时到期，并固定模板／厂商编号／变量快照及凭证 ID／模式。接收时不调用厂商。`ActiveRecord.after_all_transactions_commit` 将 `Sms::DeliveryHandoff` 延后至全部外层事务提交；回滚会删除接收行及其入队回调。队列入队尽力执行，失败时已提交台账仍可供恢复使用。固定凭证身份不等于固定密钥／配置版本：任务与回执验签读取保留行的当前值。

恢复按上文周期扫描已提交的 queued 行。入队标记缺失或已过五分钟时可修复交接；准备领取滞留 30 分钟时可用新令牌重新领取。`Sms::DeliveryDispatch.start` 在外部操作前原子检查当前令牌，写入 `dispatch_started_at` 并增加 `delivery_attempts`；替换令牌隔离旧准备任务。在此边界前再次检查到期、模块启用及收件人退订，尚未尝试的行可变为 `expired` 或 `suppressed`。

`Sms::Campaigns::DeliveryPolicy` 增加当前营销联系人／有效状态／号码／授权检查，直接营销消息也适用；活动另检查免打扰／频次／取消／失败／截止时间。未来 `delivery_due_at` 限制交接、准备、开始及恢复。`Sms::DispatchLimiter` 锁定保留凭证，读取实时 `sender_rate_per_second`（`0 < rate <= 1`，默认 1），仅在持久授权当前到期尝试时推进 `dispatch_next_at`。所有使用该凭证的租户、活动及直接发送共用此时钟。延迟释放准备领取，不调用厂商，也不重置有效期；`wait_until` 入队仅作加速，不能替代数据库到期检查。账户节流限制派发授权，不保证运营商送达。

已尝试载荷绝不重发。超时、畸形接受应答及已尝试崩溃变为 `unknown`，已证实拒绝变为 `failed`。部分结果或扩展传输错误中的可用已校验厂商 ID 及应答／审计哈希会保留，供查询／提前回执关联。完成写入匹配不可变派发标记及原令牌或已清除的令牌；恢复保留唯一尝试令牌供真实迟到结果使用，但不会让该行再次可领取。语句／连接故障仅重试带隔离条件的台账写入，每次转换最多尝试三次，外部调用及回执投影不在重试内。完成写入耗尽后可用保留事实进行有界 unknown 记录，不倒退已保存的接受状态或终态回执。可恢复条件与排期不保证恢复或投递时间。

`Sms::ReconcileMessagesJob` 每 15 分钟执行，重投已认证回执，并查询声明 `query_supported?` 的适配器（阿里云与 Twilio，含 Twilio Message fetch 回调丢失兜底）。两分钟宽限及三天最大年龄，包括未决行超龄判断，均使用 `COALESCE(dispatch_started_at, sent_at, created_at)`：优先派发，历史行再回退至接受／接收时间。阿里云查询 SendDate 使用同一时间优先级并转为 `Asia/Shanghai`。更早的未决 pending／sent 变为 `unknown`，不标失败死信。迟到送达可修复 unknown／failed，后续失败不倒退 delivered。增量生命周期迁移仅将新行默认状态改为 queued，不补发既有 pending 行。API、抑制及诊断元数据见[短信](sms)，`send_sms` 事务性接收见[流程图运行时](flowchart-runtime)。

### 流程图步骤：enqueue_job

`enqueue_job` 步骤动作从流程图调度一个 `ApplicationJob` 子类。`jobClass` 引用 `job_classes` 来源（`app/jobs` 下的任务类），运行时再由 `FlowchartRuntime::Invocable.job!` 解析，因此不在允许名单内的类无法入队。`when` 为 `now`、`at`（`runAt` 表达式，必填）、`after`（`waitSeconds`，最长 30 天）或 `recurring`（`cronExpression` 与 `timezone`，或 `intervalSeconds` 加 `recurrenceLimit`；时间跨度上限 30 天，cron 或时区无效时校验失败）。`jobArgs`、`queueName`、`priority`（0–1000）可选。调度经 `FlowchartRuntime::JobSchedule` 完成；步骤把任务 id 写入 `resultVar`（默认 `enqueued_job_id`），失败代码为 `enqueue_job.failed`。`JobSchedule` 直接调用 `perform_later`，因此公开提交中的入队是否等到事务提交，取决于该任务类的 Active Job `enqueue_after_transaction_commit` 设置；入队的任务应保持幂等。字段见 [流程图步骤动作](flowchart-step-actions)。

### 短信活动调度与恢复

草稿保存／预览不产生发送任务。确认后启动提交冻结内容／设置／受众规则及凭证身份，设为 `scheduled`，并在最外层提交后尽力将 `Sms::Campaigns::SchedulerJob` 入队。生产 `sms_campaign_scheduler` 在 `default` 队列每分钟运行，开发环境无启用的周期项。一分钟为扫描间隔，不保证精确发送时间。

调度器每批扫描 100 个待发送／发送中活动，跳过未来排期，通过 `Current.set` 建立不依赖 URL 的租户上下文。令牌／租约缺失或过期时生成随机执行令牌与 15 分钟租约，否则续用有效令牌。它还修复到期收件人的继续执行及到期排队消息交接（使用一分钟交接恢复阈值），无需等租约到期。重复任务由租约／令牌、收件人锁及稳定消息键隔离。

`Sms::Campaigns::RunJob#perform(customer_id, campaign_id, run_token)` 按给定客户查询活动并恢复 `Current.customer`。`Run` 检查／续租；首次执行在单个事务内每批处理 100 条，构建完整收件人台账、联系人快照、解析变量及初始资格，与 `started_at` 原子提交。最多匹配 10,000 人。启动时冻结的规则只对当前联系人数据评估一次，快照提交后恢复不新增成员，也不重新计算个性化。快照／规则无效或受众超限均在接收前失败；快照前到期则活动失败，快照后到期关闭剩余未尝试任务。

后续每次最多处理 100 个到期待处理收件人，应用免打扰、活动频次、滚动接收速率、每日／号码预算及绝对截止时间。`Sms::Gateway.send_campaign` 通过既有核心发件箱接收，并原子关联每位收件人的唯一消息；回滚移除两者且不交接。延迟收件人／消息保留到期时间与原因；任务尽力安排下一到期时刻继续（至少延后一秒），以数据库／调度器恢复为准。

取消使执行令牌失效，并在与最终派发开始共用的串行锁内仅关闭待处理／未尝试排队任务。失败／到期活动同样关闭未尝试任务。存在 `dispatch_started_at` 后，沿用核心未知隔离及回执／查询处理，不再次发送。`completed` 表示派发编排结束，不代表全部收件人确认送达。报告从收件人／消息台账推导，执行／取消时刷新写侧统计，回执可尽力触发刷新；报告／CSV GET 只读。联系人／授权、开始时名单、策略及报告语义见[短信受众与活动](sms-campaigns)。

### 测试数据库与上传隔离

RSpec 框架使用 `config/storage.yml` 的 test Disk 服务。目录前缀取非空的 `ACTIVE_STORAGE_ROOT`，否则为 `<Rails.root>/tmp/storage`，先展开为绝对路径、去除末尾斜杠，再追加 `TEST_ENV_NUMBER`，确保各进程目录保持同级。第一个工作进程的后缀为空，使用 `tmp/storage`；进程 `2` 使用同级目录 `tmp/storage2`。显式前缀仍按进程划分：进程 `2` 将 `/tmp/my-run/storage` 转为 `/tmp/my-run/storage2`。开发／生产仍使用 `local` 服务及 `storage/` 目录。

`TEST_DATABASE` 指定独立、可重建的 SQL 数据库；未指定时，各测试进程使用 `storage/test<TEST_ENV_NUMBER>.sqlite3`。各自启动的验证运行须使用不同数据库文件和上传前缀。单进程网站验证的准备与运行始终采用同一环境：

```bash
ls -ld storage tmp /tmp/opencode
env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bin/rails db:schema:load
env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bundle exec rspec spec/config/active_storage_isolation_spec.rb spec/services/websites spec/services/feature_modules/website spec/requests/websites spec/models/website_spec.rb spec/models/website_page_spec.rb
```

取消 `SKIP_AUTH`，让授权检查使用真实门禁；单进程运行还须取消 `TEST_ENV_NUMBER`。仅向明确选定的可重建测试数据库加载 schema。优先通过常规 blob／附件接口清理；整目录删除仅限当前进程／运行独占分配的目录，不得删除共享父目录或开发／生产上传文件。`spec/support` 中未发现全局删除上传目录的钩子；存储隔离回归仅删除自身新建的第二个工作进程目录，再确认第一个进程的真实字节仍在。

附件测试数据须明确设置 `Current.customer` 或权威租户标记。残留的其他客户上下文可能触发租户拒绝，文案却与存储缺失相同，因此排查导入失败时须断言源文件存在。实际字节 MIME 及导入约定见[网站](websites)和[网站构建器](website-builder)。记录命令、范围及原始数量／日志；定向通过不替换历史全量验证证据。

## 需要特别注意

### 路由审计：持久交接及恢复不变量

主库台账提交与 Solid Queue 入队不是跨库同一事务。[短信](sms)使用已提交 queued 台账、提交后尽力入队及周期恢复，以令牌隔离唯一尝试，结果不明后不重发。[邮件](email)使用到期／入队／领取／尝试标记及 `Emails::Cron::RecoverMessages`，活动延后／进度及回执收件箱修复交接／关联。[支付](payments)保留验签正文／账户，投影失败重试，每小时重投失败／滞留 received。[账单](billing)保存永久尝试及事务性通知意图，提交后由 `DispatchNoticeJob` 处理；业务／入队意图去重不等于 SMTP 恰好一次。

AI 入队失败结束 generation 并创建可见失败轮次，轮询仅将有效 generation 标 pending。语音检查入队确认、有条件领取 processing，持久终态后清除音频。清理五分钟滞留阈值仍在每日 4:45 排期检查，不保证五分钟内恢复。支持回复仅在全部事务提交后广播。见 [AI 助手](ai-assistant)、[语音转文字](speech-to-text)、[支持工单](support-tickets)。

:::note
任务／发件箱／回执／到期及生命周期存储 API 已按源码及当前 schema 记载。网站后续验证仅加载独立测试 schema，并定向通过 572 个网站／存储用例。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。真实队列与 worker 重启证据仍须单独确认。
:::

:::attention
只有 `config/environments/production.rb` 把 `config.active_job.queue_adapter` 设为 `:solid_queue`。`config/environments/development.rb` 没有设置适配器。Active Job 的 railtie 随后在非测试环境赋 `:async`，在 `Rails.env.test?` 时赋 `:test`。开发环境里的 `perform_later` 走 `:async` 适配器，不会写入 Solid Queue 的表，除非另行设置适配器。
:::

:::attention
`config/recurring.yml` 把生效的周期表放在 `production:` 键下。该文件的 `development:` 键是注释。读取这份文件的调度器属于 Solid Queue，由 `bin/jobs`（`SolidQueue::Cli`）启动，或在设置了 `SOLID_QUEUE_IN_PUMA` 时由 `config/puma.rb` 的 `plugin :solid_queue` 启动。当该任务的适配器是 `:solid_queue` 时，`SolidQueue::RecurringTask#enqueue` 通过 `SolidQueue::Job.enqueue` 入队。这两处都没有选择 Sidekiq。
:::

:::attention
`Payments::ProcessWebhookEventJob` 在 `ensure` 里调用 `Current.reset`。`Current` 是请求状态。工作线程如果设置了 `Current.customer` 却不重置，同一线程上的下一个任务会沿用那个客户。
:::

:::attention
生产环境的 Solid Queue、Solid Cache、Solid Cable 各自使用 `config/database.yml` 里的库名（`queue`、`cache`、`cable`），不使用 primary 文件。开发环境的 `database.yml` 没有 `queue` 连接。`config.solid_queue.connects_to` 只在 production 里设置。
:::

## 关键代码

```yaml
# config/storage.yml
test:
  service: Disk
  root: <%= "#{File.expand_path(ENV['ACTIVE_STORAGE_ROOT'].presence || Rails.root.join('tmp/storage'))}#{ENV['TEST_ENV_NUMBER']}" %>
```

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store

config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
```

```yaml
# config/queue.yml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 0.1
```

```yaml
# config/recurring.yml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
  sms_recover_messages:
    class: "Sms::RecoverMessagesJob"
    queue: default
    schedule: every 5 minutes
  sms_campaign_scheduler:
    class: "Sms::Campaigns::SchedulerJob"
    queue: default
    schedule: every minute
  billing_daily:
    class: "Billing::DailyBillingJob"
    queue: default
    schedule: every day at 3am
```

```ruby
# app/jobs/notifications/broadcast_announcement_job.rb
def self.schedule(announcement)
  return unless announcement.scheduled?
  return if announcement.starts_at.blank?

  set(wait_until: announcement.starts_at).perform_later(announcement.id)
end
```

```ruby
# config/puma.rb
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```
