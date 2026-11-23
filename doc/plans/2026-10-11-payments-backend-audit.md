# Payments backend audit — 2026-10-11

This fragment records the backend lane and its integration requirements. It is
not a replacement for the bilingual Payments developer-reference pages. No
RSpec runs were requested; verification in this lane is Ruby syntax and diff
checks only.

## Issue ledger

These are local handoff IDs because the dispatch did not supply issue IDs.

| ID | Backend change | Integration requirement |
| --- | --- | --- |
| PAY-BE-01 | Webhook payment, refund and dispute lookup is scoped to the incoming provider and verified account's customer, then checked against the saved merchant account/mode. Disabled accounts remain valid for historical settlement. Missing signing identity does not mutate records. | A now persists and forwards verified account identity; its job still needs to release the event transaction before handler HTTP. Query/refund/close now use B's pinned facade. |
| PAY-BE-02 | Query, Stripe webhooks and token charges compare the reported currency as well as the amount. Stripe amounts are interpreted using the reported currency. | Gateways return validated normalized `amount` and `currency` when available. |
| PAY-BE-03 | Query consumes normalized `settled_at`; otherwise it parses provider completion fields. Stripe webhook settlement uses the expanded charge timestamp, then the signed success-event timestamp, never PaymentIntent creation. Token/agreement charges consume normalized completion timestamps. | Stripe query/token gateway paths should return the real capture timestamp as `settled_at`; unexpanded token responses otherwise use the existing local-time fallback. |
| PAY-BE-04 | Paused subscriptions are included in enrollment deduplication. The subscribe hook runs after the pending enrollment commits. | None for paused enrollment deduplication. |
| PAY-BE-05 | Signing, cancellation, dunning, SCA reactivation and period advancement read persisted state under lock. Cancelled/expired floors are preserved; stale workers cannot advance or pause a newer anchor. | None for the persisted-state transition fix. |
| PAY-BE-06 | Checkout and token attempts commit before outbound writes. A saved attempt context retains merchant identity and original parameters; pending checkout retries reuse the original flow/payload without another write. Write activities also refuse a mismatch between the saved and currently active account. | Facade/provider must select the saved write account atomically and honor saved client-IP context on unresolved retries. |
| PAY-BE-07 | `Refund#mark_processing!` and `Payment#mark_pending!` lock and reload before applying terminal guards. | None. |
| PAY-BE-08 | Transport failures and unclassified API errors preserve the original attempt/refund key and reservation. Only explicit `definitive? == true` (without `uncertain?`) or a definitive normalized outcome releases them. Unresolved agreement queries never mint another charge or retire an attempt on generic query error. | Gateway lane must expose explicit rejection classification; the `ApiError` class alone no longer establishes non-execution. |
| PAY-BE-09 | Subscribe contract requires currency; the subscription model rejects blank/unrecognized currency. | None. |
| PAY-BE-10 | Reconcile consumes canonical gateway `rows` if supplied. Native WeChat bills normalize BOM, localized headers, backtick values and summary footers. Forward matching also checks provider and currency; malformed asserted amounts are discrepancies. | Canonical gateway rows use major-unit `amount`, `out_trade_no`, and optional `currency`. |
| PAY-BE-11 | Due population, atomic claims, dunning, period advancement and SCA recovery are restricted to `managed_by: "payments"`. Billing mandate activation never sets `next_charge_at`. | B supplies `managed_by` and metadata in its lifecycle migration. Apply that migration before running the integration specs. |
| PAY-BE-12 | Verified Billing setup/agreement events run through `PaymentAuthorization.handle_verified_event!` before trade routing. Unavailable authorization lookups and incomplete invoice projections raise retryable errors. Invoice settlement always passes the captured payment and `source: :gateway`, including success replays. | The job may mark an event processed only after these projections return successfully. |
| PAY-BE-13 | Local card backfill requires the exact SetupIntent/PaymentIntent placeholder and fetches through its verified historical account. Query recovers missing Stripe IDs through the existing read-only metadata search. Historical bills accept a payment/account pin and persist account identity in their summary. | The only facade edit in this integration is `fetch_payment_method`'s explicit `merchant_account:` / `historical:` support. |
| PAY-BE-14 | Stripe ambiguous checkout/token writes older than 23 hours use read-only reconciliation and never replay the write. Unresolved outcomes are blocked for manual review on the same payment. Expired uncertain refunds retain the original reservation and are not automatically resubmitted. | Stripe retention is at least 24 hours; the one-hour margin covers transport/worker delay. There is no automatic fresh operation after an unresolved read. |

## Interfaces

### Verified webhook identity

```ruby
Payments::Activities::HandleWebhook.call(
  provider: provider,
  verified_payload: payload,
  signing_account_id: gateway.account.id,
  signing_merchant_id: gateway.account.merchant_id
)
```

The account ID must originate from signature verification, not from payload
metadata or a payment looked up using attacker-supplied references. Existing
merchant-only calls resolve the globally unique **incoming provider + verified
merchant ID**. Calls with neither identity are dropped. An explicitly supplied
account ID and merchant ID must agree.

New attempts match account ID, original merchant ID and mode. Pre-snapshot
records use the environment's single customer/provider/mode account binding;
historical account identity cannot be reconstructed after an in-place merchant
replacement. Backfill or explicit historical binding is required for such rows.

A has moved inline handling outside its enqueue transaction and persists the
verified account in the event envelope. The async job still holds
`event.with_lock` while invoking the handler; it must release that transaction
before Billing authorization queries or card backfill HTTP. Card fetch now
passes `merchant_account: signing_account, historical: true` and never resolves
an active replacement for that historical request.

### Saved payment attempt

`Payment#attempt_context` reads `prepay_payload["_attempt"]`;
`Payment#merchant_account_id` reads its saved account ID. This context is local
bookkeeping, retained by `mark_pending!`, and excluded from Charge's returned
prepay payload.

Common fields: `operation`, `provider`, `flow`, `user_id`, `external_ref`,
`amount` (major-unit decimal string), `currency`, `subject`, `body`, `expires_at`,
`merchant_account_id`, `merchant_id`, `mode`.

- Checkout: original `openid`, effective `save_card`, `client_ip`; member identity
  is retained on `Payment#user_id`; persisted `Payment#flow` is reused.
- Token charge: `payment_method_id`, original `psp_payment_method_id`.
- Agreement charge: `subscription_id`, original `psp_agreement_id`.

Provider/order contents are immutable for an unresolved attempt. Checkout
retries reuse the saved optional values; token retries reject a changed token.
Callers must also invoke these activities outside an enclosing transaction;
exiting the activity's own lock cannot commit an outer caller transaction.
The facade must select the saved account for charge/query/refund/close and
recurring writes. Disabling new checkout must not prevent historical queries,
refunds or authenticated webhook settlement.

### Normalized gateway result

Success results may carry major-unit `amount`, `currency`, and a Time-like
`settled_at`. Remote queries return the gateway result unchanged while applying
guarded local settlement. A recorded success instead repairs its invoice
projection and returns local evidence without another remote read. `paid_at`
is also accepted as an explicit completion field.
`download_bill` may return `rows: [{ out_trade_no:, amount:, currency: }]` alongside
the original `csv` attachment and `raw_summary`.

## Completed A/B integration and remaining interfaces

- `HandleWebhook` calls the actual Billing authorization service first. A setup
  or agreement Result consumes the event; transient lookup Results are converted
  to retryable errors. Local member vaults only match exact remote-intent IDs.
- `MarkInvoicePaid` receives `source: :gateway` and the recorded payment. It owns
  notice creation; Payments neither duplicates notices nor swallows projection
  errors. An already-captured payment still retries its missing invoice projection.
- `Gateway.query/refund/close` use B's historical `for_payment` resolution.
  Missing Stripe intent IDs use the existing gateway metadata search without a
  financial write. Explicit historical bills resolve via `gateway_for_merchant`;
  scheduled downloads pin the enumerated current-mode account.
- Canonical WeChat refund rows reconcile against scoped refund identity and
  amount, preserving a later successful refund against an earlier processing
  bill snapshot. Refund rows cannot mask a missing capture in the reverse leg.
- `managed_by` is the ownership authority. JSON metadata is correlation data;
  it does not override the typed scheduler owner. All general recovery paths
  leave Billing mandates unscheduled.
- `AttemptSafety` uses the original record's creation time as a conservative
  retry-age anchor. After 23 hours, Stripe writes are replaced by reconciliation;
  unknown results retain their operation identity and a machine-readable
  `idempotency_window_expired` review reason. Refunds without a query API remain
  reserved for webhook/manual reconciliation.

Remaining interfaces:

1. A's async webhook processor must not hold the event transaction during
   handler HTTP; completion must follow successful projection.
2. The write facade's `charge` / `charge_token` still select the currently active
   account. Activities reject a pre-call identity mismatch, but the facade must
   itself select the persisted account to close the account-change race. It also
   still extracts the current request IP instead of the saved attempt IP.
3. Gateways must distinguish a definitive API rejection explicitly (`definitive?`)
   or return a normalized failed outcome. Unclassified API failures remain live.

## Regression specs updated

- `spec/models/payments/payment_spec.rb`: stale pending response after capture;
  preservation of saved merchant identity.
- `spec/models/payments/refund_spec.rb`: stale processing response after refund
  success preserves status, PSP ID, notification and refunded order state.
- `spec/models/payments/subscription_spec.rb`: terminal floors, stale anchor,
  stale SCA lookup, blank currency.
- `spec/services/payments/activities/charge_spec.rb`: transaction depth at HTTP,
  timeout identity/flow reuse, pending payload reuse, immutable save-card/member
  context, changed order refusal, definitive rejection.
- `spec/services/payments/activities/charge_token_spec.rb`: uncertain API retry,
  late SCA response after capture, unknown PSP outcome.
- `spec/services/payments/activities/create_subscription_spec.rb`: paused
  deduplication, gateway call outside lock, concurrent cancellation.
- `spec/services/payments/activities/handle_webhook_spec.rb`: verified-account
  dispatch fixtures, cross-provider forged binding, refund collisions,
  exact/disabled historical accounts, currency mismatch, success-event time.
- `spec/services/payments/activities/query_spec.rb`: currency mismatch, expanded
  capture timestamp, normalized settlement evidence.
- `spec/services/payments/activities/refund_spec.rb`: uncertain API failure keeps
  full amount reserved and reuses the original refund key.
- `spec/services/payments/activities/reconcile_spec.rb`: native WeChat bill,
  canonical rows with original attachment, provider mismatch, malformed amount.
- `spec/services/payments/contracts/subscribe_spec.rb`: missing/blank currency.
- `spec/services/payments/cron/charge_due_subscriptions_spec.rb`: unresolved
  agreement recovery, generic query error, cancellation during dunning,
  real Billing ownership exclusion and stale ownership claims.
- `spec/services/payments/activities/billing_integration_spec.rb`: actual B
  authorization and A/B invoice/entitlement projection, replay repair, transient
  authorization failure, historical local vault and Billing SCA exclusion.
- `spec/services/payments/activities/retry_age_spec.rb`: read-only expired-key
  recovery/search, unknown/API-query outcomes, safe-window token reuse and
  expired refund reservations.
- `spec/services/payments/activities/historical_operations_spec.rb`: real facade
  query/refund/close with disabled non-current-mode credentials, pinned bill
  reconciliation and cross-tenant fast-path rejection.

## Developer docs merge requirement

Update `doc/reference/en/payments.md` and `doc/reference/zh-CN/payments.md` in
lockstep: Activities, gateway result contracts, verified webhook identity,
disabled historical accounts, commit-before-HTTP attempts, immutable retries,
subscription terminal floors/deduplication, currency validation, WeChat bills,
and Billing-owned scheduler exclusion. Update the Billing reference pages for
mandate tagging. This lane only owns this new audit fragment.

## 中文交接摘要

### 问题与实现

- PAY-BE-01：回调按入站支付渠道和验签商户所属客户查询，再核对保存的商户账号、商户标识与模式；停用账号仍可处理历史结算。未提供验签身份时不修改记录。
- PAY-BE-02：查询、Stripe 回调和令牌扣款同时校验金额与币种；Stripe 金额按上报币种换算。
- PAY-BE-03：优先采用网关返回的 `settled_at`。Stripe 回调使用扣款时间，未展开扣款对象时采用已验签成功事件的时间，不使用 PaymentIntent 创建时间。
- PAY-BE-04：暂停中的订阅参与重复报名检查；订阅记录提交后才调用网关。
- PAY-BE-05：签约、取消、催缴暂停、SCA 恢复及周期推进均加锁读取数据库状态；取消和过期状态不可被陈旧实例覆盖，旧任务不能推进或暂停新周期。
- PAY-BE-06：扣款标识及原始参数先提交，再发起远程写入；待支付重试复用原支付流程和预支付数据。
- PAY-BE-07：退款处理中及支付待处理状态均加锁检查终态，避免迟到的同步响应覆盖成功回调。
- PAY-BE-08：传输错误和未明确分类的 API 错误保留原操作标识和退款额度预留；只有显式 `definitive? == true` 且并非不确定结果，或标准化的明确失败结果，才释放。不能仅凭 `ApiError` 类判断未执行。
- PAY-BE-09：订阅合约要求币种，模型拒绝空白或未支持的币种。
- PAY-BE-10：优先使用网关标准化账单行；微信原生账单处理 BOM、中文表头、反引号及汇总尾部，并核对渠道、币种及异常金额。
- PAY-BE-11：到期范围、原子认领、催缴、周期推进和 SCA 恢复仅处理 `managed_by: "payments"`；Billing 授权激活不设置 `next_charge_at`。B 已提供相关迁移，运行集成测试前需应用。
- PAY-BE-12：已验签的 Billing 授权事件先交给 `PaymentAuthorization.handle_verified_event!`，再进行交易路由；查询不可用或发票投影未完成时抛出可重试错误。已成功扣款也必须补齐发票投影，始终传入支付记录及 `source: :gateway`。
- PAY-BE-13：本地卡记录严格匹配远程意向标识，并通过验签历史账号补全。Stripe 丢失响应时复用已有只读元数据查询；历史账单可按支付或账号绑定，并在汇总中保存账号身份。
- PAY-BE-14：Stripe 扣款尝试超过 23 小时后只查询对账，不重放写入；结果未确定时保留原操作并标记人工核查。过期的不确定退款继续预留额度，不自动重发。

### 接口与待合并项

`signing_account_id` 必须来自实际验签账号，不得从回调元数据或交易引用反推。
网关门面需使用 `Payment#merchant_account_id` 和 `Payment#attempt_context` 中的原始参数。
`amount` 使用主货币单位；`settled_at` 为真实完成时间。标准账单行包含
`out_trade_no`、`amount` 及可选 `currency`。

已有但未保存账号快照的记录按当前环境的客户／渠道／模式账号绑定；原商户标识被原地替换后无法恢复历史身份，需补录明确绑定。
A 已将同步处理移出入队事务，并保存验签账号；异步任务仍需解除事件事务后再调用处理器。
卡信息补全现已传入验签账号及 `historical: true`，不再替换成当前环境账号。
微信标准化退款行按退款自身标识和金额核对；账单中的较早处理中快照不得覆盖已成功退款，也不能掩盖缺失的扣款记录。
调用扣款活动时也不得持有外层事务；活动退出自身锁后，外层事务仍未提交。
令牌扣款的未展开响应需由 Stripe 网关补充真实扣款时间。

集成使用实际 B 授权服务及 A/B 发票、权益投影，并新增英文清单中的三份集成回归文件。
剩余接口是：异步任务在 HTTP 前释放事务；写入门面直接选取已保存的账号和 IP，消除校验后的账号变更窗口；网关显式标识明确拒绝。
本工作未运行 RSpec，仅执行 Ruby 语法与差异检查。
合并时需同步更新中英文 Payments 开发参考页的对应章节，以及 Billing 授权标记说明；本工作仅新增此审计片段。
