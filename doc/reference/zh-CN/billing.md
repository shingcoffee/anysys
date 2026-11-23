---
title: "账单"
summary: "持久化订阅意图、结算后生效的套餐变更、有限权益、优惠计次及平台统一收款。"
---

## 概要

账单是平台基础能力，不属于 `FeatureModules`。目录及策略管理位于 `/:cid/admin/maintenance/platform/billing/`，仅平台所有者可访问；租户订阅、账单及付款方式管理位于 `/:cid/admin/settings/billing/`，由管理员／所有者按 URL 租户范围访问。认证及租户隔离仍由控制器强制执行，参见 [authentication](authentication)。超出创建额度后，仍可读取、删除现有资源、管理安全设置及处理付款。

全局目录包括 Plans、PlanLimits、Coupons、CountableItems 和 Settings。租户记录包括 Subscriptions、PlanChanges、CouponRedemptions、Invoices、InvoiceLineItems、PaymentMethods、CollectionAttempts、InvoiceSequences 和 Notices。支付订单、扣款、凭据及定期支付授权属于平台客户 **81721200**，参见 [payments](payments)。租户账单 ID 不能直接授权访问平台 Payments 记录。

## 流程

```text
目录命令／Onboarding／租户订阅请求
    -> 持久化请求及已购买／目标权益快照
    -> GenerateInvoice（唯一永久标识）
    -> 提交意图事务
    -> FinalizeInvoiceJob -> FinalizeInvoice -> CollectInvoice（B）
    -> MarkInvoicePaid 事务：订阅 -> 账单
    -> ApplyInvoiceSettlement（A）-> 提交权益投影
```

每日续费协调器仅准备下一账期，不提前推进服务周期。支付尝试、对账、催收、授权及通知派发由账单收款分区负责。零金额账单也走同一结算钩子。人工收款账单在所有者确认结算前仍未付款，不能直接激活付费初始订阅或升级。

## 实现

### 订阅意图及快照

`Subscribe.call(customer:, plan:, coupon: nil, request_key:)` 返回 `Billing::Result`，状态为 `active`、`trialing`、`awaiting_payment`、`unchanged`、`conflict` 或 `invalid`。仅支持 USD／CNY。币种在受理时确定一次，`zh` 对应 CNY，其余对应 USD。快照包含 `plan_id`、`code`、`name`、`amount_cents`、`currency`、`interval`、`limits` 及宽限策略。目录修改不会重写已购买的额度或价格；旧快照缺少的新项目按零容量处理。

每个租户最多一条有效记录，包含 `pending`、`trialing`、`active`、`past_due`、`paused`。非试用的正价初始订阅先进入 pending，结算前使用免费回退权益。已受理账期不会随结算时间移动。普通请求按不可变到期时间及宽限期结束；零宽限期的初始／续费请求可在受理账期结束前付款，但未付时不提供已购买权益。延迟处理的零金额周期仍走同一结算钩子，不要求时间戳精确相等，也不移动受理日期。请求结束后的正金额款项须核对，不重新开通。付费试用设置 `customers.trial_used_at`，取消后重新订阅不能再次试用。免费开通后转付费套餐不再授予试用。

请求 UUID 在历史记录中永久保留，重放已取消的开通请求不会新增有效订阅或扣款。即使 cron 延迟，显式的新开通请求也可结束已超过逻辑期限的旧订阅，原欠款及历史仍保留。`Onboarding.call(customer)` 使用确定性的永久开通 UUID，检查已有有效免费默认套餐，恢复 `Current`，并在客户创建事务提交后调用。GET 不创建种子数据。`StandardPlans.seed!` 是显式命令，仅创建缺少的套餐、保留目录编辑和归档；免费种子额度为 page=10／entity=5／member=1。

### 逻辑有效订阅及重新开通

`Entitlements.current_subscription(customer:, at: Time.current)` 是统一的只读当前意图查询。`Subscription.live` 仍用于存储状态唯一性及后台任务，不代表可否重新开通。`PlanChangePolicy.expiration_at(subscription:, at:)` 根据实际试用／账期边界、预约取消及账单受理请求期限判断。尚未到期的 pending／paused 意图仍为当前订阅，即使权益来自免费回退。正常可续费的订阅在宽限期内不会被提前结束。零宽限期续费在调度延迟后仍可按原边界准备，只要下一受理账期尚未结束；账期仅在结算时推进。

租户 show／update／preview 使用逻辑查询。已结束请求单独作为最新历史传入，现有开通表单即可使用，不展示为当前套餐或未来预约。GET 不结束记录、不结算账单、不创建配置。已逻辑结束请求的变更预览返回 `no_active_subscription`；写入仍按客户→订阅→账单锁顺序重新校验。显式作废的未付初始账单属于已结束意图，以作废记录的更新时间为终止边界。

设置、服务商发现及默认就绪检查使用同一查询：已逻辑结束、但存储状态仍为 live 的旧记录，不能固定新授权的币种／周期。没有当前意图时，设置按初始规则确定币种，周期取月付。现有账单恢复明确使用其自身订阅及冻结币种／周期，不借用最新开通条款。

结束前，领域通过 B 的 `MarkInvoicePaid` 投影已记录的网关／人工／零金额结算；已验证的准时续费款项可以推进原订阅，避免误终止。此过程不调用服务商 HTTP，真实欠款及不可变财务条款仍保留。套餐变更遵守 B 的安全作废冲突：不确定账单／支付尝试继续保留以便对账，到期目标则进入终态。租户任何历史尝试仍处于 prepared／submitting／pending／SCA／unknown，或有未投影的捕获证据时，新开通返回 `conflict/collection_in_flight`。已结束请求的迟到款项记录为已付款待核对，不恢复订阅；不确定性消除后才可继续新的显式请求。历史 UUID 重放仍返回 unchanged。

默认目录尚未配置时，只读 `StandardPlans.starter_limits` 提供确定的入门版有限回退：**50 个页面、25 个实体、5 位会员**。读取不创建套餐、订阅、设置或计数项。已配置的有效免费默认套餐优先，包括平台有意设置的零额度。显式无效默认项仍报告 `fallback_configuration_invalid`，现有订阅付款恢复继续可用。没有目录默认项时，初始开通可以使用入门版回退，避免冻结新应用的注册及核心资源创建。

### 套餐变更、取消及续费

`ChangePlan.call(subscription:, new_plan:, request_key:)` 持久化唯一待处理 PlanChange。同目标／同键复用原账单，不同目标须先显式取消已有变更。同计费周期且当前币种价格严格更高时，生成 awaiting_payment 按比例升级请求；降价、同价、切换周期或试用中变更均安排在原边界生效。同套餐返回 unchanged。逾期、暂停、待付款订阅拒绝新变更；已预约取消须先恢复。

按比例计费用 Rational 时间比例及整数最小货币单位，不使用浮点金额，也不应用优惠券。`CancelPlanChange.call(subscription:, plan_change:)` 通过 B 安全作废关联未付账单；支付结果不明或已捕获款项时返回 conflict。已写入未付续费账单的预约目标也必须走该安全作废流程。替代账单使用边界键加 `:revision:<已作废数量>`，不会按执行日期生成键，也不会重写原账单。

`CancelSubscription.call(subscription:, immediately: false)` 取消可安全撤销的待处理变更，并保留当前边界前的访问权。所有者立即取消会终止权益，但保留真实欠款及历史。`ResumeSubscription.call(subscription:)` 仅在边界前清除预约取消，不恢复暂停／已结束订阅，也不恢复已取消变更。

`Renewal.prepare(subscription:, at: Time.current)` 返回 `invoice_ready`、`not_due`、`blocked` 或 `ended`。它选择预约目标快照或现有购买条款，准备／复用唯一下一账期账单，订阅日期不变。`ApplyInvoiceSettlement.call(invoice:, paid_at:)` 在 B 的已付款账单事务内一次性应用目标和账期，并记录 `entitlements_applied_at`，返回 `applied`、`recovered`、`unchanged` 或 `review_required`。按月／按年计算保留原日期意图，例如 31 日→二月末→三月 31 日；已受理的周期切换在边界重置锚点。

边界到达时，无未决付款的即时变更到期并安全作废，随后按原套餐续费。存在处理中的付款时，变更在快照宽限期内阻止冲突续费。有效结算应用目标后，仍从原边界续费，不追溯移动服务日期。宽限期结束后终止访问；已结束／过时意图的迟到款项须核对，不能悄然恢复权益。

### 欠款及有限权益

`RecordInvoiceDebt.call(invoice:, at:)` 仅记录续费欠款，`past_due_at` 固定取不可变 due_at。按比例升级失败不会让已购买的基础订阅逾期。`ExpireOverdueSubscription.call(subscription:, at:)` 按固定期限结束初始／续费请求，并保留未决付款证据。有效续费结算清除已解决的欠款；已结束订阅须显式重新开通。

`Entitlements.for(customer:, at: Time.current)` 是只读查询，提供 `source`、`plan_snapshot`、`expires_at`、`limits` 及可选配置原因 `reason`。购买／试用权益持续至边界，之后按不可变账单／订阅策略提供有限访问宽限期，即使 cron 延迟也不会无限延长。初始待付款、暂停、取消、到期及超过访问宽限期的客户使用有限免费回退。没有配置默认项时使用入门版额度；有意设置的零默认额度仍为零。目录修改不改变已受理购买额度，购买快照缺少的项目仍按零容量处理。只有客户 81721200 保留平台配额豁免；所有者访问其他租户 URL 不会转移该豁免。

仅发布 page／entity／member 配额。这些权威计数器统计总量，目录命令不允许将其改标为按月统计。会员用量只统计 member 角色账户，不计管理员；管理端创建用户仅在目标角色为 member 时调用该限制。可计数项页面列出全部目录行，开关可启用或停用任意一项。核心项缺失或停用时，守卫仍保持有限额度。存储、支持、通信及支付行可以开关，但不是已实施配额，用量返回 nil，不伪装为零。Quota 保留 `limit`、`usage`、`remaining`、`allow?` 接口，额度降低或回退不会删除数据。

### 优惠券及目录命令

`ApplyCoupon.call(subscription:, coupon:)` 原子预留库存，并创建包含受理条款的唯一 CouponRedemption。重复关联同一优惠券幂等，不能替换。到期、归档及库存限制仅约束新兑换，不撤销已受理优惠。期限从兑换开始计次：初始／续费账单中折扣前为正的订阅小计，在定稿时消耗一个周期。免费及按比例账单不计次；100% 折扣周期仍计一次。重复定稿／重试不会重复消耗，作废也不补回库存或次数。

`Discounts.reserve_for_invoice!(invoice:)` 在 B 的草稿定稿事务内运行，返回兑换／周期 ID、整数折扣及本地化描述键和参数。百分比／固定优惠不超过非负订阅小计，固定金额必须明确为 USD／CNY；先优惠后计税。已出具账单的财务行、条款、编号及日期不可变，策略修改仅影响新账单。

目录修改使用 `Catalog::SavePlan`、`SaveCoupon`、`ArchivePlan`、`ArchiveCoupon`、`UpdateCountableItems`。保存命令返回 saved／invalid、记录、保留提交值的 Reform `form` 及字段错误。套餐和经过校验的额度在同一事务保存。目录套餐没有额度行时为不限：新建表单留空、填 `-1` 或 `unlimited` 都会保存该标记。有效免费默认套餐必须启用、未归档、两种币种均为零、无试用，并为所有核心项设置有限额度。替换默认标志在同一事务清除原标志，数据库唯一索引防止多个默认套餐；无替代时不得归档／停用当前默认套餐。已引用套餐的代码／价格／周期身份不能重写，新定价应创建新记录。归档保留所有订阅／变更／优惠历史，外键阻止硬删除。

### 持久化、收款边界及部署

合并迁移 `20261011000100_add_billing_subscription_lifecycle.rb` 提供 A／B 所有账单表和列。唯一索引约束有效开通、请求身份、待处理变更、未决支付尝试、账单键、优惠周期、默认项和编号序列；限制性外键保护财务历史。授权收款归属以 `managed_by = billing` 为准，`metadata` 仅保存服务商关联信息。账单授权的 `next_charge_at = NULL`，普通 Payments cron 及激活／领取守卫必须遵守归属。平台账单令牌的 user_id 为空，并明确购买客户及授权人；普通会员令牌保留用户归属。

`Result.transaction` 在读取状态前取得 SQLite 写入保留锁，仅在调用方未持有事务时有限重试 busy 错误。锁顺序为订阅→账单→辅助记录，意图事务内不调用服务商 HTTP。B 负责不可变定稿、持久化编号分配、支付尝试结果、唯一 `MarkInvoicePaid` 入口及事务性通知／发件箱；A 仅调用固定接口，不执行服务商操作。

:::attention
授权部署前运行只读 `billing:repair_report`。它报告而非删除冲突历史：孤立外键、重复记录、租户／授权不匹配、未完成扣款、未投影成功款项、无效默认项／金额及不明优惠消耗。迁移拒绝已检测出的未解决冲突。重建历史快照带标记，账单行及编号不变，编号头取已有有效后缀最大值。历史授权账户不得按当前模式推断。

预检在**首次 DDL 或数据写入前**拒绝四类未解决历史证据：`unpaid_active_initial_intents` 标识完全没有已付基础周期账单的正价 active 订阅；独立的 `unpaid_active_current_periods` 标识当前完整账期缺少已结算基础周期覆盖的正价 active 订阅，即使更早账期已经付款；`unresolved_proration_intents` 标识没有对应永久目标的 draft／open／uncollectible 按比例账单；`invoice_payment_mismatch` 标识矛盾的显式支付／订单关联。报告保留订阅、账单、支付、订单 ID 及机器可读支付冲突原因，不按当前目录推断结算，不把草稿默认零金额当作已付款，不猜测目标，也不替换为其他支付。

历史已付人工账单可以没有 PSP 外键，已结算的零金额基础周期也属于付款证据。尚未出具的零金额草稿不是付款证据：正价 active 父记录会被拒绝，已有 pending 初始父记录则可保留受理草稿，留待正常定稿，但不获得权益投影收据。只要存在 PSP 外键，即使人工账单已付，也须核对支付／订单的平台归属、精确 `billing-inv-<invoice_id>` 关联、订单币种及双方金额。金额以 BigDecimal 主单位精确乘 100 与账单最小单位比较，不舍入、不换汇、不猜计价单位、不修改财务数据。历史目标／访问权仍须凭证核对后部署；未声称真实客户数据库实际存在这些问题。

当前账期的覆盖凭证必须属于同一订阅、租户及币种：可以由一条已付基础周期完整包含当前账期（包括较短的目标账期），或由首尾精确相接的已付基础周期链覆盖。没有权威历史意图的部分重叠账期按证据不足拒绝；仅已付按比例账单不能证明基础周期已结算。旧 schema 通过排除按比例明细识别基础周期；存在显式账单 `purpose` 时，仅 `initial`／`renewal` 可作为凭证。基础周期完整已付时，附带的已结算按比例账单仍有效。免费 active 订阅及历史 pending／trialing／past_due／paused／cancelled／expired 状态保留原日期、状态和债务。

实现入口为 `AddBillingSubscriptionLifecycle.report(connection)`：其中 `paid_recurring`／`covered` 递归 SQL 计算整个窗口的覆盖证据，私有方法 `ongoing_original_trial_sql(connection)` 为两项正价 active 检查提供相同试用条件。`AddBillingSubscriptionLifecycle#up` 在添加任何列之前调用报告；`billing:repair_report` 调用同一类方法，存在问题时以非零状态退出。该迁移／报告门禁独立于 `PaymentHistoricalBindingsV1` 账户关联修复，不增加运行时兼容路径。

两项正价 active 检查仅豁免确实仍在进行的原始试用：`started_at == current_period_start`、`current_period_end == trial_end`，且 `current_period_start <= now < trial_end`。续费后保留的 `trial_end`、已推进账期上的未来试用标记，以及已过期或尚未开始的原始 active 试用，均不能绕过结算检查。历史试用后的已付覆盖仍有效，原试用日期及使用标记均保留。

修复报告操作步骤：

1. 对目标部署数据库运行 `RAILS_ENV=production bin/rails billing:repair_report`。任务只读、没有 apply 模式，存在任何问题时以非零状态退出。保存报告，逐个订阅 ID 核对原账期、购买金额、试用日期，以及同租户／币种账单的日期、状态、明细和显式支付关联。
2. 对 `unpaid_active_current_periods`，必须证明**整个**当前账期。9 月 1 日至 10 月 1 日的已付账单，不能授权已推进至 10 月 1 日至 11 月 1 日、续费仍为 open 的 active 窗口；10 月到期宽限结束后仍然如此。宽限内的未付提前推进窗口同样不属于已结算购买账期。无永久意图的旧 schema 中，含糊的重叠促销账期须凭权威证据核对。
3. 部署前，由所有者依据权威证据核对原结算／访问意图，保留债务和财务历史。报告及迁移不会将账单设为已付、猜测服务商／账户／目标、回退日期或改变状态。核对完成后重新运行报告，解决所有问题再执行迁移；`up` 在任何修改前再次执行同一预检。
:::

### 迁移回归核验

`spec/migrate/add_billing_subscription_lifecycle_spec.rb` 从 `git show 91b89d3e:db/schema.rb` 原样重建相关表及既有外键。每个用例使用独立 ActiveRecord 连接和一次性 SQLite 文件；这些用例关闭 Rails 事务夹具，清理后检查应用连接池及配置仍为原对象。运行环境须保留固定 Git 对象。夹具直接写入历史行，不调用当前模型回调或服务商操作。

核验覆盖 USD／CNY 价格、计费周期、账期、账单号及折扣／税款带符号明细保留；有号／无号草稿、存续编号缺口及中间号删除后的序列最大值；Billing／Payments 授权明确归属；归档目录硬删除限制；预检记录 ID 证据；以及真实 SQLite 唯一性／外键／检查约束。当前账期回归覆盖宽限前后“上期已付／本期未付”的续费、保留的试用历史、完整／包含／相接已付窗口、不完整／重叠／外租户证据、已结算人工／零金额／按比例账单及历史状态。拒绝用例除比较全部旧行、schema 和授权调度外，还捕获 SQL，证明**没有尝试任何 DDL 或数据写入**。若最大编号已删除且无证据，无法恢复：迁移仅依据仍存续的有效后缀初始化。

原 QA 运行复现了七个真实 **MIG-L1**、**MIG-L2**、**MIG-FK1** 安全失败。修复生产预检后，未修改的旧 schema 迁移／支付回填测试组在 `TEST_DATABASE=storage/migration_verify.sqlite3`、随机种子 `81721200` 下通过，结果为 **58 个示例，0 个失败**；随后 A 配额／生命周期样本通过 **42 个示例，0 个失败**。拒绝用例比较前后所有历史行及 SQLite schema 定义，有效人工／归档／历史／精确平台支付关联仍能迁移，财务数据不重写。原始及跟进证据见 `docs/audits/2026-10-11-billing-migration-qa.md`。本次核验覆盖合成历史用例及独立连接，不代表真实客户部署验收。

2026-10-12 的 HIGH 跟进修复了原 58 个示例未覆盖的“账期已推进但未付款”缺口。一次定向运行通过 **90 个示例，0 个失败**（原 58 个＋新增 32 个），环境为 `RAILS_ENV=test TEST_DATABASE=storage/migration_final_verify.sqlite3`，随机种子 `81721200`。启动前已取消 DATABASE_URL、继承的 RUBYOPT／浏览器预加载、SKIP_AUTH、并行工作进程及浏览器夹具覆盖变量。“9 月已付／10 月未付”夹具的报告精确为 `{"unpaid_active_current_periods":[20]}`，在尝试任何 DDL／数据写入前拒绝，Billing 及普通 Payments 调度保持不变。源码依据、命令和 JSON 结果文件见同一迁移 QA 审计。

:::attention
RC-11 源码跟进本身未运行迁移或测试。当前 `db/schema.rb`（版本 `2026_10_11_190000`）已包含账单生命周期契约及历史支付关联。账单请求／路由核验使用独立、按 schema 加载的数据库；实际部署及支付服务商验收另行进行。B／C／F 契约见 `docs/audits/2026-10-11-billing-partition-a-handoff.md`；逻辑生命周期审计、已编写测试及历史数据预检缺口见 `2026-10-11-billing-rc11-lifecycle.md`。
:::

### 出具、支付尝试及收款策略

`GenerateInvoice.call(subscription:, purpose:, idempotency_key:, period_start:, period_end:, terms_snapshot:, plan_change: nil, extra_line_items: [])` 复用唯一账单身份，不替换冻结行。`FinalizeInvoice.call(invoice:)` 仅出具一次草稿、预留优惠／税并分配持久客户序列 `INV-<客户>-<至少五位后缀>`，不统计草稿数量。重复出具／结算不重新编号或计算财务条款。

`Result.collect_after_commit` 仅排入 `FinalizeInvoiceJob`，不在回调内调用收款 HTTP。任务拒绝真实未提交事务，本地定稿提交后才收款。`Cron::FinalizeDraftInvoices` 在每日续费前恢复已受理持久草稿，包括尚不属于订阅续费集合的 pending 初始账单及账期中按比例账单。`PlanChangePolicy.accepted_invoice?` 校验租户、币种、来源账期及目标状态。UUID／同目标重放仅重新排入同一草稿，重复 worker 仍保留唯一账单、编号、优惠周期及收款身份。提交后排队丢失时，以数据库草稿作为恢复依据。

`PlanChangePolicy.grace_deadline` 控制未付访问权，`request_deadline` 控制意图结束及结算资格。`Invoice#collection_deadline` 直接委托 `request_deadline`，扣款准入、重放及结算使用同一请求期限。零宽限期初始／续费请求可在不可变 `period_end` 前付款；受理数秒后成功扣款可授予剩余受理账期，付款前仍无已购买权益。按比例变更保留正常边界等待期。逾期任务结束原请求，不新建支付或开通。

财务状态 `draft/open/paid/void/uncollectible` 与收款状态 `ready/manual/blocked/pending/requires_action/retry_wait/exhausted/settled/stopped` 分开。`CollectInvoice.call(invoice:, trigger: :initial, at:)` 接受 initial／retry／recovery／reconcile，返回 succeeded／pending／requires_action／pending_manual／retry_scheduled／exhausted／skipped／blocked。`Collector` 准备唯一 CollectionAttempt 及相同请求键的平台支付，HTTP 前提交，再独立保存结果。unknown／处理中／SCA 保留原身份，对账投影已捕获支付并查询固定账户；通用查询错误不能证明交易不存在。Stripe 无已知 intent 的重放限 23 小时及账单截止时间。

`ApiError` 本身不代表拒付，收款通过 `Payments::Activities::AttemptSafety.definitive_rejection?` 判断。结果不明／未分类错误保留原支付／键及 unknown 尝试，不增加失败次数，也不安排新的扣款。权威拒付才释放尝试，允许排期或显式恢复。人工／零金额转换不调用服务商 HTTP，可在调用方事务内执行；正金额网关收款及服务商对账仍保留提交后执行守卫。

若定稿派发丢失，`ReconcileCollections` 还会恢复已受理并提交的草稿：日期与受理条款一致的 pending 初始账单、下一边界的续费账单，以及与待处理变更一致的 awaiting_payment 按比例账单。它复用 A 的 `accepted_invoice?` 校验，已结束／到期／过时意图不出具。订阅→账单锁内仅成功完成草稿转换的调用在定稿提交后排入现有 `FinalizeInvoiceJob`；回滚不排队，重复扫描不再安排处置任务。零金额账单本地结算，不排入收款任务。同一任务负责到期判断／初始收款，定稿时不再排入自身。每日初始收款集合及重复任务均经过唯一尝试／支付守卫，任一执行顺序都只扣款一次；过期领取不构成重新扣款许可。

仅确定失败提交增加 `attempt_count`。重试偏移以 `first_failed_at` 为绝对基准：`[1,3,7]` 通常为初次加三次重试后耗尽；延迟 worker 跳过已过偏移，不集中补扣。`[]` 表示不重试。付款方式缺失／不兼容只阻塞，不造尝试；人工账单不调用厂商。已出具策略不可变，`AuthorizeInvoiceCollection.call(invoice:, actor:, mode:, note:)` 仅由所有者为未结收款记录覆盖，不改财务条款。催收与初始收款选择不同集合，对账先于到期决策。

新扣款准备及提交前，账单客户／币种须与其自身订阅及受理快照一致。币种不一致时，在 PSP 提交前返回 blocked/currency_mismatch，而非等到结算才发现。历史未决操作仍可查询，以记录并核对真实款项。已知账户路由标识／模式变化会阻止重放／新收款，其后的否定查询结果不能将原尝试认定为交易不存在。

`Billing::Settings` 不再选择全局 `gateway_provider`，收款使用租户已验证默认方式。设置校验税率 0..10000 基点、非负宽限／通知天数及严格递增、唯一的正整数重试偏移。422 保留原无效排期项，不转为零或恢复默认；显式空排期保持为空。

`MarkInvoicePaid.call(invoice:, payment: nil, source:, paid_at:, actor: nil, reference: nil, note: nil)` 是结算入口。网关证明须匹配平台订单／账单、金额／币种、记录尝试／账户／键及捕获时间。人工结算要求所有者及非空凭据，拒绝未决捕获；零结算无需厂商。open／uncollectible 欠款可结算，已作废／结束／过时／重复捕获保留为核对事件，不自动恢复服务。先订阅后账单的锁内包含已付款转换及 A 幂等投影。

### 服务商授权、移除及通知

`AvailableProviders.call(customer:, currency:, interval: nil)` 仅为已实现 Stripe／支付宝及当前模式已配齐的平台账户返回描述。设置／默认就绪及供应商发现使用 `Entitlements.current_subscription`，账单就绪显式传入冻结币种／周期。PayPal／微信注册不代表账单设置可用。Stripe 使用确定性 Customer／SetupIntent 键及精确平台令牌。支付宝仅支持 **CNY 月付**，提供签名页面授权／服务端查询；年付或不兼容周期／额度／日历锚点频率要求重新授权。种子按月，所有者创建年付须匹配授权；账单支付宝操作按固定账户选择沙箱／正式环境。

`SetUpPaymentMethod.call(customer:, actor:, provider:, return_url:, request_key:)` 外部操作前保存租户方式／平台授权关联。pending 设置保留原默认方式。`PaymentAuthorization.confirm!(payment_method:, verified_event: nil)` 使用类型化已验签账户证明或服务端查询，浏览器 PSP ID／返回查询不能激活。已移除／过期方式不能被迟到成功恢复。`RemovePaymentMethod` 提交 removed／default=false，本地取消账单授权／令牌并记录待撤销；`RevokePaymentMethods` 重试远端收尾。默认选择为显式就绪校验命令。

已受理授权 metadata 保存含账户／供应商／商户／模式的 `billing_authorization_context`。Stripe 验签事件使用受理上下文，收款就绪拒绝后续账户漂移及历史授权审核行。`PaymentAuthorization.action_for(payment_method:, return_url:)` 仅读取既有精确 Stripe intent／customer 或签署支付宝交接；GET 不创建／重放设置、不保存引用／令牌、不激活。不兼容已完成设置不替换原就绪默认。未绑定历史方式仍可本地移除，不猜测当前账户收尾。

Stripe 身份按精确账户行及受理时的原 metadata 校验，不与当前可变商户路由标识比较；设置重试沿用原 metadata 参数。历史查询允许使用路由标识／模式编辑后的固定账户行，新设置／扣款仍检查配置漂移。Billing 支付宝历史查询／退款／关闭／撤销在已记录时使用受理模式。关联 metadata 不新增生命周期状态；历史凭证版本缺失及旧标识外部路由仍属[支付](payments)中记载的限制。

`Notifier` 在事务中保存唯一 Notice 业务事件意图，`DispatchNotices`／`DispatchNoticeJob` 提交后派发并恢复 pending。已付／出具按账单去重，失败按尝试，试用按结束时间，使用购买客户语言。`CollectionMaintenanceJob` 每 15 分钟对账、撤销及派发；通知去重不是邮件传输恰好一次保证。见[后台任务](background-jobs)及[支付](payments)。

## 需要特别注意

### 路由审计：服务端权威及端到端不变量

两套账单界面均属于 admin。租户记录按 URL 客户限定，所有者也一样；所有平台动作／格式要求固定所有者及实际外层 CID `81721200`。浏览器写入仅接受目录代码及稳定 UUID，价格／币种／租户／账户／令牌／返回 URL 由服务端决定。Result 决定真实 303 成功、422 无效及 409 冲突。失败表单保留实际 Reform form、原额度／重试输入及优惠／结算凭据。目录 DELETE 归档；计数项 GET 不创建种子。

已实现租户新增路由，前缀为 `/:cid/admin/settings/billing`：

| 动词／路径 | 契约 |
| --- | --- |
| GET `subscription/plan_change_preview?plan_code=...` | 只读 kind／effective_at／currency／subtotal_cents／tax_cents／total_cents／allowed／reason；受理命令重新计算 |
| DELETE `subscription/plan_change` | 取消有效订阅待处理变更，未决付款冲突为 409 |
| POST `payment_methods/setup_intent` | 固定 Stripe 及稳定请求 UUID，返回限定 Billing ID／action／确认地址及顶层 client_secret |
| GET `payment_methods/:id/authorization` | 仅限定操作／状态，厂商返回关联不激活 |
| POST `payment_methods/:id/confirmation` | 精确限定方式，服务端查询验证确认 |
| POST `invoices/:invoice_id/payment` | 限定恢复触发，租户不能覆盖收款模式 |

历史／目录使用固定每页 25 条 Pagy、确定顺序、转义字面 q 及白名单 status／tenant_id，分页保留语言／范围。显示以有效订阅存储币种为准。仅获准租户账单详情通过 `InvoicePaymentAction.for(invoice:)` 获取精确 Stripe SCA 尝试；操作响应 private／no-store／no-referrer，表格／下载／所有者详情不含密钥。下载仍为可打印 HTML／另存 PDF，不是生成 PDF 附件。见[租户与角色](tenancy-and-roles)。

租户端展示由 `Customer*` 子类负责；共享组件在 `customer_settings: true` 时委托给 `CustomerSubscriptionComponent`、`CustomerPaymentMethodsComponent`、`CustomerInvoiceTableComponent` 及 `CustomerInvoiceDetailComponent`，平台视图仍使用基础模板。三个租户页面（`subscription`、`payment_methods`、`invoices`）均包裹在 `Billing::Admin::CustomerBillingPageComponent.new(customer_id:, active:)` 中，由其提供页头与共用分区标签栏（套餐／付款方式／发票，当前标签带 `aria-current="page"`）；`active:` 仅限 `:plan`、`:payment_methods`、`:invoices`。装饰图标统一来自 `Billing::Admin::IconComponent`。

* **套餐**——当前订阅卡片（套餐名、状态徽章、价格、续订日期、计费周期、默认付款方式——视图以 `default_payment_method:` 传入有效的默认 `@payment_method`——以及「更换套餐」「管理付款方式」「查看发票」快捷入口）与 page／entity／member 用量卡片并列；无限额度只显示数量，不显示进度条。无订阅时卡片引导客户浏览套餐。套餐卡片（`li[data-plan-code]`）标记当前套餐，年付套餐附月均价，并打开 `#plan-review` 面板。优惠券与取消／恢复订阅卡片位于底部网格。
* **付款方式**——已保存的付款方式以卡片（`li[data-payment-method-id]`）呈现，含服务商、默认／状态徽章、账户、授权时间及扣款就绪状态；「移除」「继续授权」「设为默认」位于卡片底部。服务商授权区（`#authorize-payment-method`）始终展开，页头「添加付款方式」直接定位至该区。
* **发票**——`CustomerInvoiceSummaryComponent` 在发票记录上方显示按币种汇总的待付金额（链接至 `status=open`）、最近付款及下次续订或预定取消日期。控制器通过 `billing_invoice_summary(Billing::Invoice.for_current_customer, subscription:)` 生成概览。发票记录以 `compact: true` 嵌入 `HistoryFiltersComponent`，即标签视觉隐藏的单行工具栏；未付发票行高亮，其「查看」按钮为主按钮。

付款方式、套餐、优惠券经挂载视图／组件传入 `pagination:`／`page_path:` 并渲染 `Admin::PaginationComponent`，旧页可从 UI 访问。`Billing::ControllerPresentation` 仅适配请求：控制器保留认证、租户范围查找及所有者操作能力判断，再将账单计算委托给只读 `Billing::PresentationFacts` 查询 API：

* `usage(customer:)`、`coupon_benefit(subscription:, pending_change: nil)`、`subscription_actions(subscription:, pending_change:, at:)` 投影权威配额计数、受理优惠条款／剩余次数及取消资格。
* `subscription_recovery(subscription:, invoices:, entitlements:, actions:)`、`provider_options(customer:, currency:)`、`method_readiness(payment_method:, currency:, provider_options:)` 提供恢复链接／访问宽限期及服务商／默认付款方式就绪状态。
* `invoice_summary(invoices:, subscription:)` 接收已按租户限定的发票关系，返回 `outstanding`（open／uncollectible 发票按币种汇总）、`unpaid_count`、`last_paid` 及 `renewal`（仅 `active`／`trialing` 订阅；已预定取消时 `ends:` 为 true）。
* `invoice_collection(invoice:, owner_actions: false, at:)` 提供财务／收款状态、有效模式、下次尝试、原因及 `can_retry`、`can_mark_paid`、`can_void`、`can_authorize_collection`。调用方须先授权访问账单；`owner_actions` 是控制器确定的能力，不接受浏览器输入。`can_cancel_immediately?(subscription:)` 提供平台订阅取消资格。

查询不修改记录、不定稿／结算账单、不预留优惠，也不调用支付服务商。账单请求期限统一委托给 `Invoice#collection_deadline` → `PlanChangePolicy.request_deadline`；恢复访问宽限期仍取 `PlanChangePolicy.access_deadline`。零宽限期的初始／续费请求在受理账期结束前仍可恢复。uncollectible 财务状态不会遮蔽未决／SCA／待对账收款状态，且可在请求期限内使用就绪方式显式恢复。无效／矛盾出具策略显示 unavailable，不借当前设置。投影不含凭据；方式就绪使用 `charge_ready`、`ready`、`default_eligible`、`reason`／`reason_key`，服务商使用 `enabled`／币种兼容。分页子集不能证明全部保存方式均不可用。命令仍在锁内重查权威状态。

套餐预览 GET 对 HTML 渲染订阅审核页面，对 JSON 返回固定预览字段。变更失败保留所选审核、提交 UUID 及 Reform form。已受理草稿等待异步定稿时，以 303 跳转并提示待付款；只有命令返回 `applied` 才提示变更已生效。设置／确认 URL 使用服务端生成的限定请求来源及 Billing 方式身份，不接受客户端返回地址或 PSP 令牌提示。外层 CID 非 `81721200` 的平台路径，即使已认证所有者访问也返回 404；角色不符访问正式平台路径仍被授权守卫拒绝。

:::note
2026-10-11，在 schema 版本 `2026_10_11_190000` 执行 `db:schema:load` 后，使用 `RAILS_ENV=test TEST_DATABASE=storage/billing_c_verify.sqlite3` 运行完整账单请求／路由测试组，结果为 **313 个示例，0 个失败**。本次核验覆盖账单 HTTP／查询整合，包括无效表单保留、异步草稿提示、生成的授权 URL、租户／平台守卫及恢复投影。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。实际部署及支付服务商、浏览器、并发验收仍独立于这两次运行。RC-11 交接仍保留明确历史财务记录核对要求。
:::

## 关键代码

```ruby
result = Billing::Activities::ChangePlan.call(
  subscription: subscription, new_plan: target, request_key: request_uuid
)
# result.plan_change 和 result.invoice 可重新加载；awaiting_payment 仍未付款。

prepared = Billing::Renewal.prepare(subscription: subscription, at: Time.current)
# 此处不推进账期；B 仅在意图提交后定稿／收款。

entitlements = Billing::Entitlements.for(customer: customer)
# entitlements.source / limits / expires_at；查询不会开通订阅。

collection = Billing::PresentationFacts.invoice_collection(invoice: authorized_invoice)
# collection[:state] / [:can_retry] / [:deadline]；只读，不含 PSP 密钥。
```
