---
title: "支付"
summary: "网关注册、已提交支付尝试、验签账户绑定结算及定期收款归属。"
---

## 概要

`FeatureModules::Payment::Registration`（键 `payment`）通过支付宝、微信、Stripe、PayPal 完成收款、退款、订阅及对账。注册／凭据发现使用一个 Base 子类及 `register!`，不需厂商专用迁移或商户列。结算处理仍按供应商实现；仅注册不会自动实现新厂商回调或账单语义。

客户把 `Payments::MerchantAccount#status` 设为 `"active"` 并填好凭证 JSON，该网关才参与收款。结账和 `Payments::CredentialResolver` 只保留 active 行。平台是否开放该网关是 `Payments::PlatformGateway` 上的另一面开关。

## 配置支付供应商

1. 在 `/81721200/admin/maintenance/platform/module_settings/payment/gateways` 开放要提供的网关，再到 `/:cid/admin/maintenance/modules` 为各客户启用支付模块。
2. 在 `/:cid/admin/settings/modules/payments/merchant_accounts` 编辑该客户的 **Sandbox** 或 **Production** 行。将预置的 `unset-...` 商户标识改为该供应商下**跨客户唯一**的值，填齐下文的**所有**凭证字段，然后启用该行。Rails 生产环境只用 `production` 行，其他环境只用 `sandbox` 行。平台关闭网关也会停用租户账户；重新开放后仍需逐一启用。
3. 将通知端点部署到可从公网访问的 HTTPS 域名，设置 `APP_HOST` 为公网主机。公开的 `POST https://<host>/payments/webhooks/<provider>` **不带租户前缀**。生产环境的 `force_ssl` 会生成 HTTPS URL；开发环境的路由辅助方法则默认生成 HTTP URL，除非另行配置 HTTPS。应在实际运行环境核对支付宝／微信订单的 `notify_url` 和支付宝 WAP 的买家返回地址。租户可选的通知地址覆盖项仅影响回调，**不影响**支付宝的买家返回地址。微信支付请求不会附带买家结果页 URL。结果页 `/:cid/payments/result/:out_trade_no` 不是 webhook。应以真实付款及通知验证接通情况；支付宝和微信的**连接测试**仅返回预设成功，不会请求厂商。

生产环境启动必须提供 `APP_HOST`、安全的 `APP_PROTOCOL`（默认 `https`），以及合法的可选 `APP_PORT`。邮件和网关共用经过校验的应用 `default_url_options`；网关不会重新读取环境变量，也不会回退到 localhost。缺少主机时，唯一例外是设置 `SECRET_KEY_BASE_DUMMY=1`，且顶层任务**仅为** `assets:precompile`：此时 `assets-build.invalid` 明确标记为构建元数据。服务器、工作进程、迁移及混合任务仍执行严格的运行配置校验。

### 支付宝（`alipay`）

1. 在[支付宝开放平台](https://openhome.alipay.com/platform/developerIndex.htm)创建并审核应用，开通所需网页或移动支付产品，配置 **RSA2 公钥模式**。将应用 **App ID** 填入商户标识，将**应用私钥 PEM** 填入 `private_key_pem`，将**支付宝公钥 PEM** 填入 `platform_public_key_pem`。适配器使用公钥模式，不能填写证书模式的文件。参见支付宝[官方 SDK 配置](https://github.com/alipay/alipay-easysdk/blob/master/java/README.md)。
2. 开放 `POST https://<host>/payments/webhooks/alipay`；应用会在支付请求中传入该 `notify_url`。H5/WAP 请求还会传入浏览器结果页地址。分别核实扫码、H5 和应用内支付权限；应用内支付需要买家 ID，周期代扣还需要单独开通协议产品。
3. 普通非账单 API 使用 `https://openapi.alipay.com/gateway.do`，应用 Sandbox 行也一样。账单授权／收款按配置选择沙箱／正式端点；历史 Billing 查询／退款／关闭／撤销在已记录时使用受理模式。须以交易及签名通知验证所用流程／环境。

### 微信支付（`wechat_pay`）

1. 申请商户号（`mchid`），绑定具备支付权限的公众号或小程序 AppID，按业务开通 [JSAPI](https://pay.weixin.qq.com/doc/v3/merchant/4015423216)、[H5](https://pay.weixin.qq.com/doc/v3/merchant/4015614193) 及 Native 产品。在商户平台登记实际的 [JSAPI 支付授权目录](https://pay.weixin.qq.com/doc/v3/merchant/4013287088)和 [H5 支付域名](https://pay.weixin.qq.com/doc/v3/merchant/4013287193)。JSAPI 还需要该 AppID 下付款人的 OpenID。
2. 将 `mchid` 填入商户标识，填写 `appid`、32 位 `api_key_v3`、商户 API 证书的 `private_key_pem`、微信支付 `platform_public_key_pem` 和商户证书序列号 `wechat_cert_serial`。这些**不是同一把密钥或证书**；参见微信[APIv3 参数说明](https://pay.weixin.qq.com/doc/v3/merchant/4013070756)与[证书说明](https://pay.weixin.qq.com/doc/v3/merchant/4024350132)。使用前确认商户的微信平台证书／公钥模式与适配器验签方式匹配。
3. 确保订单生成的 `notify_url` 指向 `https://<host>/payments/webhooks/wechat_pay`（也可使用租户覆盖地址），须满足微信的[公网 HTTPS 回调要求](https://pay.weixin.qq.com/doc/v3/merchant/4012075420)。**退款结果通知需单独配置：**在微信商户平台的**交易中心 → 退款管理 → 退款配置**填入同一公网回调地址；适配器发起退款时未传可选的 [`notify_url`](https://pay.weixin.qq.com/doc/v3/merchant/4012791862)，订单回调不会自动用于退款通知。适配器在 Sandbox 行也始终请求 `api.mch.weixin.qq.com`，尚未实现协议代扣。应验证真实扫码、H5 或 JSAPI 支付、退款及通知，不要只看**连接测试**。

### Stripe（`stripe`）

1. 在 [Stripe 控制台 → API keys](https://docs.stripe.com/keys) 获取 Sandbox 行的 `sk_test_...` 与 `pk_test_...`。在 [Workbench → Webhooks](https://docs.stripe.com/webhooks) 建立 **Your account／snapshot events／webhook endpoint** 目标，地址为 `https://<host>/payments/webhooks/stripe`，复制其 `whsec_...` 签名密钥。分别填写 `secret_key`、`publishable_key`、`webhook_signing_secret`，并设置租户唯一的商户路由标识（应用会写入 Stripe 对象的 metadata）。
2. 订阅 `payment_intent.succeeded`、`setup_intent.succeeded`、`refund.updated`、`charge.refund.updated` 及 `charge.dispute.created`、`.updated`、`.closed`。在 Stripe 账户中启用所需[支付方式](https://docs.stripe.com/payments/payment-element)；应用通过 Payment Element 完成卡支付。
3. Production 行须使用独立的 `sk_live_...`、`pk_live_...` 和**正式环境 webhook** 自己的 `whsec_...`。每个环境都要验证结账、签名回调，以及所需的绑卡与退款流程。[测试与正式环境的密钥、端点](https://docs.stripe.com/keys)彼此独立。

### PayPal（`paypal`）

1. 在 [PayPal 开发者控制台 → Apps & Credentials](https://developer.paypal.com/api/rest/)创建或选择 **Sandbox REST 应用**，复制 Client ID 和 Client secret。在**同一应用**的 Webhooks 下添加 `https://<host>/payments/webhooks/paypal`，复制其 **Webhook ID**。填写 `client_id`、`client_secret`、`webhook_id` 及租户唯一的商户路由标识（应用将其写入订单 `custom_id`）。参见[官方 webhook 配置说明](https://developer.paypal.com/api/rest/webhooks/rest/)。
2. 订阅 `PAYMENT.CAPTURE.COMPLETED`、`PAYMENT.CAPTURE.REFUNDED` 及 `CUSTOMER.DISPUTE.CREATED`、`.UPDATED`、`.RESOLVED`。使用真实沙箱签名通知；[模拟事件不支持回传验签](https://developer.paypal.com/api/rest/webhooks/rest/)。退款请求现包含商户 `custom_id`；旧版／提前回调按供应商限定的本地退款号、账单号或 capture 关联路由，不访问未验签链接。钱包／游客卡选项取决于资格。
3. 为 Production 行在 **Live** 下重新取得应用凭证、建立 webhook 并填写对应 Webhook ID；参见 [PayPal 上线指南](https://developer.paypal.com/api/rest/production/)。适配器会切换沙箱与正式 API；尚未实现 PayPal 订阅、绑卡和账单下载。

## 流程

```text
平台所有者把 Payments::PlatformGateway 标为 available
        |
        v
FeatureModules::Payment::Provisioner
        |  每个 (客户, provider, mode) 一行 MerchantAccount
        |  merchant_id 为 unset-<provider>-<mode>-<id>，status 为 disabled
        v
管理员把 status 设为 active 并写入凭证 JSON
        |
        v
Payments::EligibleGateways
        |  平台已开放 AND configured? AND 币种匹配
        v
Payments::Activities::Charge（以及退款、订阅、绑卡、对账）
        |
        v
Payments::Gateway -> Payments::Gateways::<Vendor>#charge
        |
        v
POST /payments/webhooks/:provider
        |
        v
Payments::WebhooksController
        v
Payments::WebhookDispatcher
        |  先 extract_merchant_id，再 verify_notification
        v
Payments::WebhookEvent + Payments::ProcessWebhookEventJob
        v
Payments::Activities::HandleWebhook
```

公开结账是 `/:cid/payments/checkout` 上的 `Payments::CheckoutsController`。成员绑卡是 `/:cid/member/payments/payment_methods` 上的 `Member::Payments::PaymentMethodsController`。这两条分别是公开 URL 和成员 URL，不在四个管理面里。

## 实现

### 一个网关文件

`Payments::Gateways` 是指向 `app/services/payments/gateways` 的 `PluginRegistry`，`defaults: false`。注册表没有全局默认网关。子类声明 `key`（写入 `MerchantAccount#provider`，并出现在回调 URL 里）、`display_name`、`credential_fields`、`supported_flows` 和 `capabilities`。`supported_flows` 取自 `:qr`、`:h5`、`:jsapi`、`:card`。类实现 `extract_merchant_id(headers, body)`，实例实现 `charge`、`query`、`refund`、`close`、`subscribe`、`cancel_subscription`、`charge_subscription`、`download_bill`、`verify_notification`。卡组织网关再实现 `vault_card`、`detach_token`、`charge_token`、`fetch_payment_method`。`register!` 写在类体末尾。

`extract_merchant_id` 通常在验签前提供路由提示。精确记录的 Stripe／PayPal PSP 操作按已固定的历史账户路由，不依赖当前环境模式；已知但未绑定或关联不唯一的本地操作被拒绝，须离线修复。Stripe 事件既无本地关联也无路由提示时，可先通过官方签名校验器认证唯一的保留账户，再返回路由；无效或共享密钥导致的歧义会被拒绝。仅有 ID 的载荷不是认证。`event_id` 是 `Payments::WebhookEvent` 的去重键；为空时，`WebhookDispatcher` 在请求内直接调用 `HandleWebhook`。

`POST /payments/webhooks/:provider` 的路由约束在请求时读取 `Payments::Gateways.keys`。`routes.rb` 不列举厂商名。`Payments::WebhooksController` 继承 `ActionController::API`（无会话、无 CSRF）。`alipay` 的响应正文是 `success`。其他厂商是 `head :ok`。`SignatureInvalid` 为 400。`TenantNotFound` 为 404。

`Payments::Gateway` 是门面。新操作由 `CredentialResolver.call` 要求运行模式下的 active 账户（生产为 `production`，其余为 `sandbox`）。`by_merchant_id` 可使用保留的已停用账户验签。`for_payment(customer:, payment:, historical: true)` 默认按精确历史行及客户／供应商查找；`historical: false` 还校验受理时的商户标识／模式快照。门面的新写入必须同时满足该严格绑定及 active、已配置、平台已开放条件。历史查询／退款／关闭拒绝不同的显式商户，允许同一保留行的标签／模式修改，绝不替换为当前模式的新账户。

### 商户账户

`Payments::MerchantAccount` 按租户隔离。唯一约束是 `(customer_id, provider, mode)`，以及另一条 `(provider, merchant_id)`。厂商密钥在加密的 `credentials` JSON 里。用 `credential` 读取。`write_credentials` 在新值为空时保留原值。`configured?` 要求 `enabled?`、商户号非空且不以 `unset-` 开头，并且每个 `credential_fields` 名称都有值。`STATUSES` 为 `active` 与 `disabled`。

`Payments::EligibleGateways.for` 保留同时满足这些条件的网关：在 `PlatformGateway.available_providers` 中、当前 mode 有已配置的 active 账户、`supported_currencies` 包含请求的币种。`Payments::SetDefaultGateway` 只为该集合中的 provider 写入 `Payments::DefaultGateway`。

`FeatureModules::Payment::Provisioner` 为每个平台已开放的已注册网关，在 `sandbox` 和 `production` 各建一行 disabled 记录。`revoke` 把该客户全部账户改成 `disabled`，JSON 保留。`PlatformGatewaysController` 关闭某个平台通道时，同样禁用该 provider 的租户行。打开时会补齐缺失行。

### 活动

`Payments::Activities::Charge` 锁住订单，拒绝已结清或已过期的订单，用 `Payments::FlowSelector` 选择流程，再调用 `Payments::Gateway.charge`。只有网关 `capabilities` 含 `:tokenized_cards` 且存在用户时才转发 `save_card`。同级活动还有 `Query`、`Refund`、`CreateSubscription`、`CancelSubscription`、`ChargeToken`、`VaultCard`、`Reconcile`、`HandleWebhook`。通知金额存在且与 `payment.amount` 不一致时，`HandleWebhook` 不会把支付标成已付。

交接输入合同（金额、币种 `CNY`、标题、可选备注、`expires_at`、`metadata`）写在注册类上。完成时返回 `payment_reference`、`status`（`succeeded` 或 `failed`）和 `paid_at`。流程图步骤如何调用模块见 [flowchart-runtime](flowchart-runtime)。

### 流程图步骤

`request_payment`（字段 `amount`、`currency`、`subject`，均为表达式）不在提交内创建订单或扣款。`FlowchartRuntime::Payments.request` 用 `Payments::Money.normalize` 规范化金额、把币种转为大写，检查支付模块已注册交接且对运行客户启用，然后写入 `ctx[:submission_outcome]["handoff"] = { "module_key" => "payment", "input" => { amount, currency, subject } }`。运行成功后，`PublicPagesController` 用该输入启动支付交接，由 `Payments::CheckoutsController` 创建唯一的 `Payments::Order`（`build_order_from`）。失败代码为 `request_payment.invalid_order` 与 `request_payment.module_disabled`。这与原设计不同：原设计由步骤自行创建待支付订单。

`refund_payment`（字段 `payment`、`amount`、可选 `reason`）调用 `FlowchartRuntime::Payments.refund`。支付必须属于运行客户（否则 `refund_payment.not_found`）；退款在 `Current.set(customer:)` 下运行 `Payments::Activities::Refund`。`Payments::Errors::RefundNotAllowed` 映射为 `refund_payment.not_captured`、`non_positive`、`exceeds_remainder` 或 `billing_collection`；其他支付错误为 `refund_payment.failed`。见 [流程图运行时](flowchart-runtime) 与 [流程图步骤动作](flowchart-step-actions)。

### 历史数据预检

仅修复数据的迁移 `20261011190000_backfill_payment_historical_bindings.rb` 与 Billing 财务生命周期迁移独立。部署前，请对目标数据库执行离线预检：

```bash
RAILS_ENV=production bin/rails payments:historical_bindings:preflight
RAILS_ENV=production bin/rails payments:historical_bindings:apply
```

版本化修复仅接受已明确保存的账户 ID，或与已记录支付操作 ID／已验签事件签署方一致的唯一 `(provider, merchant_id)`。它校验租户／供应商归属及关联冲突；某客户在某供应商下只有一个可用账户，不构成充分证据。缺失、冲突、跨租户或格式错误的证据按记录 ID 报告。应用修复或迁移发现未解决项时，会在写入前拒绝整个计划，不会悄悄猜测。

修复仅补充 `_attempt` 身份或服务端 `_anysys_verification` 封装，保留金额、状态、时间、订单／交易／退款号及原载荷字段。它不会重建或授权旧财务重试；新恢复的尝试身份标记为 `historical_identity_backfill`，供后续对账。迁移回退明确为不可逆。请求路径没有兼容／补写分支，不执行 PSP／网络查询，也不改写 Billing 生命周期行。明确商户证据已丢失时，应先依据权威 PSP／事件记录在外部核对，再重跑预检；运行时仍拒绝未绑定记录。

迁移边界测试现位于 `spec/migrate/backfill_payment_historical_bindings_spec.rb`，既有服务测试保留供应商／证据矩阵。迁移测试按 `91b89d3e:db/schema.rb` 重建 SQLite 表并写入尚无身份封装的真实旧结构行，核验签署方／操作 ID 确定性映射、重复应用稳定性、证据缺失／歧义／跨租户时拒绝整个计划，以及不可逆回退。它们逐项比较完整旧财务／用户／退款记录和表结构，仅允许新增身份封装。版本化修复中继承 Base 的行类在子进程内使用该一次性数据库，RSpec 应用连接池不重新配置；不执行服务商操作。精确专项结果及共享夹具说明见 `docs/audits/2026-10-11-billing-migration-qa.md`。

### 四个面

| 面 | 路径 | 控制器 |
| --- | --- | --- |
| 条目 | `/:cid/admin/modules/payments/transactions`、`/reconciliations`、`/disputes` | `Admin::Modules::Payments::TransactionsController`、`RefundsController`、`ReconciliationsController`、`DisputesController` |
| 客户设置 | `/:cid/admin/settings/modules/payments/merchant_accounts` | `Admin::Settings::Modules::Payments::MerchantAccountsController`、`DefaultGatewaysController` |
| 启用 / 停用 | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`、`ModuleEnablementsController`（`provision!` / `revoke`） |
| 平台设置 | `/:cid/admin/maintenance/platform/module_settings/payment/gateways` 与 `/webhook_events` | `Admin::Maintenance::Platform::Payments::PlatformGatewaysController`、`WebhookEventsController`；共用窗格在 `ModuleSettingsController` |

`TransactionsController` 列出 `Payments::Payment.for_current_customer.commerce`，排除 `external_ref` 以 `billing-inv-` 开头的订单。本模块不提供后台「订阅」页：组织自身的套餐、付款方式与发票统一在「设置 / 账单」（`/:cid/admin/settings/billing/*`，见[账单](billing)）中管理，`/:cid/admin/modules/payments/subscriptions` 返回 404。会员仍可在 `/:cid/member/payments/subscriptions` 查看并取消本人的 `payments_managed` 银行卡订阅。`Refund` 拒绝 `billing_collection` 支付。账单授权不在此模块取消。注册类的 `entries_for("transactions")` 是另一条关系：支付模块的 `FeatureModules::Log`。侧栏链接指向专用控制器。

模块键是 `payment`。URL 段是 `payments`。

通用支付配置页（`/:cid/admin/settings/modules/payments`，可从「设置 / 支付」中的 `/:cid/admin/settings/modules/payments/return_url` 进入）中的可选返回网址，仅在平台所有者为支付模块开启交接后提供。它是用户经页面交接完成付款后的客户级备用跳转位置；页面单独指定的退出目标优先生效。交接开启时，独立付款结果页的「返回」按钮也使用此网址。关闭交接会隐藏表单，并暂停使用已存网址（但保留原值）；独立结果页改用默认返回位置。它不会更改支付网关的通知回调、买家返回地址或商户账户设置。各模块的用途与回退顺序见[模块框架](module-framework)。

## 需要特别注意

### 路由审计：结账、结算及定期收款不变量

公开结账／状态／结果允许外租户已登录访客，仍保留 URL 租户订单／支付范围及 `current_tenant_user` 卡片归属。默认供应商统一复用。交接扣款／完成除令牌外，还要求调用派生订单号及金额身份。金额按币种归一后须有限且为正，用户补填字段必须是标量；调用缺失回退公共根路径。见[模块框架](module-framework)及[租户与角色](tenancy-and-roles)。

`PrepareAttempt` 在 HTTP 前提交身份，在 `_attempt` 固定供应商／流程／用户、金额／内容、账户／模式及操作参数；pending 重试保留原流程／载荷。确定拒绝可失败，结果不明保留身份／预留。`AttemptSafety` 将 Stripe 单次／令牌扣款／退款重放限制为 23 小时，之后对账。结账在供应商选择 POST、创建 PaymentIntent 前收集同租户会员 Stripe 保存卡片同意，后续组件不能更改固定同意。网关扣款／令牌扣款使用已提交合规账户及已记录 IP，不重新选择环境。

Billing 收款共用 `AttemptSafety.definitive_rejection?`：普通 API 异常或形似“未找到”但未分类的载荷，都不能释放原操作身份。不确定写入可能已完成扣款，恢复须先对账同一支付，再考虑再次提交。确定拒付才允许使用新键发起尝试，成功结算仅应用一次。已提交收款回归测试通过第二连接核实持久记录，并验证不确定响应后不会发生第二次扣款。

Billing 零宽限期扣款使用受理请求期限，不使用未付访问宽限期：初始／续费请求可在固定账期内收款并应用有效捕获款项，付款前不授予已购买权益。恢复定稿只在提交后安排现有处置任务，每日批次及重复投递共用唯一收款尝试。逾期且已结束的请求不能授权再次提交 PSP。

Webhook 记录通过服务端专用 `_anysys_verification` 载荷保留验签账户 ID 及原正文。已验签的支付／退款结算绑定该账户行，不再比对当前可变的商户路由标识；验签账户缺失时抛出可重试的凭证错误。供应商／客户、声明金额／币种及 PSP 身份检查继续生效。`ProcessWebhookEventJob` 在短行锁内领取十分钟的 `_anysys_processing` 租约，释放事件事务后运行处理器及供应商 HTTP，仅在投影成功且领取令牌仍匹配时记为 processed。失败投影释放租约；过期领取可恢复，旧工作进程不能完成或清除后继领取。租约到期／恢复期间仍依赖领域处理器的幂等性。主库／队列库分离，滞留 received 行仍需每小时重投。使用已停用历史账户确认的 Billing 授权可进入 active，但不会因此成为默认或可扣款方式；收款仍受就绪条件约束。

商户账户表单仅接受共用类型化属性及实际所选供应商的凭证字段。更新时供应商来自已按租户限定的持久化账户；伪造 provider／mode 或外供应商凭证字段不会成为模型列，也不能更改供应商身份。密钥留空保留原加密值。

定期订阅去重包含可恢复 paused 行，要求支持币种。遗留的 `pending_sign` 卡订阅会在下次创建时完成激活，而不会被当作已经生效直接返回。账单令牌会被拒绝。催收／SCA 按持久化状态保留取消／到期。`managed_by == "billing"` 授权不由通用 Payments 排期，[账单](billing)负责收款。平台账单令牌使用空 `user_id` 及购买客户／授权人字段，与会员卡片区分。已验签 Stripe 设置及支付宝协议事件同步精确账单授权／结算，失败可继续重试。

支付宝校验业务根／码，暂时失败保留不明结果，URL／RSA 使用模块错误。查询返回主货币单位金额、大写币种及权威 settled_at。微信签署供应商 HTTPS 账单 URI，检查所提供 SHA1 并规范支付／退款／冲正行。Reconcile 固定账户／供应商／币种，退款行比对精确本地 Refund 身份／金额／结果，处理中快照不倒退已认证成功。仅退款账单跳过反向支付检查；冲正／未匹配行仍为差异。微信退款回调配置及缺少 pending 单次自动查询仍是边界。

支付／邮件 webhook 约束从锚定 PATH_INFO 解析可选格式前的供应商，`.json`／`.xml` 保留注册供应商分发及验证，查询／正文提示不能选路由。已验签结算可跨账户标签修改继续处理；首次到达的旧标签通知及已销毁密钥历史仍要求保留路由／密钥身份，未实现历史密钥版本库。

已验签 Billing Stripe 设置 metadata 同样按账户 ID 绑定，路由标识编辑后仍保留受理时的原上下文。历史查询使用固定账户行当前保留的凭证；即使本地行仍在，替换凭证后也可能无法访问原 PSP 账户。此时须由所有者核对并保留正确凭证，不能猜测替代账户或重新扣款。已知路由标识／模式变化后出现否定查询结果，Billing 仍保留结果不明的原尝试。本次源码跟进不增加凭证版本库或路由别名。

:::note
网关、尝试／退款对账、回调及 intent 前同意 API 已按源码记载。支付 RSpec 跟进审计仍记录独立数据库上的定向验证。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。该运行不是真实 PSP、部署或并发测试。
:::

:::attention
新网关是 `app/services/payments/gateways/` 下一个继承 `Payments::Gateways::Base` 并调用 `register!` 的文件。`Payments::WebhookDispatcher`、`Payments::WebhooksController` 的路由约束，以及 `Payments::MerchantAccount` 的校验，都读取 `Payments::Gateways`。不要新增类型化的凭证列。密钥经 `MerchantAccount#write_credentials` 进入加密的 `credentials` JSON。表单留空会保留已存密钥。
:::

:::attention
`Payments::MerchantAccount#enabled?` 和 `Payments::CredentialResolver` 按 `status == "active"` 过滤。结账还经过 `Payments::EligibleGateways`，它要求出现在 `Payments::PlatformGateway.available_providers` 里，并且 `MerchantAccount#configured?` 为真。商户号仍是 `unset-<provider>-...`，或缺少某个 `credential_fields` 值时，即使 status 已是 active，也不会进入结账。`Provisioner` 创建的行是 `disabled`。
:::

:::attention
`extract_merchant_id` 仅提供路由输入，不是证明。验签使用精确保留账户，包括已停用历史行。商户 ID 在供应商内跨租户唯一；支付宝要求确认正文 `success`。
:::

:::attention
`WebhookDispatcher` 在主库事务中记录及请求入队，延迟／跨库入队仍需恢复。重复 ID 保留原验签正文／账户；failed 或 received 滞留 10 分钟的行可重投。结算拒绝声明金额不匹配。
:::

## 关键代码

```ruby
# app/services/payments/gateways.rb
module Gateways
  extend PluginRegistry.build(label: "payment gateway", dir: "app/services/payments/gateways", defaults: false)
end
```

```ruby
# app/models/payments/merchant_account.rb
def enabled? = status == "active"

def configured?
  return false unless enabled?
  return false if merchant_id.blank? || merchant_id.to_s.start_with?("unset-")

  gateway_class.credential_fields.all? { |f| credential(f[:name]).present? }
end
```

```ruby
# app/services/payments/credential_resolver.rb
def self.call(customer:, provider:, mode: default_mode)
  acc = Payments::MerchantAccount.unscoped_by_tenant
                              .where(customer_id: customer.id,
                                     provider: provider, mode: mode,
                                     status: "active")
                              .first
```

```ruby
# config/routes.rb
post "/payments/webhooks/:provider",
     to: "payments/webhooks#create",
     as: :payments_webhook,
     constraints: ->(req) {
        provider = req.path_info.match(%r{\A/payments/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
       Payments::Gateways.keys.map(&:to_s).include?(provider)
     }
```
