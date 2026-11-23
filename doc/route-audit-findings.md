# Route audit findings

## Scope and method

Audit date: **2026-11-04**. Source baseline: **`fa7c9fb8`**, initially clean worktree. This report supersedes the earlier partial report at this path. Findings only; application code has not been changed.

The actual `config/routes.rb` DSL was expanded in an isolated Rails route set, including the installed Devise and Doorkeeper route macros: **724 route entries, 212 distinct routed controllers, and 545 distinct controller/action pairs**. Update verbs and repeated mounts account for multiple entries. GET also admits HEAD. Conditional root/glob routes are included. Framework routes automatically mounted outside this file are not included in that count, but were followed where a declared route hands off to them, notably Active Storage direct uploads.

All declared route families were statically traced through their controllers, inherited filters, principal services/activities/contracts/models, and relevant jobs/rendering boundaries. The route-to-source appendix provides the coverage map. Static coverage is not exhaustive execution of every possible branch or arbitrary owner-installed generator. Files under `app/services/page_layout_templates/templates/` were excluded per the project instruction.

Verification comprised source/spec inspection, installed-gem source inspection, safe standalone probes, synthetic SQLite SELECTs, and Brakeman. No real provider calls, application database writes, exploit requests to a running application, server restarts, or full RSpec runs were performed. Probe scripts and scanner output reside outside the repository in `/tmp/opencode`. Specific verification limits are stated with findings; a source-proven race is not represented as a concurrency test.

Installed versions observed: **Ruby 3.2.8, Rails 8.1.3, Devise 5.0.4, Doorkeeper 5.9.6**. These are the resolved versions, rather than the stack-description versions. Source references are repository-relative `file:line` references at the baseline. Gem references name the installed gem and source path.

### Summary

**53 findings: 2 critical, 11 high, 31 medium, 9 low.** Conditional policy/architecture risks and unconfirmed leads are listed separately and are not included in that count.

| Priority | IDs | Main concern |
|---|---|---|
| Critical | A01–A02 | Two independently reproducible SQL-injection sinks permit cross-tenant/database reads |
| High | A03–A04, A06, A11–A12, A21–A23, A28, A33, A45 | Shared cached-data disclosure, stored executable URLs, financial side-effect/settlement/idempotency failures, account pre-hijacking, credential logging, captcha bypass, storage exhaustion, destructive purge race |
| Medium | See individual findings | Authorization lifetimes, races, provider integration, resource controls, state/version integrity, lifecycle cleanup |
| Low | A10, A18, A42–A44, A49–A52 | Metadata interference, incomplete cancellation/protection, information oracle, policy/localization/introspection defects |

Severity describes plausible impact with the documented prerequisites, not an assertion that every installation is exploitable. Confidence is high unless an environmental or policy qualification is stated. Recommended directions are for manual review; none has been implemented.

## Findings: entities, pages, flowcharts, and shared definitions

### A01 — Critical — Raw subquery condition fields escape tenant and ownership predicates

**Routes:** `GET/POST /:cid/admin/maintenance/pages/:page_id/preview`; `GET .../pages/:page_id/module_data/:module_id`; `GET .../pages/:page_id/field_options/:field_id`; corresponding platform remounts; `GET /:cid/admin/pages/:page_id/form`; public `GET /:cid/page/:uuid` and GET aliases; `GET /:cid/member/pages/:id`. Owner-authored flowchart queries use the same sink.

**Chain:** page preview/render/options controller → `PageRendering`/`PageContentGenerator` → `CompositePageRenderer#fetch_list_data` or `DynamicOptionsResolver#resolve_field` → `QueryBuilder` → `WhereClauseBuilder#build_rule/#build_comparison_raw` → ActiveRecord `where`.

**Evidence:** `app/services/flowchart_runtime/where_clause_builder.rb:122–130` accepts a non-`data.` field as a raw expression on the `subQuery` branch, bypassing normal column validation. Lines `252–262` interpolate it into `CAST(...)` with no bindings; lines `50–54` apply that SQL. Consumers are `app/services/composite_page_renderer.rb:63–84` and `app/services/page_content_generator/dynamic_options_resolver.rb:55–74`. `app/controllers/admin/maintenance/page_module_data_controller.rb:30–33` serializes returned rows and their JSON data. Configuration validation does not close this boundary: `app/models/page.rb:204–237`, `app/services/pages/configuration_validator.rb:24–34`.

**Trigger:** a tenant admin supplies a composite/query-option condition such as:

```json
{
  "field": "1 AS NUMERIC)=0) OR 1=1 OR (CAST(1",
  "op": "==",
  "subQuery": { "entityId": 1, "aggregateFunction": "count" }
}
```

The generated fragment places `OR 1=1` outside the enclosing tenant/entity predicate. The actual builder was exercised against synthetic SQLite data; both tenants' rows were returned.

**Impact:** tenant administrators can read other customers' entry rows. Saved malicious configurations can expose projected values to public/member page visitors. Members do not inject this configuration through an ordinary GET; a page author supplies it. The 200-row ordinary pagination ceiling does not restore authorization. Compatible UNION/scalar extraction is possible; stacked writes were not demonstrated.

**Direction:** emit allowlisted identifier/JSON/subquery nodes through ActiveRecord/Arel with bound values. Wrapping the same raw field in `Arel.sql` would retain the bug.

### A02 — Critical — Formula string literals become executable SQL

**Routes:** definition creation at `POST /:cid/admin/maintenance/entities`, update at `PATCH/PUT /:cid/admin/maintenance/entities/:id`, and their platform remounts; reads through `GET /:cid/admin/entities/:id`, entry show/CSV, page module-data/composite reads. Assistant entity operations preserve the same formula when emitted by the provider.

**Chain:** entity definition contract/version writer → `Entities::DerivedExpressions.calculated` → `FlowchartRuntime::FormulaCompiler` → `DerivedValues` or `QueryBuilder` SELECT expressions → entry/page presentation.

**Evidence:** `app/services/flowchart_runtime/formula_compiler.rb:33–35` accepts apostrophes inside double-quoted formula strings; lines `208–212` wrap the token in SQL apostrophes without escaping. `app/services/entities/derived_expressions.rb:25–35`, `app/services/entities/derived_values.rb:24–27`, and `app/services/flowchart_runtime/query_builder.rb:238–244,357–366` execute it. `app/services/entities/contracts/definition.rb:59–70` checks field shape, not this serialization. The assistant semantic validator checks identifier tokens, while injected SQL stays in one STRING token: `app/services/entity_definitions/api/semantic_validator.rb:359–385`.

**Trigger:** a text-valued Calculated field with a valid slug and formula:

```text
"x' || (SELECT encrypted_password FROM users LIMIT 1) || 'x"
```

Actual compiler output:

```sql
'x' || (SELECT encrypted_password FROM users LIMIT 1) || 'x'
```

Synthetic SELECT-only probes extracted another tenant's sentinel and combined both tenants' synthetic email/password-hash values while the outer entry remained tenant-scoped.

**Impact:** a tenant-authored definition can read database tables outside normal tenant/sensitive-column filters, including password hashes and raw tokens. Rails-encrypted columns remain ciphertext at this SQL boundary. No destructive SQL was executed or needed to establish the defect.

**Direction:** use adapter quoting/Arel quoted nodes for literals and typed SQL emission. Replacing the entire SQL-transpiler grammar with Dentaku is not a necessary or compatible fix; the source documents why that parser swap was rejected.

### A03 — High — Shared Page cached content contains platform-tenant data

**Routes:** producer `PATCH/PUT /81721200/admin/maintenance/platform/pages/:id`; consumers `GET /:cid/admin/maintenance/pages/:id.json` and `GET/POST .../pages/:page_id/preview` without replacement configuration.

**Chain:** platform page save → `generate_content` under `Current.customer_id = 81721200` → composite/query-option values embedded in ERB/HTML → global `Page#content` → another tenant's maintenance JSON/default preview.

**Evidence:** `app/controllers/admin/maintenance/pages_controller.rb:124–127` saves the generated artifact; `app/services/page_content_generator.rb:391–417` selects the current customer for generation; `app/services/page_content_generator/composite_renderer.rb:64–70` and `form_fields.rb:95–113` embed fetched values. `app/models/page.rb:36–43` resolves configuration, not `content`. JSON returns the global content at `pages_controller.rb:61–67`; preview prefers it at `app/controllers/admin/maintenance/page_previews_controller.rb:28–42`.

**Trigger/impact:** save a shared page containing a platform-populated composite list or query-backed select, then read its cached content as another tenant's admin. Data embedded during the platform save crosses the tenant boundary, even when the viewing tenant has a configuration override. Disclosure is limited to data included in that artifact.

**Qualification:** public/member/admin `PageRendering` regenerates content and is not this cached-read path. Render-time `entity_entries` options alone are not sufficient to prove leakage; generation-time query options/composite lists are. Source-confirmed, without querying application data.

**Direction:** cache only tenant-independent definitions, or key generated artifacts by resolved tenant/version and regenerate when reading tenant-sensitive previews.

### A04 — High — Stored page button URLs execute JavaScript

**Routes:** page create/update and preview/render routes, public/member/admin page views, and shared remounts.

**Chain:** stored layout `button_url` → `PageContentGenerator::LayoutElements` → `FormFields::ButtonElementComponent` → anchor `href`.

**Evidence:** `app/services/page_content_generator/layout_elements.rb:123–135` forwards the URL; `app/components/form_fields/button_element_component.rb:18–24` stores it unchanged; `app/components/form_fields/button_element_component.html.erb:2` emits it. Page validation has no URL-scheme check. `config/initializers/content_security_policy.rb:7–29` contains commented-out policy configuration.

**Trigger/impact:** store `javascript:alert(document.domain)` as the button URL and induce a visitor to click. Isolated rendering emitted that executable href. HTML/Ruby-string escaping does not reject its scheme. Script can act with the visitor's same-origin session, including a platform owner inspecting a tenant's page or another tenant's user on a shared host.

**Qualification:** browser execution and upstream CSP were not tested.

**Direction:** one Addressable-backed URL policy with explicit allowed schemes/relative forms; retain output escaping and appropriate Rails/Loofah sanitization for actual HTML.

### A05 — Medium — A page override URL can reset an owner-only flowchart override

**Route:** `DELETE /:cid/admin/maintenance/pages/:page_id/override.json?flowchart_id=:shared_flowchart_id`.

**Chain:** page-path admin gate → `SharedResourceOverridesController#find_record` → first populated merged parent param → `Flowchart.accessible.find` → `reset_customer_override!(current_customer_id)`.

**Evidence:** `app/controllers/admin/maintenance/shared_resource_overrides_controller.rb:12–17,44–51` scans constant/entity/flowchart/page IDs in that order using merged `params`; destruction is at line `20`. `app/services/flowchart_visibility.rb:19–24` does not classify this shared controller as owner-only. `app/controllers/concerns/route_authorization.rb:130–145` sees a page path/controller. `app/models/concerns/versionable.rb:149–165` removes the tenant override head and versions.

**Trigger/impact:** a same-tenant admin supplies a query `flowchart_id` on a page override DELETE. The page need not exist, because it is never loaded. A parameter probe confirmed the flowchart is selected. This destructively resets the current tenant's owner-managed execution definition, bypassing the direct flowchart route gate. It does not change the global flowchart or another tenant's override.

**Direction:** derive the parent type and ID exclusively from routed path parameters, then enforce the selected resource's authorization.

### A06 — High — Trace rollback discards financial ledger records after real refunds

**Routes:** `POST /:cid/admin/maintenance/flowcharts/:flowchart_id/traces` and its platform remount. Public page submission is an additional conditional consumer when its executable flow contains a refund followed by rollback.

**Chain:** `FlowchartTracesController#create` → rollback-only outer transaction → actual `ActivityTracer` execution → generated refund step → `FlowchartRuntime::Payments.refund` → `Payments::Activities::Refund` → vendor refund → outer rollback.

**Evidence:** `app/controllers/admin/maintenance/flowchart_traces_controller.rb:18–23` unconditionally rolls back after execution. `app/services/activity_tracer.rb:133–145` executes the actual activity. The generated step is `app/services/code_generators/element_types/process/payments/refund_payment_generator.rb:22–28`; runtime calls the real activity at `app/services/flowchart_runtime/payments.rb:31–49`. `app/services/payments/activities/refund.rb:21–48` creates the row/key in a nested `with_lock` transaction, then calls the PSP. Inside an outer transaction that row is not independently committed.

**Trigger/impact:** the owner traces a real eligible non-billing payment refund. The provider can return money while local reservation, refund status, audit row, and idempotency identity disappear. Repeated partial-refund traces can generate distinct keys. Provider refund ceilings still apply. Other external HTTP/file effects are likewise not undone by database rollback.

**Additional reach:** `app/services/pages/public_submission.rb:95–104` wraps activity execution and later completion/bridge work in a transaction. A refund followed by failure/bridge/handoff rejection has the same durability problem. Anonymous reach depends on the launched page's audience and owner-authored flow.

**Qualification:** owner-only trace authorization is intact; no vendor call was made.

**Direction:** supply dry-run financial/storage/HTTP ports for tracing and keep durable external-operation identity outside rollback-only execution. A database transaction cannot undo an accepted refund.

### A07 — Medium — Definition save and launch checks are not atomic

**Routes:** page/flowchart update and launch routes, including platform remounts.

**Chain:** controller reads draft/head/stamp → concurrent save or launch → stale object passes checks → version promotion/status save.

**Evidence:** `app/controllers/admin/maintenance/flowcharts_controller.rb:98–102,134–139`; `flowchart_launches_controller.rb:20–26,54–59`; `app/models/flowchart.rb:106–110,126–131`; `app/models/concerns/versionable.rb:228–265,331–335`. Page timestamp checks happen before the transaction at `app/controllers/admin/maintenance/pages_controller.rb:113–118,176–184`; page launch locks the customer but does not refresh/version-check the page at `app/models/concerns/page_launch_lifecycle.rb:23–32`.

**Trigger/impact:** a loaded draft update can resume after another request launches it and write based on its stale draft state. Conversely, launch loaded from A can promote A after another save committed B. Lost edits, stale validation, and modification of a launched definition result. Existing customer locks do not serialize every definition writer.

**Verification:** concrete source interleavings; no database concurrency run.

**Direction:** fresh validation under a shared write boundary, optimistic locking/atomic head compare-and-swap across save, promote, reset, and launch.

### A08 — Medium — Page version changes bypass edit stamps and retain stale previews

**Routes:** `POST .../pages/:page_id/versions`; `PUT .../pages/:page_id/versions/:id/default`; later update/default preview, including platform remounts.

**Chain:** `PageVersionsController` → `BaseVersionsController` → `Versionable#restore_as_new!/#set_current_version!` → head-only update → unchanged page timestamp/content → old editor/preview.

**Evidence:** `app/controllers/admin/maintenance/base_versions_controller.rb:38–53`; `app/models/concerns/versionable.rb:187–194,279–294`; `app/controllers/admin/maintenance/pages_controller.rb:176–184`; `page_previews_controller.rb:32–40`.

**Trigger/impact:** editor A loads stamp T; another action selects/restores version B without changing T; A's old save still passes the timestamp check. Preview can display content from the former version while configuration resolves B. This is also a sequential defect, not only a race.

**Direction:** version/head-based edit identity, consistent lock/version bump on promotions, and version-aware cached content.

### A09 — Medium — Entry reference validation races deletion and bridge cascades

**Routes:** entity/association entry POST/update racing entry DELETE/batch DELETE.

**Chain:** unlocked reference existence validation → target deletion and cascade → validated writer commits JSON reference/bridge row.

**Evidence:** `app/contracts/entity_entry_contract.rb:208–215,227–231` counts without a shared commit boundary. `app/services/entities/activities/create_association_entries.rb:41–55` validates before persistence; `entry_writer.rb:18–32` does the same on updates. `app/models/entity_entry.rb:224–250` cascades currently present bridge rows. `app/services/entities/delete_entry.rb:9–10` does not share customer serialization with those writers. `db/schema.rb:1908–1910` has no FK for participant IDs inside JSON.

**Trigger/impact:** pause a writer after validation, delete its target and finish the cascade, then resume. A newly inserted/changed reference can point to the already-deleted row. Tenant/target validation is correct when checked, but not guaranteed through commit.

**Verification:** source interleaving, not a concurrency test.

**Direction:** serialize target/reference creation and deletion, revalidate under that boundary, and use database-backed reference constraints where practical.

### A10 — Low — Tenant overrides update the shared global parent's timestamp

**Routes:** tenant updates of shared Entity/Page/Flowchart bodies.

**Chain:** dirty virtual definition attribute → ActiveRecord parent timestamp → after-save tenant version storage.

**Evidence:** virtual attributes in `app/models/entity.rb:23–31`, `page.rb:31–32`, `flowchart.rb:21–22`; version callback at `app/models/concerns/versionable.rb:61,331–335`. Installed ActiveRecord `timestamp.rb:130–145` and `attribute_methods/dirty.rb:233–246` timestamp the parent save. A connection-free ActiveRecord probe changed dirty attributes from `[configuration]` to `[configuration, updated_at]`.

**Impact:** one tenant's override changes metadata visible to other tenants/platform and can cause unrelated shared-page timestamp conflicts. Global identity/default head remains protected. Constants' separate override storage is not implicated.

**Direction:** isolate override-line metadata and edit tokens from the global parent's timestamp.

## Findings: authentication and account lifecycle

### A11 — High — Unproved member signup binds a victim inbox to attacker credentials/tenant

**Routes:** `POST /:cid/auth`; redemption at `GET /auth/confirmation` or an earlier `GET /auth/sign_up/confirm` token.

**Chain:** `RegistrationsController#create` → `RegisterMember` → persistent user/password/member assignment → Devise confirmation → custom automatic sign-in. Customer signup's existing-user branch adopts the same row.

**Evidence:** `app/controllers/authentication/registrations_controller.rb:23–30`; `app/services/authentication/register_member.rb:30–32,51–55,68–75`; global email uniqueness at `app/models/authentication/user.rb:93–95`, `db/schema.rb:1773`. Devise `models/confirmable.rb:79–102` preserves password/customer. `app/controllers/authentication/confirmations_controller.rb:40–45` establishes sign-in; `customer_registrations_controller.rb:55–78,91–95` confirms an existing pending account.

**Trigger/impact:** register the victim's email in an attacker-controlled signup-enabled tenant with a known password. When the victim follows confirmation, that password and tenant survive. Global uniqueness blocks independent signup. MFA remains applicable if configured; this is not a universal MFA bypass.

**Direction:** prove mailbox ownership before durable credential/membership selection; do not adopt an unrelated pending member account during new-customer signup.

### A12 — High — Mail-job logs expose raw authentication and recovery tokens

**Routes:** sign-in-link, customer-signup/resend, member signup/confirmation, password reset, and MFA-recovery issuance.

**Chain:** token issuance → mailer `deliver_later` arguments → `ActionMailer::MailDeliveryJob` → Active Job INFO enqueue/perform logs.

**Evidence:** `app/services/authentication/issue_sign_in_link.rb:55–60`, `issue_customer_signup.rb:24–25`, `app/concepts/member/mfa/operation/request_reset_link.rb:14–15`, `app/models/authentication/user.rb:346–347`. Installed `actionmailer-8.1.3/lib/action_mailer/mail_delivery_job.rb:13–21` inherits `ActiveJob::Base`; `activejob-8.1.3/lib/active_job/logging.rb:18–26` defaults `log_arguments` to true; `log_subscriber.rb:22–24,76–82,204–223` formats arguments without request-parameter filtering. Production logs at INFO: `config/environments/production.rb:36–41`.

**Trigger/impact:** successful eligible mail issuance logs the raw bearer. An isolated real job-formatter probe printed the placeholder token. Log readers can redeem before expiry/consumption; sign-in links grant the first factor, reset links permit credential replacement, MFA-recovery links disable MFA. Ordinary sign-in/reset still faces applicable MFA.

**Direction:** dedicated sensitive mail-delivery jobs with Rails' `log_arguments=false`; request `filter_parameters` alone does not cover this channel.

### A13 — Medium — Custom password sign-in leaks account existence through timing

**Route:** `POST /auth/sign_in` with password intent.

**Chain:** skipped Warden params strategy → `SignInFlow` missing-user return versus `PasswordVerification` → BCrypt.

**Evidence:** `app/controllers/authentication/sessions_controller.rb:13–16,43–47`; `app/services/authentication/sign_in_flow.rb:36–42`; `password_verification.rb:7–12`. Devise's strategy performs a paranoid dummy hash at `devise-5.0.4/lib/devise/strategies/database_authenticatable.rb:19–24`; this app enables paranoid mode at `config/initializers/devise.rb:55–57` but bypasses that strategy.

**Verification/impact:** lookup-stubbed service timings at real BCrypt cost 12 were roughly 0.002–0.028 ms for missing accounts and 251–253 ms for existing passworded accounts with wrong passwords. HTTP latency was not measured. IP throttling limits volume but does not equalize the branches; active eligible passworded accounts are distinguishable.

**Direction:** reuse Devise/Warden's maintained credential strategy or preserve its dummy-hash behavior without double-counting Lockable failures.

### A14 — Medium — MFA attempt limits admit excess concurrent guesses

**Routes:** POST auth MFA session/setup and DELETE authenticated MFA reauthentication.

**Chain:** `Throttle.exceeded?` read → OTP/password check → later `record_failure` increment.

**Evidence:** `app/services/authentication/throttle.rb:19–24,78–84,90–92`; `app/controllers/authentication/mfa_sessions_controller.rb:15–26`, `mfa_setups_controller.rb:23–35`, `mfas_controller.rb:16–25`. The OTP replay lock in `app/models/authentication/user/mfa_methods.rb:34–45` does not include the limiter precheck.

**Verification/impact:** 20 synchronized in-memory callers passed a five-failure precheck before recording failures. Amplification depends on server concurrency; it is not unlimited guessing and does not defeat OTP replay prevention. Source comments already acknowledge residual slack. Member Enable/Disable's account-serialized operation has stronger protection and is not identical.

**Direction:** atomically reserve admission or serialize the decision/outcome, preserving intended failure-only/reset semantics.

### A15 — Medium — MFA-recovery links survive password/email revocation events

**Routes:** `POST /:cid/auth/mfa_recovery`; `POST /:cid/auth/mfa_recovery/consume`, with an intervening password/email change.

**Chain:** `ResetToken` user/customer/OTP fingerprint → credential change → uninvalidated token → `ConsumeResetLink` → MFA disabled.

**Evidence:** `app/concepts/member/mfa/reset_token.rb:37–54,73–78`; `operation/consume_reset_link.rb:9–13`; `app/services/authentication/credential_lifecycle.rb:41–54` revokes devices/OAuth/sign-in links but not this grant.

**Verification/impact:** real token verification on in-memory account state accepted after email/password changes and rejected after OTP rotation. A previously issued 15-minute recovery bearer can strip MFA after credential revocation. It does not reveal the new password or independently establish a session. Devise password-reset tokens already invalidate on credential change and do not share this gap.

**Direction:** bind recovery validity to a credential/recovery revocation epoch; Rails `generates_token_for` can reduce custom state projection, but consumption still needs locking.

### A16 — Medium — Concurrent confirmation consumers can both open sessions

**Routes:** `GET /auth/confirmation`; existing-pending-user branch of `GET /auth/sign_up/confirm`.

**Chain:** two preloaded unconfirmed snapshots → Devise in-memory confirmation guard/save → custom `SignInFlow.complete`.

**Evidence:** `app/controllers/authentication/confirmations_controller.rb:40–45`; `customer_registrations_controller.rb:58–72,91–95`; installed Devise `models/confirmable.rb:79–102,236–243,343–355`. A `confirmed_at`-only change is not within the app credential mutation lock: `app/services/authentication/credential_lifecycle.rb:7–10`.

**Verification/impact:** actual Devise methods accepted two in-memory unconfirmed snapshots. Both concurrent bearers can pass the custom sign-in completion; sequential reuse is rejected. Possession of the token is required, and MFA remains applicable. The new-tenant signup uniqueness handler is a separate case.

**Direction:** atomically consume/recheck confirmation and permit only its winning consumer to establish the session.

### A17 — Medium — Raw confirmation columns are login bearers for pending accounts

**Route:** `GET /auth/confirmation`.

**Evidence/chain:** installed Devise `models/confirmable.rb:248–254,343–354` stores/looks up the emailed raw token. `app/models/authentication/user.rb:17–20` encrypts OTP, not confirmation; `db/schema.rb:1745` stores it. `app/controllers/authentication/confirmations_controller.rb:40–45` adds automatic sign-in after confirmation.

**Impact/prerequisite:** reading an eligible unconsumed token from the database supplies the first factor without the password. This is a credential-storage weakness with a database-read prerequisite, not a public disclosure endpoint. Configured MFA still applies. The two SQL findings materially increase the importance of this exposure.

**Direction:** digest-backed confirmation grants with atomic consumption, or avoid treating confirmation as login.

### A18 — Low — Cancel does not cancel optional member MFA enrollment

**Routes:** `GET /:cid/member/security/mfa/setup`, then its Cancel/security link.

**Chain/evidence:** setup persists a pending secret at `app/controllers/member/mfa_controller.rb:34–39`, `app/controllers/concerns/authentication/mfa_enrollment.rb:21–24`; that secret creates an enrollment obligation at `app/services/authentication/mfa_obligation.rb:40–49`. The security GET is not exempt: `app/controllers/concerns/authentication/enforces_mfa.rb:22–38,50–53`. Cancel links there without clearing pending state: `app/views/member/mfa/setup.html.erb:53–56`.

**Impact:** an opt-in member clicking Cancel is redirected back into enrollment and remains gated from ordinary member pages until completion/recovery/abort.

**Direction:** distinct pending enrollment state and a CSRF-protected abort of only uncompleted enrollment.

## Findings: payments and billing

### A19 — Medium — Public checkout exposes predictable internal orders and permits conditional collection interference

**Routes:** `GET/POST /:cid/payments/checkout`.

**Chain:** public checkout → `set_or_build_order` by `external_ref` → `Charge` → alternate-provider sibling query/close → new checkout attempt → billing/subscription collection invariants.

**Evidence:** `app/controllers/payments/checkouts_controller.rb:19,318–337`; displayed subject/ref/amount/currency at `app/components/payments/checkout_component.html.erb:2–4`. Predictable `billing-inv-<id>` comes from `app/services/billing/collector.rb:174–181`; `sub-<id>-<date>` from `app/services/payments/cron/charge_due_subscriptions.rb:181`. `app/services/payments/activities/charge.rb:19,141–175` closes siblings before preparing the new attempt. `app/services/billing/collector.rb:36–43` blocks on unrelated unresolved payments; settlement requires a collection attempt at `app/services/billing/activities/mark_invoice_paid.rb:56–65`.

**Trigger/impact:** without a session handoff, enumerate existing internal refs in a payments-enabled tenant. A hit discloses identity/amount. With another eligible provider and a successful query/close, POST can interfere with a live collection and create a non-collection attempt. Such a billing payment cannot settle its invoice and may block collection; a pending recurring-period checkout row stalls that cron at `charge_due_subscriptions.rb:80–90`.

**Important correction:** unresolved same-provider billing/recurring payload replay is blocked by operation binding in `app/services/payments/activities/prepare_attempt.rb:15–31`. Captured siblings, failed closes, module/provider checks, and mismatched active handoffs also constrain the attack. Financial availability impact is conditional on the documented order/provider state.

**Direction:** payer-authorized/signed opaque checkout identity and explicit checkout-domain exclusion for internal collection orders before any sibling side effect.

### A20 — Medium — Public results enumerate billing collection attempts

**Routes:** `GET /:cid/payments/result/:payment_id`; `GET /:cid/payments/:id/status`.

**Chain/evidence:** predictable `billing-invoice-<id>-<ordinal>` at `app/services/billing/collector.rb:171–181` → public tenant-scoped `out_trade_no` lookup at `app/controllers/payments/results_controller.rb:16,25–32`, `checkouts_controller.rb:193–212` → pending query at `results_controller.rb:58–64` → result status/internal reference at `app/components/payments/result_component.html.erb:9`.

**Impact:** anonymous invoice-attempt existence/status oracle and repeatable PSP reads on unresolved hits. Results work without a payments-module enablement guard; status does not. Integer-ID fallback remains platform-owner-only. Projection of an authentic verified capture is not by itself unauthorized settlement.

**Direction:** signed/opaque result authorization bound to the payer/checkout, with bounded polling.

### A21 — High — PayPal treats pending/declined/failed captures as paid

**Routes:** public status/results and provider-switch queries.

**Chain:** `Activities::Query` → `Gateways::Paypal#query/#query_result` → `HandleWebhook.finalize_success!` → payment/order success → possible handoff release.

**Evidence:** `app/services/payments/gateways/paypal.rb:194–201` maps order `COMPLETED` to success; `343–349` extracts capture identity/amount but ignores capture status. `app/services/payments/activities/query.rb:19–40` accepts a matching amount and finalizes; `app/models/payments/payment.rb:93–98` marks the order paid; `app/services/payments/handoff_completion.rb:57–69` can release the handoff.

**Verification:** network-free real adapter calls with matching amounts and capture statuses `PENDING`, `DECLINED`, and `FAILED` each returned local `succeeded`. PayPal explicitly requires checking capture status even when the order is `COMPLETED`: [OrderStatus](https://github.com/paypal/PayPal-Ruby-Server-SDK/blob/main/doc/models/order-status.md), [CaptureStatus](https://github.com/paypal/PayPal-Ruby-Server-SDK/blob/main/doc/models/capture-status.md).

**Impact:** fulfillment/local success before actual funds capture; future query short-circuits on local success.

**Direction:** separate order approval/completion from capture settlement, validating capture status/identity/amount before finalization.

### A22 — High — Retried completed partial-refund POST issues another refund

**Route:** `POST /:cid/admin/modules/payments/transactions/:transaction_id/refunds`.

**Chain:** refund form/controller → `Activities::Refund` searches only unresolved equal-amount rows → new refund/key after first success → PSP.

**Evidence:** `app/controllers/admin/modules/payments/refunds_controller.rb:19–26`; form at `app/components/payments/admin/refund_dialog_component.html.erb:13–31` carries only amount/reason; `app/services/payments/activities/refund.rb:26–48` excludes succeeded rows from replay lookup. The ceiling at `103–121` limits cumulative refunds, not duplicate intended operations.

**Verification/impact:** two identical $25 requests against a synthetic $100 capture produced two remote writes, distinct keys, and $50 refunded. Lost-response retry or a second submission after terminal success can refund twice. PSP idempotency cannot deduplicate different keys.

**Direction:** durable per-user-action request identity retained across retries and terminal outcomes, separate from legitimate later refunds of the same amount.

### A23 — High — Old PayPal refund retries exceed PSP idempotency retention

**Route:** the refund POST in A22.

**Chain/evidence:** `app/services/payments/activities/refund.rb:33–48` reuses and resubmits unresolved rows; `app/services/payments/activities/attempt_safety.rb:15–17,41–48` guards age only for Stripe; `app/services/payments/gateways/paypal.rb:210–226` reissues refund even with a recorded PSP refund ID and has no reconciliation query.

**Trigger/impact:** remotely accepted partial refund remains locally unresolved through lost response/receipt; retry after PayPal retention can create another refund with the old key. Official SDK documentation states 45-day refund-key retention: [Refund Captured Payment](https://github.com/paypal/PayPal-Ruby-Server-SDK/blob/main/doc/controllers/payments.md#refund-captured-payment). A 90-day synthetic PayPal attempt was not treated as expired.

**Qualification:** occurrence requires an old unresolved attempt; actual PSP behavior/account policy was not exercised.

**Direction:** provider-specific retry-retention bounds and query/reconciliation using known PSP identity before another financial write.

### A24 — Medium — Refund callbacks are not bound to amount/currency/parent capture

**Routes:** `POST /payments/webhooks/:provider`; verified event redrive; refund ledger views.

**Chain:** verified merchant notification → provider refund handler → `settle_refund` reference/PSP-ID match → local requested amount drives refund totals.

**Evidence:** `app/services/payments/activities/handle_webhook.rb:234–250,259–273,433–447,533–538`; `app/models/payments/refund.rb:38–44,56–64` uses local amount. Merchant/provider/tenant binding exists, but these refund assertions do not.

**Verification/impact:** a same-merchant synthetic callback naming the local key marked a $50 USD request succeeded while reporting €1 EUR. This requires a genuine verified event with mismatched reconciliation metadata, e.g. an external merchant API operation; it is not a signature-forgery or cross-tenant claim. Ledger totals/order state can diverge from actual returned funds.

**Direction:** validate parent payment/capture, amount, currency, and refund identity before settlement; quarantine mismatches.

### A25 — Medium — Alipay commerce sandbox accounts send to production

**Routes:** commerce checkout/query/results/refunds/reconciliation and merchant configuration.

**Evidence/chain:** `app/services/payments/credential_resolver.rb:5–6` selects sandbox outside production, but `app/services/payments/gateways/alipay.rb:17,53–65,74–94,227–230,270–276` uses the production commerce target. Mode-aware logic exists in the billing path at `143–152,223–225`.

**Verification/impact:** a sandbox account's actual QR adapter method selected `https://openapi.alipay.com/gateway.do` without HTTP. Genuine sandbox credentials fail; live credentials accidentally placed in the sandbox-labelled row can reach live financial operations.

**Direction:** one mode-aware endpoint selector used by every API and H5 path.

### A26 — Medium — Reverse reconciliation uses UTC rather than PSP settlement day

**Routes:** admin reconciliation index/show/download, fed by daily jobs.

**Chain/evidence:** `DailyMaintenanceJob` → `DownloadBills` → `Activities::Reconcile`; `app/services/payments/activities/reconcile.rb:45–49` uses application beginning/end-of-day. `config/application.rb:41` leaves Rails' UTC default; Alipay settlement timestamps use Beijing at `handle_webhook.rb:127–143,330–331`; WeChat bill parsing at `app/services/payments/gateways/wechat_pay/bill_parser.rb:69,80` does likewise.

**Trigger/impact:** `2026-11-01T18:00:00Z` is November 2 02:00 Beijing. The November 2 reverse query excludes it, while November 1 includes it. A timezone probe confirmed this. Result: false/incomplete settlement discrepancies around provider day boundaries.

**Direction:** provider-defined settlement timezone/day interval, converted to UTC for local queries.

### A27 — Medium — An overlapping due charge can begin after member cancellation succeeds

**Route:** `POST /:cid/member/payments/subscriptions/:subscription_id/cancellation`.

**Chain:** cron active check → concurrent `CancelSubscription`/local cancelled state → cron builds period order → `ChargeToken` without subscription recheck.

**Evidence:** `app/controllers/member/payments/subscription_cancellations_controller.rb:15–23,37–45`; `app/services/payments/activities/cancel_subscription.rb:6–12`; Stripe cancellation is local at `app/services/payments/gateways/stripe.rb:355–364`. Cron at `charge_due_subscriptions.rb:74–111` checks once; `activities/charge_token.rb:19–66` locks the order, not cancellation-compatible subscription state. Stripe off-session capture is at `stripe.rb:278–289`.

**Verification/impact:** interleaving the real cancellation activity in a stubbed cron flow still reached charge with `status=cancelled`. No real capture occurred. Later cron selection excludes cancelled rows, so this is an overlapping-period issue, not indefinite charging.

**Direction:** durable linearization of charge authorization versus cancellation. If already-claimed periods are intentionally chargeable, make that policy explicit and treat the behavior as a policy tradeoff.

## Findings: captcha, public callbacks, and resource boundaries

### A28 — High — Nested multipart files bypass captcha through fail-open serialization

**Routes:** captcha-gated POST public pages/aliases and other browser mutations using the same snapshot path.

**Chain:** `RackGate#challenge` → shallow `RequestSnapshot` file extraction → nested UploadedFile remains in cached params → cache serialization exception → original request dispatched.

**Evidence:** `app/services/captcha/request_snapshot.rb:86–119` handles only top-level uploads; line `35` serializes retained params. `app/services/captcha/rack_gate.rb:53–57,87–91` rescues capture exceptions into fail-open dispatch at `14–15`.

**Trigger/verification:** submit a CSRF-valid form with a one-byte nested file named `entity[bypass]` while a configured `every_hit` rule requires challenge. Real snapshot code extracted no file; both MemoryStore/default Marshal serialization rejected the retained IO; an isolated real gate returned downstream 200 with one downstream call. CSRF validity was assumed/stubbed, not bypassed.

**Impact:** challenge enforcement can be skipped before provider/fail-closed policy is consulted; the file need not be an accepted form field.

**Direction:** recursive shape-preserving upload extraction, bounded serializable params, and explicit capture-failure behavior that cannot authorize the original mutation.

### A29 — Medium — Abandoned captcha uploads persist after snapshot expiry

**Routes:** captcha-gated multipart mutations followed by an abandoned challenge.

**Chain/evidence:** `app/services/captcha/request_snapshot.rb:109–116` writes Active Storage blobs before verification; cache TTL at `35` expires metadata only. `prune_orphans!` exists at `55–59`, but no caller/schedule was found, including `config/recurring.yml`. Normal cleanup requires replay at `app/services/captcha/request_replayer.rb:64–65,120–127`. Shipped production storage is local: `config/environments/production.rb:24–25`, `config/storage.yml:8–10`.

**Verification/impact:** storage-stub capture left the created blob after metadata expired at 601 seconds. Repeated CSRF-valid pre-captcha uploads can fill persistent storage despite the five-MiB individual-file limit. Deployment-specific external cleanup could mitigate this; none is represented in source.

**Direction:** scheduled retriable orphan cleanup and an aggregate admission/storage budget before creating blobs.

### A30 — Medium — Invalid SES callbacks amplify synchronous certificate fetches

**Route:** `POST /email/webhooks/ses`.

**Chain:** retained credentials loop → fresh SES adapter/verifier → SNS certificate download/retry before topic/signature rejection.

**Evidence:** `app/controllers/emails/webhooks_controller.rb:46–57`; `app/services/email/providers/ses.rb:59–76,107–109`. Installed `aws-sdk-sns-1.118.0/lib/aws-sdk-sns/message_verifier.rb:127–138,183–202` fetches with default Net::HTTP timeouts and three attempts. Default surface throttling excludes callbacks at `app/services/captcha/surface_catalog.rb:33–45`.

**Trigger/verification:** a well-shaped bogus SNS envelope points to an AWS-allowed `.pem` path. Two fresh verifier instances with stubbed 404 responses caused six fetch attempts with 60-second open/read defaults. No network was used.

**Impact:** unauthenticated requests can occupy request threads with repeated outbound work. AWS HTTPS/hostname restrictions still apply; arbitrary-host SSRF was not established.

**Direction:** appropriately scoped long-lived verifier/certificate cache, prefilter configured topic, strict transport budgets and bounded callback ingress.

### A31 — Medium — Public regex rules run without a deadline before activity timeout

**Routes:** POST public page/aliases with a stored `matches_regex` rule.

**Chain:** `PublicSubmission#prepare_input` → `FormParams#permit_parts` → `RulesEngine#apply` → unbounded Ruby regex.

**Evidence:** `app/services/pages/rules_engine.rb:259–265`; `form_params.rb:116–118`; `public_submission.rb:43–50`. `app/services/activity_tracer.rb:102–109` starts its deadline later. Configuration validation at `app/services/pages/configuration_validator.rb:59–83` does not reject non-linear patterns or impose a match deadline.

**Verification/impact:** the real validator accepted `\A(a+)+\1\z`; Ruby 3.2.8 had `Regexp.timeout=nil` and `linear_time?=false`. A 33-byte nonmatching input did not finish in a bounded 300-ms child probe, which was killed/reaped. A bad saved rule lets anonymous input consume worker CPU outside the activity budget.

**Direction:** per-regex deadlines and input bounds, or RE2 with an explicitly restricted authoring grammar; backreferences/lookarounds require a compatibility decision.

### A32 — Medium — Assigning an unconfigured captcha provider silently removes protection

**Route:** `PATCH/PUT /81721200/admin/maintenance/platform/module_settings/captcha/settings`.

**Chain/evidence:** `app/services/captcha/activities/update_provider_settings.rb:44–59` checks provider registration, not readiness; `app/models/captcha/provider_settings.rb:75–80` disables the previous assignment. Its active accessor at `33–35` yields none for the unconfigured selection; `app/services/captcha/rack_gate.rb:80–85`/`activities/verify.rb:33–34` treat that as unavailable/disabled. The UI lists unconfigured choices at `app/components/admin/maintenance/platform/captcha/settings_component.html.erb:24–28`.

**Trigger/impact:** replace a working provider with a known unconfigured provider; assignment reports success but effective captcha disappears, including configured fail-closed surfaces. An isolated persistence-stub probe confirmed successful selection of an unready target. Only the owner can configure this; the defect is misleading successful configuration, not lower-role access.

**Direction:** readiness validation before switching; preserve the working assignment and distinguish intentional disablement from unusable selection.

## Findings: admin module execution, uploads, and website lifecycle

### A33 — High — Email direct-upload admission has no size or cumulative tenant budget

**Route:** `POST /:cid/admin/modules/emails/attachments`, then returned Active Storage direct-upload URL.

**Chain:** `AttachmentsController#create` → `Blob.create_before_direct_upload!` with client size → DiskService signed upload authorization → direct disk write.

**Evidence:** `app/controllers/admin/modules/emails/attachments_controller.rb:24–27,43–46`; local production storage at `config/environments/production.rb:24–25`, `config/storage.yml:8–10`. Installed Active Storage `disk_service.rb:86–98` signs the admitted size; `disk_controller.rb:24–28,58–59` and `disk_service.rb:21–24` accept/copy matching bytes.

**Trigger/impact:** any email-enabled tenant admin authorizes arbitrarily large or repeated small uploads without associating a template/sending mail. Shared storage can be exhausted and other tenants disrupted. Deployment ingress limits constrain individual requests, not cumulative usage. No large upload was performed.

**Direction:** pre-storage size/count/type admission and customer storage reservation/quota; attachment validators alone do not prevent direct-upload consumption.

### A34 — Medium — Email CSV exports preserve spreadsheet formulas

**Route:** `GET /:cid/admin/modules/emails/dashboard.csv`.

**Chain/evidence:** authored/interpolated message subject → `app/services/emails/analytics/export_csv.rb:19–22` writes raw recipient/subject → export at `app/controllers/admin/modules/emails/dashboard_controller.rb:24,36–37`. Subject input/rendering is at `templates_controller.rb:457–460`, `app/services/emails/template_renderer.rb:20–23,106–115`. SMS already neutralizes this boundary at `app/services/sms/campaign_report_csv.rb:27–32`.

**Verification/impact:** the real exporter emitted an unneutralized `=1+1` subject. A spreadsheet may evaluate formula-leading content when an admin/platform owner opens it. Spreadsheet execution/exfiltration was not attempted; a member-controlled subject path was not established.

**Direction:** one shared CSV-cell neutralization policy across exports, in addition to proper CSV quoting.

### A35 — Medium — Template version restore/default bypasses the active-send content lock

**Routes:** POST email template versions; PUT `.../templates/:template_id/versions/:id/default`.

**Chain:** version controller → base restore/default → `Versionable` → template payload `update_columns`/rich-text save → later fanout batch.

**Evidence:** `app/models/emails/template.rb:34,42–52` locks ordinary authored content during pending/processing sends. `app/controllers/admin/modules/emails/template_versions_controller.rb:23–26` checks only enablement; `app/controllers/admin/maintenance/base_versions_controller.rb:38–40,50–52` calls direct head switches; `app/models/emails/template.rb:118–155` bypasses scalar validations. `app/jobs/emails/send_activities/send_activity_job.rb:58–62` renders during fanout.

**Impact:** restoring an older version changes scheduled/in-flight content despite the lock; different batches can receive different versions. Sequential restore is enough.

**Direction:** enforce the same lock at every version writer, or pin immutable reviewed template versions per send run.

### A36 — Medium — Audio decoding happens before enablement/throttle rejection

**Routes:** POST cookie assistant transcriptions and desktop assistant transcriptions.

**Chain:** `Preflight` → `activity_guard` → synchronous `AudioProbe`/FFmpeg → only afterward disabled/unconfigured/rate-limit checks.

**Evidence:** `app/services/ai_assistant/activities/preflight.rb:25–31,88–99`; `app/services/speech_to_text/activities/enqueue_transcription.rb:67–74`; `app/services/speech_to_text/audio_probe.rb:29–41,53–78` copies input and allows a 30-second subprocess budget on the request thread.

**Trigger/impact:** authenticated admin sends shape-valid audio after exhausting allowance or with disabled/unconfigured assistant. Rejected transcription still consumes decoder CPU/process/worker time outside the enforced allowance. Host exhaustion was not attempted.

**Direction:** cheap authorization/readiness/admission before decoding, bounded decoder concurrency, and asynchronous analysis where compatible with the contract.

### A37 — Medium — In-flight assistant writes survive mid-provider authorization revocation

**Routes:** POST cookie/desktop assistant messages, followed by background reply execution.

**Chain:** initial `ExecutionPolicy` → provider wait → generation-only `GenerationWriteGuard` → page/website/operation writer.

**Evidence:** `app/services/ai_assistant/activities/reply.rb:27–32`; `assistant/execution_policy.rb:38–50`; `assistant/generation_write_guard.rb:31–36,50–53`. `assistant/tools/session.rb:189–192,214–226` guards page generation without rechecking actor/module policy; `assistant/generate_page.rb:20–31,45–54` writes. Operation authorization exists at `app/services/operations/activities/execute.rb:40–47` but uses a supplied possibly cached actor at `app/services/operations/authorization.rb:9–13` and does not check assistant enablement. Website processing checks Website enablement, not the complete assistant-user policy.

**Trigger/impact:** deactivate/demote the initiating admin or disable the assistant module while the model is in flight, leaving its generation current/running. Returned tool/content can still mutate the existing tenant. Cancellation/supersession is enforced; queued work checked after revocation is a different, rejected case. No new cross-tenant escalation was demonstrated.

**Verification:** write-boundary source review and counterevidence check; no database interleaving run.

**Direction:** fresh persisted execution authorization at irreversible write boundaries under the appropriate lock, alongside generation freshness.

### A38 — Medium — Assistant website revisions overwrite intervening draft edits

**Routes:** POST assistant message, concurrent PATCH/PUT website page.

**Chain/evidence:** `app/services/ai_assistant/assistant/prompt/sections/website_catalog.rb:56–64,72–74` provides a full replacement snapshot; `app/services/websites/assistant/processor.rb:158–174,193–201,219–223` reloads the current page but passes the model replacement without expected version/fingerprint; `app/services/websites/activities/save_page.rb:14–17,76–84` persists it.

**Impact:** another admin's successful draft edit during model latency is silently replaced. Final locks provide atomicity, not stale-read detection. Undo may recover but does not prevent loss.

**Direction:** include the model's input version/fingerprint and require reviewed rebase/conflict handling before replacement.

### A39 — Medium — Website Undo omits theme/navigation-position changes from its fingerprint

**Route:** `POST /:cid/admin/modules/ai_assistant/messages/:id/undo`.

**Chain/evidence:** `app/services/websites/assistant/undo.rb:43–45` omits `theme_key`, `layout_key`, and `position`; `100–105` treats equal fingerprints as unchanged; `121–122` deletes assistant-created pages. Theme updates are accepted at `app/controllers/admin/modules/website/pages_controller.rb:184–186`; ordering persists at `app/services/websites/activities/reorder_pages.rb:14–16`.

**Verification/impact:** actual fingerprints on record doubles stayed equal after these fields changed. Editing a valid theme/reordering an assistant-created draft, then Undoing its creation, can delete later work. Ordinary editor layout changes are restricted, so theme/position are the primary reachable examples.

**Direction:** fingerprint every user-editable persisted field relevant to the proposed inverse operation.

### A40 — Medium — Deletion can remove a concurrently promoted website home page

**Routes:** DELETE website page racing update with `home=true`.

**Chain/evidence:** page loads at `app/controllers/admin/modules/website/pages_controller.rb:152–156`; `app/services/websites/activities/destroy_page.rb:8–17` checks stale `home?` and destroys without reload/shared lock. Promotion at `save_page.rb:12–17,162–164,188–194` demotes the prior home. `app/models/website_page.rb:16–21` has no fresh destroy guard; public home returns 404 at `app/controllers/websites/pages_controller.rb:18–19,43–46`.

**Trigger/impact:** deletion loads an inner page; another request promotes it and demotes the old home; deletion resumes with stale state. The site is left without its new home. Source interleaving, not a concurrency test.

**Direction:** use the promotion-compatible customer lock and fresh protected-home check inside deletion.

### A41 — Medium — Catalog GETs mutate every tenant's website sections and can lose edits

**Routes:** tenant website settings GETs; platform skeleton/layout catalog GETs.

**Chain:** settings/gallery → `Websites::Catalog.layouts/skeletons/sync!` → `ensure_layouts!` → `fill_page_media!` → unscoped page backfill.

**Evidence:** `app/components/websites/admin/settings_form_component.rb:89–90`, `skeleton_replace_component.rb:86–90`; platform gallery controllers invoke sync. `app/services/websites/catalog.rb:1156–1158,1178–1185,1215–1220,1258,1297–1304` iterates all `WebsitePage` rows and writes entire transformed `sections` via `update_columns`. Media substitutions occur at `app/services/websites/media.rb:549–558,652–666`. `WebsitePage` has no tenant default scope. Normal `SavePage` locks/reloads; this backfill does not.

**Verification/impact:** real backfill/media methods on doubles targeted two customers. Opening one tenant's settings on an unsynchronized worker can modify other tenants' eligible media, including published pages; the caller cannot choose arbitrary replacement content. A concurrent editor save can additionally be overwritten by the stale whole-section write.

**Direction:** move migration-like backfills out of request GETs, scope intentionally, and use fresh narrow updates through the customer-serialized writer.

### A42 — Low — Template-token errors reveal another tenant's attribute existence

**Route:** PATCH/PUT customer email template token.

**Chain/evidence:** owned token is loaded at `app/controllers/admin/settings/modules/emails/template_tokens_controller.rb:81–82`; update assigns submitted foreign entity ID at `app/concepts/emails/template_tokens/operation/update.rb:26–29`. `app/models/emails/template_token.rb:112–130` checks that entity's schema before tenant accessibility; errors render through the form.

**Verification/impact:** real validation on doubles returned only `entity_not_accessible` for a known foreign slug, but additionally `unknown_attribute` for a missing guessed slug. Update is rejected; the oracle discloses schema metadata, not entry values.

**Direction:** resolve/authorize entities in a permitted scope before dereferencing their schema, and avoid distinguishable forbidden-object validation.

### A43 — Low — Non-owner platform-tenant admins can revoke owner trusted devices

**Route:** DELETE `/81721200/admin/modules/authentication/users/:owner_id/trusted_devices/:id`.

**Evidence/chain:** `app/controllers/admin/modules/authentication/user_trusted_devices_controller.rb:14–17` uses the tenant user's device association without `OwnerAccountProtectable`. That concern's intended restriction is at `app/controllers/concerns/authentication/owner_account_protectable.rb:13–15,27–33`; the row enables trusted-device verification at `app/models/authentication/trusted_device.rb:40–49`.

**Impact:** a non-owner admin in customer 81721200 can remove the owner's trusted-device record and force renewed MFA. This does not grant owner access or disable MFA.

**Direction:** apply the same owner-account security mutation protection to device deletion.

### A44 — Low — Custom role creation/assignment contradicts the stated three-role policy

**Routes:** POST customer roles and user-role assignments.

**Evidence/chain:** `app/controllers/admin/settings/modules/authentication/roles_controller.rb:39–40,79–80` accepts custom keys; `app/concepts/roles/operation/create.rb:10–15` creates `system:false`; contract at `app/concepts/roles/contract/create.rb:6–11` allows arbitrary syntactically valid keys. `app/concepts/user_roles/operation/assign.rb:26–33,47–48` retains one reserved role but also assigns nonreserved roles. Request specs intentionally expect custom-role creation.

**Impact:** `manager` or other custom roles can be persisted/assigned despite AGENTS.md saying no additional roles. Current namespace gates still require reserved roles, and interactive owner minting remains prohibited. This is a policy mismatch, not established privilege escalation.

**Direction:** decide whether the written three-role policy or implemented supplemental-grant roles is authoritative, then align validation/routes.

## Findings: platform maintenance and runtime

### A45 — High — Empty-trash can permanently delete a just-restored customer

**Routes:** DELETE platform customers/empty_trash racing PATCH customer restoration.

**Chain/evidence:** `app/controllers/admin/maintenance/platform/customers_controller.rb:47–48` passes deleted customers; `app/services/customers/purge.rb:38–43` snapshots IDs. At `64–74`, purge locks `Customer.unscoped.where(id: @customer_ids)` without rechecking deletion state. Restoration uses `customer_restorations_controller.rb:7–9`, `base_restorations_controller.rb:21–25`, `app/models/concerns/soft_deletable.rb:55–56`.

**Trigger/impact:** capture trash ID, restore/commit in another owner tab, then purge locks and deletes it. A successful restoration can be followed by irreversible active-customer data loss.

**Verification:** source interleaving; no destructive/concurrent database test.

**Direction:** revalidate trash state inside a boundary shared with restoration and exclude/abort changed records.

### A46 — Medium — Customer purge deletes blob metadata but retains file bytes

**Route:** DELETE platform customers/empty_trash.

**Chain/evidence:** `app/services/customers/purge.rb:71–74,93–97,128–135,170–183` constructs anonymous table models and `delete_all`s customer blobs/attachments. `db/schema.rb:34–45` contains blob customer/key/service metadata. There is no service-aware file deletion. Active Storage `Blob#purge/#purge_later` supplies that lifecycle; production storage is local.

**Impact:** files and possible derivatives remain after their database identity disappears, retaining deleted-customer data and consuming storage. Ordinary blob lookup stops working; no public download bypass was shown.

**Direction:** preserve retriable cleanup identity and integrate Active Storage purge. A GlobalID purge enqueued after deleting the blob row cannot resolve it.

### A47 — Medium — Generator mutations change disk and then fail in production

**Routes:** platform code-generator create/update/destroy.

**Chain/evidence:** `app/controllers/admin/maintenance/platform/code_generators_controller.rb:93–96,208–211` mutates source before `Rails.autoloaders.main.reload`. `config/environments/production.rb:6–10` disables reloading/enables eager loading. Installed Zeitwerk `loader.rb:241–243` raises `ReloadingDisabledError`; an isolated loader probe confirmed it.

**Impact:** failure response after the file changed; running process keeps previous code while the next boot sees changed/deleted source. Neither the response nor loader state represents transactional publication.

**Direction:** explicit production publication/deployment lifecycle rather than reloading a reload-disabled app loader.

### A48 — Medium — Generator load failure leaves last-known-good source overwritten

**Routes:** platform code-generator create/update.

**Chain/evidence:** `app/services/code_generators/generator_validator.rb:20–59` compiles/checks regex declarations; `app/controllers/admin/maintenance/platform/code_generators_controller.rb:196–213` writes live source before registry loading, with no restore. `app/services/code_generators/generator_registry.rb:96–110` surfaces load failures; production eager-loads the file.

**Verification/impact:** a syntactically valid class-body `raise` passed real validation without execution. Ordinary missing-constant/DSL initialization mistakes can remain on disk after publication fails, break discovery, or prevent next boot. This is independent of the intentional owner-only Ruby-editing capability.

**Direction:** staged atomic publication, preserve old source through validation/load failure, and explicit recoverability. Atomic rename alone does not establish successful multi-process publication.

### A49 — Low — New element-type generator creation succeeds but cannot be discovered

**Route:** POST platform code_generators with `kind=element_type` and a new type.

**Evidence/chain:** `code_generators_controller.rb:169–171` writes a new directory; `app/services/code_generators/generator_registry.rb:57,61–65` scans only start/end/decision/loop/subflow; success redirect at controller `60–61` later requires registry membership at `110–112`.

**Verification/impact:** valid `Custom::CustomGenerator` assembled/validated; its new directory falls outside discovery. File exists, success redirects to 404.

**Direction:** align creation validation and supported discovery or implement deliberate dynamic type registration.

### A50 — Low — Regex generator I/O analysis disagrees with valid Ruby syntax

**Routes:** generator detail and POST test_run.

**Chain/evidence:** `app/services/code_generators/test_runner.rb:23–31` → `code_introspector.rb:5–8,14–19,37–41` strips strings/uses regex. Existing AST analyzer at `app/services/code_generators/io_extractor/body_analyzer.rb:39–65,83–87` recognizes the missed constructs.

**Verification/impact:** `ctx[:total] ||= ctx[:seed]` reports no output in test-run analysis, while the AST finds `total`. `ctx[:out] = "hello #{ctx[:name]}"` reports no input while AST finds `name`. Wiring/detail guidance can omit requirements and disagree with IO endpoints; generated code was not executed.

**Direction:** consolidate on Ripper/Prism AST-backed analysis, preserving supported `dig`/`fetch` semantics.

### A51 — Low — Failed captcha/AI settings saves discard submitted nonsecret values

**Routes:** PATCH/PUT platform captcha and AI settings.

**Chain/evidence:** controllers load one display instance, activities assign a separately loaded failed instance, error rendering retains the original. Captcha: `app/controllers/admin/maintenance/platform/captcha/settings_controller.rb:22–30,54–57`, `app/services/captcha/activities/update_provider_settings.rb:16–24,31–32`. AI: corresponding controller `23–31,56–62`, activity `20–27,36–37`.

**Impact:** invalid submission rerenders persisted values and loses otherwise valid edits, requiring re-entry.

**Direction:** render the returned failed model while preserving secret masking.

### A52 — Low — Displayed generator errors/editor wording and credential placeholders bypass I18n

**Routes:** generator new/edit/create/update/validation; email credential forms.

**Evidence/chain:** `app/services/code_generators/generator_validator.rb:24,31,35,42,52,58` constructs displayed English errors; validation controller `app/controllers/admin/maintenance/platform/code_generators/validations_controller.rb:10–12` and generator form render them. `app/components/platform/code_generators/form_component.html.erb:149` includes literal wording; `app/components/admin/maintenance/platform/emails/credential_form_component.html.erb:64,94,163,177` has literal placeholders.

**Impact:** zh-CN users receive English-only user-facing copy, violating required bilingual delivery. This is separate from model-facing English API descriptions, which are intentionally untranslated.

**Direction:** add matching en/zh-CN keys and translate at call time, preserving existing locale keys and English text.

### A53 — Medium — All routes run on an end-of-life Ruby branch

**Scope/evidence:** `.ruby-version:1` pins 3.2.8; `ruby -v` confirmed it. Ruby's [official maintenance-branch page](https://www.ruby-lang.org/en/downloads/branches/) lists Ruby 3.2 as EOL on **2026-04-01**. Brakeman independently flagged the branch (its cutoff is the previous day's maintenance end).

**Impact:** the runtime serving all routes no longer receives upstream fixes, including future security fixes. This audit does not assert a particular exploitable Ruby CVE.

**Direction:** move to a supported runtime compatible with the resolved Rails/gem stack and verify its native/provider dependencies.

## Conditional policy and architecture risks

These are demonstrated behaviors, but their classification depends on the intended trust/product policy. They are not additional confirmed-vulnerability counts.

1. **Owner generator editing is trusted Ruby publication, not a discovered privilege escalation.** `SourceAssembler` accepts Ruby class-body content; saves/load/preview/test/IO invoke generator code in the app process (`app/services/code_generators/source_assembler.rb:38–51,138–141`, `generator_interface.rb:15–35`, controller `208–211`). Only the pinned platform owner is authorized. That grants process/filesystem/environment/database capability, broader than UI-only administration, by design. If this trust is unacceptable, use a restricted data DSL or OS-isolated execution. No reliable in-process Ruby sandbox is recommended. The HTTP test route calls `TestRunner.run`, not `execute`; it runs generator implementation methods, not the emitted step. A47–A48 are independently real operational defects.
2. **Immediate email replacement without old-inbox notice.** `config/initializers/devise.rb:21` disables reconfirmation; notifications retain Devise's false defaults. Passworded account/member edits require current password (`app/controllers/authentication/registrations_controller.rb:86–108`, `app/contracts/member/profiles/update_contract.rb:35–52`). A valid request immediately moves recovery to the new address. Decide whether mailbox proof/old-address notification is required; Devise supports both. This is not a demonstrated current-password bypass.
3. **New MFA mandates do not reauthorize existing desktop OAuth families.** Cookie/browser requests reread `MfaObligation`; Bearer controllers skip it (`app/controllers/concerns/oauth/bearer_authenticatable.rb:16–20`). `TokenIdentity` checks scope/client/account, not current MFA obligation (`app/services/oauth/token_identity.rb:22–32`); refresh does not revisit browser MFA. First enrollment does not revoke prior credentials (`app/services/authentication/credential_lifecycle.rb:41–44`). A real in-memory decision probe accepted the token while obligation was `enroll`. New OAuth authorization is correctly MFA-gated. If a newly imposed mandate must cover existing families immediately, this is a medium policy gap; otherwise define the grace/revocation semantics explicitly.
4. **Member MFA recovery trusts mailbox possession alone.** `RequestResetLink`/`ConsumeResetLink` disable MFA through an emailed bearer, while sign-in links use the same inbox. This limits MFA independence under mailbox compromise. A15 is the distinct credential-change revocation defect.
5. **Member page surface enablement is navigation visibility, not direct-URL revocation.** `Member::Sources::Pages`/navigation checks surface enablement, but `Member::PagesController#show` checks launch/audience without that toggle. Decide whether hiding the navigation should deny page URLs; current authority is the page's audience/launch state.

## Mature library/framework replacement opportunities

These identify actual hand-written implementation seams, not generic recommendations to replace application policy. Prefer a thin application facade. A listed library does not automatically fix authorization, tenancy, atomicity, or admission budgets.

| Current source / implementation | Established replacement | Benefit, limits, and relevant findings |
|---|---|---|
| `flowchart_runtime/where_clause_builder.rb:67–141,224–262`; formula literal emission at `formula_compiler.rb:208–212` | **Installed ActiveRecord/Arel and adapter quoting** | Replace SQL string serialization with typed/bound nodes. Keep DSL/field allowlists and SQLite-specific JSON/subquery semantics. Arel APIs require upgrade-focused coverage. Addresses A01/A02; `Arel.sql(raw_input)` is not a fix. |
| Custom credential flow in `authentication/sign_in_flow.rb`, `password_verification.rb`; skipped Warden strategy | **Installed Devise/Warden strategy** | Restore maintained paranoid hashing/Lockable strategy behavior. Keep tenant eligibility, custom responses, MFA/session completion; avoid duplicate failure accounting. A13. |
| `authentication/throttle.rb` and repeated flood-limit plumbing | **Installed Rack::Attack / Rails rate-limiting primitives** | Shared counter/window/admission handling. Failure-only versus count-all, clear-on-success, and concurrency semantics require explicit preservation. A14. |
| `member/mfa/reset_token.rb` custom state/expiry projection | **Rails `generates_token_for`** | Bind validity to explicit changing credential state; retain locked verification/consumption. Not a direct substitute for pre-user signup tokens. A15. |
| `ai_assistant/assistant/markdown.rb:40–91` regex Markdown parser | **Installed Kramdown + GFM parser** | Mature block/nesting parsing, behind a restricted converter and current Rails safe-list sanitization. Rendering differences require focused checks; parser is not sanitizer. No current XSS bypass was established here. |
| `pages/formula_evaluator.rb`, its `tokenizer.rb`/`parser.rb` | **Installed Dentaku** behind a page-calculation adapter | Eliminate duplicate evaluator machinery; map field tokens and constrain functions/length/depth. Preserve nil/date/numeric/browser semantics. Do not confuse this Ruby evaluator with the SQL compiler, whose documented parser incompatibility remains valid. |
| `captcha/request_replayer.rb:70–118` manual multipart body/header assembly | **[http-form_data](https://github.com/httprb/form_data)** | Mature multipart/IO encoding and name/filename quoting. Recursive extraction, nested shape, MIME validation, and aggregate limits remain application work. Encoder replacement alone does not fix A28. |
| Author-defined regex at `pages/rules_engine.rb:259–265` and custom format matching | **[RE2](https://github.com/mudge/re2)**, or Ruby's per-regex timeout | Bounded non-backtracking matching. RE2 rejects lookarounds/backreferences and adds a native dependency; define supported grammar. A31. |
| Page link output and duplicated URI checks | **Installed Addressable::URI + Rails/Loofah safe-list boundaries** | One explicit scheme/relative URL policy. Parsing/escaping alone do not reject executable schemes. A04. |
| `code_generators/code_introspector.rb`, regex declarations in `generator_validator.rb` | **Existing Ripper AST analyzer / installed Prism** | Consolidate structural/source-range analysis, interpolation/operator assignment support. AST parsing does not prove load-time success or sandbox Ruby. A48/A50. |
| Generator `File.write` publication | **ActiveSupport `File.atomic_write`** | Avoid partially visible files; add publication locking, failure restoration, and production/multi-process lifecycle. A47/A48 need more than atomic rename. |
| Customer purge's raw Active Storage row deletion | **Active Storage `Blob#purge/#purge_later`** | Service-aware original/variant cleanup with preserved retry identity; asynchronous file deletion is not a database rollback. A46. |
| Repeated attachment validation / direct-upload admission | **[active_storage_validations](https://github.com/igorkasyanchuk/active_storage_validations)**; installed **Marcel** for bytes | Established size/count/type/dimension validation. Does not impose pre-upload/cumulative tenant budgets; analyzers cost resources. Help attachments currently rely on MIME headers at `app/services/help/attachment_rules.rb:60–63`; Marcel can improve that classification seam. A33. |
| Duplicated recurrence arithmetic in `emails/send_activities/start_send_activity.rb:83–109,145–165` | **[ice_cube](https://github.com/ice-cube-ruby/ice_cube)** | Mature schedule/occurrence calculation. Map only supported presets and preserve COUNT/UNTIL/catch-up/month-end/DST policy. Significant semantics review, not a drop-in recurrence rewrite. |
| Ad hoc page/settings JSON shape checks | **Installed JSONSchemer** | Schema types/enums/bounds for modules/predicates/layout/config, retaining Reform/domain validation and form-string normalization. Does not enforce tenancy or safe SQL by itself. |
| PayPal REST/OAuth request and response parsing in `payments/gateways/paypal.rb:158–227,301–349` | Official **[paypal-server-sdk](https://github.com/paypal/PayPal-Ruby-Server-SDK)** | Replace Orders/Payments models and OAuth/endpoint plumbing behind existing gateway. Distinguishes order/capture enums. Webhook verification is not fully covered; retain a narrow wrapper and application settlement/idempotency policy. Source already evaluated an earlier SDK; this is a partial migration opportunity. A21/A23. |
| PayPal client-credentials acquisition only | **[oauth2](https://github.com/ruby-oauth/oauth2)** | Smaller maintained token/expiry/bearer replacement if retaining REST adapter; overlaps the official SDK option and does not fix financial response semantics. |
| Stripe-specific recurring period/SCA/dunning/cancellation engine | **Stripe Billing/Subscriptions via installed official Stripe SDK** | Delegates provider lifecycle/cancellation. Significant migration, fees, and product/merchant tradeoffs; not a vendor-neutral Alipay/WeChat substitute. A27. |
| Version save/promote/launch hand-written stale checks | **ActiveRecord optimistic locking / atomic head CAS** | Framework-supported conflict detection, consistently integrated with head tables and `update_column` bypasses. A07/A08/A38/A40. |

**Already library-backed:** Doorkeeper PKCE, ROTP/RQRCode, Rails signed/encrypted tokens, Twilio signatures, Phonelib, SES/SNS, official Stripe/AWS clients, RubyLLM/STT adapters, Mail/SMTP/DKIM, Faraday, RubyMoney, Pagy, Liquid, Rubyzip, JWT, Loofah, TSort, Builder, caxlsx, Prawn, BCrypt/SCrypt/Argon2. Keep these thin wrappers; the findings mostly concern integration/policy around them.

**No verified mature drop-in:** Aliyun RPC/NLS signing, Alipay RSA2/OpenAPI, and WeChat APIv3 signing/decryption/certificate lifecycle. The Ruby `aliyun-sdk` examined covers OSS, not these RPC services; the older `wx_pay` targets XML/MD5, not APIv3. Alipay's cited process-global rationale is outdated because `Alipay::Client` supports instance credentials, but suitable current maintenance/maturity was not established. A guessed incompatible vendor gem is not a recommendation. The hand-written SQL formula transpiler also has a documented compatibility justification for retaining its grammar; its SQL serializer is still defective.

## Revalidation of the earlier report

| Earlier conclusion | Current disposition |
|---|---|
| Composite-list SQL injection | Confirmed and executed with synthetic data; consolidate expanded public/member/admin/options consumers into A01. |
| Public checkout same-provider replay of billing/recurring prepay | Corrected: `PrepareAttempt` operation binding blocks that unresolved replay. Predictable-order disclosure/conditional alternate-provider interference remains A19. |
| Public billing-result identifiers are enumerable | Confirmed, A20; medium impact. Genuine capture projection is not itself a settlement-auth bypass. |
| Unconfirmed member signup pre-hijacking | Confirmed, A11, with MFA qualification. |
| Immediate email change | Behavior confirmed; classified as a policy-dependent recovery risk rather than current-password bypass. |
| Raw confirmation/login tokens | Confirmed, A17; sequential replay rejection does not cover the A16 race. |
| Unsandboxed generator editor is standalone high RCE | Reclassified as intentional pinned-owner trusted-code capability. A47/A48 describe real publication defects. |
| Generator category statement payload executes on ordinary autoload | Not confirmed: isolated Zeitwerk namespace validation rejected that directory with `NameError` before autoload. Invalid publication/boot handling remains relevant; direct owner Ruby editing already exists. |
| No confirmed defects in other route groups | Superseded by the evidence-backed findings and coverage map in this report. |

## Verification evidence and limits

- The actual route file expanded successfully without application initialization: **724 entries / 212 controllers / 545 unique actions**. Installed Devise/Doorkeeper generated routes include `/oauth/authorize/native` and `/oauth/introspect`; neither is omitted from the inventory.
- Real condition/formula compiler output executed only against synthetic/in-memory SQLite SELECT data and demonstrated cross-tenant reads. No real user data was accessed and no SQL writes were tested.
- Standalone probes verified PayPal capture-state mapping, duplicate partial refunds, mismatched refund-event settlement, old PayPal retry exemption, Alipay sandbox endpoint choice, checkout operation binding, Beijing/UTC boundaries, token/confirmation behavior, upload snapshot/cache failure, CSV output, and selected pure-control-flow decisions.
- Critical routes/findings received a separate counterevidence review. In particular, cached-page exposure was restricted to cache-preferring maintenance reads; operation authorization was acknowledged; checkout same-provider replay was rejected.
- Brakeman **7.1.2** completed with **37 warnings and zero scan errors**, using `--skip-files app/services/page_layout_templates/templates/`. Its output is supporting evidence, not 37 confirmed vulnerabilities. Dynamic eval is owner-generated activity execution; signed click redirects and registered generator file lookup have additional validation; many SQL warnings involve checked identifiers. Confirmed SQL findings above were independently traced/probed.
- No passing RSpec/full-request/browser/provider/concurrent-database claim is made. Provider/environment prerequisites and deployment storage/ingress/cleanup controls remain unverified. Pure/stub probes establish method decisions, not production timing or provider capture.
- An Alipay native bill-type/archive/parser mismatch remains an **unconfirmed integration lead**: download cron supplies `all`, adapter sends `ALL`, while a gateway spec uses `trade`; native archive/header handling was not established against current vendor documentation. It is not included in the finding count.
- Generic Operations concurrent same-key replay deserves an isolated integration check, but this audit did not establish a declared HTTP route exposing the necessary caller-selected key/concurrent execution. It is not counted as a confirmed route defect.
- No general cross-tenant controller-IDOR, interactive owner-role minting, PKCE/redirect bypass, or webhook-signature forgery was established. Those checked boundaries do not invalidate the specific downstream defects above.

## Route-to-source coverage appendix

The following inventory links every declared URL/action to its principal implementation chain. Common filters, source-path conventions, resource expansions, and repeated tenant/platform mounts are defined in the appendix to keep it reviewable.

### Appendix conventions and common source chain

This appendix is a static coverage map of the **724 entries / 212 routed controllers / 545 distinct controller/action pairs** in `/tmp/opencode/route-audit-inventory.json`, generated by the isolated mapper `/tmp/opencode/route_audit_inventory.rb`. It documents the already-audited source chains; it does not add execution or security-test claims. The numbered route ledger preserves the inventory's original entry numbers, including duplicate root destinations, aliases, verb variants and remounts.

- **Exact paths:** the ledger retains every JSON path verbatim, including `/:customer_id`, nested IDs, `:module_key`, `:key`, `:slug`, `:page_slug`, `:uuid`, `:provider`, `:kind`, and `(.:format)`. `:cid` in the findings is shorthand only. No prefix substitution or resource compression is needed to reconstruct the 724 entries.
- **GET/HEAD and formats:** every GET also accepts implicit HEAD; this does not add a separate JSON entry. HEAD may deliberately avoid token consumption. `(.:format)` is optional format syntax, not an extra endpoint. `/` and `/*shortcut_path` shortcut declarations have `format: false`: dots belong to the shortcut path. `/email/track/:message_id/open.gif(.:format)` retains its literal `.gif` plus the optional format exactly as emitted by Rails.
- **Resource macros:** plural `resources` expands to index/new/create/show/edit/PATCH update/PUT update/DELETE destroy, subject to each declared `only`/`except`; singular `resource` omits the resource's own ID and index. Collection/member custom actions and nested parent parameters are separate entries. PATCH and PUT are counted separately when the inventory contains separate entries; the manually declared registration update remains the single verb expression `PUT|PATCH`. No omitted action is inferred from a conventional full CRUD macro.
- **Controller source convention:** every application identifier `x/y` below maps to `app/controllers/x/y_controller.rb` and its namespaced CamelCase class (`x/y` → `X::YController`, applying the source's acronym spelling, e.g. `Oauth`, `AiAssistant`, `Sms`, `IoParams`). `rails/health` is the framework exception. The catalogue names actual superclass/includes and action sources; the final source-file index resolves all linked principal downstream classes to repository files.
- **Chain IDs:** `Cnnn.action` is a unique controller/action source record. Each numbered route row points to exactly one such record. The source record gives the principal action-specific handoff; its family reference supplies shared deeper collaborators, not an assertion that every family service executes on every action. Direct model reads/saves, empty actions, inherited implementations, redirects, and implicit template rendering are identified explicitly.
- **Implicit rendering:** an empty or read-only Ruby action still runs inherited filters and Rails implicit rendering of `app/views/<controller>/<action>.html.erb` (or the explicit alternate template). ViewComponents are reached through those templates/presenters; there need not be a service call. Registered module/descriptor surfaces can select components dynamically. The source chains describe the principal boundary rather than every possible installed module branch.

**ApplicationController concern chain:** `app/controllers/application_controller.rb` → `TenantContext` (`app/controllers/concerns/tenant_context.rb`: request metadata, PATH_INFO customer lookup, Current context and protected cross-tenant checks) → `FeatureModules::HostIntegration` (`app/controllers/concerns/feature_modules/host_integration.rb`: enabled registrations' before_request callbacks and module host helpers) → `RouteAuthorization` (`app/controllers/concerns/route_authorization.rb`: Devise authentication, admin/member/owner path roles, platform path identity, CanCan verb/route subject through `app/models/ability.rb`) → `SetLocale` (`app/controllers/concerns/set_locale.rb`) → `Authentication::HandlesCredentialConflicts` (`app/controllers/concerns/authentication/handles_credential_conflicts.rb`) → `Authentication::EnforcesMfa` (`app/controllers/concerns/authentication/enforces_mfa.rb`: `MfaObligation`, `MfaSessionVerification` and challenge/enrollment routing). Browser-version and importmap/ETag hooks, dashboard/member layouts, Rails forgery handling, and the controller's own filters then form its rendering/request boundary. Included concerns register callbacks; this list states the composition, with prepended filters and explicit skips called out below.

**Inheritance exceptions:** Devise sessions/passwords/confirmations/registrations inherit installed Devise controllers, whose parent is ApplicationController; app authentication includes/overrides add throttle, permitted params, trusted devices and session completion. OAuth authorization uses Doorkeeper's **browser** base configured as ApplicationController; OAuth token/revoke/introspect use **ApplicationMetalController → ActionController::API → ActionController::Metal** (the installed gem's default metal base), while discovery/userinfo and payment/email/SMS webhooks use **ActionController::API**. Rails Health, email tracking and unavailable-root are **ActionController::Base directly**. They do not inherit the application's common concerns. Desktop entity-definition/message/transcription controllers do inherit ApplicationController, but prepend `Oauth::BearerAuthenticatable`, establish a request-only Warden user, and skip cookie forgery/MFA/browser checks. Public unsubscribe/challenge/payment controllers have their explicit authentication/MFA/browser exceptions in the controller source; public path classification alone is not a claim that a sensitive auth action lacks a signed-in/pending-auth guard.

**Reusable inherited implementations:** `app/controllers/admin/maintenance/base_versions_controller.rb` implements current-line index/show, restore-as-new create, default-head selection and version destruction/orphan sweep; entity promotions override create/default. `app/controllers/admin/maintenance/base_restorations_controller.rb` implements declared restore update actions; Page restoration has its own update. `app/controllers/concerns/soft_deletable_controller.rb` supplies trash/empty_trash where not overridden; platform Customer empty_trash uses `Customers::Purge`. `app/controllers/admin/maintenance/platform/base_credentials_controller.rb` supplies credential create/update and subclass persistence hooks. Customer and platform billing inherit their respective `app/controllers/admin/settings/billing/base_controller.rb` and `app/controllers/admin/maintenance/platform/billing/base_controller.rb`. Payment/website/SMS module base controllers add module availability/context; `app/controllers/member/base_controller.rb` adds member layout/current user/owned-record checks.

The module base sources are `app/controllers/admin/modules/payments/base_controller.rb`, `app/controllers/admin/modules/website/base_controller.rb` and `app/controllers/admin/modules/sms/base_controller.rb`; SMS additionally performs explicit admin checks, request-body/attribute parsing and scoped record lookup. Captcha surfaces/pages inherit `app/controllers/admin/maintenance/platform/captcha/throttles_controller.rb` for shared throttle parameters/redirects. Installed Devise 5.0.4 action sources are `app/controllers/devise/sessions_controller.rb`, `passwords_controller.rb`, `confirmations_controller.rb` and `registrations_controller.rb` under that same gem directory; Recoverable/Confirmable/Lockable and account callbacks live under `lib/devise/models/`. These gem paths describe inherited actions rather than nonexistent application overrides.

### Constraints, ordering, aliases and remounts

| Declaration boundary | Source and precise coverage meaning |
|---|---|
| Tenant scope | `config/routes.rb` requires `customer_id: /\d{8}/`. JSON paths keep `:customer_id`; record IDs retain their own names. Protected platform URLs additionally require the outer customer path to be `81721200` in RouteAuthorization. |
| Conditional roots and last-resort shortcuts | In route order: `/` → websites/pages home, websites/pages show, public_pages show, unavailable-root, then home index. `PageShortcuts::RouteConstraint` / `PageShortcuts::Resolver.unavailable_root?` determine selection. The three GET `/*shortcut_path` destinations and POST `/`/`/*shortcut_path` aliases are the final declarations; website targets never match POST. These entries remain separate in the ledger even when verb/path are identical. |
| Public page/action/website constraints | `:uuid` uses `/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/i` at routes.rb:209; `:action_key` is `[a-z][a-z0-9_]{1,62}`; `:page_slug` is `[a-z0-9]+(?:-[a-z0-9]+)*`; `:signed_id` is `[^\/]+`. Help/developer-doc `:slug` uses `[a-z0-9]+(?:-[a-z0-9]+)*`. These are recognition constraints, not renamed parameters. |
| Provider callbacks | Payments/email provider recognition consults the runtime gateway/provider registry; SMS consults its adapter registry. SMS retains `:kind`. Controllers then perform adapter verification and credential/event binding. The inventory contains one declared dynamic route per callback, not one entry per installed provider. |
| Generator/reference constraints | Generator `:slug` is `[^.]+` (can span slash-separated registered identities); nested generator routes use `:code_generator_slug`. Step `:generator_action` / `:element_type` are `[A-Za-z0-9_]+`; reference `:source` is `[a-z][a-z0-9_]*`. IO POST actions map to `show`, rather than assumed `create`. |
| Shared tenant/platform remounts | Constants, entities, flowcharts, pages and declared subresources are explicitly remounted under `/:customer_id/admin/maintenance/platform/`; their controller identifiers remain `admin/maintenance/...`, without `/platform/`. Every remount is a separate exact ledger row. Overrides are tenant-only; domain membership/domain editors, tenant step/element IO, field-template collection and standalone template picker/preview are not inferred platform remounts. Platform-specific generator IO controllers have their own entries. |
| Module path/controller aliases | Public `/email/...` uses `emails/...`; platform `/module_settings/email/...` uses `admin/maintenance/platform/emails/...`; `/module_settings/payment/...` uses the payments controllers. Admin records remain `/modules/emails`, `/modules/payments`; generic module records and how-to/configuration routes preserve the JSON's distinct key/parent names. Settings website/captcha roots and admin root/assistant aliases appear separately. |
| Last-resort member descriptors | `/:customer_id/member/:key(.:format)` and `/:customer_id/member/:key/:id(.:format)` are declared after fixed member routes. Known fixed paths are **`/:customer_id/member`**, **`/member/profile`**, **`/member/profile/edit`**, **`/member/security`**, **`/member/security/mfa`**, **`/member/security/mfa/setup`**, **`/member/trusted_devices/:id`**, **`/member/pages/:id`**, **`/member/payments/payment_methods`**, **`/member/payments/payment_methods/new`**, **`/member/payments/payment_methods/setup_intent`**, **`/member/payments/payment_methods/:id`**, **`/member/payments/subscriptions`**, **`/member/payments/subscriptions/:id`**, and **`/member/payments/subscriptions/:subscription_id/cancellation`** (all `/member/...` entries in this cell carry the leading `/:customer_id`; verbs/actions are in the exact ledger). Builtin descriptors are rejected by SurfacesController; registered entity/custom descriptor keys are resolved by Member::Surfaces, not invented fixed endpoints. Pages and descriptor surfaces explicitly permit same-tenant admin/owner read previews. |

### Principal downstream chain families

Links resolve to source files; the source-file index below also lists their complete repository-relative paths. These common references complement each action-specific source record.

| Reference | Shared downstream source chain |
|---|---|
| **APP** | ApplicationController common chain above → [`Current`](../app/models/current.rb) / [`Customer`](../app/models/customer.rb) / [`Ability`](../app/models/ability.rb); direct records, presenters or implicit templates named in each action row. |
| **API** | ActionController::API; no ApplicationController browser/tenant/role/MFA chain. OAuth identity/metadata logic is explicit in the action row. |
| **BARE** | ActionController::Base directly; no ApplicationController concerns. The unavailable-root action returns its own response. |
| **HEALTH** | Installed railties 8.1.3 `lib/rails/health_controller.rb`: Rails::HealthController < ActionController::Base, show → render_up / rescue render_down; no application domain writer. |
| **TRACK** | ActionController::Base directly; signed tracking payload binds [`Emails::Message`](../app/models/emails/message.rb) and click destination → [`Emails::MessageEvent`](../app/models/emails/message_event.rb). No tenant URL/cookie authentication chain. |
| **AUTH** | [`Authentication::SignInFlow`](../app/services/authentication/sign_in_flow.rb) → [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb) / user eligibility → [`Authentication::MfaObligation`](../app/services/authentication/mfa_obligation.rb) → [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb) / [`Authentication::LandingPath`](../app/services/authentication/landing_path.rb). [`Authentication::User`](../app/models/authentication/user.rb) callbacks → [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) (trusted-device, sign-in-link and OAuth revocation), [`Authentication::AuditLog`](../app/services/authentication/audit_log.rb) / [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb). Request/reset/signup mail reaches ActionMailer::MailDeliveryJob; Devise inherited actions are identified separately below. |
| **OAUTH_BROWSER** | Doorkeeper 5.9.6 `app/controllers/doorkeeper/authorizations_controller.rb` → browser base configured as ApplicationController in `config/initializers/doorkeeper.rb`; [`Oauth::AuthenticateResourceOwner`](../app/services/oauth/authenticate_resource_owner.rb) → Devise/MFA/desktop protocol; Doorkeeper pre-authorization/authorization-code grant → [`Oauth::AccessToken`](../app/models/oauth/access_token.rb) / [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb). Native result/handoff is a browser action, not a token endpoint. |
| **OAUTH_METAL** | Doorkeeper 5.9.6 `app/controllers/doorkeeper/tokens_controller.rb` → Doorkeeper::ApplicationMetalController (`app/controllers/doorkeeper/application_metal_controller.rb`) → default ActionController::API → ActionController::Metal (`lib/doorkeeper/config.rb:408–409`). Token/revoke/introspect use Doorkeeper OAuth request/grant validation, not ApplicationController cookies/tenant/MFA. [`Oauth::AuthorizationCodeExchange`](../app/services/oauth/authorization_code_exchange.rb) / [`Oauth::AccessToken`](../app/models/oauth/access_token.rb) provide app grant/refresh lifecycle; `config/initializers/doorkeeper.rb` binds PKCE, client, scope, hash and lifetime settings. |
| **DESKTOP** | [`Oauth::BearerAuthenticatable`](../app/controllers/concerns/oauth/bearer_authenticatable.rb) prepends [`Oauth::TokenIdentity`](../app/services/oauth/token_identity.rb) (Doorkeeper Bearer token, desktop client/profile scope, eligible [`Authentication::User`](../app/models/authentication/user.rb)); request-only Warden principal → common TenantContext and RouteAuthorization. It skips forgery/MFA and browser-version checking. Cookies alone are not accepted. |
| **ENTRY** | [`Entity`](../app/models/entity.rb) / [`EntityEntry`](../app/models/entity_entry.rb) → [`Entities::Activities::CreateEntry`](../app/services/entities/activities/create_entry.rb) / [`Entities::Activities::UpdateEntry`](../app/services/entities/activities/update_entry.rb) / association activities → [`EntityEntryContract`](../app/contracts/entity_entry_contract.rb) → [`Entities::Activities::EntryWriter`](../app/services/entities/activities/entry_writer.rb). Display/reference/CSV → [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) / [`Entities::DerivedValues`](../app/services/entities/derived_values.rb) / [`Entities::DerivedExpressions`](../app/services/entities/derived_expressions.rb) → [`FlowchartRuntime::FormulaCompiler`](../app/services/flowchart_runtime/formula_compiler.rb). Person links → [`People::Link`](../app/services/people/link.rb) / [`People::Ownership`](../app/services/people/ownership.rb); delete → [`Entities::DeleteEntry`](../app/services/entities/delete_entry.rb) and EntityEntry cascades. |
| **DEF** | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) (`app/controllers/concerns/admin/maintenance/shared_resource_mode.rb`) selects tenant-owned/override versus platform shared identity. [`Versionable`](../app/models/concerns/versionable.rb) (`app/models/concerns/versionable.rb`) → current-line versions/resolved_current_version and customer heads, with [`SoftDeletable`](../app/models/concerns/soft_deletable.rb) and resource lifecycle. [`Entity`](../app/models/entity.rb) / [`Page`](../app/models/page.rb) / [`Flowchart`](../app/models/flowchart.rb) / [`Constant`](../app/models/constant.rb) are the primary records; [`ConstantCustomerOverride`](../app/models/constant_customer_override.rb) stores constant options. BaseVersionsController/BaseRestorationsController inherited implementations are named below. |
| **DEF_MAIL** | Email TemplateVersionsController → `app/controllers/admin/maintenance/base_versions_controller.rb` → [`Emails::Template`](../app/models/emails/template.rb) / [`Emails::TemplateVersion`](../app/models/emails/template_version.rb) / [`Versionable`](../app/models/concerns/versionable.rb). The subclass adds module enablement; template payload includes scalar, rich-text and attachment state. |
| **PAGE** | [`PageRendering`](../app/controllers/concerns/page_rendering.rb) → [`Page`](../app/models/page.rb).generate_content → [`PageContentGenerator`](../app/services/page_content_generator.rb) / [`CompositePageRenderer`](../app/services/composite_page_renderer.rb) / [`PageContentGenerator::DynamicOptionsResolver`](../app/services/page_content_generator/dynamic_options_resolver.rb) → [`FlowchartRuntime::QueryBuilder`](../app/services/flowchart_runtime/query_builder.rb) → [`FlowchartRuntime::WhereClauseBuilder`](../app/services/flowchart_runtime/where_clause_builder.rb); field/ViewComponent rendering and generated ERB. Submission → [`Pages::PublicSubmission`](../app/services/pages/public_submission.rb) → [`Pages::FormParams`](../app/services/pages/form_params.rb) / [`Pages::RulesEngine`](../app/services/pages/rules_engine.rb) / [`Pages::AudienceGuard`](../app/services/pages/audience_guard.rb) → [`ActivityTracer`](../app/services/activity_tracer.rb) / [`ActivityGenerator`](../app/services/activity_generator.rb) → domain writers, [`People::Ownership`](../app/services/people/ownership.rb) and [`FeatureModules::Invocation`](../app/services/feature_modules/invocation.rb) handoffs. Definition reads resolve the current customer version; maintenance cached previews are explicitly distinguished below. |
| **SHORTCUT** | [`PageShortcuts::RouteConstraint`](../app/controllers/concerns/page_shortcuts/route_constraint.rb) → [`PageShortcuts::Resolver`](../app/services/page_shortcuts/resolver.rb) / [`PageShortcuts::PathPolicy`](../app/services/page_shortcuts/path_policy.rb) / [`PageShortcuts::TargetEligibility`](../app/services/page_shortcuts/target_eligibility.rb) → [`PageShortcut`](../app/models/page_shortcut.rb), [`WebsitePage`](../app/models/website_page.rb) or [`Page`](../app/models/page.rb). [`PageShortcuts::RouteContext`](../app/controllers/concerns/page_shortcuts/route_context.rb) supplies the same existing public controller with target/tenant; [`PageShortcuts::PublicPathContext`](../app/controllers/concerns/page_shortcuts/public_path_context.rb) / [`PageShortcuts::PublicPath`](../app/services/page_shortcuts/public_path.rb) build canonical public links. |
| **CAPTCHA** | [`Captcha::RackGate`](../app/services/captcha/rack_gate.rb) → [`Captcha::UrlMatcher`](../app/services/captcha/url_matcher.rb) / [`Captcha::ThrottleRegistry`](../app/services/captcha/throttle_registry.rb) / [`Captcha::ProviderSettings`](../app/models/captcha/provider_settings.rb) → [`Captcha::RequestSnapshot`](../app/services/captcha/request_snapshot.rb). Challenge → [`Captcha::Activities::Verify`](../app/services/captcha/activities/verify.rb) → [`Captcha::Providers`](../app/services/captcha/providers.rb) registry/adapter → [`Captcha::Grant`](../app/services/captcha/grant.rb) → [`Captcha::RequestReplayer`](../app/services/captcha/request_replayer.rb) / [`Captcha::RequestPassage`](../app/services/captcha/request_passage.rb). Admin changes use UpdateProviderSettings/UpdateUrlThrottle and provider/surface registries; this names the boundary without repeating the findings. |
| **MAIL** | [`Emails::Gateway`](../app/services/emails/gateway.rb) → [`Emails::Activities::Send`](../app/services/emails/activities/send.rb) / [`Email::Contracts::Send`](../app/services/email/contracts/send.rb) → [`Emails::CompileTemplate`](../app/services/emails/compile_template.rb) / [`Emails::TemplateRenderer`](../app/services/emails/template_renderer.rb) / [`Emails::VariableContext`](../app/services/emails/variable_context.rb) → [`Emails::MessageAdmission`](../app/services/emails/message_admission.rb) / [`Emails::Quota`](../app/services/emails/quota.rb) → [`Emails::Message`](../app/models/emails/message.rb) → [`Emails::DeliveryHandoff`](../app/services/emails/delivery_handoff.rb) / [`Emails::DeliverMessageJob`](../app/jobs/emails/deliver_message_job.rb) → [`Email::Providers`](../app/services/email/providers.rb) / [`Email::CredentialResolver`](../app/services/email/credential_resolver.rb) / [`Emails::Credential`](../app/models/emails/credential.rb). Bulk audience/schedule → [`Emails::SendActivities::Build`](../app/services/emails/send_activities/build.rb) / [`Emails::SendActivities::StartSendActivity`](../app/services/emails/send_activities/start_send_activity.rb) → [`Emails::SendActivities::SendActivityJob`](../app/jobs/emails/send_activities/send_activity_job.rb). Callback [`Emails::ReceiptInbox`](../app/services/emails/receipt_inbox.rb) records [`Emails::BackendReceipt`](../app/models/emails/backend_receipt.rb) and synchronously projects message state / [`Emails::Suppression`](../app/models/emails/suppression.rb); [`Emails::ReconcileMessagesJob`](../app/jobs/emails/reconcile_messages_job.rb) / [`Emails::Cron::RecoverMessages`](../app/services/emails/cron/recover_messages.rb) recover queued messages and pending receipts. Tracking records [`Emails::MessageEvent`](../app/models/emails/message_event.rb). Version writers use DEF_MAIL. |
| **SMS** | [`Sms::Contacts::Save`](../app/services/sms/contacts/save.rb) / [`Sms::Contacts::RecordConsent`](../app/services/sms/contacts/record_consent.rb) / [`Sms::Contacts::SyncEntity`](../app/services/sms/contacts/sync_entity.rb) → [`Sms::Contracts::Contact`](../app/services/sms/contracts/contact.rb) / [`Sms::Contracts::ConsentEvent`](../app/services/sms/contracts/consent_event.rb) / [`Sms::Contracts::EntitySync`](../app/services/sms/contracts/entity_sync.rb) → [`Sms::Contact`](../app/models/sms/contact.rb) / [`Sms::ConsentEvent`](../app/models/sms/consent_event.rb); segment → [`Sms::Contracts::Segment`](../app/services/sms/contracts/segment.rb) / [`Sms::Audience::SaveSegment`](../app/services/sms/audience/save_segment.rb) / [`Sms::Audience::Preview`](../app/services/sms/audience/preview.rb). Campaign → [`Sms::Campaigns::Save`](../app/services/sms/campaigns/save.rb) / [`Sms::Campaigns::Launch`](../app/services/sms/campaigns/launch.rb) → [`Sms::Campaigns::Snapshot`](../app/services/sms/campaigns/snapshot.rb) / [`Sms::Campaigns::ReviewToken`](../app/services/sms/campaigns/review_token.rb) → [`Sms::Campaigns::SchedulerJob`](../app/jobs/sms/campaigns/scheduler_job.rb) / [`Sms::Campaigns::RunJob`](../app/jobs/sms/campaigns/run_job.rb) / [`Sms::Campaigns::Run`](../app/services/sms/campaigns/run.rb) → [`Sms::CampaignRecipient`](../app/models/sms/campaign_recipient.rb) snapshots. Direct/campaign send → [`Sms::Gateway`](../app/services/sms/gateway.rb) → [`Sms::Activities::Send`](../app/services/sms/activities/send.rb) / [`Sms::Contracts::Send`](../app/services/sms/contracts/send.rb) → [`Sms::MessageAdmission`](../app/services/sms/message_admission.rb) / [`Sms::Quota`](../app/services/sms/quota.rb) → [`Sms::Message`](../app/models/sms/message.rb) → [`Sms::DeliveryHandoff`](../app/services/sms/delivery_handoff.rb) / [`Sms::DeliverMessageJob`](../app/jobs/sms/deliver_message_job.rb) / [`Sms::DispatchLimiter`](../app/services/sms/dispatch_limiter.rb) → [`Sms::Adapters`](../app/services/sms/adapters.rb) / [`Sms::CredentialResolver`](../app/services/sms/credential_resolver.rb) / [`Sms::Credential`](../app/models/sms/credential.rb). Callback [`Sms::ReceiptInbox`](../app/services/sms/receipt_inbox.rb) records [`Sms::BackendReceipt`](../app/models/sms/backend_receipt.rb) and synchronously applies [`Sms::DeliveryProjection`](../app/services/sms/delivery_projection.rb) / [`Sms::OptOut`](../app/models/sms/opt_out.rb); [`Sms::ReconcileMessagesJob`](../app/jobs/sms/reconcile_messages_job.rb) / [`Sms::Cron::ReconcileMessages`](../app/services/sms/cron/reconcile_messages.rb) reconcile receipts/provider state. |
| **PAY** | [`Payments::Contracts::Charge`](../app/services/payments/contracts/charge.rb) → [`Payments::Activities::Charge`](../app/services/payments/activities/charge.rb) → [`Payments::Activities::PrepareAttempt`](../app/services/payments/activities/prepare_attempt.rb) → [`Payments::Gateway`](../app/services/payments/gateway.rb) / [`Payments::Gateways`](../app/services/payments/gateways.rb) / [`Payments::CredentialResolver`](../app/services/payments/credential_resolver.rb) → [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb), [`Payments::Order`](../app/models/payments/order.rb), [`Payments::Payment`](../app/models/payments/payment.rb). Query/refund → [`Payments::Activities::Query`](../app/services/payments/activities/query.rb) / [`Payments::Activities::Refund`](../app/services/payments/activities/refund.rb) → gateway and [`Payments::Refund`](../app/models/payments/refund.rb). [`Payments::WebhookDispatcher`](../app/services/payments/webhook_dispatcher.rb) → [`Payments::WebhookEvent`](../app/models/payments/webhook_event.rb) / [`Payments::ProcessWebhookEventJob`](../app/jobs/payments/process_webhook_event_job.rb) → [`Payments::Activities::HandleWebhook`](../app/services/payments/activities/handle_webhook.rb) → settlement/billing/handoff. Reconciliation → [`Payments::Cron::DownloadBills`](../app/services/payments/cron/download_bills.rb) / [`Payments::Activities::Reconcile`](../app/services/payments/activities/reconcile.rb) → [`Payments::ReconciliationBill`](../app/models/payments/reconciliation_bill.rb); transaction/reconciliation GETs primarily read stored rows. |
| **BILL** | Customer and platform billing BaseControllers → [`Billing::Pagination`](../app/controllers/concerns/billing/pagination.rb) / [`Billing::ControllerPresentation`](../app/controllers/concerns/billing/controller_presentation.rb) / [`Billing::Entitlements`](../app/services/billing/entitlements.rb). Action-specific contracts/activities → [`Billing::Collector`](../app/services/billing/collector.rb) / [`Billing::PaymentAuthorization`](../app/services/billing/payment_authorization.rb) → payment gateways and [`Billing::Plan`](../app/models/billing/plan.rb) / [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::Invoice`](../app/models/billing/invoice.rb) / [`Billing::PaymentMethod`](../app/models/billing/payment_method.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) / [`Billing::CollectionAttempt`](../app/models/billing/collection_attempt.rb). Catalog writers are Billing::Catalog services listed by action; tenant settings scope records to Current.customer, platform oversight deliberately uses cross-tenant relations. |
| **AI** | [`AiAssistant::MessageSending`](../app/controllers/concerns/ai_assistant/message_sending.rb) → [`AiAssistant::Activities::SendMessage`](../app/services/ai_assistant/activities/send_message.rb) / [`AiAssistant::Activities::Preflight`](../app/services/ai_assistant/activities/preflight.rb) → [`AiAssistant::Conversation`](../app/models/ai_assistant/conversation.rb) / [`AiAssistant::Message`](../app/models/ai_assistant/message.rb) → [`AiAssistant::ReplyJob`](../app/jobs/ai_assistant/reply_job.rb) → [`AiAssistant::Activities::Reply`](../app/services/ai_assistant/activities/reply.rb) → [`AiAssistant::Assistant::ExecutionPolicy`](../app/services/ai_assistant/assistant/execution_policy.rb) / [`AiAssistant::Assistant::GenerationWriteGuard`](../app/services/ai_assistant/assistant/generation_write_guard.rb) → [`AiAssistant::Assistant::Tools::Session`](../app/services/ai_assistant/assistant/tools/session.rb) → [`Operations::Activities::Execute`](../app/services/operations/activities/execute.rb) / [`Operations::Activities::Confirm`](../app/services/operations/activities/confirm.rb) and entity writers, [`AiAssistant::Assistant::GeneratePage`](../app/services/ai_assistant/assistant/generate_page.rb) or [`Websites::Assistant::Processor`](../app/services/websites/assistant/processor.rb). STT → [`SpeechToText::TranscriptionEnqueueing`](../app/controllers/concerns/speech_to_text/transcription_enqueueing.rb) → [`SpeechToText::Activities::EnqueueTranscription`](../app/services/speech_to_text/activities/enqueue_transcription.rb) → [`SpeechToText::AudioProbe`](../app/services/speech_to_text/audio_probe.rb) → [`SpeechToText::Clip`](../app/models/speech_to_text/clip.rb) → [`SpeechToText::TranscribeJob`](../app/jobs/speech_to_text/transcribe_job.rb) → [`SpeechToText::Activities::Transcribe`](../app/services/speech_to_text/activities/transcribe.rb) / provider. Stop/regenerate/undo/proposal actions have distinct activity rows below. |
| **DESKTOP_AI** | DESKTOP authentication chain + AI message/preflight/reply/STT chain; desktop history and transcription polling add ListMessages/ShowTranscription and ownership projection. |
| **WEB** | [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → [`Website`](../app/models/website.rb) / [`WebsitePage`](../app/models/website_page.rb); [`Websites::Catalog`](../app/services/websites/catalog.rb) / [`WebsiteSkeleton`](../app/models/website_skeleton.rb) / [`WebsiteLayout`](../app/models/website_layout.rb) → [`Websites::Theme`](../app/services/websites/theme.rb) and public ViewComponents. Mutations → [`Websites::Activities::SavePage`](../app/services/websites/activities/save_page.rb) / SaveSite / DestroyPage / ReorderPages / ReplaceSkeleton / UploadMedia; media → [`Websites::MediaPolicy`](../app/services/websites/media_policy.rb) and Active Storage. Platform previews use [`Websites::CatalogPreview`](../app/controllers/concerns/websites/catalog_preview.rb). |
| **MEMBER** | `app/controllers/member/base_controller.rb` → current_member, authorize_owned!, [`Member::Navigation`](../app/services/member/navigation.rb) / [`Member::Surfaces`](../app/services/member/surfaces.rb). Entity descriptors → [`Member::EntitySurfaceBuilder`](../app/services/member/entity_surface_builder.rb) → [`People::Ownership`](../app/services/people/ownership.rb).scope → [`EntityEntry`](../app/models/entity_entry.rb); [`Member::PageFilters`](../app/services/member/page_filters.rb) / [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) render member-only fields. Profile mutation → [`Member::Profiles::UpdateContract`](../app/contracts/member/profiles/update_contract.rb) → [`Authentication::User`](../app/models/authentication/user.rb) / [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb). |
| **AUTH_MEMBER** | MEMBER base/owned-record chain + AUTH user/credential/MFA chain. MFA setup and recovery use [`Member::Mfa::Operation::Enable`](../app/concepts/member/mfa/operation/enable.rb) / [`Member::Mfa::Operation::Disable`](../app/concepts/member/mfa/operation/disable.rb) / reset-link operations, [`Member::Mfa::ResetToken`](../app/concepts/member/mfa/reset_token.rb) and [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb). |
| **MEMBER_PAGE** | MEMBER base + PAGE generated rendering; PagesController explicitly admits same-tenant admin/owner GET/HEAD preview. Writes submit through the public UUID controller and its audience/ownership guards. |
| **PAY_MEMBER** | MEMBER base/owned-record chain + PAY gateway/merchant chain. [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) / [`Payments::Subscription`](../app/models/payments/subscription.rb) scope customer and member; [`Payments::Activities::VaultCard`](../app/services/payments/activities/vault_card.rb) and [`Payments::Activities::CancelSubscription`](../app/services/payments/activities/cancel_subscription.rb) are the principal writes. |
| **DOC** | [`DeveloperDocs::Catalog`](../app/services/developer_docs/catalog.rb) / [`DeveloperDocs::Repository`](../app/services/developer_docs/repository.rb) / [`DeveloperDocs::Renderer`](../app/services/developer_docs/renderer.rb) → Kramdown/GFM parsing → Nokogiri/Loofah allow-list sanitization and link rewriting → document components/templates. Customer-help [`CustomerDocs::Catalog`](../app/services/customer_docs/catalog.rb) / [`CustomerDocs::Repository`](../app/services/customer_docs/repository.rb) inherit the shared reader/rendering boundary; locale/slug/source-file selection is server-side. |
| **GEN** | [`CodeGenerators::GeneratorRegistry`](../app/services/code_generators/generator_registry.rb) / [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) → registered generator source/instance → [`CodeGenerators::GeneratorInterface`](../app/services/code_generators/generator_interface.rb) / [`CodeGenerators::SourceAssembler`](../app/services/code_generators/source_assembler.rb) / [`CodeGenerators::GeneratorValidator`](../app/services/code_generators/generator_validator.rb) / [`CodeGenerators::TestRunner`](../app/services/code_generators/test_runner.rb) / [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) / [`CodeGenerators::CodeIntrospector`](../app/services/code_generators/code_introspector.rb). Flowchart validation/execution → [`FlowchartServerValidator`](../app/services/flowchart_server_validator.rb) / [`ActivityGenerator`](../app/services/activity_generator.rb) / [`ActivityTracer`](../app/services/activity_tracer.rb). IO/reference/implicit-key endpoints are metadata readers; trace and owner generator-instance methods have execution boundaries described in findings. |
| **HELP** | [`Help::Activities::CreateRequest`](../app/services/help/activities/create_request.rb) / [`Help::Activities::AddMessage`](../app/services/help/activities/add_message.rb) / [`Help::Activities::Resolve`](../app/services/help/activities/resolve.rb) / [`Help::Activities::SendEmail`](../app/services/help/activities/send_email.rb) → [`Help::AttachmentRules`](../app/services/help/attachment_rules.rb) → [`SupportTicket`](../app/models/support_ticket.rb) / [`SupportTicketMessage`](../app/models/support_ticket_message.rb) / [`SupportTicketRead`](../app/models/support_ticket_read.rb) → notifications and help mail jobs. |

### Public, root/alias, callback, OAuth, Devise and auth surfaces

**77 route entries · 31 controllers · 67 controller/action pairs.**

#### C001 — `rails/health`

Controller source: installed railties 8.1.3 `lib/rails/health_controller.rb`; `Rails::HealthController < ActionController::Base`.
Family reference: **HEALTH**. Rails::HealthController#show renders the framework health response; no application model/service.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C001.show` | Rails::HealthController#show renders the framework health response; no application model/service |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0001 | `GET` | `/up(.:format)` | `show` | `C001.show` |

#### C002 — `captcha/challenges`

Controller source: `app/controllers/captcha/challenges_controller.rb`; superclass `ApplicationController`.
Family reference: **CAPTCHA**. [`Captcha::ReturnTo`](../app/services/captcha/return_to.rb) → [`Captcha::UrlMatcher`](../app/services/captcha/url_matcher.rb) → [`Captcha::ProviderSettings`](../app/models/captcha/provider_settings.rb); challenge template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C002.show` | [`Captcha::Grant`](../app/services/captcha/grant.rb) lookup and challenge template |
| `C002.create` | [`Captcha::VerificationContext`](../app/services/captcha/verification_context.rb) → [`Captcha::Activities::Verify`](../app/services/captcha/activities/verify.rb) → [`Captcha::Grant`](../app/services/captcha/grant.rb) → [`Captcha::RequestSnapshot`](../app/services/captcha/request_snapshot.rb) → [`Captcha::RequestReplayer`](../app/services/captcha/request_replayer.rb) / [`Captcha::RequestPassage`](../app/services/captcha/request_passage.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0002 | `GET` | `/captcha/challenge(.:format)` | `show` | `C002.show` |
| R0003 | `POST` | `/captcha/challenge(.:format)` | `create` | `C002.create` |

#### C003 — `websites/pages`

Controller source: `app/controllers/websites/pages_controller.rb`; superclass `ApplicationController`; includes `Websites::CurrentSite`, `PageShortcuts::RouteContext`, `PageShortcuts::PublicPathContext`.
Family reference: **WEB**. [`Website`](../app/models/website.rb) / [`WebsitePage`](../app/models/website_page.rb) → [`Websites::HomeSiteLocalization`](../app/services/websites/home_site_localization.rb) → [`Websites::Theme`](../app/services/websites/theme.rb); website show template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C003.home` | published site's home [`WebsitePage`](../app/models/website_page.rb) (or shortcut target) → public chrome/show template |
| `C003.show` | published [`WebsitePage`](../app/models/website_page.rb) by :page_slug (or shortcut target) → public chrome/show template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0004 | `GET` | `/` | `home` | `C003.home` |
| R0005 | `GET` | `/` | `show` | `C003.show` |
| R0063 | `GET` | `/:customer_id/site(.:format)` | `home` | `C003.home` |
| R0065 | `GET` | `/:customer_id/site/:page_slug(.:format)` | `show` | `C003.show` |
| R0720 | `GET` | `/*shortcut_path` | `home` | `C003.home` |
| R0721 | `GET` | `/*shortcut_path` | `show` | `C003.show` |

#### C004 — `public_pages`

Controller source: `app/controllers/public_pages_controller.rb`; superclass `ApplicationController`; includes `CaptchaProtectable`, `PageRendering`, `PageAudienceRouting`, `PageShortcuts::RouteContext`, `PageShortcuts::PublicPathContext`.
Family reference: **PAGE**. [`Page`](../app/models/page.rb); [`PageShortcuts::RouteContext`](../app/controllers/concerns/page_shortcuts/route_context.rb) / [`PageShortcuts::PublicPathContext`](../app/controllers/concerns/page_shortcuts/public_path_context.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C004.show` | accessible launched [`Page`](../app/models/page.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb) → [`Pages::Prefill`](../app/services/pages/prefill.rb); generated page ERB |
| `C004.submit` | [`Pages::FormParams`](../app/services/pages/form_params.rb) → [`Pages::AudienceGuard`](../app/services/pages/audience_guard.rb) → [`Pages::PublicSubmission`](../app/services/pages/public_submission.rb) → [`ActivityTracer`](../app/services/activity_tracer.rb) / [`FlowchartRuntime::Authentication`](../app/services/flowchart_runtime/authentication.rb); [`FeatureModules::Invocation`](../app/services/feature_modules/invocation.rb) and payment/page handoffs |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0006 | `GET` | `/` | `show` | `C004.show` |
| R0060 | `GET` | `/:customer_id/page/:uuid(.:format)` | `show` | `C004.show` |
| R0061 | `POST` | `/:customer_id/page/:uuid(.:format)` | `submit` | `C004.submit` |
| R0722 | `GET` | `/*shortcut_path` | `show` | `C004.show` |
| R0723 | `POST` | `/` | `submit` | `C004.submit` |
| R0724 | `POST` | `/*shortcut_path` | `submit` | `C004.submit` |

#### C005 — `page_shortcuts/unavailable`

Controller source: `app/controllers/page_shortcuts/unavailable_controller.rb`; superclass `ActionController::Base`.
Family reference: **BARE**. ActionController::Base → head :not_found unavailable-root response; no application model/service.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C005.show` | ActionController::Base → head :not_found unavailable-root response; no application model/service |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0007 | `GET` | `/` | `show` | `C005.show` |

#### C006 — `home`

Controller source: `app/controllers/home_controller.rb`; superclass `ApplicationController`; includes `Authentication::FinishesSignIn`.
Family reference: **AUTH**. [`Authentication::User`](../app/models/authentication/user.rb) → [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb); signed-in landing redirect or new-user auth landing template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C006.index` | [`Authentication::User`](../app/models/authentication/user.rb) → [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb); signed-in landing redirect or new-user auth landing template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0008 | `GET` | `/` | `index` | `C006.index` |

#### C007 — `oauth/authorizations`

Controller source: `app/controllers/oauth/authorizations_controller.rb`; superclass `Doorkeeper::AuthorizationsController`.
Family reference: **OAUTH_BROWSER**. Doorkeeper::AuthorizationsController → [`Oauth::AuthenticateResourceOwner`](../app/services/oauth/authenticate_resource_owner.rb) / [`Oauth::Protocol`](../app/services/oauth/protocol.rb); browser authorization and native-handoff templates.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C007.show` | inherited Doorkeeper native authorization-result action |
| `C007.new` | inherited Doorkeeper pre-authorization → resource-owner authentication, MFA and desktop parameter checks |
| `C007.destroy` | validated inherited Doorkeeper denial → OAuth error/denial redirect |
| `C007.create` | inherited Doorkeeper authorization → [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) → authorization grant/token and native handoff |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0009 | `GET` | `/oauth/authorize/native(.:format)` | `show` | `C007.show` |
| R0010 | `GET` | `/oauth/authorize(.:format)` | `new` | `C007.new` |
| R0011 | `DELETE` | `/oauth/authorize(.:format)` | `destroy` | `C007.destroy` |
| R0012 | `POST` | `/oauth/authorize(.:format)` | `create` | `C007.create` |

#### C008 — `oauth/tokens`

Controller source: `app/controllers/oauth/tokens_controller.rb`; superclass `Doorkeeper::TokensController`.
Family reference: **OAUTH_METAL**. Doorkeeper::TokensController → [`Oauth::AccessToken`](../app/models/oauth/access_token.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C008.create` | inherited Doorkeeper token grant/refresh → [`Oauth::AuthorizationCodeExchange`](../app/services/oauth/authorization_code_exchange.rb) → [`Oauth::AccessToken`](../app/models/oauth/access_token.rb) |
| `C008.revoke` | inherited Doorkeeper revocation; app refresh-token lookup → [`Oauth::AccessToken`](../app/models/oauth/access_token.rb) |
| `C008.introspect` | inherited Doorkeeper token introspection → [`Oauth::AccessToken`](../app/models/oauth/access_token.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0013 | `POST` | `/oauth/token(.:format)` | `create` | `C008.create` |
| R0014 | `POST` | `/oauth/revoke(.:format)` | `revoke` | `C008.revoke` |
| R0015 | `POST` | `/oauth/introspect(.:format)` | `introspect` | `C008.introspect` |

#### C009 — `oauth/discovery`

Controller source: `app/controllers/oauth/discovery_controller.rb`; superclass `ActionController::API`.
Family reference: **API**. ActionController::API → [`Oauth::ServerMetadata`](../app/services/oauth/server_metadata.rb) / [`Oauth::Protocol`](../app/services/oauth/protocol.rb) → JSON metadata.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C009.show` | ActionController::API → [`Oauth::ServerMetadata`](../app/services/oauth/server_metadata.rb) / [`Oauth::Protocol`](../app/services/oauth/protocol.rb) → JSON metadata |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0016 | `GET` | `/.well-known/oauth-authorization-server(.:format)` | `show` | `C009.show` |

#### C010 — `oauth/userinfo`

Controller source: `app/controllers/oauth/userinfo_controller.rb`; superclass `ActionController::API`; includes `Doorkeeper::Rails::Helpers`.
Family reference: **API**. ActionController::API + Doorkeeper helpers → [`Oauth::TokenIdentity`](../app/services/oauth/token_identity.rb) → [`Authentication::User`](../app/models/authentication/user.rb) → [`Oauth::Userinfo`](../app/services/oauth/userinfo.rb) JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C010.show` | ActionController::API + Doorkeeper helpers → [`Oauth::TokenIdentity`](../app/services/oauth/token_identity.rb) → [`Authentication::User`](../app/models/authentication/user.rb) → [`Oauth::Userinfo`](../app/services/oauth/userinfo.rb) JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0017 | `GET` | `/oauth/userinfo(.:format)` | `show` | `C010.show` |

#### C011 — `locales`

Controller source: `app/controllers/locales_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`SetLocale`](../app/controllers/concerns/set_locale.rb); validated locale → current [`Authentication::User`](../app/models/authentication/user.rb) locale preference + cookie; same-origin redirect.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C011.update` | [`SetLocale`](../app/controllers/concerns/set_locale.rb); validated locale → current [`Authentication::User`](../app/models/authentication/user.rb) locale preference + cookie; same-origin redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0018 | `PATCH` | `/locale(.:format)` | `update` | `C011.update` |

#### C012 — `payments/webhooks`

Controller source: `app/controllers/payments/webhooks_controller.rb`; superclass `ActionController::API`.
Family reference: **PAY**. ActionController::API → [`Payments::WebhookDispatcher`](../app/services/payments/webhook_dispatcher.rb) → [`Payments::WebhookEvent`](../app/models/payments/webhook_event.rb) → [`Payments::ProcessWebhookEventJob`](../app/jobs/payments/process_webhook_event_job.rb) → [`Payments::Activities::HandleWebhook`](../app/services/payments/activities/handle_webhook.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C012.create` | ActionController::API → [`Payments::WebhookDispatcher`](../app/services/payments/webhook_dispatcher.rb) → [`Payments::WebhookEvent`](../app/models/payments/webhook_event.rb) → [`Payments::ProcessWebhookEventJob`](../app/jobs/payments/process_webhook_event_job.rb) → [`Payments::Activities::HandleWebhook`](../app/services/payments/activities/handle_webhook.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0019 | `POST` | `/payments/webhooks/:provider(.:format)` | `create` | `C012.create` |

#### C013 — `sms/webhooks`

Controller source: `app/controllers/sms/webhooks_controller.rb`; superclass `ActionController::API`.
Family reference: **SMS**. ActionController::API → [`Sms::Adapters`](../app/services/sms/adapters.rb) / [`Sms::Credential`](../app/models/sms/credential.rb) verification → [`WebhookCredentialBinding`](../app/services/webhook_credential_binding.rb) → [`Sms::ReceiptInbox`](../app/services/sms/receipt_inbox.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C013.create` | ActionController::API → [`Sms::Adapters`](../app/services/sms/adapters.rb) / [`Sms::Credential`](../app/models/sms/credential.rb) verification → [`WebhookCredentialBinding`](../app/services/webhook_credential_binding.rb) → [`Sms::ReceiptInbox`](../app/services/sms/receipt_inbox.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0020 | `POST` | `/sms/webhooks/:provider/:kind(.:format)` | `create` | `C013.create` |

#### C014 — `sms/unsubscribes`

Controller source: `app/controllers/sms/unsubscribes_controller.rb`; superclass `ApplicationController`.
Family reference: **SMS**. [`Sms::Campaigns::Unsubscribe`](../app/services/sms/campaigns/unsubscribe.rb) signed-token resolution.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C014.show` | [`Sms::Campaigns::Unsubscribe`](../app/services/sms/campaigns/unsubscribe.rb).preview → masked phone confirmation template |
| `C014.create` | [`Sms::Campaigns::Unsubscribe`](../app/services/sms/campaigns/unsubscribe.rb).call → contact consent/opt-out mutation and confirmation |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0021 | `GET` | `/sms/unsubscribes/:token(.:format)` | `show` | `C014.show` |
| R0022 | `POST` | `/sms/unsubscribes/:token(.:format)` | `create` | `C014.create` |

#### C015 — `emails/webhooks`

Controller source: `app/controllers/emails/webhooks_controller.rb`; superclass `ActionController::API`.
Family reference: **MAIL**. ActionController::API → [`Email::Providers`](../app/services/email/providers.rb) / [`Emails::Credential`](../app/models/emails/credential.rb) verification → [`WebhookCredentialBinding`](../app/services/webhook_credential_binding.rb) → [`Emails::ReceiptInbox`](../app/services/emails/receipt_inbox.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C015.create` | ActionController::API → [`Email::Providers`](../app/services/email/providers.rb) / [`Emails::Credential`](../app/models/emails/credential.rb) verification → [`WebhookCredentialBinding`](../app/services/webhook_credential_binding.rb) → [`Emails::ReceiptInbox`](../app/services/emails/receipt_inbox.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0023 | `POST` | `/email/webhooks/:provider(.:format)` | `create` | `C015.create` |

#### C016 — `emails/tracking`

Controller source: `app/controllers/emails/tracking_controller.rb`; superclass `ActionController::Base`.
Family reference: **TRACK**. ActionController::Base → [`Emails::Message`](../app/models/emails/message.rb) + email_tracking MessageVerifier.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C016.open` | [`Emails::MessageEvent`](../app/models/emails/message_event.rb).record_open! → GIF response |
| `C016.click` | verified URL + HTTP(S) check → [`Emails::MessageEvent`](../app/models/emails/message_event.rb).record_click! → redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0024 | `GET` | `/email/track/:message_id/open.gif(.:format)` | `open` | `C016.open` |
| R0025 | `GET` | `/email/track/:message_id/click(.:format)` | `click` | `C016.click` |

#### C017 — `emails/unsubscribes`

Controller source: `app/controllers/emails/unsubscribes_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::SendActivities::SendActivityUnsubscribe`](../app/services/emails/send_activities/send_activity_unsubscribe.rb) signed-token resolution.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C017.show` | emailed_address lookup → read-only confirmation template |
| `C017.create` | unsubscribe → subscriber suppression/state change → confirmed/not-found template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0026 | `GET` | `/unsubscribe/:token(.:format)` | `show` | `C017.show` |
| R0027 | `POST` | `/unsubscribe/:token(.:format)` | `create` | `C017.create` |

#### C018 — `authentication/sessions`

Controller source: `app/controllers/authentication/sessions_controller.rb`; superclass `Devise::SessionsController`; includes `TenantContext`, `Authentication::TrustedDeviceCookieable`, `Authentication::FinishesSignIn`, `Authentication::IssuesSignInLink`, `Authentication::PermitsUserParams`.
Family reference: **AUTH**. Devise::SessionsController + [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb) / [`Authentication::TrustedDeviceCookieable`](../app/controllers/concerns/authentication/trusted_device_cookieable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C018.new` | session unconfirmed-email notice → implicit sign-in template |
| `C018.create` | [`Authentication::Throttle`](../app/services/authentication/throttle.rb) → [`Authentication::SignInFlow`](../app/services/authentication/sign_in_flow.rb) / [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb), or [`Authentication::IssueSignInLink`](../app/services/authentication/issue_sign_in_link.rb) → audit + sign-in/MFA completion |
| `C018.destroy` | Devise/Warden sign_out → [`Authentication::AuditLog`](../app/services/authentication/audit_log.rb) → signed-out redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0028 | `GET` | `/auth/sign_in(.:format)` | `new` | `C018.new` |
| R0029 | `POST` | `/auth/sign_in(.:format)` | `create` | `C018.create` |
| R0030 | `DELETE` | `/auth/sign_out(.:format)` | `destroy` | `C018.destroy` |

#### C019 — `authentication/passwords`

Controller source: `app/controllers/authentication/passwords_controller.rb`; superclass `Devise::PasswordsController`; includes `TenantContext`, `Authentication::PermitsUserParams`, `Authentication::EmailFloodThrottled`.
Family reference: **AUTH**. Devise::PasswordsController + [`Authentication::EmailFloodThrottled`](../app/controllers/concerns/authentication/email_flood_throttled.rb) → [`Authentication::User`](../app/models/authentication/user.rb) (Devise Recoverable).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C019.new` | inherited Devise new-resource → password-request template |
| `C019.edit` | inherited Devise token form + reset-availability check |
| `C019.update` | inherited Devise reset_password_by_token → [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) + audit; sign-in-after-reset disabled |
| `C019.create` | inherited Devise reset-password instructions → mail job + [`Authentication::AuditLog`](../app/services/authentication/audit_log.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0031 | `GET` | `/auth/password/new(.:format)` | `new` | `C019.new` |
| R0032 | `GET` | `/auth/password/edit(.:format)` | `edit` | `C019.edit` |
| R0033 | `PATCH` | `/auth/password(.:format)` | `update` | `C019.update` |
| R0034 | `PUT` | `/auth/password(.:format)` | `update` | `C019.update` |
| R0035 | `POST` | `/auth/password(.:format)` | `create` | `C019.create` |

#### C020 — `authentication/confirmations`

Controller source: `app/controllers/authentication/confirmations_controller.rb`; superclass `Devise::ConfirmationsController`; includes `TenantContext`, `Authentication::EmailFloodThrottled`, `Authentication::PermitsUserParams`, `Authentication::TrustedDeviceCookieable`, `Authentication::FinishesSignIn`, `Authentication::NoStore`.
Family reference: **AUTH**. Devise::ConfirmationsController → [`Authentication::User`](../app/models/authentication/user.rb) (Devise Confirmable).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C020.new` | empty override → implicit confirmation-request template |
| `C020.show` | confirm_by_token → [`Authentication::SignInFlow`](../app/services/authentication/sign_in_flow.rb).complete → [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb); HEAD returns without consumption |
| `C020.create` | inherited Devise resend_confirmation_instructions + email flood guard |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0036 | `GET` | `/auth/confirmation/new(.:format)` | `new` | `C020.new` |
| R0037 | `GET` | `/auth/confirmation(.:format)` | `show` | `C020.show` |
| R0038 | `POST` | `/auth/confirmation(.:format)` | `create` | `C020.create` |

#### C021 — `authentication/customer_registrations`

Controller source: `app/controllers/authentication/customer_registrations_controller.rb`; superclass `ApplicationController`; includes `Authentication::EmailFloodThrottled`, `Authentication::NoStore`, `Authentication::PermitsUserParams`, `Authentication::TrustedDeviceCookieable`, `Authentication::FinishesSignIn`.
Family reference: **AUTH**. [`Authentication::PlatformSettings`](../app/models/authentication/platform_settings.rb) / [`Authentication::User`](../app/models/authentication/user.rb); customer signup templates.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C021.new` | signup-enabled state + new user → implicit template |
| `C021.create` | [`Authentication::CustomerSignupToken`](../app/services/authentication/customer_signup_token.rb) normalization → [`Authentication::IssueCustomerSignup`](../app/services/authentication/issue_customer_signup.rb) → check-email redirect |
| `C021.check_email` | session email → implicit check-email template |
| `C021.resend` | [`Authentication::IssueCustomerSignup`](../app/services/authentication/issue_customer_signup.rb) → check-email redirect |
| `C021.confirm` | [`Authentication::CustomerSignupToken`](../app/services/authentication/customer_signup_token.rb).verify → existing user confirmation or [`Authentication::CustomerSignup`](../app/services/authentication/customer_signup.rb) → [`Authentication::SignInFlow`](../app/services/authentication/sign_in_flow.rb).complete; HEAD does not consume |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0039 | `GET` | `/auth/sign_up(.:format)` | `new` | `C021.new` |
| R0040 | `POST` | `/auth/sign_up(.:format)` | `create` | `C021.create` |
| R0041 | `GET` | `/auth/sign_up/check_email(.:format)` | `check_email` | `C021.check_email` |
| R0042 | `POST` | `/auth/sign_up/resend(.:format)` | `resend` | `C021.resend` |
| R0043 | `GET` | `/auth/sign_up/confirm(.:format)` | `confirm` | `C021.confirm` |

#### C022 — `authentication/sign_in_links`

Controller source: `app/controllers/authentication/sign_in_links_controller.rb`; superclass `ApplicationController`; includes `TenantContext`, `Authentication::IssuesSignInLink`, `Authentication::PermitsUserParams`, `Authentication::TrustedDeviceCookieable`, `Authentication::FinishesSignIn`, `Authentication::NoStore`.
Family reference: **AUTH**. [`Authentication::IssuesSignInLink`](../app/controllers/concerns/authentication/issues_sign_in_link.rb) / [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C022.create` | [`Authentication::IssueSignInLink`](../app/services/authentication/issue_sign_in_link.rb) → mail job/check-email redirect |
| `C022.check_email` | session issued-link email → implicit template |
| `C022.show` | [`Authentication::ConsumeSignInLink`](../app/services/authentication/consume_sign_in_link.rb) → [`Authentication::SignInFlow`](../app/services/authentication/sign_in_flow.rb).complete → session/MFA; HEAD does not consume |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0044 | `POST` | `/auth/sign_in_link(.:format)` | `create` | `C022.create` |
| R0045 | `GET` | `/auth/sign_in_link/check_email(.:format)` | `check_email` | `C022.check_email` |
| R0046 | `GET` | `/auth/sign_in_link(.:format)` | `show` | `C022.show` |

#### C023 — `authentication/registrations`

Controller source: `app/controllers/authentication/registrations_controller.rb`; superclass `Devise::RegistrationsController`; includes `TenantContext`, `Authentication::PermitsUserParams`.
Family reference: **AUTH**. Devise::RegistrationsController → [`Authentication::User`](../app/models/authentication/user.rb); tenant signup/configuration checks.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C023.new` | build_resource → implicit tenant registration template |
| `C023.create` | [`Authentication::RegisterMember`](../app/services/authentication/register_member.rb) → user/member role/confirmation, or [`Authentication::NotifyExistingMember`](../app/services/authentication/notify_existing_member.rb); [`Authentication::UniformTiming`](../app/services/authentication/uniform_timing.rb) |
| `C023.edit` | authenticated current user → account-edit template |
| `C023.update` | [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb) → user update → [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) → [`Authentication::LandingPath`](../app/services/authentication/landing_path.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0047 | `GET` | `/:customer_id/auth/sign_up(.:format)` | `new` | `C023.new` |
| R0048 | `POST` | `/:customer_id/auth(.:format)` | `create` | `C023.create` |
| R0049 | `GET` | `/auth/edit(.:format)` | `edit` | `C023.edit` |
| R0050 | <code>PUT&#124;PATCH</code> | `/auth(.:format)` | `update` | `C023.update` |

#### C024 — `authentication/mfa_setups`

Controller source: `app/controllers/authentication/mfa_setups_controller.rb`; superclass `ApplicationController`; includes `Authentication::FinishesSignIn`, `Authentication::MfaEnrollment`, `Authentication::RequiresSignIn`.
Family reference: **AUTH**. [`Authentication::RequiresSignIn`](../app/controllers/concerns/authentication/requires_sign_in.rb) + [`Authentication::MfaEnrollment`](../app/controllers/concerns/authentication/mfa_enrollment.rb) → [`Authentication::User`](../app/models/authentication/user.rb) MFA methods.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C024.show` | pending MFA enrollment/QR → implicit setup template |
| `C024.create` | [`Authentication::Throttle`](../app/services/authentication/throttle.rb) + [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → OTP enrollment/verification → [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0051 | `GET` | `/:customer_id/auth/mfa/setup(.:format)` | `show` | `C024.show` |
| R0052 | `POST` | `/:customer_id/auth/mfa/setup(.:format)` | `create` | `C024.create` |

#### C025 — `authentication/mfa_sessions`

Controller source: `app/controllers/authentication/mfa_sessions_controller.rb`; superclass `ApplicationController`; includes `Authentication::FinishesSignIn`, `Authentication::RequiresSignIn`.
Family reference: **AUTH**. [`Authentication::RequiresSignIn`](../app/controllers/concerns/authentication/requires_sign_in.rb) → [`Authentication::User`](../app/models/authentication/user.rb) MFA methods.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C025.show` | implicit MFA challenge template |
| `C025.create` | [`Authentication::Throttle`](../app/services/authentication/throttle.rb) → verify_otp → [`Authentication::AuditLog`](../app/services/authentication/audit_log.rb) → [`Authentication::TrustedDevice`](../app/models/authentication/trusted_device.rb) / [`Authentication::FinishesSignIn`](../app/controllers/concerns/authentication/finishes_sign_in.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0053 | `GET` | `/:customer_id/auth/mfa/session(.:format)` | `show` | `C025.show` |
| R0054 | `POST` | `/:customer_id/auth/mfa/session(.:format)` | `create` | `C025.create` |

#### C026 — `authentication/mfas`

Controller source: `app/controllers/authentication/mfas_controller.rb`; superclass `ApplicationController`; includes `Authentication::RequiresSignIn`.
Family reference: **AUTH**. [`Authentication::RequiresSignIn`](../app/controllers/concerns/authentication/requires_sign_in.rb) → [`Authentication::Throttle`](../app/services/authentication/throttle.rb) + [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb) / OTP → [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → [`Authentication::User`](../app/models/authentication/user.rb).disable_mfa!.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C026.destroy` | [`Authentication::RequiresSignIn`](../app/controllers/concerns/authentication/requires_sign_in.rb) → [`Authentication::Throttle`](../app/services/authentication/throttle.rb) + [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb) / OTP → [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → [`Authentication::User`](../app/models/authentication/user.rb).disable_mfa! |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0055 | `DELETE` | `/:customer_id/auth/mfa(.:format)` | `destroy` | `C026.destroy` |

#### C027 — `authentication/mfa_recoveries`

Controller source: `app/controllers/authentication/mfa_recoveries_controller.rb`; superclass `ApplicationController`; includes `Authentication::EmailFloodThrottled`, `Authentication::NoStore`.
Family reference: **AUTH**. [`Member::Mfa::ResetToken`](../app/concepts/member/mfa/reset_token.rb); recovery templates.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C027.consume` | GET renders confirmation; POST → [`Member::Mfa::Operation::ConsumeResetLink`](../app/concepts/member/mfa/operation/consume_reset_link.rb) → disable MFA/sign-out; HEAD no consumption |
| `C027.new` | implicit recovery-request template |
| `C027.create` | [`Member::Mfa::Contracts::ResetRequest`](../app/concepts/member/mfa/contracts/reset_request.rb) → [`Member::Mfa::Operation::RequestResetLink`](../app/concepts/member/mfa/operation/request_reset_link.rb) → email reset link |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0056 | `GET` | `/:customer_id/auth/mfa_recovery/consume(.:format)` | `consume` | `C027.consume` |
| R0057 | `POST` | `/:customer_id/auth/mfa_recovery/consume(.:format)` | `consume` | `C027.consume` |
| R0058 | `GET` | `/:customer_id/auth/mfa_recovery/new(.:format)` | `new` | `C027.new` |
| R0059 | `POST` | `/:customer_id/auth/mfa_recovery(.:format)` | `create` | `C027.create` |

#### C028 — `pages/actions`

Controller source: `app/controllers/pages/actions_controller.rb`; superclass `ApplicationController`; includes `PageRendering`, `PageAudienceRouting`, `PageShortcuts::PublicPathContext`.
Family reference: **PAGE**. [`Pages::ActionResolver`](../app/services/pages/action_resolver.rb) → audience-specific page redirect + optional [`Pages::Continuation`](../app/services/pages/continuation.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C028.show` | [`Pages::ActionResolver`](../app/services/pages/action_resolver.rb) → audience-specific page redirect + optional [`Pages::Continuation`](../app/services/pages/continuation.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0062 | `GET` | `/:customer_id/actions/:action_key(.:format)` | `show` | `C028.show` |

#### C029 — `websites/assets`

Controller source: `app/controllers/websites/assets_controller.rb`; superclass `ApplicationController`; includes `Websites::CurrentSite`.
Family reference: **WEB**. [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → ActiveStorage::Blob.find_signed → [`Websites::MediaPolicy`](../app/services/websites/media_policy.rb) → identified image bytes response.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C029.show` | [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → ActiveStorage::Blob.find_signed → [`Websites::MediaPolicy`](../app/services/websites/media_policy.rb) → identified image bytes response |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0064 | `GET` | `/:customer_id/site/media/:signed_id(.:format)` | `show` | `C029.show` |

#### C030 — `payments/checkouts`

Controller source: `app/controllers/payments/checkouts_controller.rb`; superclass `ApplicationController`; includes `FeatureModules::InvocationContext`.
Family reference: **PAY**. [`Customer`](../app/models/customer.rb) / [`Payments::Order`](../app/models/payments/order.rb); [`FeatureModules::InvocationContext`](../app/controllers/concerns/feature_modules/invocation_context.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C030.start` | invocation → [`Payments::HandoffCompletion`](../app/services/payments/handoff_completion.rb) order reference → [`Payments::Order`](../app/models/payments/order.rb) (or collect redirect) |
| `C030.collect` | [`FeatureModules::HandoffCompletion`](../app/services/feature_modules/handoff_completion.rb) fields → [`Payments::HandoffEntryComponent`](../app/components/payments/handoff_entry_component.rb) |
| `C030.complete` | [`FeatureModules::HandoffCompletion`](../app/services/feature_modules/handoff_completion.rb).complete! → [`Payments::Order`](../app/models/payments/order.rb) → checkout redirect |
| `C030.show` | [`Payments::EligibleGateways`](../app/services/payments/eligible_gateways.rb) / [`Payments::DefaultGateway`](../app/models/payments/default_gateway.rb) → [`Payments::CheckoutComponent`](../app/components/payments/checkout_component.rb) |
| `C030.create` | [`Payments::Contracts::Charge`](../app/services/payments/contracts/charge.rb) → [`Payments::Activities::Charge`](../app/services/payments/activities/charge.rb) → [`Payments::Activities::PrepareAttempt`](../app/services/payments/activities/prepare_attempt.rb) → [`Payments::Gateway`](../app/services/payments/gateway.rb); flow-specific checkout component |
| `C030.status` | [`Payments::Payment`](../app/models/payments/payment.rb) by :id/out_trade_no → [`Payments::Activities::Query`](../app/services/payments/activities/query.rb) → JSON status |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0066 | `GET` | `/:customer_id/payments/checkout/start(.:format)` | `start` | `C030.start` |
| R0067 | `GET` | `/:customer_id/payments/checkout/collect(.:format)` | `collect` | `C030.collect` |
| R0068 | `POST` | `/:customer_id/payments/checkout/complete(.:format)` | `complete` | `C030.complete` |
| R0069 | `GET` | `/:customer_id/payments/checkout(.:format)` | `show` | `C030.show` |
| R0070 | `POST` | `/:customer_id/payments/checkout(.:format)` | `create` | `C030.create` |
| R0071 | `GET` | `/:customer_id/payments/:id/status(.:format)` | `status` | `C030.status` |

#### C031 — `payments/results`

Controller source: `app/controllers/payments/results_controller.rb`; superclass `ApplicationController`; includes `FeatureModules::InvocationContext`.
Family reference: **PAY**. [`Payments::Payment`](../app/models/payments/payment.rb) by :payment_id/out_trade_no → pending [`Payments::Activities::Query`](../app/services/payments/activities/query.rb) → [`Payments::HandoffCompletion`](../app/services/payments/handoff_completion.rb) / [`FeatureModules::ExitResolver`](../app/services/feature_modules/exit_resolver.rb) → [`Payments::ResultComponent`](../app/components/payments/result_component.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C031.show` | [`Payments::Payment`](../app/models/payments/payment.rb) by :payment_id/out_trade_no → pending [`Payments::Activities::Query`](../app/services/payments/activities/query.rb) → [`Payments::HandoffCompletion`](../app/services/payments/handoff_completion.rb) / [`FeatureModules::ExitResolver`](../app/services/feature_modules/exit_resolver.rb) → [`Payments::ResultComponent`](../app/components/payments/result_component.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0072 | `GET` | `/:customer_id/payments/result/:payment_id(.:format)` | `show` | `C031.show` |

### Admin core, desktop, entry and page browsing

**51 route entries · 27 controllers · 45 controller/action pairs.**

#### C032 — `admin/assistants`

Controller source: `app/controllers/admin/assistants_controller.rb`; superclass `ApplicationController`.
Family reference: **AI**. [`AiAssistant::Conversation`](../app/models/ai_assistant/conversation.rb).resolve → messages/image attachments + provider/module availability → implicit composer template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C032.show` | [`AiAssistant::Conversation`](../app/models/ai_assistant/conversation.rb).resolve → messages/image attachments + provider/module availability → implicit composer template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0073 | `GET` | `/:customer_id/admin(.:format)` | `show` | `C032.show` |
| R0075 | `GET` | `/:customer_id/admin/assistant(.:format)` | `show` | `C032.show` |

#### C033 — `admin/dashboards`

Controller source: `app/controllers/admin/dashboards_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`Dashboard::Home`](../app/services/dashboard/home.rb) → implicit dashboard template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C033.show` | [`Dashboard::Home`](../app/services/dashboard/home.rb) → implicit dashboard template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0074 | `GET` | `/:customer_id/admin/dashboard(.:format)` | `show` | `C033.show` |

#### C034 — `admin/platform_announcement_dismissals`

Controller source: `app/controllers/admin/platform_announcement_dismissals_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`PlatformAnnouncements::Resolver`](../app/services/platform_announcements/resolver.rb) → [`PlatformAnnouncementDismissal`](../app/models/platform_announcement_dismissal.rb).record! → [`Platform::AnnouncementBannerComponent`](../app/components/platform/announcement_banner_component.rb) Turbo replacement/redirect.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C034.create` | [`PlatformAnnouncements::Resolver`](../app/services/platform_announcements/resolver.rb) → [`PlatformAnnouncementDismissal`](../app/models/platform_announcement_dismissal.rb).record! → [`Platform::AnnouncementBannerComponent`](../app/components/platform/announcement_banner_component.rb) Turbo replacement/redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0076 | `POST` | `/:customer_id/admin/platform_announcement_dismissals(.:format)` | `create` | `C034.create` |

#### C035 — `admin/platform_announcement_reads`

Controller source: `app/controllers/admin/platform_announcement_reads_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`PlatformAnnouncements::InboxResolver`](../app/services/platform_announcements/inbox_resolver.rb) → [`PlatformAnnouncementRead`](../app/models/platform_announcement_read.rb).record! → [`Notifications::Stream`](../app/services/notifications/stream.rb) / bell and inbox components.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C035.create` | [`PlatformAnnouncements::InboxResolver`](../app/services/platform_announcements/inbox_resolver.rb) → [`PlatformAnnouncementRead`](../app/models/platform_announcement_read.rb).record! → [`Notifications::Stream`](../app/services/notifications/stream.rb) / bell and inbox components |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0077 | `POST` | `/:customer_id/admin/platform_announcement_reads(.:format)` | `create` | `C035.create` |

#### C036 — `admin/support_ticket_reads`

Controller source: `app/controllers/admin/support_ticket_reads_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. [`Notifications::Inbox`](../app/services/notifications/inbox.rb).visible_support_ticket → [`SupportTicketRead`](../app/models/support_ticket_read.rb).record! → redirect.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C036.create` | [`Notifications::Inbox`](../app/services/notifications/inbox.rb).visible_support_ticket → [`SupportTicketRead`](../app/models/support_ticket_read.rb).record! → redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0078 | `POST` | `/:customer_id/admin/support_ticket_reads(.:format)` | `create` | `C036.create` |

#### C037 — `admin/support_ticket_messages`

Controller source: `app/controllers/admin/support_ticket_messages_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. owned [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::AddMessage`](../app/services/help/activities/add_message.rb) → message/attachments/notifications.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C037.create` | owned [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::AddMessage`](../app/services/help/activities/add_message.rb) → message/attachments/notifications |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0079 | `POST` | `/:customer_id/admin/support_tickets/:support_ticket_id/messages(.:format)` | `create` | `C037.create` |

#### C038 — `admin/support_tickets`

Controller source: `app/controllers/admin/support_tickets_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. [`SupportTicket`](../app/models/support_ticket.rb) customer/user scope.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C038.create` | [`Help::Activities::CreateRequest`](../app/services/help/activities/create_request.rb) → ticket/messages/attachments → notification |
| `C038.show` | [`SupportTicketRead`](../app/models/support_ticket_read.rb).record! → implicit thread template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0080 | `POST` | `/:customer_id/admin/support_tickets(.:format)` | `create` | `C038.create` |
| R0081 | `GET` | `/:customer_id/admin/support_tickets/:id(.:format)` | `show` | `C038.show` |

#### C039 — `admin/help_emails`

Controller source: `app/controllers/admin/help_emails_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. [`Help::Activities::SendEmail`](../app/services/help/activities/send_email.rb) → attachment admission + outbound help email.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C039.create` | [`Help::Activities::SendEmail`](../app/services/help/activities/send_email.rb) → attachment admission + outbound help email |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0082 | `POST` | `/:customer_id/admin/help_emails(.:format)` | `create` | `C039.create` |

#### C040 — `admin/help/docs`

Controller source: `app/controllers/admin/help/docs_controller.rb`; superclass `ApplicationController`.
Family reference: **DOC**. [`CustomerDocs::Catalog`](../app/services/customer_docs/catalog.rb) → [`CustomerDocs::Repository`](../app/services/customer_docs/repository.rb) → rendered customer-help page or missing template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C040.index` | [`CustomerDocs::Catalog`](../app/services/customer_docs/catalog.rb) → [`CustomerDocs::Repository`](../app/services/customer_docs/repository.rb) → rendered customer-help page or missing template |
| `C040.show` | [`CustomerDocs::Catalog`](../app/services/customer_docs/catalog.rb) → [`CustomerDocs::Repository`](../app/services/customer_docs/repository.rb) → rendered customer-help page or missing template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0083 | `GET` | `/:customer_id/admin/help/docs(.:format)` | `index` | `C040.index` |
| R0084 | `GET` | `/:customer_id/admin/help/docs/:slug(.:format)` | `show` | `C040.show` |

#### C041 — `admin/entity_definitions`

Controller source: `app/controllers/admin/entity_definitions_controller.rb`; superclass `ApplicationController`; includes `Oauth::BearerAuthenticatable`.
Family reference: **DESKTOP**. [`EntityDefinitions::List`](../app/services/entity_definitions/list.rb) → accessible [`Entity`](../app/models/entity.rb) / version projection → JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C041.index` | [`EntityDefinitions::List`](../app/services/entity_definitions/list.rb) → accessible [`Entity`](../app/models/entity.rb) / version projection → JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0085 | `GET` | `/:customer_id/admin/entity_definitions(.:format)` | `index` | `C041.index` |

#### C042 — `admin/assistant/messages`

Controller source: `app/controllers/admin/assistant/messages_controller.rb`; superclass `ApplicationController`; includes `Oauth::BearerAuthenticatable`, `::AiAssistant::MessageSending`.
Family reference: **DESKTOP_AI**. [`AiAssistant::MessageSending`](../app/controllers/concerns/ai_assistant/message_sending.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C042.index` | [`AiAssistant::Activities::ListMessages`](../app/services/ai_assistant/activities/list_messages.rb) → serialized [`AiAssistant::Message`](../app/models/ai_assistant/message.rb) history |
| `C042.create` | [`AiAssistant::MessageSending`](../app/controllers/concerns/ai_assistant/message_sending.rb) → [`AiAssistant::Activities::SendMessage`](../app/services/ai_assistant/activities/send_message.rb) → preflight + reply job |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0086 | `GET` | `/:customer_id/admin/assistant/messages(.:format)` | `index` | `C042.index` |
| R0087 | `POST` | `/:customer_id/admin/assistant/messages(.:format)` | `create` | `C042.create` |

#### C043 — `admin/assistant/transcriptions`

Controller source: `app/controllers/admin/assistant/transcriptions_controller.rb`; superclass `ApplicationController`; includes `Oauth::BearerAuthenticatable`, `::SpeechToText::TranscriptionEnqueueing`.
Family reference: **DESKTOP_AI**. [`SpeechToText::TranscriptionEnqueueing`](../app/controllers/concerns/speech_to_text/transcription_enqueueing.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C043.create` | [`SpeechToText::Activities::EnqueueTranscription`](../app/services/speech_to_text/activities/enqueue_transcription.rb) → [`SpeechToText::Clip`](../app/models/speech_to_text/clip.rb) / transcription job |
| `C043.show` | [`SpeechToText::Activities::ShowTranscription`](../app/services/speech_to_text/activities/show_transcription.rb) → owned [`SpeechToText::Clip`](../app/models/speech_to_text/clip.rb) JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0088 | `POST` | `/:customer_id/admin/assistant/transcriptions(.:format)` | `create` | `C043.create` |
| R0089 | `GET` | `/:customer_id/admin/assistant/transcriptions/:id(.:format)` | `show` | `C043.show` |

#### C044 — `admin/domains`

Controller source: `app/controllers/admin/domains_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`Admin::Domains::Directory`](../app/services/admin/domains/directory.rb) / [`EntityDomainVisibility`](../app/services/entity_domain_visibility.rb) → [`Admin::Domains::DirectoryComponent`](../app/components/admin/domains/directory_component.rb); index/show use load_directory.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C044.index` | [`Admin::Domains::Directory`](../app/services/admin/domains/directory.rb) / [`EntityDomainVisibility`](../app/services/entity_domain_visibility.rb) → [`Admin::Domains::DirectoryComponent`](../app/components/admin/domains/directory_component.rb); index/show use load_directory |
| `C044.show` | [`Admin::Domains::Directory`](../app/services/admin/domains/directory.rb) / [`EntityDomainVisibility`](../app/services/entity_domain_visibility.rb) → [`Admin::Domains::DirectoryComponent`](../app/components/admin/domains/directory_component.rb); index/show use load_directory |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0090 | `GET` | `/:customer_id/admin/domains(.:format)` | `index` | `C044.index` |
| R0091 | `GET` | `/:customer_id/admin/domains/:id(.:format)` | `show` | `C044.show` |

#### C045 — `admin/entity_entries`

Controller source: `app/controllers/admin/entity_entries_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. accessible [`Entity`](../app/models/entity.rb) → customer-scoped [`EntityEntry`](../app/models/entity_entry.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C045.batch_destroy` | [`Entities::DeleteEntry`](../app/services/entities/delete_entry.rb) → [`EntityEntry`](../app/models/entity_entry.rb) deletion/reference cascade |
| `C045.create` | [`Entities::Activities::CreateEntry`](../app/services/entities/activities/create_entry.rb) → [`EntityEntryContract`](../app/contracts/entity_entry_contract.rb) → [`EntityEntry`](../app/models/entity_entry.rb) |
| `C045.new` | [`Entities::EntryForm`](../app/services/entities/entry_form.rb) → entry form/quick-add dialog |
| `C045.edit` | [`Entities::EntryForm`](../app/services/entities/entry_form.rb) → entry form/quick-add dialog |
| `C045.show` | [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) / [`Entities::EntryAssociations`](../app/services/entities/entry_associations.rb) → detail template |
| `C045.update` | [`Entities::Activities::UpdateEntry`](../app/services/entities/activities/update_entry.rb) → [`EntityEntryContract`](../app/contracts/entity_entry_contract.rb) → [`EntityEntry`](../app/models/entity_entry.rb) |
| `C045.destroy` | [`Entities::DeleteEntry`](../app/services/entities/delete_entry.rb) → [`EntityEntry`](../app/models/entity_entry.rb) deletion/reference cascade |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0092 | `DELETE` | `/:customer_id/admin/entities/:entity_id/entries/batch(.:format)` | `batch_destroy` | `C045.batch_destroy` |
| R0101 | `POST` | `/:customer_id/admin/entities/:entity_id/entries(.:format)` | `create` | `C045.create` |
| R0102 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/new(.:format)` | `new` | `C045.new` |
| R0103 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/:id/edit(.:format)` | `edit` | `C045.edit` |
| R0104 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/:id(.:format)` | `show` | `C045.show` |
| R0105 | `PATCH` | `/:customer_id/admin/entities/:entity_id/entries/:id(.:format)` | `update` | `C045.update` |
| R0106 | `PUT` | `/:customer_id/admin/entities/:entity_id/entries/:id(.:format)` | `update` | `C045.update` |
| R0107 | `DELETE` | `/:customer_id/admin/entities/:entity_id/entries/:id(.:format)` | `destroy` | `C045.destroy` |

#### C046 — `admin/entity_association_entries`

Controller source: `app/controllers/admin/entity_association_entries_controller.rb`; superclass `ApplicationController`; includes `SafeReturnTo`.
Family reference: **ENTRY**. [`Entity`](../app/models/entity.rb) / parent [`EntityEntry`](../app/models/entity_entry.rb) → [`Entities::EntryAssociations`](../app/services/entities/entry_associations.rb); [`SafeReturnTo`](../app/controllers/concerns/safe_return_to.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C046.create` | [`Entities::Activities::CreateAssociationEntries`](../app/services/entities/activities/create_association_entries.rb) → bridge entries/contracts |
| `C046.new` | [`Entities::EntryForm`](../app/services/entities/entry_form.rb) → association entry form |
| `C046.edit` | [`Entities::EntryForm`](../app/services/entities/entry_form.rb) → association entry form |
| `C046.update` | [`Entities::Activities::UpdateAssociationEntry`](../app/services/entities/activities/update_association_entry.rb) → bridge entry/contracts |
| `C046.destroy` | [`Entities::DeleteEntry`](../app/services/entities/delete_entry.rb) → bridge row cascade |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0093 | `POST` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries(.:format)` | `create` | `C046.create` |
| R0094 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/new(.:format)` | `new` | `C046.new` |
| R0095 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/:id/edit(.:format)` | `edit` | `C046.edit` |
| R0096 | `PATCH` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/:id(.:format)` | `update` | `C046.update` |
| R0097 | `PUT` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/:id(.:format)` | `update` | `C046.update` |
| R0098 | `DELETE` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/:id(.:format)` | `destroy` | `C046.destroy` |

#### C047 — `admin/entity_entry_person_links`

Controller source: `app/controllers/admin/entity_entry_person_links_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`Entity`](../app/models/entity.rb) / [`EntityEntry`](../app/models/entity_entry.rb) → [`People::Link`](../app/services/people/link.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C047.candidates` | [`People::Link`](../app/services/people/link.rb) candidates → JSON |
| `C047.create` | [`People::Link`](../app/services/people/link.rb) → user/person linkage mutation |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0099 | `GET` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/person_link/candidates(.:format)` | `candidates` | `C047.candidates` |
| R0100 | `POST` | `/:customer_id/admin/entities/:entity_id/entries/:entry_id/person_link(.:format)` | `create` | `C047.create` |

#### C048 — `admin/entity_index_settings`

Controller source: `app/controllers/admin/entity_index_settings_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`Entity`](../app/models/entity.rb) → [`EntityIndexSettings::Operation::Update`](../app/concepts/entity_index_settings/operation/update.rb) → [`EntityIndexSetting`](../app/models/entity_index_setting.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C048.update` | [`Entity`](../app/models/entity.rb) → [`EntityIndexSettings::Operation::Update`](../app/concepts/entity_index_settings/operation/update.rb) → [`EntityIndexSetting`](../app/models/entity_index_setting.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0108 | `PATCH` | `/:customer_id/admin/entities/:entity_id/index_setting(.:format)` | `update` | `C048.update` |
| R0109 | `PUT` | `/:customer_id/admin/entities/:entity_id/index_setting(.:format)` | `update` | `C048.update` |

#### C049 — `admin/entities`

Controller source: `app/controllers/admin/entities_controller.rb`; superclass `ApplicationController`; includes `Listable`.
Family reference: **ENTRY**. [`Entity`](../app/models/entity.rb) / [`EntityIndexSetting`](../app/models/entity_index_setting.rb) → [`Admin::Entities::FiltersBuilder`](../app/services/admin/entities/filters_builder.rb) / [`Admin::Entities::ColumnsBuilder`](../app/services/admin/entities/columns_builder.rb) → [`EntityEntry`](../app/models/entity_entry.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) or [`Admin::Entities::EntriesCsv`](../app/services/admin/entities/entries_csv.rb); [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C049.show` | [`Entity`](../app/models/entity.rb) / [`EntityIndexSetting`](../app/models/entity_index_setting.rb) → [`Admin::Entities::FiltersBuilder`](../app/services/admin/entities/filters_builder.rb) / [`Admin::Entities::ColumnsBuilder`](../app/services/admin/entities/columns_builder.rb) → [`EntityEntry`](../app/models/entity_entry.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) or [`Admin::Entities::EntriesCsv`](../app/services/admin/entities/entries_csv.rb); [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0110 | `GET` | `/:customer_id/admin/entities/:id(.:format)` | `show` | `C049.show` |

#### C050 — `admin/entity_pages`

Controller source: `app/controllers/admin/entity_pages_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. accessible [`Entity`](../app/models/entity.rb) by :entity_id → redirect to unified /admin/pages/entities/:entity_id filter, retaining permitted query parameters.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C050.index` | accessible [`Entity`](../app/models/entity.rb) by :entity_id → redirect to unified /admin/pages/entities/:entity_id filter, retaining permitted query parameters |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0111 | `GET` | `/:customer_id/admin/entities/:entity_id/pages(.:format)` | `index` | `C050.index` |

#### C051 — `admin/page_forms`

Controller source: `app/controllers/admin/page_forms_controller.rb`; superclass `ApplicationController`; includes `PageRendering`.
Family reference: **PAGE**. admin-visible launched [`Page`](../app/models/page.rb) → [`Pages::Prefill`](../app/services/pages/prefill.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb); generated ERB submits to public UUID endpoint.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C051.show` | admin-visible launched [`Page`](../app/models/page.rb) → [`Pages::Prefill`](../app/services/pages/prefill.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb); generated ERB submits to public UUID endpoint |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0112 | `GET` | `/:customer_id/admin/pages/:page_id/form(.:format)` | `show` | `C051.show` |

#### C052 — `admin/pages`

Controller source: `app/controllers/admin/pages_controller.rb`; superclass `ApplicationController`; includes `Listable`.
Family reference: **PAGE**. [`Admin::Pages::BrowseScope`](../app/services/admin/pages/browse_scope.rb) / [`Page`](../app/models/page.rb) / [`Entity`](../app/models/entity.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C052.batch_update` | locked tenant [`Page`](../app/models/page.rb) rows → activate/deactivate/launch/take_offline → JSON/redirect |
| `C052.index` | [`Admin::Pages::ColumnsBuilder`](../app/services/admin/pages/columns_builder.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) / [`Pages::FormHealth`](../app/services/pages/form_health.rb) → browse template (including collection aliases) |
| `C052.show` | [`Page`](../app/models/page.rb) → publishing slide-over template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0113 | `PATCH` | `/:customer_id/admin/pages/batch(.:format)` | `batch_update` | `C052.batch_update` |
| R0114 | `GET` | `/:customer_id/admin/pages/uncategorized(.:format)` | `index` | `C052.index` |
| R0115 | `GET` | `/:customer_id/admin/pages/entities/:entity_id(.:format)` | `index` | `C052.index` |
| R0116 | `GET` | `/:customer_id/admin/pages(.:format)` | `index` | `C052.index` |
| R0117 | `GET` | `/:customer_id/admin/pages/:id(.:format)` | `show` | `C052.show` |

#### C053 — `admin/module_entries`

Controller source: `app/controllers/admin/module_entries_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb); routed parent :module_key and entry :key → entry projection.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C053.show` | [`FeatureModules::Module`](../app/models/feature_modules/module.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb); routed parent :module_key and entry :key → entry projection |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0118 | `GET` | `/:customer_id/admin/modules/:module_key/entries/:key(.:format)` | `show` | `C053.show` |

#### C054 — `admin/modules`

Controller source: `app/controllers/admin/modules_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) → module directory template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C054.index` | [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) → module directory template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0119 | `GET` | `/:customer_id/admin/modules(.:format)` | `index` | `C054.index` |

#### C055 — `admin/module_howtos`

Controller source: `app/controllers/admin/module_howtos_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) by :module_key → [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) / [`DashboardContext`](../app/services/dashboard_context.rb) → how-to template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C055.show` | [`FeatureModules::Module`](../app/models/feature_modules/module.rb) by :module_key → [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) / [`DashboardContext`](../app/services/dashboard_context.rb) → how-to template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0120 | `GET` | `/:customer_id/admin/modules/:module_key/howto(.:format)` | `show` | `C055.show` |

#### C056 — `admin/settings`

Controller source: `app/controllers/admin/settings_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`SettingsContributor`](../app/services/settings_contributor.rb) + [`DashboardContext`](../app/services/dashboard_context.rb) → settings landing template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C056.show` | [`SettingsContributor`](../app/services/settings_contributor.rb) + [`DashboardContext`](../app/services/dashboard_context.rb) → settings landing template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0121 | `GET` | `/:customer_id/admin/settings(.:format)` | `show` | `C056.show` |

#### C080 — `admin/search`

Controller source: `app/controllers/admin/search_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`SearchQuery`](../app/services/search_query.rb) → JSON/search results.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C080.index` | [`SearchQuery`](../app/services/search_query.rb) → JSON/search results |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0199 | `GET` | `/:customer_id/admin/search(.:format)` | `index` | `C080.index` |

#### C081 — `admin/maintenances`

Controller source: `app/controllers/admin/maintenances_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. maintenance landing template; no domain writer in empty show action.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C081.show` | maintenance landing template; no domain writer in empty show action |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0200 | `GET` | `/:customer_id/admin/maintenance(.:format)` | `show` | `C081.show` |

### Customer settings and billing

**77 route entries · 23 controllers · 60 controller/action pairs.**

#### C057 — `admin/settings/member_surfaces`

Controller source: `app/controllers/admin/settings/member_surfaces_controller.rb`; superclass `ApplicationController`.
Family reference: **MEMBER**. [`Member::Surfaces`](../app/services/member/surfaces.rb) / [`Admin::Settings::MemberRowPresenter`](../app/presenters/admin/settings/member_row_presenter.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C057.show` | source :source_key + surface :key → settings/template |
| `C057.update` | [`Member::Settings::Operation::Update`](../app/concepts/member/settings/operation/update.rb) → surface visibility/configuration |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0122 | `GET` | `/:customer_id/admin/settings/member/sources/:source_key/surfaces/:key(.:format)` | `show` | `C057.show` |
| R0123 | `PATCH` | `/:customer_id/admin/settings/member/sources/:source_key/surfaces/:key(.:format)` | `update` | `C057.update` |
| R0124 | `PUT` | `/:customer_id/admin/settings/member/sources/:source_key/surfaces/:key(.:format)` | `update` | `C057.update` |

#### C058 — `admin/settings/member_sources`

Controller source: `app/controllers/admin/settings/member_sources_controller.rb`; superclass `ApplicationController`.
Family reference: **MEMBER**. [`Member::Surfaces`](../app/services/member/surfaces.rb) / [`Admin::Settings::MemberRowPresenter`](../app/presenters/admin/settings/member_row_presenter.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C058.show` | source by :key → source settings/template |
| `C058.update` | [`Member::Settings::Operation::Update`](../app/concepts/member/settings/operation/update.rb) → source visibility/configuration |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0125 | `GET` | `/:customer_id/admin/settings/member/sources/:key(.:format)` | `show` | `C058.show` |
| R0126 | `PATCH` | `/:customer_id/admin/settings/member/sources/:key(.:format)` | `update` | `C058.update` |
| R0127 | `PUT` | `/:customer_id/admin/settings/member/sources/:key(.:format)` | `update` | `C058.update` |

#### C059 — `admin/settings/members`

Controller source: `app/controllers/admin/settings/members_controller.rb`; superclass `ApplicationController`.
Family reference: **MEMBER**. [`Member::Surfaces`](../app/services/member/surfaces.rb) / [`Admin::Settings::MemberHubCardPresenter`](../app/presenters/admin/settings/member_hub_card_presenter.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C059.show` | member hub settings/template |
| `C059.update` | [`Member::Settings::Operation::Update`](../app/concepts/member/settings/operation/update.rb) → customer member settings |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0128 | `GET` | `/:customer_id/admin/settings/member(.:format)` | `show` | `C059.show` |
| R0129 | `PATCH` | `/:customer_id/admin/settings/member(.:format)` | `update` | `C059.update` |
| R0130 | `PUT` | `/:customer_id/admin/settings/member(.:format)` | `update` | `C059.update` |

#### C060 — `admin/settings/modules/payments/merchant_accounts`

Controller source: `app/controllers/admin/settings/modules/payments/merchant_accounts_controller.rb`; superclass `::Admin::Modules::Payments::BaseController`.
Family reference: **PAY**. [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) / [`Payments::PlatformGateway`](../app/models/payments/platform_gateway.rb) / [`Payments::Gateways`](../app/services/payments/gateways.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C060.test_connection` | [`Payments::Gateway`](../app/services/payments/gateway.rb).test_connection → JSON |
| `C060.index` | [`Payments::Admin::GatewayGalleryComponent`](../app/components/payments/admin/gateway_gallery_component.rb) + [`Payments::DefaultGateway`](../app/models/payments/default_gateway.rb) |
| `C060.create` | shared/account fields + registered credential keys → encrypted [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) save |
| `C060.new` | [`Payments::Admin::GatewayConfigComponent`](../app/components/payments/admin/gateway_config_component.rb) → credential form |
| `C060.edit` | [`Payments::Admin::GatewayConfigComponent`](../app/components/payments/admin/gateway_config_component.rb) → credential form |
| `C060.update` | shared/account fields + registered credential keys → encrypted [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0131 | `POST` | `/:customer_id/admin/settings/modules/payments/merchant_accounts/:id/test_connection(.:format)` | `test_connection` | `C060.test_connection` |
| R0132 | `GET` | `/:customer_id/admin/settings/modules/payments/merchant_accounts(.:format)` | `index` | `C060.index` |
| R0133 | `POST` | `/:customer_id/admin/settings/modules/payments/merchant_accounts(.:format)` | `create` | `C060.create` |
| R0134 | `GET` | `/:customer_id/admin/settings/modules/payments/merchant_accounts/new(.:format)` | `new` | `C060.new` |
| R0135 | `GET` | `/:customer_id/admin/settings/modules/payments/merchant_accounts/:id/edit(.:format)` | `edit` | `C060.edit` |
| R0136 | `PATCH` | `/:customer_id/admin/settings/modules/payments/merchant_accounts/:id(.:format)` | `update` | `C060.update` |
| R0137 | `PUT` | `/:customer_id/admin/settings/modules/payments/merchant_accounts/:id(.:format)` | `update` | `C060.update` |

#### C061 — `admin/settings/modules/payments/default_gateways`

Controller source: `app/controllers/admin/settings/modules/payments/default_gateways_controller.rb`; superclass `::Admin::Modules::Payments::BaseController`.
Family reference: **PAY**. [`Payments::SetDefaultGateway`](../app/services/payments/set_default_gateway.rb) → [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) / customer default selection.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C061.update` | [`Payments::SetDefaultGateway`](../app/services/payments/set_default_gateway.rb) → [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) / customer default selection |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0138 | `PATCH` | `/:customer_id/admin/settings/modules/payments/default_gateway(.:format)` | `update` | `C061.update` |
| R0139 | `PUT` | `/:customer_id/admin/settings/modules/payments/default_gateway(.:format)` | `update` | `C061.update` |

#### C062 — `admin/settings/modules/authentication/role_grants`

Controller source: `app/controllers/admin/settings/modules/authentication/role_grants_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Role`](../app/models/role.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C062.show` | [`AccessPoints::Catalog`](../app/services/access_points/catalog.rb) → grants template |
| `C062.update` | [`RoleGrants::Operation::Update`](../app/concepts/role_grants/operation/update.rb) → role grants |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0140 | `GET` | `/:customer_id/admin/settings/modules/authentication/roles/:role_id/grants(.:format)` | `show` | `C062.show` |
| R0141 | `PATCH` | `/:customer_id/admin/settings/modules/authentication/roles/:role_id/grants(.:format)` | `update` | `C062.update` |
| R0142 | `PUT` | `/:customer_id/admin/settings/modules/authentication/roles/:role_id/grants(.:format)` | `update` | `C062.update` |

#### C063 — `admin/settings/modules/authentication/roles`

Controller source: `app/controllers/admin/settings/modules/authentication/roles_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Role`](../app/models/role.rb); role templates.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C063.index` | [`Role`](../app/models/role.rb) / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → role browse/form/detail |
| `C063.create` | [`Roles::Operation::Create`](../app/concepts/roles/operation/create.rb) → Reform contract → [`Role`](../app/models/role.rb) |
| `C063.new` | [`Role`](../app/models/role.rb) / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → role browse/form/detail |
| `C063.edit` | [`Role`](../app/models/role.rb) / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → role browse/form/detail |
| `C063.show` | [`Role`](../app/models/role.rb) / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → role browse/form/detail |
| `C063.update` | [`Roles::Operation::Update`](../app/concepts/roles/operation/update.rb) → Reform contract → [`Role`](../app/models/role.rb) |
| `C063.destroy` | [`Roles::Operation::Destroy`](../app/concepts/roles/operation/destroy.rb) → [`Role`](../app/models/role.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0143 | `GET` | `/:customer_id/admin/settings/modules/authentication/roles(.:format)` | `index` | `C063.index` |
| R0144 | `POST` | `/:customer_id/admin/settings/modules/authentication/roles(.:format)` | `create` | `C063.create` |
| R0145 | `GET` | `/:customer_id/admin/settings/modules/authentication/roles/new(.:format)` | `new` | `C063.new` |
| R0146 | `GET` | `/:customer_id/admin/settings/modules/authentication/roles/:id/edit(.:format)` | `edit` | `C063.edit` |
| R0147 | `GET` | `/:customer_id/admin/settings/modules/authentication/roles/:id(.:format)` | `show` | `C063.show` |
| R0148 | `PATCH` | `/:customer_id/admin/settings/modules/authentication/roles/:id(.:format)` | `update` | `C063.update` |
| R0149 | `PUT` | `/:customer_id/admin/settings/modules/authentication/roles/:id(.:format)` | `update` | `C063.update` |
| R0150 | `DELETE` | `/:customer_id/admin/settings/modules/authentication/roles/:id(.:format)` | `destroy` | `C063.destroy` |

#### C064 — `admin/settings/modules/authentication/user_role_assignments`

Controller source: `app/controllers/admin/settings/modules/authentication/user_role_assignments_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Authentication::User`](../app/models/authentication/user.rb) / [`UsersRole`](../app/models/users_role.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C064.index` | user role list/template |
| `C064.create` | [`UserRoles::Operation::Assign`](../app/concepts/user_roles/operation/assign.rb) → [`UserRoles::AssignmentPolicy`](../app/services/user_roles/assignment_policy.rb) → [`UsersRole`](../app/models/users_role.rb) |
| `C064.destroy` | [`UserRoles::AssignmentPolicy`](../app/services/user_roles/assignment_policy.rb) → [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → [`UsersRole`](../app/models/users_role.rb) destroy |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0151 | `GET` | `/:customer_id/admin/settings/modules/authentication/user_role_assignments(.:format)` | `index` | `C064.index` |
| R0152 | `POST` | `/:customer_id/admin/settings/modules/authentication/user_role_assignments(.:format)` | `create` | `C064.create` |
| R0153 | `DELETE` | `/:customer_id/admin/settings/modules/authentication/user_role_assignments/:id(.:format)` | `destroy` | `C064.destroy` |

#### C065 — `admin/settings/modules/authentication/sign_up`

Controller source: `app/controllers/admin/settings/modules/authentication/sign_up_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Authentication::Settings`](../app/services/authentication/settings.rb) + [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C065.show` | signup setting → implicit template |
| `C065.update` | boolean signup_enabled configuration → assignment save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0154 | `GET` | `/:customer_id/admin/settings/modules/authentication/sign_up(.:format)` | `show` | `C065.show` |
| R0155 | `PATCH` | `/:customer_id/admin/settings/modules/authentication/sign_up(.:format)` | `update` | `C065.update` |
| R0156 | `PUT` | `/:customer_id/admin/settings/modules/authentication/sign_up(.:format)` | `update` | `C065.update` |

#### C066 — `admin/settings/modules/authentication/forget_password`

Controller source: `app/controllers/admin/settings/modules/authentication/forget_password_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Authentication::Settings`](../app/services/authentication/settings.rb) + [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C066.show` | forget-password setting → implicit template |
| `C066.update` | boolean forget_password_enabled configuration → assignment save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0157 | `GET` | `/:customer_id/admin/settings/modules/authentication/forget_password(.:format)` | `show` | `C066.show` |
| R0158 | `PATCH` | `/:customer_id/admin/settings/modules/authentication/forget_password(.:format)` | `update` | `C066.update` |
| R0159 | `PUT` | `/:customer_id/admin/settings/modules/authentication/forget_password(.:format)` | `update` | `C066.update` |

#### C067 — `admin/settings/modules/captcha/status`

Controller source: `app/controllers/admin/settings/modules/captcha/status_controller.rb`; superclass `ApplicationController`.
Family reference: **CAPTCHA**. [`Captcha::ProviderSettings`](../app/models/captcha/provider_settings.rb) / [`Captcha::ThrottleRegistry`](../app/services/captcha/throttle_registry.rb) / [`Page`](../app/models/page.rb) → customer captcha status template; both root/status aliases.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C067.show` | [`Captcha::ProviderSettings`](../app/models/captcha/provider_settings.rb) / [`Captcha::ThrottleRegistry`](../app/services/captcha/throttle_registry.rb) / [`Page`](../app/models/page.rb) → customer captcha status template; both root/status aliases |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0160 | `GET` | `/:customer_id/admin/settings/modules/captcha(.:format)` | `show` | `C067.show` |
| R0161 | `GET` | `/:customer_id/admin/settings/modules/captcha/status(.:format)` | `show` | `C067.show` |

#### C068 — `admin/settings/modules/captcha/pages`

Controller source: `app/controllers/admin/settings/modules/captcha/pages_controller.rb`; superclass `ApplicationController`.
Family reference: **CAPTCHA**. customer [`Page`](../app/models/page.rb) → [`Captcha::Activities::UpdateUrlThrottle`](../app/services/captcha/activities/update_url_throttle.rb) → per-page throttle settings.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C068.update` | customer [`Page`](../app/models/page.rb) → [`Captcha::Activities::UpdateUrlThrottle`](../app/services/captcha/activities/update_url_throttle.rb) → per-page throttle settings |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0162 | `PATCH` | `/:customer_id/admin/settings/modules/captcha/pages/:id(.:format)` | `update` | `C068.update` |
| R0163 | `PUT` | `/:customer_id/admin/settings/modules/captcha/pages/:id(.:format)` | `update` | `C068.update` |

#### C069 — `admin/settings/modules/emails/template_tokens`

Controller source: `app/controllers/admin/settings/modules/emails/template_tokens_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::TemplateToken`](../app/models/emails/template_token.rb) + accessible [`Entity`](../app/models/entity.rb) options.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C069.index` | token browse/bulk form/edit template |
| `C069.create` | [`Emails::TemplateTokens::Operation::BulkCreate`](../app/concepts/emails/template_tokens/operation/bulk_create.rb) → contracts → tokens |
| `C069.new` | token browse/bulk form/edit template |
| `C069.edit` | token browse/bulk form/edit template |
| `C069.update` | [`Emails::TemplateTokens::Operation::Update`](../app/concepts/emails/template_tokens/operation/update.rb) → token validation/save |
| `C069.destroy` | [`Emails::TemplateTokens::Operation::Destroy`](../app/concepts/emails/template_tokens/operation/destroy.rb) → token deletion |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0164 | `GET` | `/:customer_id/admin/settings/modules/emails/template_tokens(.:format)` | `index` | `C069.index` |
| R0165 | `POST` | `/:customer_id/admin/settings/modules/emails/template_tokens(.:format)` | `create` | `C069.create` |
| R0166 | `GET` | `/:customer_id/admin/settings/modules/emails/template_tokens/new(.:format)` | `new` | `C069.new` |
| R0167 | `GET` | `/:customer_id/admin/settings/modules/emails/template_tokens/:id/edit(.:format)` | `edit` | `C069.edit` |
| R0168 | `PATCH` | `/:customer_id/admin/settings/modules/emails/template_tokens/:id(.:format)` | `update` | `C069.update` |
| R0169 | `PUT` | `/:customer_id/admin/settings/modules/emails/template_tokens/:id(.:format)` | `update` | `C069.update` |
| R0170 | `DELETE` | `/:customer_id/admin/settings/modules/emails/template_tokens/:id(.:format)` | `destroy` | `C069.destroy` |

#### C070 — `admin/settings/modules/website/sites`

Controller source: `app/controllers/admin/settings/modules/website/sites_controller.rb`; superclass `::Admin::Modules::Website::BaseController`.
Family reference: **WEB**. [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → [`Website`](../app/models/website.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C070.show` | site settings → [`Websites::Catalog`](../app/services/websites/catalog.rb) / settings form |
| `C070.update` | [`Websites::Activities::SaveSite`](../app/services/websites/activities/save_site.rb) → site validation/save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0171 | `GET` | `/:customer_id/admin/settings/modules/website(.:format)` | `show` | `C070.show` |
| R0172 | `GET` | `/:customer_id/admin/settings/modules/website/site(.:format)` | `show` | `C070.show` |
| R0173 | `PATCH` | `/:customer_id/admin/settings/modules/website/site(.:format)` | `update` | `C070.update` |
| R0174 | `PUT` | `/:customer_id/admin/settings/modules/website/site(.:format)` | `update` | `C070.update` |

#### C071 — `admin/settings/modules/website/skeletons`

Controller source: `app/controllers/admin/settings/modules/website/skeletons_controller.rb`; superclass `::Admin::Modules::Website::BaseController`.
Family reference: **WEB**. [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → [`Websites::Activities::ReplaceSkeleton`](../app/services/websites/activities/replace_skeleton.rb) → [`Website`](../app/models/website.rb) / [`WebsitePage`](../app/models/website_page.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C071.create` | [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → [`Websites::Activities::ReplaceSkeleton`](../app/services/websites/activities/replace_skeleton.rb) → [`Website`](../app/models/website.rb) / [`WebsitePage`](../app/models/website_page.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0175 | `POST` | `/:customer_id/admin/settings/modules/website/skeleton(.:format)` | `create` | `C071.create` |

#### C072 — `admin/settings/billing/subscriptions`

Controller source: `app/controllers/admin/settings/billing/subscriptions_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. customer billing BaseController overview: [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::Plan`](../app/models/billing/plan.rb) / [`Billing::Entitlements`](../app/services/billing/entitlements.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C072.plan_change_preview` | [`Billing::PlanChangePolicy`](../app/services/billing/plan_change_policy.rb).preview → review template |
| `C072.show` | subscription/payment-method/usage/recovery overview → template |
| `C072.update` | [`Billing::Contracts::Subscribe`](../app/services/billing/contracts/subscribe.rb) / [`Billing::Contracts::ChangePlan`](../app/services/billing/contracts/change_plan.rb) → [`Billing::Activities::Subscribe`](../app/services/billing/activities/subscribe.rb) / [`Billing::Activities::ChangePlan`](../app/services/billing/activities/change_plan.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0176 | `GET` | `/:customer_id/admin/settings/billing/subscription/plan_change_preview(.:format)` | `plan_change_preview` | `C072.plan_change_preview` |
| R0178 | `GET` | `/:customer_id/admin/settings/billing/subscription(.:format)` | `show` | `C072.show` |
| R0179 | `PATCH` | `/:customer_id/admin/settings/billing/subscription(.:format)` | `update` | `C072.update` |
| R0180 | `PUT` | `/:customer_id/admin/settings/billing/subscription(.:format)` | `update` | `C072.update` |

#### C073 — `admin/settings/billing/plan_changes`

Controller source: `app/controllers/admin/settings/billing/plan_changes_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) → [`Billing::Activities::CancelPlanChange`](../app/services/billing/activities/cancel_plan_change.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C073.destroy` | [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) → [`Billing::Activities::CancelPlanChange`](../app/services/billing/activities/cancel_plan_change.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0177 | `DELETE` | `/:customer_id/admin/settings/billing/subscription/plan_change(.:format)` | `destroy` | `C073.destroy` |

#### C074 — `admin/settings/billing/cancellations`

Controller source: `app/controllers/admin/settings/billing/cancellations_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. customer live [`Billing::Subscription`](../app/models/billing/subscription.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C074.destroy` | [`Billing::Activities::ResumeSubscription`](../app/services/billing/activities/resume_subscription.rb) |
| `C074.create` | [`Billing::Activities::CancelSubscription`](../app/services/billing/activities/cancel_subscription.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0181 | `DELETE` | `/:customer_id/admin/settings/billing/cancellation(.:format)` | `destroy` | `C074.destroy` |
| R0182 | `POST` | `/:customer_id/admin/settings/billing/cancellation(.:format)` | `create` | `C074.create` |

#### C075 — `admin/settings/billing/coupon_redemptions`

Controller source: `app/controllers/admin/settings/billing/coupon_redemptions_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::Coupon`](../app/models/billing/coupon.rb) → [`Billing::Activities::ApplyCoupon`](../app/services/billing/activities/apply_coupon.rb) → subscription benefit.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C075.create` | [`Billing::Coupon`](../app/models/billing/coupon.rb) → [`Billing::Activities::ApplyCoupon`](../app/services/billing/activities/apply_coupon.rb) → subscription benefit |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0183 | `POST` | `/:customer_id/admin/settings/billing/coupon_redemption(.:format)` | `create` | `C075.create` |

#### C076 — `admin/settings/billing/payment_methods`

Controller source: `app/controllers/admin/settings/billing/payment_methods_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. customer [`Billing::PaymentMethod`](../app/models/billing/payment_method.rb) / [`Billing::PaymentAuthorization`](../app/services/billing/payment_authorization.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C076.setup_intent` | [`Billing::Contracts::PaymentMethod`](../app/services/billing/contracts/payment_method.rb) → [`Billing::Activities::SetUpPaymentMethod`](../app/services/billing/activities/set_up_payment_method.rb) → provider authorization |
| `C076.make_default` | [`Billing::Activities::MakeDefaultPaymentMethod`](../app/services/billing/activities/make_default_payment_method.rb) |
| `C076.authorization` | [`Billing::PaymentAuthorization`](../app/services/billing/payment_authorization.rb) → provider authorization redirect/form |
| `C076.confirmation` | [`Billing::PaymentAuthorization`](../app/services/billing/payment_authorization.rb) → provider confirmation and stored method |
| `C076.index` | billing methods/provider options → payment-method template |
| `C076.create` | [`Billing::Contracts::PaymentMethod`](../app/services/billing/contracts/payment_method.rb) → [`Billing::Activities::SetUpPaymentMethod`](../app/services/billing/activities/set_up_payment_method.rb) → provider authorization |
| `C076.destroy` | [`Billing::Activities::RemovePaymentMethod`](../app/services/billing/activities/remove_payment_method.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0184 | `POST` | `/:customer_id/admin/settings/billing/payment_methods/setup_intent(.:format)` | `setup_intent` | `C076.setup_intent` |
| R0185 | `PATCH` | `/:customer_id/admin/settings/billing/payment_methods/:id/make_default(.:format)` | `make_default` | `C076.make_default` |
| R0186 | `GET` | `/:customer_id/admin/settings/billing/payment_methods/:id/authorization(.:format)` | `authorization` | `C076.authorization` |
| R0187 | `POST` | `/:customer_id/admin/settings/billing/payment_methods/:id/confirmation(.:format)` | `confirmation` | `C076.confirmation` |
| R0188 | `GET` | `/:customer_id/admin/settings/billing/payment_methods(.:format)` | `index` | `C076.index` |
| R0189 | `POST` | `/:customer_id/admin/settings/billing/payment_methods(.:format)` | `create` | `C076.create` |
| R0190 | `DELETE` | `/:customer_id/admin/settings/billing/payment_methods/:id(.:format)` | `destroy` | `C076.destroy` |

#### C077 — `admin/settings/billing/invoices`

Controller source: `app/controllers/admin/settings/billing/invoices_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. customer-scoped [`Billing::Invoice`](../app/models/billing/invoice.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C077.download` | invoice/status presentation → HTML download document |
| `C077.index` | invoice pagination/history → template |
| `C077.show` | [`Billing::InvoicePaymentAction`](../app/services/billing/invoice_payment_action.rb) → invoice template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0191 | `GET` | `/:customer_id/admin/settings/billing/invoices/:id/download(.:format)` | `download` | `C077.download` |
| R0193 | `GET` | `/:customer_id/admin/settings/billing/invoices(.:format)` | `index` | `C077.index` |
| R0194 | `GET` | `/:customer_id/admin/settings/billing/invoices/:id(.:format)` | `show` | `C077.show` |

#### C078 — `admin/settings/billing/invoice_payments`

Controller source: `app/controllers/admin/settings/billing/invoice_payments_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. customer [`Billing::Invoice`](../app/models/billing/invoice.rb) → [`Billing::Activities::CollectInvoice`](../app/services/billing/activities/collect_invoice.rb) → [`Billing::InvoicePaymentAction`](../app/services/billing/invoice_payment_action.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C078.create` | customer [`Billing::Invoice`](../app/models/billing/invoice.rb) → [`Billing::Activities::CollectInvoice`](../app/services/billing/activities/collect_invoice.rb) → [`Billing::InvoicePaymentAction`](../app/services/billing/invoice_payment_action.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0192 | `POST` | `/:customer_id/admin/settings/billing/invoices/:invoice_id/payment(.:format)` | `create` | `C078.create` |

#### C079 — `admin/module_configs`

Controller source: `app/controllers/admin/module_configs_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C079.show` | configuration presenter/template, including :entry_key alias |
| `C079.update` | permitted config + exit override → customer assignment configuration save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0195 | `GET` | `/:customer_id/admin/settings/modules/:key/:entry_key(.:format)` | `show` | `C079.show` |
| R0196 | `GET` | `/:customer_id/admin/settings/modules/:key(.:format)` | `show` | `C079.show` |
| R0197 | `PATCH` | `/:customer_id/admin/settings/modules/:key(.:format)` | `update` | `C079.update` |
| R0198 | `PUT` | `/:customer_id/admin/settings/modules/:key(.:format)` | `update` | `C079.update` |

### Tenant maintenance and shared platform remounts

**218 route entries · 43 controllers · 109 controller/action pairs.**

#### C082 — `admin/maintenance/customer_profiles`

Controller source: `app/controllers/admin/maintenance/customer_profiles_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. current [`Customer`](../app/models/customer.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C082.edit` | customer profile templates |
| `C082.show` | customer profile templates |
| `C082.update` | permitted profile attributes → [`Customer`](../app/models/customer.rb) save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0201 | `GET` | `/:customer_id/admin/maintenance/customer_profile/edit(.:format)` | `edit` | `C082.edit` |
| R0202 | `GET` | `/:customer_id/admin/maintenance/customer_profile(.:format)` | `show` | `C082.show` |
| R0203 | `PATCH` | `/:customer_id/admin/maintenance/customer_profile(.:format)` | `update` | `C082.update` |
| R0204 | `PUT` | `/:customer_id/admin/maintenance/customer_profile(.:format)` | `update` | `C082.update` |

#### C083 — `admin/maintenance/page_shortcuts`

Controller source: `app/controllers/admin/maintenance/page_shortcuts_controller.rb`; superclass `ApplicationController`.
Family reference: **SHORTCUT**. customer [`PageShortcut`](../app/models/page_shortcut.rb) + [`PageShortcuts::TargetEligibility`](../app/services/page_shortcuts/target_eligibility.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C083.index` | website/public-page targets → shortcut template |
| `C083.create` | [`PageShortcuts::Activities::Save`](../app/services/page_shortcuts/activities/save.rb) → [`PageShortcut`](../app/models/page_shortcut.rb) |
| `C083.update` | [`PageShortcuts::Activities::Save`](../app/services/page_shortcuts/activities/save.rb) → [`PageShortcut`](../app/models/page_shortcut.rb) |
| `C083.destroy` | [`PageShortcuts::Activities::Destroy`](../app/services/page_shortcuts/activities/destroy.rb) → [`PageShortcut`](../app/models/page_shortcut.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0205 | `GET` | `/:customer_id/admin/maintenance/page_shortcuts(.:format)` | `index` | `C083.index` |
| R0206 | `POST` | `/:customer_id/admin/maintenance/page_shortcuts(.:format)` | `create` | `C083.create` |
| R0207 | `PATCH` | `/:customer_id/admin/maintenance/page_shortcuts/:id(.:format)` | `update` | `C083.update` |
| R0208 | `PUT` | `/:customer_id/admin/maintenance/page_shortcuts/:id(.:format)` | `update` | `C083.update` |
| R0209 | `DELETE` | `/:customer_id/admin/maintenance/page_shortcuts/:id(.:format)` | `destroy` | `C083.destroy` |

#### C084 — `admin/maintenance/constant_copies`

Controller source: `app/controllers/admin/maintenance/constant_copies_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → accessible [`Constant`](../app/models/constant.rb) → copy form payload/template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C084.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → accessible [`Constant`](../app/models/constant.rb) → copy form payload/template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0210 | `GET` | `/:customer_id/admin/maintenance/constants/:constant_id/copy(.:format)` | `show` | `C084.show` |
| R0329 | `GET` | `/:customer_id/admin/maintenance/platform/constants/:constant_id/copy(.:format)` | `show` | `C084.show` |

#### C085 — `admin/maintenance/shared_resource_overrides`

Controller source: `app/controllers/admin/maintenance/shared_resource_overrides_controller.rb`; superclass `ApplicationController`.
Family reference: **DEF**. routed parent identifier → accessible [`Constant`](../app/models/constant.rb) / [`Entity`](../app/models/entity.rb) / [`Flowchart`](../app/models/flowchart.rb) / [`Page`](../app/models/page.rb) → reset_customer_override!; four tenant-only DELETE mounts.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C085.destroy` | routed parent identifier → accessible [`Constant`](../app/models/constant.rb) / [`Entity`](../app/models/entity.rb) / [`Flowchart`](../app/models/flowchart.rb) / [`Page`](../app/models/page.rb) → reset_customer_override!; four tenant-only DELETE mounts |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0211 | `DELETE` | `/:customer_id/admin/maintenance/constants/:constant_id/override(.:format)` | `destroy` | `C085.destroy` |
| R0231 | `DELETE` | `/:customer_id/admin/maintenance/entities/:entity_id/override(.:format)` | `destroy` | `C085.destroy` |
| R0265 | `DELETE` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/override(.:format)` | `destroy` | `C085.destroy` |
| R0297 | `DELETE` | `/:customer_id/admin/maintenance/pages/:page_id/override(.:format)` | `destroy` | `C085.destroy` |

#### C086 — `admin/maintenance/constants`

Controller source: `app/controllers/admin/maintenance/constants_controller.rb`; superclass `ApplicationController`; includes `Listable`, `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Constant`](../app/models/constant.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C086.index` | scoped constant browse/form/detail |
| `C086.create` | platform global or tenant-owned [`Constant`](../app/models/constant.rb) save |
| `C086.new` | scoped constant browse/form/detail |
| `C086.edit` | scoped constant browse/form/detail |
| `C086.show` | scoped constant browse/form/detail |
| `C086.update` | global/owned save or tenant [`ConstantCustomerOverride`](../app/models/constant_customer_override.rb) options save |
| `C086.destroy` | permitted constant destroy |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0212 | `GET` | `/:customer_id/admin/maintenance/constants(.:format)` | `index` | `C086.index` |
| R0213 | `POST` | `/:customer_id/admin/maintenance/constants(.:format)` | `create` | `C086.create` |
| R0214 | `GET` | `/:customer_id/admin/maintenance/constants/new(.:format)` | `new` | `C086.new` |
| R0215 | `GET` | `/:customer_id/admin/maintenance/constants/:id/edit(.:format)` | `edit` | `C086.edit` |
| R0216 | `GET` | `/:customer_id/admin/maintenance/constants/:id(.:format)` | `show` | `C086.show` |
| R0217 | `PATCH` | `/:customer_id/admin/maintenance/constants/:id(.:format)` | `update` | `C086.update` |
| R0218 | `PUT` | `/:customer_id/admin/maintenance/constants/:id(.:format)` | `update` | `C086.update` |
| R0219 | `DELETE` | `/:customer_id/admin/maintenance/constants/:id(.:format)` | `destroy` | `C086.destroy` |
| R0330 | `GET` | `/:customer_id/admin/maintenance/platform/constants(.:format)` | `index` | `C086.index` |
| R0331 | `POST` | `/:customer_id/admin/maintenance/platform/constants(.:format)` | `create` | `C086.create` |
| R0332 | `GET` | `/:customer_id/admin/maintenance/platform/constants/new(.:format)` | `new` | `C086.new` |
| R0333 | `GET` | `/:customer_id/admin/maintenance/platform/constants/:id/edit(.:format)` | `edit` | `C086.edit` |
| R0334 | `GET` | `/:customer_id/admin/maintenance/platform/constants/:id(.:format)` | `show` | `C086.show` |
| R0335 | `PATCH` | `/:customer_id/admin/maintenance/platform/constants/:id(.:format)` | `update` | `C086.update` |
| R0336 | `PUT` | `/:customer_id/admin/maintenance/platform/constants/:id(.:format)` | `update` | `C086.update` |
| R0337 | `DELETE` | `/:customer_id/admin/maintenance/platform/constants/:id(.:format)` | `destroy` | `C086.destroy` |

#### C087 — `admin/maintenance/module_enablements`

Controller source: `app/controllers/admin/maintenance/module_enablements_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C087.destroy` | assignment suspended + registration_class.deprovision! in transaction |
| `C087.create` | registration_class.provision! → assignment + module rows in transaction |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0220 | `DELETE` | `/:customer_id/admin/maintenance/modules/:module_id/enablement(.:format)` | `destroy` | `C087.destroy` |
| R0221 | `POST` | `/:customer_id/admin/maintenance/modules/:module_id/enablement(.:format)` | `create` | `C087.create` |

#### C088 — `admin/maintenance/module_sub_toggles`

Controller source: `app/controllers/admin/maintenance/module_sub_toggles_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) → [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) sub-module config save.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C088.update` | [`FeatureModules::Module`](../app/models/feature_modules/module.rb) → [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) sub-module config save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0222 | `PATCH` | `/:customer_id/admin/maintenance/modules/:module_id/sub_toggle(.:format)` | `update` | `C088.update` |
| R0223 | `PUT` | `/:customer_id/admin/maintenance/modules/:module_id/sub_toggle(.:format)` | `update` | `C088.update` |

#### C089 — `admin/maintenance/module_owner_configurations`

Controller source: `app/controllers/admin/maintenance/module_owner_configurations_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) → permitted owner config/numeric limits save.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C089.update` | [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) → permitted owner config/numeric limits save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0224 | `PATCH` | `/:customer_id/admin/maintenance/modules/:module_id/owner_configuration(.:format)` | `update` | `C089.update` |
| R0225 | `PUT` | `/:customer_id/admin/maintenance/modules/:module_id/owner_configuration(.:format)` | `update` | `C089.update` |

#### C090 — `admin/maintenance/modules`

Controller source: `app/controllers/admin/maintenance/modules_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) → [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) → module maintenance template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C090.index` | [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`FeatureModules::CustomerAssignment`](../app/models/feature_modules/customer_assignment.rb) → [`Dashboard::ModuleCards`](../app/services/dashboard/module_cards.rb) → module maintenance template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0226 | `GET` | `/:customer_id/admin/maintenance/modules(.:format)` | `index` | `C090.index` |

#### C091 — `admin/maintenance/entity_restorations`

Controller source: `app/controllers/admin/maintenance/entity_restorations_controller.rb`; superclass `BaseRestorationsController`.
Family reference: **DEF**. inherited BaseRestorationsController#update → [`Entity`](../app/models/entity.rb).restore → [`SoftDeletable`](../app/models/concerns/soft_deletable.rb); bound [`Page`](../app/models/page.rb) follow-up notice.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C091.update` | inherited BaseRestorationsController#update → [`Entity`](../app/models/entity.rb).restore → [`SoftDeletable`](../app/models/concerns/soft_deletable.rb); bound [`Page`](../app/models/page.rb) follow-up notice |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0227 | `PATCH` | `/:customer_id/admin/maintenance/entities/:entity_id/restoration(.:format)` | `update` | `C091.update` |
| R0228 | `PUT` | `/:customer_id/admin/maintenance/entities/:entity_id/restoration(.:format)` | `update` | `C091.update` |
| R0338 | `PATCH` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/restoration(.:format)` | `update` | `C091.update` |
| R0339 | `PUT` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/restoration(.:format)` | `update` | `C091.update` |

#### C092 — `admin/maintenance/entity_copies`

Controller source: `app/controllers/admin/maintenance/entity_copies_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Entity`](../app/models/entity.rb) resolved version → copy form.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C092.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Entity`](../app/models/entity.rb) resolved version → copy form |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0229 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/copy(.:format)` | `show` | `C092.show` |
| R0340 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/copy(.:format)` | `show` | `C092.show` |

#### C093 — `admin/maintenance/entity_template_previews`

Controller source: `app/controllers/admin/maintenance/entity_template_previews_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Entity`](../app/models/entity.rb) → [`TemplatePreviewBuilder`](../app/services/template_preview_builder.rb) → layout preview.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C093.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Entity`](../app/models/entity.rb) → [`TemplatePreviewBuilder`](../app/services/template_preview_builder.rb) → layout preview |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0230 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/template_preview(.:format)` | `show` | `C093.show` |
| R0341 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/template_preview(.:format)` | `show` | `C093.show` |

#### C094 — `admin/maintenance/entity_domain_memberships`

Controller source: `app/controllers/admin/maintenance/entity_domain_memberships_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`EntityDomains::Catalog`](../app/services/entity_domains/catalog.rb) / [`EntityDomain`](../app/models/entity_domain.rb) / [`EntityDomainMembership`](../app/models/entity_domain_membership.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C094.edit` | domain membership form |
| `C094.update` | [`EntityDomains::Activities::Assign`](../app/services/entity_domains/activities/assign.rb) → membership save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0232 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/domain_membership/edit(.:format)` | `edit` | `C094.edit` |
| R0233 | `PATCH` | `/:customer_id/admin/maintenance/entities/:entity_id/domain_membership(.:format)` | `update` | `C094.update` |
| R0234 | `PUT` | `/:customer_id/admin/maintenance/entities/:entity_id/domain_membership(.:format)` | `update` | `C094.update` |

#### C095 — `admin/maintenance/entity_versions`

Controller source: `app/controllers/admin/maintenance/entity_versions_controller.rb`; superclass `BaseVersionsController`.
Family reference: **DEF**. BaseVersionsController → [`Entity`](../app/models/entity.rb) / [`EntityVersion`](../app/models/entity_version.rb) / [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C095.default` | [`Entities::PromoteVersion`](../app/services/entities/promote_version.rb) → entity definition/head validation and promotion |
| `C095.page` | [`Pages::Activities::CreateFromEntityVersion`](../app/services/pages/activities/create_from_entity_version.rb) → page creation |
| `C095.index` | current-line version history/snapshot |
| `C095.create` | [`Entities::PromoteVersion`](../app/services/entities/promote_version.rb) → entity definition/head validation and promotion |
| `C095.edit` | version editor template |
| `C095.show` | current-line version history/snapshot |
| `C095.destroy` | inherited version destroy + orphan-content sweep |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0235 | `PUT` | `/:customer_id/admin/maintenance/entities/:entity_id/versions/:id/default(.:format)` | `default` | `C095.default` |
| R0236 | `POST` | `/:customer_id/admin/maintenance/entities/:entity_id/versions/:id/page(.:format)` | `page` | `C095.page` |
| R0237 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/versions(.:format)` | `index` | `C095.index` |
| R0238 | `POST` | `/:customer_id/admin/maintenance/entities/:entity_id/versions(.:format)` | `create` | `C095.create` |
| R0239 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/versions/:id/edit(.:format)` | `edit` | `C095.edit` |
| R0240 | `GET` | `/:customer_id/admin/maintenance/entities/:entity_id/versions/:id(.:format)` | `show` | `C095.show` |
| R0241 | `DELETE` | `/:customer_id/admin/maintenance/entities/:entity_id/versions/:id(.:format)` | `destroy` | `C095.destroy` |
| R0342 | `PUT` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions/:id/default(.:format)` | `default` | `C095.default` |
| R0343 | `POST` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions/:id/page(.:format)` | `page` | `C095.page` |
| R0344 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions(.:format)` | `index` | `C095.index` |
| R0345 | `POST` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions(.:format)` | `create` | `C095.create` |
| R0346 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions/:id/edit(.:format)` | `edit` | `C095.edit` |
| R0347 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions/:id(.:format)` | `show` | `C095.show` |
| R0348 | `DELETE` | `/:customer_id/admin/maintenance/platform/entities/:entity_id/versions/:id(.:format)` | `destroy` | `C095.destroy` |

#### C096 — `admin/maintenance/entities`

Controller source: `app/controllers/admin/maintenance/entities_controller.rb`; superclass `ApplicationController`; includes `SoftDeletableController`, `Listable`, `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Entity`](../app/models/entity.rb); [`Entities::Contracts::Definition`](../app/services/entities/contracts/definition.rb) / [`Entities::VersionHydrator`](../app/services/entities/version_hydrator.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C096.trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → deleted [`Entity`](../app/models/entity.rb) list |
| `C096.empty_trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → trashed entity permanent deletion |
| `C096.template_fields` | [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) → [`TemplateFieldExtractor`](../app/services/template_field_extractor.rb) |
| `C096.base_model_fields` | [`EntityDefinitions::Capabilities`](../app/services/entity_definitions/capabilities.rb) → base-model field metadata |
| `C096.index` | [`EntityDomains::Layout`](../app/services/entity_domains/layout.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) |
| `C096.create` | [`Entities::Contracts::Definition`](../app/services/entities/contracts/definition.rb) + [`Billing::Quota::Guard`](../app/services/billing/quota/guard.rb) → [`Entity`](../app/models/entity.rb) save/version |
| `C096.new` | entity + hydrated version → definition form |
| `C096.edit` | entity + hydrated version → definition form |
| `C096.show` | [`ModelGenerator`](../app/services/model_generator.rb) / [`ContractGenerator`](../app/services/contract_generator.rb) → definition/code preview |
| `C096.update` | definition/identity guard → [`Entity`](../app/models/entity.rb) save/version |
| `C096.destroy` | soft deletion → dependent lifecycle |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0242 | `GET` | `/:customer_id/admin/maintenance/entities/trash(.:format)` | `trash` | `C096.trash` |
| R0243 | `DELETE` | `/:customer_id/admin/maintenance/entities/empty_trash(.:format)` | `empty_trash` | `C096.empty_trash` |
| R0244 | `GET` | `/:customer_id/admin/maintenance/entities/template_fields(.:format)` | `template_fields` | `C096.template_fields` |
| R0245 | `GET` | `/:customer_id/admin/maintenance/entities/base_model_fields(.:format)` | `base_model_fields` | `C096.base_model_fields` |
| R0246 | `GET` | `/:customer_id/admin/maintenance/entities(.:format)` | `index` | `C096.index` |
| R0247 | `POST` | `/:customer_id/admin/maintenance/entities(.:format)` | `create` | `C096.create` |
| R0248 | `GET` | `/:customer_id/admin/maintenance/entities/new(.:format)` | `new` | `C096.new` |
| R0249 | `GET` | `/:customer_id/admin/maintenance/entities/:id/edit(.:format)` | `edit` | `C096.edit` |
| R0250 | `GET` | `/:customer_id/admin/maintenance/entities/:id(.:format)` | `show` | `C096.show` |
| R0251 | `PATCH` | `/:customer_id/admin/maintenance/entities/:id(.:format)` | `update` | `C096.update` |
| R0252 | `PUT` | `/:customer_id/admin/maintenance/entities/:id(.:format)` | `update` | `C096.update` |
| R0253 | `DELETE` | `/:customer_id/admin/maintenance/entities/:id(.:format)` | `destroy` | `C096.destroy` |
| R0349 | `GET` | `/:customer_id/admin/maintenance/platform/entities/trash(.:format)` | `trash` | `C096.trash` |
| R0350 | `DELETE` | `/:customer_id/admin/maintenance/platform/entities/empty_trash(.:format)` | `empty_trash` | `C096.empty_trash` |
| R0351 | `GET` | `/:customer_id/admin/maintenance/platform/entities/template_fields(.:format)` | `template_fields` | `C096.template_fields` |
| R0352 | `GET` | `/:customer_id/admin/maintenance/platform/entities/base_model_fields(.:format)` | `base_model_fields` | `C096.base_model_fields` |
| R0353 | `GET` | `/:customer_id/admin/maintenance/platform/entities(.:format)` | `index` | `C096.index` |
| R0354 | `POST` | `/:customer_id/admin/maintenance/platform/entities(.:format)` | `create` | `C096.create` |
| R0355 | `GET` | `/:customer_id/admin/maintenance/platform/entities/new(.:format)` | `new` | `C096.new` |
| R0356 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:id/edit(.:format)` | `edit` | `C096.edit` |
| R0357 | `GET` | `/:customer_id/admin/maintenance/platform/entities/:id(.:format)` | `show` | `C096.show` |
| R0358 | `PATCH` | `/:customer_id/admin/maintenance/platform/entities/:id(.:format)` | `update` | `C096.update` |
| R0359 | `PUT` | `/:customer_id/admin/maintenance/platform/entities/:id(.:format)` | `update` | `C096.update` |
| R0360 | `DELETE` | `/:customer_id/admin/maintenance/platform/entities/:id(.:format)` | `destroy` | `C096.destroy` |

#### C097 — `admin/maintenance/entity_domains`

Controller source: `app/controllers/admin/maintenance/entity_domains_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`EntityDomain`](../app/models/entity_domain.rb) / [`EntityDomains::Catalog`](../app/services/entity_domains/catalog.rb) / [`EntityDomainMembership`](../app/models/entity_domain_membership.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C097.create` | [`EntityDomains::Activities::Save`](../app/services/entity_domains/activities/save.rb) → domain/memberships |
| `C097.new` | domain editor template |
| `C097.edit` | domain editor template |
| `C097.update` | [`EntityDomains::Activities::Save`](../app/services/entity_domains/activities/save.rb) → domain/memberships |
| `C097.destroy` | [`EntityDomains::Activities::Destroy`](../app/services/entity_domains/activities/destroy.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0254 | `POST` | `/:customer_id/admin/maintenance/entity_domains(.:format)` | `create` | `C097.create` |
| R0255 | `GET` | `/:customer_id/admin/maintenance/entity_domains/new(.:format)` | `new` | `C097.new` |
| R0256 | `GET` | `/:customer_id/admin/maintenance/entity_domains/:id/edit(.:format)` | `edit` | `C097.edit` |
| R0257 | `PATCH` | `/:customer_id/admin/maintenance/entity_domains/:id(.:format)` | `update` | `C097.update` |
| R0258 | `PUT` | `/:customer_id/admin/maintenance/entity_domains/:id(.:format)` | `update` | `C097.update` |
| R0259 | `DELETE` | `/:customer_id/admin/maintenance/entity_domains/:id(.:format)` | `destroy` | `C097.destroy` |

#### C098 — `admin/maintenance/template_picker_cards`

Controller source: `app/controllers/admin/maintenance/template_picker_cards_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) catalog → picker cards template; excluded template-body directory not read.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C098.show` | [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) catalog → picker cards template; excluded template-body directory not read |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0260 | `GET` | `/:customer_id/admin/maintenance/template_picker_cards(.:format)` | `show` | `C098.show` |

#### C099 — `admin/maintenance/template_previews`

Controller source: `app/controllers/admin/maintenance/template_previews_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) → [`TemplatePreviewBuilder`](../app/services/template_preview_builder.rb) → preview template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C099.show` | [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) → [`TemplatePreviewBuilder`](../app/services/template_preview_builder.rb) → preview template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0261 | `GET` | `/:customer_id/admin/maintenance/template_previews/:id(.:format)` | `show` | `C099.show` |

#### C100 — `admin/maintenance/flowchart_restorations`

Controller source: `app/controllers/admin/maintenance/flowchart_restorations_controller.rb`; superclass `BaseRestorationsController`.
Family reference: **DEF**. inherited BaseRestorationsController#update → [`Flowchart`](../app/models/flowchart.rb).restore / [`SoftDeletable`](../app/models/concerns/soft_deletable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C100.update` | inherited BaseRestorationsController#update → [`Flowchart`](../app/models/flowchart.rb).restore / [`SoftDeletable`](../app/models/concerns/soft_deletable.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0262 | `PATCH` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/restoration(.:format)` | `update` | `C100.update` |
| R0263 | `PUT` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/restoration(.:format)` | `update` | `C100.update` |
| R0361 | `PATCH` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/restoration(.:format)` | `update` | `C100.update` |
| R0362 | `PUT` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/restoration(.:format)` | `update` | `C100.update` |

#### C101 — `admin/maintenance/flowchart_copies`

Controller source: `app/controllers/admin/maintenance/flowchart_copies_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart`](../app/models/flowchart.rb) / [`Entity`](../app/models/entity.rb) → resolved-definition copy form.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C101.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart`](../app/models/flowchart.rb) / [`Entity`](../app/models/entity.rb) → resolved-definition copy form |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0264 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/copy(.:format)` | `show` | `C101.show` |
| R0363 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/copy(.:format)` | `show` | `C101.show` |

#### C102 — `admin/maintenance/flowcharts`

Controller source: `app/controllers/admin/maintenance/flowcharts_controller.rb`; superclass `ApplicationController`; includes `SoftDeletableController`, `Listable`, `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart`](../app/models/flowchart.rb) / [`Entity`](../app/models/entity.rb) → [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C102.trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → trash list |
| `C102.empty_trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → permanent deletion |
| `C102.index` | scoped flowchart list/detail/editor |
| `C102.create` | flowchart configuration save → version/head |
| `C102.new` | scoped flowchart list/detail/editor |
| `C102.edit` | scoped flowchart list/detail/editor |
| `C102.show` | scoped flowchart list/detail/editor |
| `C102.update` | flowchart configuration save → version/head |
| `C102.destroy` | flowchart soft deletion |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0266 | `GET` | `/:customer_id/admin/maintenance/flowcharts/trash(.:format)` | `trash` | `C102.trash` |
| R0267 | `DELETE` | `/:customer_id/admin/maintenance/flowcharts/empty_trash(.:format)` | `empty_trash` | `C102.empty_trash` |
| R0285 | `GET` | `/:customer_id/admin/maintenance/flowcharts(.:format)` | `index` | `C102.index` |
| R0286 | `POST` | `/:customer_id/admin/maintenance/flowcharts(.:format)` | `create` | `C102.create` |
| R0287 | `GET` | `/:customer_id/admin/maintenance/flowcharts/new(.:format)` | `new` | `C102.new` |
| R0288 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:id/edit(.:format)` | `edit` | `C102.edit` |
| R0289 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:id(.:format)` | `show` | `C102.show` |
| R0290 | `PATCH` | `/:customer_id/admin/maintenance/flowcharts/:id(.:format)` | `update` | `C102.update` |
| R0291 | `PUT` | `/:customer_id/admin/maintenance/flowcharts/:id(.:format)` | `update` | `C102.update` |
| R0292 | `DELETE` | `/:customer_id/admin/maintenance/flowcharts/:id(.:format)` | `destroy` | `C102.destroy` |
| R0364 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/trash(.:format)` | `trash` | `C102.trash` |
| R0365 | `DELETE` | `/:customer_id/admin/maintenance/platform/flowcharts/empty_trash(.:format)` | `empty_trash` | `C102.empty_trash` |
| R0381 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts(.:format)` | `index` | `C102.index` |
| R0382 | `POST` | `/:customer_id/admin/maintenance/platform/flowcharts(.:format)` | `create` | `C102.create` |
| R0383 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/new(.:format)` | `new` | `C102.new` |
| R0384 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:id/edit(.:format)` | `edit` | `C102.edit` |
| R0385 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:id(.:format)` | `show` | `C102.show` |
| R0386 | `PATCH` | `/:customer_id/admin/maintenance/platform/flowcharts/:id(.:format)` | `update` | `C102.update` |
| R0387 | `PUT` | `/:customer_id/admin/maintenance/platform/flowcharts/:id(.:format)` | `update` | `C102.update` |
| R0388 | `DELETE` | `/:customer_id/admin/maintenance/platform/flowcharts/:id(.:format)` | `destroy` | `C102.destroy` |

#### C103 — `admin/maintenance/flowcharts/step_io_params`

Controller source: `app/controllers/admin/maintenance/flowcharts/step_io_params_controller.rb`; superclass `ApplicationController`; includes `GeneratorIoIntrospection`.
Family reference: **GEN**. [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) step-action inputs/outputs; POST transports configuration, not activity execution.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C103.show` | [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) step-action inputs/outputs; POST transports configuration, not activity execution |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0268 | `POST` | `/:customer_id/admin/maintenance/flowcharts/step_actions/:generator_action/io_params(.:format)` | `show` | `C103.show` |

#### C104 — `admin/maintenance/flowcharts/element_io_params`

Controller source: `app/controllers/admin/maintenance/flowcharts/element_io_params_controller.rb`; superclass `ApplicationController`; includes `GeneratorIoIntrospection`.
Family reference: **GEN**. [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) element-type inputs/outputs; tenant-only mount.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C104.show` | [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) element-type inputs/outputs; tenant-only mount |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0269 | `POST` | `/:customer_id/admin/maintenance/flowcharts/element_types/:element_type/io_params(.:format)` | `show` | `C104.show` |

#### C105 — `admin/maintenance/flowchart_reference_options`

Controller source: `app/controllers/admin/maintenance/flowchart_reference_options_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::ReferenceSources`](../app/services/code_generators/reference_sources.rb) → source-specific accessible model query → capped JSON options.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C105.show` | [`CodeGenerators::ReferenceSources`](../app/services/code_generators/reference_sources.rb) → source-specific accessible model query → capped JSON options |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0270 | `GET` | `/:customer_id/admin/maintenance/flowcharts/reference_options/:source(.:format)` | `show` | `C105.show` |
| R0366 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/reference_options/:source(.:format)` | `show` | `C105.show` |

#### C106 — `admin/maintenance/flowcharts/implicit_keys`

Controller source: `app/controllers/admin/maintenance/flowcharts/implicit_keys_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. YAML.safe_load_file of config/flowchart_validation.yml → JSON implicit_context_keys metadata.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C106.show` | YAML.safe_load_file of config/flowchart_validation.yml → JSON implicit_context_keys metadata |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0271 | `GET` | `/:customer_id/admin/maintenance/flowcharts/validation/implicit_keys(.:format)` | `show` | `C106.show` |
| R0367 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/validation/implicit_keys(.:format)` | `show` | `C106.show` |

#### C107 — `admin/maintenance/flowchart_versions`

Controller source: `app/controllers/admin/maintenance/flowchart_versions_controller.rb`; superclass `BaseVersionsController`.
Family reference: **DEF**. BaseVersionsController → [`Flowchart`](../app/models/flowchart.rb) / [`FlowchartVersion`](../app/models/flowchart_version.rb) / [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C107.default` | inherited set_current_version! |
| `C107.index` | inherited current-line version history/snapshot |
| `C107.create` | inherited restore_as_new! |
| `C107.edit` | flowchart version editor |
| `C107.show` | inherited current-line version history/snapshot |
| `C107.destroy` | inherited version destroy + content sweep |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0272 | `PUT` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions/:id/default(.:format)` | `default` | `C107.default` |
| R0273 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions(.:format)` | `index` | `C107.index` |
| R0274 | `POST` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions(.:format)` | `create` | `C107.create` |
| R0275 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions/:id/edit(.:format)` | `edit` | `C107.edit` |
| R0276 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions/:id(.:format)` | `show` | `C107.show` |
| R0277 | `DELETE` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/versions/:id(.:format)` | `destroy` | `C107.destroy` |
| R0368 | `PUT` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions/:id/default(.:format)` | `default` | `C107.default` |
| R0369 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions(.:format)` | `index` | `C107.index` |
| R0370 | `POST` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions(.:format)` | `create` | `C107.create` |
| R0371 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions/:id/edit(.:format)` | `edit` | `C107.edit` |
| R0372 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions/:id(.:format)` | `show` | `C107.show` |
| R0373 | `DELETE` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/versions/:id(.:format)` | `destroy` | `C107.destroy` |

#### C108 — `admin/maintenance/flowchart_launches`

Controller source: `app/controllers/admin/maintenance/flowchart_launches_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart`](../app/models/flowchart.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C108.destroy` | take_offline! → bound-page lifecycle |
| `C108.create` | [`FlowchartServerValidator`](../app/services/flowchart_server_validator.rb) / [`FlowchartInputOutputValidator`](../app/services/flowchart_input_output_validator.rb) → launch! |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0278 | `DELETE` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/launch(.:format)` | `destroy` | `C108.destroy` |
| R0279 | `POST` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/launch(.:format)` | `create` | `C108.create` |
| R0374 | `DELETE` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/launch(.:format)` | `destroy` | `C108.destroy` |
| R0375 | `POST` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/launch(.:format)` | `create` | `C108.create` |

#### C109 — `admin/maintenance/flowcharts/validations`

Controller source: `app/controllers/admin/maintenance/flowcharts/validations_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`Flowchart`](../app/models/flowchart.rb) → [`FlowchartServerValidator`](../app/services/flowchart_server_validator.rb) → validation JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C109.create` | [`Flowchart`](../app/models/flowchart.rb) → [`FlowchartServerValidator`](../app/services/flowchart_server_validator.rb) → validation JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0280 | `POST` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/validation(.:format)` | `create` | `C109.create` |
| R0376 | `POST` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/validation(.:format)` | `create` | `C109.create` |

#### C110 — `admin/maintenance/flowchart_crud_types`

Controller source: `app/controllers/admin/maintenance/flowchart_crud_types_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart::CRUD_TYPES`](../app/models/flowchart.rb) → guarded crud_type save.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C110.update` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Flowchart::CRUD_TYPES`](../app/models/flowchart.rb) → guarded crud_type save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0281 | `PATCH` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/crud_type(.:format)` | `update` | `C110.update` |
| R0282 | `PUT` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/crud_type(.:format)` | `update` | `C110.update` |
| R0377 | `PATCH` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/crud_type(.:format)` | `update` | `C110.update` |
| R0378 | `PUT` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/crud_type(.:format)` | `update` | `C110.update` |

#### C111 — `admin/maintenance/flowchart_traces`

Controller source: `app/controllers/admin/maintenance/flowchart_traces_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`Flowchart`](../app/models/flowchart.rb) → [`ActivityGenerator`](../app/services/activity_generator.rb) / [`ActivityTracer`](../app/services/activity_tracer.rb) → [`FlowchartRuntime::Authentication`](../app/services/flowchart_runtime/authentication.rb) → [`ContextSanitizer`](../app/services/context_sanitizer.rb); trace executes inside rollback-only transaction.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C111.create` | [`Flowchart`](../app/models/flowchart.rb) → [`ActivityGenerator`](../app/services/activity_generator.rb) / [`ActivityTracer`](../app/services/activity_tracer.rb) → [`FlowchartRuntime::Authentication`](../app/services/flowchart_runtime/authentication.rb) → [`ContextSanitizer`](../app/services/context_sanitizer.rb); trace executes inside rollback-only transaction |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0283 | `POST` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/traces(.:format)` | `create` | `C111.create` |
| R0379 | `POST` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/traces(.:format)` | `create` | `C111.create` |

#### C112 — `admin/maintenance/flowchart_documents`

Controller source: `app/controllers/admin/maintenance/flowchart_documents_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`Flowchart`](../app/models/flowchart.rb) → [`FlowchartDocumenter`](../app/services/flowchart_documenter.rb) → generated document.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C112.show` | [`Flowchart`](../app/models/flowchart.rb) → [`FlowchartDocumenter`](../app/services/flowchart_documenter.rb) → generated document |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0284 | `GET` | `/:customer_id/admin/maintenance/flowcharts/:flowchart_id/document(.:format)` | `show` | `C112.show` |
| R0380 | `GET` | `/:customer_id/admin/maintenance/platform/flowcharts/:flowchart_id/document(.:format)` | `show` | `C112.show` |

#### C113 — `admin/maintenance/page_restorations`

Controller source: `app/controllers/admin/maintenance/page_restorations_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → deleted [`Page`](../app/models/page.rb).restore (controller-defined update).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C113.update` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → deleted [`Page`](../app/models/page.rb).restore (controller-defined update) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0293 | `PATCH` | `/:customer_id/admin/maintenance/pages/:page_id/restoration(.:format)` | `update` | `C113.update` |
| R0294 | `PUT` | `/:customer_id/admin/maintenance/pages/:page_id/restoration(.:format)` | `update` | `C113.update` |
| R0389 | `PATCH` | `/:customer_id/admin/maintenance/platform/pages/:page_id/restoration(.:format)` | `update` | `C113.update` |
| R0390 | `PUT` | `/:customer_id/admin/maintenance/platform/pages/:page_id/restoration(.:format)` | `update` | `C113.update` |

#### C114 — `admin/maintenance/page_visibilities`

Controller source: `app/controllers/admin/maintenance/page_visibilities_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`, `SafeReturnTo`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Pages::VisibilityContract`](../app/contracts/pages/visibility_contract.rb) → [`Page`](../app/models/page.rb) visibility save.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C114.update` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Pages::VisibilityContract`](../app/contracts/pages/visibility_contract.rb) → [`Page`](../app/models/page.rb) visibility save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0295 | `PATCH` | `/:customer_id/admin/maintenance/pages/:page_id/visibility(.:format)` | `update` | `C114.update` |
| R0296 | `PUT` | `/:customer_id/admin/maintenance/pages/:page_id/visibility(.:format)` | `update` | `C114.update` |
| R0391 | `PATCH` | `/:customer_id/admin/maintenance/platform/pages/:page_id/visibility(.:format)` | `update` | `C114.update` |
| R0392 | `PUT` | `/:customer_id/admin/maintenance/platform/pages/:page_id/visibility(.:format)` | `update` | `C114.update` |

#### C115 — `admin/maintenance/page_versions`

Controller source: `app/controllers/admin/maintenance/page_versions_controller.rb`; superclass `BaseVersionsController`.
Family reference: **DEF**. BaseVersionsController → [`Page`](../app/models/page.rb) / [`PageVersion`](../app/models/page_version.rb) / [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C115.default` | inherited set_current_version! |
| `C115.index` | inherited current-line history/snapshot |
| `C115.create` | inherited restore_as_new! |
| `C115.edit` | version editor |
| `C115.show` | inherited current-line history/snapshot |
| `C115.destroy` | inherited version destroy + content sweep |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0298 | `PUT` | `/:customer_id/admin/maintenance/pages/:page_id/versions/:id/default(.:format)` | `default` | `C115.default` |
| R0299 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/versions(.:format)` | `index` | `C115.index` |
| R0300 | `POST` | `/:customer_id/admin/maintenance/pages/:page_id/versions(.:format)` | `create` | `C115.create` |
| R0301 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/versions/:id/edit(.:format)` | `edit` | `C115.edit` |
| R0302 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/versions/:id(.:format)` | `show` | `C115.show` |
| R0303 | `DELETE` | `/:customer_id/admin/maintenance/pages/:page_id/versions/:id(.:format)` | `destroy` | `C115.destroy` |
| R0393 | `PUT` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions/:id/default(.:format)` | `default` | `C115.default` |
| R0394 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions(.:format)` | `index` | `C115.index` |
| R0395 | `POST` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions(.:format)` | `create` | `C115.create` |
| R0396 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions/:id/edit(.:format)` | `edit` | `C115.edit` |
| R0397 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions/:id(.:format)` | `show` | `C115.show` |
| R0398 | `DELETE` | `/:customer_id/admin/maintenance/platform/pages/:page_id/versions/:id(.:format)` | `destroy` | `C115.destroy` |

#### C116 — `admin/maintenance/page_copies`

Controller source: `app/controllers/admin/maintenance/page_copies_controller.rb`; superclass `PagesController`.
Family reference: **DEF**. inherits PagesController → [`Page`](../app/models/page.rb) resolved version/content → copy editor.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C116.show` | inherits PagesController → [`Page`](../app/models/page.rb) resolved version/content → copy editor |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0304 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/copy(.:format)` | `show` | `C116.show` |
| R0399 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/copy(.:format)` | `show` | `C116.show` |

#### C117 — `admin/maintenance/page_template_applications`

Controller source: `app/controllers/admin/maintenance/page_template_applications_controller.rb`; superclass `PagesController`.
Family reference: **PAGE**. inherits PagesController → [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) / [`PageTemplateApplier`](../app/services/page_template_applier.rb) / [`ThemeResolver`](../app/components/concerns/theme_resolver.rb) → [`Page`](../app/models/page.rb) configuration save.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C117.create` | inherits PagesController → [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) / [`PageTemplateApplier`](../app/services/page_template_applier.rb) / [`ThemeResolver`](../app/components/concerns/theme_resolver.rb) → [`Page`](../app/models/page.rb) configuration save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0305 | `POST` | `/:customer_id/admin/maintenance/pages/:page_id/template_application(.:format)` | `create` | `C117.create` |
| R0400 | `POST` | `/:customer_id/admin/maintenance/platform/pages/:page_id/template_application(.:format)` | `create` | `C117.create` |

#### C118 — `admin/maintenance/pages`

Controller source: `app/controllers/admin/maintenance/pages_controller.rb`; superclass `ApplicationController`; includes `SoftDeletableController`, `Listable`, `SharedResourceMode`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) / [`Flowchart`](../app/models/flowchart.rb) / [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C118.trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → deleted pages |
| `C118.empty_trash` | inherited [`SoftDeletableController`](../app/controllers/concerns/soft_deletable_controller.rb) → permanent deletion |
| `C118.entity_flows` | accessible bindable [`Flowchart`](../app/models/flowchart.rb) → JSON |
| `C118.index` | [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → page list |
| `C118.create` | [`Pages::ConfigurationComposer`](../app/services/pages/configuration_composer.rb) + [`Billing::Quota::Guard`](../app/services/billing/quota/guard.rb) → [`Page`](../app/models/page.rb) / generated content/version |
| `C118.new` | page/entity/flowchart options → editor |
| `C118.edit` | page/entity/flowchart options → editor |
| `C118.show` | [`Pages::FormHealth`](../app/services/pages/form_health.rb) → detail/JSON cached content |
| `C118.update` | page/edit-stamp checks → [`Page`](../app/models/page.rb) save → [`PageContentGenerator`](../app/services/page_content_generator.rb) → version |
| `C118.destroy` | page soft deletion |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0306 | `GET` | `/:customer_id/admin/maintenance/pages/trash(.:format)` | `trash` | `C118.trash` |
| R0307 | `DELETE` | `/:customer_id/admin/maintenance/pages/empty_trash(.:format)` | `empty_trash` | `C118.empty_trash` |
| R0308 | `GET` | `/:customer_id/admin/maintenance/pages/entity_flows(.:format)` | `entity_flows` | `C118.entity_flows` |
| R0321 | `GET` | `/:customer_id/admin/maintenance/pages(.:format)` | `index` | `C118.index` |
| R0322 | `POST` | `/:customer_id/admin/maintenance/pages(.:format)` | `create` | `C118.create` |
| R0323 | `GET` | `/:customer_id/admin/maintenance/pages/new(.:format)` | `new` | `C118.new` |
| R0324 | `GET` | `/:customer_id/admin/maintenance/pages/:id/edit(.:format)` | `edit` | `C118.edit` |
| R0325 | `GET` | `/:customer_id/admin/maintenance/pages/:id(.:format)` | `show` | `C118.show` |
| R0326 | `PATCH` | `/:customer_id/admin/maintenance/pages/:id(.:format)` | `update` | `C118.update` |
| R0327 | `PUT` | `/:customer_id/admin/maintenance/pages/:id(.:format)` | `update` | `C118.update` |
| R0328 | `DELETE` | `/:customer_id/admin/maintenance/pages/:id(.:format)` | `destroy` | `C118.destroy` |
| R0401 | `GET` | `/:customer_id/admin/maintenance/platform/pages/trash(.:format)` | `trash` | `C118.trash` |
| R0402 | `DELETE` | `/:customer_id/admin/maintenance/platform/pages/empty_trash(.:format)` | `empty_trash` | `C118.empty_trash` |
| R0403 | `GET` | `/:customer_id/admin/maintenance/platform/pages/entity_flows(.:format)` | `entity_flows` | `C118.entity_flows` |
| R0411 | `GET` | `/:customer_id/admin/maintenance/platform/pages(.:format)` | `index` | `C118.index` |
| R0412 | `POST` | `/:customer_id/admin/maintenance/platform/pages(.:format)` | `create` | `C118.create` |
| R0413 | `GET` | `/:customer_id/admin/maintenance/platform/pages/new(.:format)` | `new` | `C118.new` |
| R0414 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:id/edit(.:format)` | `edit` | `C118.edit` |
| R0415 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:id(.:format)` | `show` | `C118.show` |
| R0416 | `PATCH` | `/:customer_id/admin/maintenance/platform/pages/:id(.:format)` | `update` | `C118.update` |
| R0417 | `PUT` | `/:customer_id/admin/maintenance/platform/pages/:id(.:format)` | `update` | `C118.update` |
| R0418 | `DELETE` | `/:customer_id/admin/maintenance/platform/pages/:id(.:format)` | `destroy` | `C118.destroy` |

#### C119 — `admin/maintenance/field_templates`

Controller source: `app/controllers/admin/maintenance/field_templates_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`FieldTemplate`](../app/models/field_template.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C119.index` | customer field-template list JSON |
| `C119.create` | [`FieldTemplates::Create`](../app/services/field_templates/create.rb) |
| `C119.update` | [`FieldTemplates::Update`](../app/services/field_templates/update.rb) |
| `C119.destroy` | [`FieldTemplates::Delete`](../app/services/field_templates/delete.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0309 | `GET` | `/:customer_id/admin/maintenance/pages/field_templates(.:format)` | `index` | `C119.index` |
| R0310 | `POST` | `/:customer_id/admin/maintenance/pages/field_templates(.:format)` | `create` | `C119.create` |
| R0311 | `PATCH` | `/:customer_id/admin/maintenance/pages/field_templates/:id(.:format)` | `update` | `C119.update` |
| R0312 | `PUT` | `/:customer_id/admin/maintenance/pages/field_templates/:id(.:format)` | `update` | `C119.update` |
| R0313 | `DELETE` | `/:customer_id/admin/maintenance/pages/field_templates/:id(.:format)` | `destroy` | `C119.destroy` |

#### C120 — `admin/maintenance/page_launches`

Controller source: `app/controllers/admin/maintenance/page_launches_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`, `SafeReturnTo`.
Family reference: **DEF**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) / [`PageLaunchLifecycle`](../app/models/concerns/page_launch_lifecycle.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C120.destroy` | page.take_offline! → launched-definition lifecycle |
| `C120.create` | page.launch! → launch validation/head/presentation |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0314 | `DELETE` | `/:customer_id/admin/maintenance/pages/:page_id/launch(.:format)` | `destroy` | `C120.destroy` |
| R0315 | `POST` | `/:customer_id/admin/maintenance/pages/:page_id/launch(.:format)` | `create` | `C120.create` |
| R0404 | `DELETE` | `/:customer_id/admin/maintenance/platform/pages/:page_id/launch(.:format)` | `destroy` | `C120.destroy` |
| R0405 | `POST` | `/:customer_id/admin/maintenance/platform/pages/:page_id/launch(.:format)` | `create` | `C120.create` |

#### C121 — `admin/maintenance/page_previews`

Controller source: `app/controllers/admin/maintenance/page_previews_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **PAGE**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → cached content or [`PageContentGenerator`](../app/services/page_content_generator.rb) → preview HTML; show/create share render_preview.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C121.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → cached content or [`PageContentGenerator`](../app/services/page_content_generator.rb) → preview HTML; show/create share render_preview |
| `C121.create` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → cached content or [`PageContentGenerator`](../app/services/page_content_generator.rb) → preview HTML; show/create share render_preview |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0316 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/preview(.:format)` | `show` | `C121.show` |
| R0317 | `POST` | `/:customer_id/admin/maintenance/pages/:page_id/preview(.:format)` | `create` | `C121.create` |
| R0406 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/preview(.:format)` | `show` | `C121.show` |
| R0407 | `POST` | `/:customer_id/admin/maintenance/platform/pages/:page_id/preview(.:format)` | `create` | `C121.create` |

#### C122 — `admin/maintenance/page_renders`

Controller source: `app/controllers/admin/maintenance/page_renders_controller.rb`; superclass `ApplicationController`; includes `PageRendering`, `SharedResourceMode`.
Family reference: **PAGE**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb) → runtime generated ERB.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C122.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb) → runtime generated ERB |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0318 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/render(.:format)` | `show` | `C122.show` |
| R0408 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/render(.:format)` | `show` | `C122.show` |

#### C123 — `admin/maintenance/page_field_options`

Controller source: `app/controllers/admin/maintenance/page_field_options_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **PAGE**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`Entities::ReferenceOptions`](../app/services/entities/reference_options.rb) or [`PageContentGenerator::DynamicOptionsResolver`](../app/services/page_content_generator/dynamic_options_resolver.rb) → field options JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C123.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`Entities::ReferenceOptions`](../app/services/entities/reference_options.rb) or [`PageContentGenerator::DynamicOptionsResolver`](../app/services/page_content_generator/dynamic_options_resolver.rb) → field options JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0319 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/field_options/:field_id(.:format)` | `show` | `C123.show` |
| R0409 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/field_options/:field_id(.:format)` | `show` | `C123.show` |

#### C124 — `admin/maintenance/page_module_data`

Controller source: `app/controllers/admin/maintenance/page_module_data_controller.rb`; superclass `ApplicationController`; includes `SharedResourceMode`.
Family reference: **PAGE**. [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`CompositePageRenderer`](../app/services/composite_page_renderer.rb) → [`FlowchartRuntime::QueryBuilder`](../app/services/flowchart_runtime/query_builder.rb) → module row JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C124.show` | [`Admin::Maintenance::SharedResourceMode`](../app/controllers/concerns/admin/maintenance/shared_resource_mode.rb) → [`Page`](../app/models/page.rb) → [`CompositePageRenderer`](../app/services/composite_page_renderer.rb) → [`FlowchartRuntime::QueryBuilder`](../app/services/flowchart_runtime/query_builder.rb) → module row JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0320 | `GET` | `/:customer_id/admin/maintenance/pages/:page_id/module_data/:module_id(.:format)` | `show` | `C124.show` |
| R0410 | `GET` | `/:customer_id/admin/maintenance/platform/pages/:page_id/module_data/:module_id(.:format)` | `show` | `C124.show` |

### Platform maintenance, configuration, billing, generators, docs and context

**144 route entries · 39 controllers · 125 controller/action pairs.**

#### C125 — `admin/maintenance/platform/customer_restorations`

Controller source: `app/controllers/admin/maintenance/platform/customer_restorations_controller.rb`; superclass `BaseRestorationsController`.
Family reference: **APP**. inherited BaseRestorationsController#update → [`Customer`](../app/models/customer.rb).restore / [`SoftDeletable`](../app/models/concerns/soft_deletable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C125.update` | inherited BaseRestorationsController#update → [`Customer`](../app/models/customer.rb).restore / [`SoftDeletable`](../app/models/concerns/soft_deletable.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0419 | `PATCH` | `/:customer_id/admin/maintenance/platform/customers/:id/restoration(.:format)` | `update` | `C125.update` |

#### C126 — `admin/maintenance/platform/customers`

Controller source: `app/controllers/admin/maintenance/platform/customers_controller.rb`; superclass `ApplicationController`; includes `SoftDeletableController`.
Family reference: **APP**. [`Customer`](../app/models/customer.rb); platform owner path gate.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C126.trash` | deleted customer list via [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) |
| `C126.empty_trash` | [`Customers::Purge`](../app/services/customers/purge.rb) → tenant table/version/blob metadata purge |
| `C126.index` | customer list/profile/forms |
| `C126.create` | permitted [`Customer`](../app/models/customer.rb) profile save |
| `C126.new` | customer list/profile/forms |
| `C126.edit` | customer list/profile/forms |
| `C126.show` | customer list/profile/forms |
| `C126.update` | permitted [`Customer`](../app/models/customer.rb) profile save |
| `C126.destroy` | customer soft deletion |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0420 | `GET` | `/:customer_id/admin/maintenance/platform/customers/trash(.:format)` | `trash` | `C126.trash` |
| R0421 | `DELETE` | `/:customer_id/admin/maintenance/platform/customers/empty_trash(.:format)` | `empty_trash` | `C126.empty_trash` |
| R0422 | `GET` | `/:customer_id/admin/maintenance/platform/customers(.:format)` | `index` | `C126.index` |
| R0423 | `POST` | `/:customer_id/admin/maintenance/platform/customers(.:format)` | `create` | `C126.create` |
| R0424 | `GET` | `/:customer_id/admin/maintenance/platform/customers/new(.:format)` | `new` | `C126.new` |
| R0425 | `GET` | `/:customer_id/admin/maintenance/platform/customers/:id/edit(.:format)` | `edit` | `C126.edit` |
| R0426 | `GET` | `/:customer_id/admin/maintenance/platform/customers/:id(.:format)` | `show` | `C126.show` |
| R0427 | `PATCH` | `/:customer_id/admin/maintenance/platform/customers/:id(.:format)` | `update` | `C126.update` |
| R0428 | `PUT` | `/:customer_id/admin/maintenance/platform/customers/:id(.:format)` | `update` | `C126.update` |
| R0429 | `DELETE` | `/:customer_id/admin/maintenance/platform/customers/:id(.:format)` | `destroy` | `C126.destroy` |

#### C127 — `admin/maintenance/platform/support_ticket_messages`

Controller source: `app/controllers/admin/maintenance/platform/support_ticket_messages_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::AddMessage`](../app/services/help/activities/add_message.rb) → platform reply/notification.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C127.create` | [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::AddMessage`](../app/services/help/activities/add_message.rb) → platform reply/notification |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0430 | `POST` | `/:customer_id/admin/maintenance/platform/support_tickets/:support_ticket_id/messages(.:format)` | `create` | `C127.create` |

#### C128 — `admin/maintenance/platform/support_ticket_resolutions`

Controller source: `app/controllers/admin/maintenance/platform/support_ticket_resolutions_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::Resolve`](../app/services/help/activities/resolve.rb) → ticket resolution.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C128.create` | [`SupportTicket`](../app/models/support_ticket.rb) → [`Help::Activities::Resolve`](../app/services/help/activities/resolve.rb) → ticket resolution |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0431 | `POST` | `/:customer_id/admin/maintenance/platform/support_tickets/:support_ticket_id/resolution(.:format)` | `create` | `C128.create` |

#### C129 — `admin/maintenance/platform/support_tickets`

Controller source: `app/controllers/admin/maintenance/platform/support_tickets_controller.rb`; superclass `ApplicationController`.
Family reference: **HELP**. cross-tenant [`SupportTicket`](../app/models/support_ticket.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C129.index` | [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → ticket list |
| `C129.show` | [`SupportTicketRead`](../app/models/support_ticket_read.rb).record! → thread template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0432 | `GET` | `/:customer_id/admin/maintenance/platform/support_tickets(.:format)` | `index` | `C129.index` |
| R0433 | `GET` | `/:customer_id/admin/maintenance/platform/support_tickets/:id(.:format)` | `show` | `C129.show` |

#### C130 — `admin/maintenance/platform/announcements`

Controller source: `app/controllers/admin/maintenance/platform/announcements_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`PlatformAnnouncement`](../app/models/platform_announcement.rb) / [`PlatformAnnouncements::TargetRules`](../app/services/platform_announcements/target_rules.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C130.audience_preview` | [`PlatformAnnouncements::TargetRules`](../app/services/platform_announcements/target_rules.rb) → matching customer count/sample |
| `C130.index` | announcement browse/audience detail/forms |
| `C130.create` | [`PlatformAnnouncements::Activities::Save`](../app/services/platform_announcements/activities/save.rb) → announcement/notification publication |
| `C130.new` | announcement browse/audience detail/forms |
| `C130.edit` | announcement browse/audience detail/forms |
| `C130.show` | announcement browse/audience detail/forms |
| `C130.update` | [`PlatformAnnouncements::Activities::Save`](../app/services/platform_announcements/activities/save.rb) → announcement/notification publication |
| `C130.destroy` | announcement destroy + [`Notifications::Stream`](../app/services/notifications/stream.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0434 | `POST` | `/:customer_id/admin/maintenance/platform/announcements/audience_preview(.:format)` | `audience_preview` | `C130.audience_preview` |
| R0435 | `GET` | `/:customer_id/admin/maintenance/platform/announcements(.:format)` | `index` | `C130.index` |
| R0436 | `POST` | `/:customer_id/admin/maintenance/platform/announcements(.:format)` | `create` | `C130.create` |
| R0437 | `GET` | `/:customer_id/admin/maintenance/platform/announcements/new(.:format)` | `new` | `C130.new` |
| R0438 | `GET` | `/:customer_id/admin/maintenance/platform/announcements/:id/edit(.:format)` | `edit` | `C130.edit` |
| R0439 | `GET` | `/:customer_id/admin/maintenance/platform/announcements/:id(.:format)` | `show` | `C130.show` |
| R0440 | `PATCH` | `/:customer_id/admin/maintenance/platform/announcements/:id(.:format)` | `update` | `C130.update` |
| R0441 | `PUT` | `/:customer_id/admin/maintenance/platform/announcements/:id(.:format)` | `update` | `C130.update` |
| R0442 | `DELETE` | `/:customer_id/admin/maintenance/platform/announcements/:id(.:format)` | `destroy` | `C130.destroy` |

#### C131 — `admin/maintenance/platform/module_settings`

Controller source: `app/controllers/admin/maintenance/platform/module_settings_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. [`FeatureModules::Module`](../app/models/feature_modules/module.rb) / [`ModuleModelDiscovery`](../app/services/module_model_discovery.rb) / [`Authentication::PlatformSettings`](../app/models/authentication/platform_settings.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C131.configuration` | module workspace/configuration/model metadata templates |
| `C131.developer` | module workspace/configuration/model metadata templates |
| `C131.index` | module workspace/configuration/model metadata templates |
| `C131.show` | module workspace/configuration/model metadata templates |
| `C131.update` | validated transaction → module status/defaults/model extensions + customer provisioning / platform signup / [`Emails::TemplateToken`](../app/models/emails/template_token.rb) attributes |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0443 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/:id/configuration(.:format)` | `configuration` | `C131.configuration` |
| R0444 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/:id/developer(.:format)` | `developer` | `C131.developer` |
| R0445 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings(.:format)` | `index` | `C131.index` |
| R0446 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/:id(.:format)` | `show` | `C131.show` |
| R0447 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/:id(.:format)` | `update` | `C131.update` |
| R0448 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/:id(.:format)` | `update` | `C131.update` |

#### C132 — `admin/maintenance/platform/emails/credentials`

Controller source: `app/controllers/admin/maintenance/platform/emails/credentials_controller.rb`; superclass `BaseCredentialsController`.
Family reference: **MAIL**. BaseCredentialsController → [`Emails::Credential`](../app/models/emails/credential.rb) / [`Email::Providers`](../app/services/email/providers.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C132.delivery` | [`Email::Activities::AssignDelivery`](../app/services/email/activities/assign_delivery.rb) → capability/provider assignment |
| `C132.index` | provider/mode credential list/forms |
| `C132.create` | [`Email::Activities::SaveCredential`](../app/services/email/activities/save_credential.rb) → encrypted credential/config save |
| `C132.new` | provider/mode credential list/forms |
| `C132.edit` | provider/mode credential list/forms |
| `C132.update` | [`Email::Activities::SaveCredential`](../app/services/email/activities/save_credential.rb) → encrypted credential/config save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0449 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials/delivery(.:format)` | `delivery` | `C132.delivery` |
| R0450 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials(.:format)` | `index` | `C132.index` |
| R0451 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials(.:format)` | `create` | `C132.create` |
| R0452 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials/new(.:format)` | `new` | `C132.new` |
| R0453 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials/:id/edit(.:format)` | `edit` | `C132.edit` |
| R0454 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials/:id(.:format)` | `update` | `C132.update` |
| R0455 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/email/credentials/:id(.:format)` | `update` | `C132.update` |

#### C133 — `admin/maintenance/platform/sms/credentials`

Controller source: `app/controllers/admin/maintenance/platform/sms/credentials_controller.rb`; superclass `BaseCredentialsController`; includes `::Sms::PlatformParameters`.
Family reference: **SMS**. BaseCredentialsController + [`Sms::PlatformParameters`](../app/controllers/concerns/sms/platform_parameters.rb) → [`Sms::Credential`](../app/models/sms/credential.rb) / [`Sms::Adapters`](../app/services/sms/adapters.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C133.delivery` | [`Sms::Activities::AssignDelivery`](../app/services/sms/activities/assign_delivery.rb) → SMS delivery assignment |
| `C133.index` | provider/mode credential list/forms |
| `C133.create` | [`Sms::PlatformCredentialSave`](../app/services/sms/platform_credential_save.rb) → credential validation/save |
| `C133.new` | provider/mode credential list/forms |
| `C133.edit` | provider/mode credential list/forms |
| `C133.update` | [`Sms::PlatformCredentialSave`](../app/services/sms/platform_credential_save.rb) → credential validation/save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0456 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials/delivery(.:format)` | `delivery` | `C133.delivery` |
| R0457 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials(.:format)` | `index` | `C133.index` |
| R0458 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials(.:format)` | `create` | `C133.create` |
| R0459 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials/new(.:format)` | `new` | `C133.new` |
| R0460 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials/:id/edit(.:format)` | `edit` | `C133.edit` |
| R0461 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials/:id(.:format)` | `update` | `C133.update` |
| R0462 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/sms/credentials/:id(.:format)` | `update` | `C133.update` |

#### C134 — `admin/maintenance/platform/sms/templates`

Controller source: `app/controllers/admin/maintenance/platform/sms/templates_controller.rb`; superclass `ApplicationController`; includes `Listable`, `::Sms::PlatformParameters`.
Family reference: **SMS**. [`Sms::Template`](../app/models/sms/template.rb) / [`Sms::PlatformParameters`](../app/controllers/concerns/sms/platform_parameters.rb) / [`Sms::RequestAttributes`](../app/services/sms/request_attributes.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C134.index` | provider template list/forms |
| `C134.create` | registered adapter parameters → [`Sms::Template`](../app/models/sms/template.rb) save |
| `C134.new` | provider template list/forms |
| `C134.edit` | provider template list/forms |
| `C134.update` | registered adapter parameters → [`Sms::Template`](../app/models/sms/template.rb) save |
| `C134.destroy` | template deletion/reference restriction |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0463 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates(.:format)` | `index` | `C134.index` |
| R0464 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates(.:format)` | `create` | `C134.create` |
| R0465 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates/new(.:format)` | `new` | `C134.new` |
| R0466 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates/:id/edit(.:format)` | `edit` | `C134.edit` |
| R0467 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates/:id(.:format)` | `update` | `C134.update` |
| R0468 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates/:id(.:format)` | `update` | `C134.update` |
| R0469 | `DELETE` | `/:customer_id/admin/maintenance/platform/module_settings/sms/templates/:id(.:format)` | `destroy` | `C134.destroy` |

#### C135 — `admin/maintenance/platform/captcha/settings`

Controller source: `app/controllers/admin/maintenance/platform/captcha/settings_controller.rb`; superclass `ApplicationController`.
Family reference: **CAPTCHA**. [`Captcha::Providers`](../app/services/captcha/providers.rb) / [`Captcha::ProviderSettings`](../app/models/captcha/provider_settings.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C135.test_connection` | [`Captcha::Activities::TestConnection`](../app/services/captcha/activities/test_connection.rb) |
| `C135.edit` | masked provider settings/templates |
| `C135.show` | masked provider settings/templates |
| `C135.update` | [`Captcha::Activities::UpdateProviderSettings`](../app/services/captcha/activities/update_provider_settings.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0470 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/settings/test_connection(.:format)` | `test_connection` | `C135.test_connection` |
| R0471 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/settings/edit(.:format)` | `edit` | `C135.edit` |
| R0472 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/settings(.:format)` | `show` | `C135.show` |
| R0473 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/settings(.:format)` | `update` | `C135.update` |
| R0474 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/settings(.:format)` | `update` | `C135.update` |

#### C136 — `admin/maintenance/platform/captcha/surfaces`

Controller source: `app/controllers/admin/maintenance/platform/captcha/surfaces_controller.rb`; superclass `ThrottlesController`.
Family reference: **CAPTCHA**. ThrottlesController → [`Captcha::SurfaceCatalog`](../app/services/captcha/surface_catalog.rb) → [`Captcha::Activities::UpdateUrlThrottle`](../app/services/captcha/activities/update_url_throttle.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C136.update` | ThrottlesController → [`Captcha::SurfaceCatalog`](../app/services/captcha/surface_catalog.rb) → [`Captcha::Activities::UpdateUrlThrottle`](../app/services/captcha/activities/update_url_throttle.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0475 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/surfaces(.:format)` | `update` | `C136.update` |
| R0476 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/surfaces(.:format)` | `update` | `C136.update` |

#### C137 — `admin/maintenance/platform/captcha/pages`

Controller source: `app/controllers/admin/maintenance/platform/captcha/pages_controller.rb`; superclass `ThrottlesController`.
Family reference: **CAPTCHA**. ThrottlesController → [`Page`](../app/models/page.rb) / [`Captcha::ThrottleRegistry`](../app/services/captcha/throttle_registry.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C137.index` | captcha surfaces/public pages/status → template |
| `C137.update` | [`Captcha::Activities::UpdateUrlThrottle`](../app/services/captcha/activities/update_url_throttle.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0477 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/pages(.:format)` | `index` | `C137.index` |
| R0478 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/pages/:id(.:format)` | `update` | `C137.update` |
| R0479 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/captcha/pages/:id(.:format)` | `update` | `C137.update` |

#### C138 — `admin/maintenance/platform/ai_assistant/settings`

Controller source: `app/controllers/admin/maintenance/platform/ai_assistant/settings_controller.rb`; superclass `ApplicationController`.
Family reference: **AI**. [`AiAssistant::Providers`](../app/services/ai_assistant/providers.rb) / [`AiAssistant::ProviderSettings`](../app/models/ai_assistant/provider_settings.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C138.test_connection` | [`AiAssistant::TestConnectionJob`](../app/jobs/ai_assistant/test_connection_job.rb) → provider test/status broadcast |
| `C138.edit` | masked provider settings/templates |
| `C138.show` | masked provider settings/templates |
| `C138.update` | [`AiAssistant::Activities::UpdateProviderSettings`](../app/services/ai_assistant/activities/update_provider_settings.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0480 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings/test_connection(.:format)` | `test_connection` | `C138.test_connection` |
| R0481 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings/edit(.:format)` | `edit` | `C138.edit` |
| R0482 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings(.:format)` | `show` | `C138.show` |
| R0483 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings(.:format)` | `update` | `C138.update` |
| R0484 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings(.:format)` | `update` | `C138.update` |

#### C139 — `admin/maintenance/platform/payments/platform_gateways`

Controller source: `app/controllers/admin/maintenance/platform/payments/platform_gateways_controller.rb`; superclass `ApplicationController`.
Family reference: **PAY**. [`Payments::Gateways`](../app/services/payments/gateways.rb) / [`Payments::PlatformGateway`](../app/models/payments/platform_gateway.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C139.index` | global gateway catalog/status template |
| `C139.update` | global gateway save → tenant [`Payments::MerchantAccount`](../app/models/payments/merchant_account.rb) disablement or [`FeatureModules::Payment::Provisioner`](../app/services/feature_modules/payment/provisioner.rb) backfill |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0485 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/payment/gateways(.:format)` | `index` | `C139.index` |
| R0486 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/payment/gateways/:provider(.:format)` | `update` | `C139.update` |
| R0487 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/payment/gateways/:provider(.:format)` | `update` | `C139.update` |

#### C140 — `admin/maintenance/platform/payments/webhook_events`

Controller source: `app/controllers/admin/maintenance/platform/payments/webhook_events_controller.rb`; superclass `ApplicationController`.
Family reference: **PAY**. cross-tenant [`Payments::WebhookEvent`](../app/models/payments/webhook_event.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C140.redrive` | [`Payments::ProcessWebhookEventJob`](../app/jobs/payments/process_webhook_event_job.rb) enqueue |
| `C140.index` | webhook-event ledger template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0488 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/payment/webhook_events/:id/redrive(.:format)` | `redrive` | `C140.redrive` |
| R0489 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/payment/webhook_events(.:format)` | `index` | `C140.index` |

#### C141 — `admin/maintenance/platform/website/skeletons`

Controller source: `app/controllers/admin/maintenance/platform/website/skeletons_controller.rb`; superclass `ApplicationController`; includes `Websites::CatalogPreview`.
Family reference: **WEB**. [`Websites::Catalog`](../app/services/websites/catalog.rb) / [`WebsiteSkeleton`](../app/models/website_skeleton.rb) + [`Websites::CatalogPreview`](../app/controllers/concerns/websites/catalog_preview.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C141.show` | skeleton catalog sync/forms |
| `C141.edit` | skeleton catalog sync/forms |
| `C141.preview` | catalog preview → public website template |
| `C141.update` | [`Websites::Activities::SaveSkeleton`](../app/services/websites/activities/save_skeleton.rb) → skeleton save/catalog refresh |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0490 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons(.:format)` | `show` | `C141.show` |
| R0491 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons/:key/edit(.:format)` | `edit` | `C141.edit` |
| R0492 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons/:key/preview(.:format)` | `preview` | `C141.preview` |
| R0493 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons/:key(.:format)` | `update` | `C141.update` |

#### C142 — `admin/maintenance/platform/website/layouts`

Controller source: `app/controllers/admin/maintenance/platform/website/layouts_controller.rb`; superclass `ApplicationController`; includes `Websites::CatalogPreview`.
Family reference: **WEB**. [`Websites::Catalog`](../app/services/websites/catalog.rb) / [`WebsiteLayout`](../app/models/website_layout.rb) + [`Websites::CatalogPreview`](../app/controllers/concerns/websites/catalog_preview.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C142.preview` | layout preview → public website template |
| `C142.index` | layout catalog sync/forms |
| `C142.create` | [`Websites::Activities::SaveLayout`](../app/services/websites/activities/save_layout.rb) → layout save/catalog refresh |
| `C142.new` | layout catalog sync/forms |
| `C142.edit` | layout catalog sync/forms |
| `C142.update` | [`Websites::Activities::SaveLayout`](../app/services/websites/activities/save_layout.rb) → layout save/catalog refresh |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0494 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts/:key/preview(.:format)` | `preview` | `C142.preview` |
| R0495 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts(.:format)` | `index` | `C142.index` |
| R0496 | `POST` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts(.:format)` | `create` | `C142.create` |
| R0497 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts/new(.:format)` | `new` | `C142.new` |
| R0498 | `GET` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts/:key/edit(.:format)` | `edit` | `C142.edit` |
| R0499 | `PATCH` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts/:key(.:format)` | `update` | `C142.update` |
| R0500 | `PUT` | `/:customer_id/admin/maintenance/platform/module_settings/website/layouts/:key(.:format)` | `update` | `C142.update` |

#### C143 — `admin/maintenance/platform/billing/plans`

Controller source: `app/controllers/admin/maintenance/platform/billing/plans_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::Plan`](../app/models/billing/plan.rb) / [`Billing::CountableItem`](../app/models/billing/countable_item.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C143.index` | plan catalog/detail |
| `C143.create` | [`Billing::Catalog::SavePlan`](../app/services/billing/catalog/save_plan.rb) → plan/limits |
| `C143.new` | [`Billing::Contracts::Plan`](../app/services/billing/contracts/plan.rb) → forms |
| `C143.edit` | [`Billing::Contracts::Plan`](../app/services/billing/contracts/plan.rb) → forms |
| `C143.show` | plan catalog/detail |
| `C143.update` | [`Billing::Catalog::SavePlan`](../app/services/billing/catalog/save_plan.rb) → plan/limits |
| `C143.destroy` | [`Billing::Catalog::ArchivePlan`](../app/services/billing/catalog/archive_plan.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0501 | `GET` | `/:customer_id/admin/maintenance/platform/billing/plans(.:format)` | `index` | `C143.index` |
| R0502 | `POST` | `/:customer_id/admin/maintenance/platform/billing/plans(.:format)` | `create` | `C143.create` |
| R0503 | `GET` | `/:customer_id/admin/maintenance/platform/billing/plans/new(.:format)` | `new` | `C143.new` |
| R0504 | `GET` | `/:customer_id/admin/maintenance/platform/billing/plans/:id/edit(.:format)` | `edit` | `C143.edit` |
| R0505 | `GET` | `/:customer_id/admin/maintenance/platform/billing/plans/:id(.:format)` | `show` | `C143.show` |
| R0506 | `PATCH` | `/:customer_id/admin/maintenance/platform/billing/plans/:id(.:format)` | `update` | `C143.update` |
| R0507 | `PUT` | `/:customer_id/admin/maintenance/platform/billing/plans/:id(.:format)` | `update` | `C143.update` |
| R0508 | `DELETE` | `/:customer_id/admin/maintenance/platform/billing/plans/:id(.:format)` | `destroy` | `C143.destroy` |

#### C144 — `admin/maintenance/platform/billing/countable_items`

Controller source: `app/controllers/admin/maintenance/platform/billing/countable_items_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::CountableItem`](../app/models/billing/countable_item.rb) / [`Billing::Countable::Registry`](../app/services/billing/countable/registry.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C144.show` | countable-item catalog template |
| `C144.update` | [`Billing::Catalog::UpdateCountableItems`](../app/services/billing/catalog/update_countable_items.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0509 | `GET` | `/:customer_id/admin/maintenance/platform/billing/countable_items(.:format)` | `show` | `C144.show` |
| R0510 | `PATCH` | `/:customer_id/admin/maintenance/platform/billing/countable_items(.:format)` | `update` | `C144.update` |
| R0511 | `PUT` | `/:customer_id/admin/maintenance/platform/billing/countable_items(.:format)` | `update` | `C144.update` |

#### C145 — `admin/maintenance/platform/billing/coupons`

Controller source: `app/controllers/admin/maintenance/platform/billing/coupons_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::Coupon`](../app/models/billing/coupon.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C145.index` | coupon catalog/detail |
| `C145.create` | [`Billing::Catalog::SaveCoupon`](../app/services/billing/catalog/save_coupon.rb) |
| `C145.new` | [`Billing::Contracts::Coupon`](../app/services/billing/contracts/coupon.rb) → forms |
| `C145.edit` | [`Billing::Contracts::Coupon`](../app/services/billing/contracts/coupon.rb) → forms |
| `C145.show` | coupon catalog/detail |
| `C145.update` | [`Billing::Catalog::SaveCoupon`](../app/services/billing/catalog/save_coupon.rb) |
| `C145.destroy` | [`Billing::Catalog::ArchiveCoupon`](../app/services/billing/catalog/archive_coupon.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0512 | `GET` | `/:customer_id/admin/maintenance/platform/billing/coupons(.:format)` | `index` | `C145.index` |
| R0513 | `POST` | `/:customer_id/admin/maintenance/platform/billing/coupons(.:format)` | `create` | `C145.create` |
| R0514 | `GET` | `/:customer_id/admin/maintenance/platform/billing/coupons/new(.:format)` | `new` | `C145.new` |
| R0515 | `GET` | `/:customer_id/admin/maintenance/platform/billing/coupons/:id/edit(.:format)` | `edit` | `C145.edit` |
| R0516 | `GET` | `/:customer_id/admin/maintenance/platform/billing/coupons/:id(.:format)` | `show` | `C145.show` |
| R0517 | `PATCH` | `/:customer_id/admin/maintenance/platform/billing/coupons/:id(.:format)` | `update` | `C145.update` |
| R0518 | `PUT` | `/:customer_id/admin/maintenance/platform/billing/coupons/:id(.:format)` | `update` | `C145.update` |
| R0519 | `DELETE` | `/:customer_id/admin/maintenance/platform/billing/coupons/:id(.:format)` | `destroy` | `C145.destroy` |

#### C146 — `admin/maintenance/platform/billing/cancellations`

Controller source: `app/controllers/admin/maintenance/platform/billing/cancellations_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. cross-tenant [`Billing::Subscription`](../app/models/billing/subscription.rb) → [`Billing::Activities::CancelSubscription`](../app/services/billing/activities/cancel_subscription.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C146.create` | cross-tenant [`Billing::Subscription`](../app/models/billing/subscription.rb) → [`Billing::Activities::CancelSubscription`](../app/services/billing/activities/cancel_subscription.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0520 | `POST` | `/:customer_id/admin/maintenance/platform/billing/subscriptions/:subscription_id/cancellation(.:format)` | `create` | `C146.create` |

#### C147 — `admin/maintenance/platform/billing/subscriptions`

Controller source: `app/controllers/admin/maintenance/platform/billing/subscriptions_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. cross-tenant [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) / [`Billing::Entitlements`](../app/services/billing/entitlements.rb) → subscription list/detail; platform billing BaseController invoice collections.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C147.index` | cross-tenant [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) / [`Billing::Entitlements`](../app/services/billing/entitlements.rb) → subscription list/detail; platform billing BaseController invoice collections |
| `C147.show` | cross-tenant [`Billing::Subscription`](../app/models/billing/subscription.rb) / [`Billing::PlanChange`](../app/models/billing/plan_change.rb) / [`Billing::Entitlements`](../app/services/billing/entitlements.rb) → subscription list/detail; platform billing BaseController invoice collections |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0521 | `GET` | `/:customer_id/admin/maintenance/platform/billing/subscriptions(.:format)` | `index` | `C147.index` |
| R0522 | `GET` | `/:customer_id/admin/maintenance/platform/billing/subscriptions/:id(.:format)` | `show` | `C147.show` |

#### C148 — `admin/maintenance/platform/billing/invoices`

Controller source: `app/controllers/admin/maintenance/platform/billing/invoices_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. cross-tenant [`Billing::Invoice`](../app/models/billing/invoice.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C148.mark_paid` | [`Billing::Activities::MarkInvoicePaid`](../app/services/billing/activities/mark_invoice_paid.rb) |
| `C148.void` | [`Billing::Activities::VoidInvoice`](../app/services/billing/activities/void_invoice.rb) |
| `C148.retry` | [`Billing::Activities::AuthorizeInvoiceCollection`](../app/services/billing/activities/authorize_invoice_collection.rb) → [`Billing::Activities::CollectInvoice`](../app/services/billing/activities/collect_invoice.rb) → collector |
| `C148.index` | invoice list/detail and history |
| `C148.show` | invoice list/detail and history |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0523 | `POST` | `/:customer_id/admin/maintenance/platform/billing/invoices/:id/mark_paid(.:format)` | `mark_paid` | `C148.mark_paid` |
| R0524 | `POST` | `/:customer_id/admin/maintenance/platform/billing/invoices/:id/void(.:format)` | `void` | `C148.void` |
| R0525 | `POST` | `/:customer_id/admin/maintenance/platform/billing/invoices/:id/retry(.:format)` | `retry` | `C148.retry` |
| R0526 | `GET` | `/:customer_id/admin/maintenance/platform/billing/invoices(.:format)` | `index` | `C148.index` |
| R0527 | `GET` | `/:customer_id/admin/maintenance/platform/billing/invoices/:id(.:format)` | `show` | `C148.show` |

#### C149 — `admin/maintenance/platform/billing/settings`

Controller source: `app/controllers/admin/maintenance/platform/billing/settings_controller.rb`; superclass `BaseController`.
Family reference: **BILL**. [`Billing::Settings`](../app/models/billing/settings.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C149.edit` | [`Billing::Contracts::Settings`](../app/services/billing/contracts/settings.rb) → form |
| `C149.show` | settings template |
| `C149.update` | [`Billing::Activities::UpdateSettings`](../app/services/billing/activities/update_settings.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0528 | `GET` | `/:customer_id/admin/maintenance/platform/billing/settings/edit(.:format)` | `edit` | `C149.edit` |
| R0529 | `GET` | `/:customer_id/admin/maintenance/platform/billing/settings(.:format)` | `show` | `C149.show` |
| R0530 | `PATCH` | `/:customer_id/admin/maintenance/platform/billing/settings(.:format)` | `update` | `C149.update` |
| R0531 | `PUT` | `/:customer_id/admin/maintenance/platform/billing/settings(.:format)` | `update` | `C149.update` |

#### C150 — `admin/maintenance/platform/industry_template_assignments`

Controller source: `app/controllers/admin/maintenance/platform/industry_template_assignments_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`IndustryTemplateMapping`](../app/models/industry_template_mapping.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C150.create` | create mapping for industry/template |
| `C150.destroy` | delete matching mapping |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0532 | `POST` | `/:customer_id/admin/maintenance/platform/industry_templates/:industry_template_id/template_assignments(.:format)` | `create` | `C150.create` |
| R0533 | `DELETE` | `/:customer_id/admin/maintenance/platform/industry_templates/:industry_template_id/template_assignments/:id(.:format)` | `destroy` | `C150.destroy` |

#### C151 — `admin/maintenance/platform/industry_template_cards`

Controller source: `app/controllers/admin/maintenance/platform/industry_template_cards_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`IndustryTemplateMapping`](../app/models/industry_template_mapping.rb) / [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) → industry picker cards.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C151.show` | [`IndustryTemplateMapping`](../app/models/industry_template_mapping.rb) / [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) → industry picker cards |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0534 | `GET` | `/:customer_id/admin/maintenance/platform/industry_templates/:industry_template_id/template_cards(.:format)` | `show` | `C151.show` |

#### C152 — `admin/maintenance/platform/industry_template_default_seeds`

Controller source: `app/controllers/admin/maintenance/platform/industry_template_default_seeds_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`IndustryTemplateMappingSeeder`](../app/services/industry_template_mapping_seeder.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C152.destroy` | clear default mappings |
| `C152.create` | seed default mappings |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0535 | `DELETE` | `/:customer_id/admin/maintenance/platform/industry_templates/default_seed(.:format)` | `destroy` | `C152.destroy` |
| R0536 | `POST` | `/:customer_id/admin/maintenance/platform/industry_templates/default_seed(.:format)` | `create` | `C152.create` |

#### C153 — `admin/maintenance/platform/industry_template_new_template_seeds`

Controller source: `app/controllers/admin/maintenance/platform/industry_template_new_template_seeds_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`IndustryTemplateMappingSeeder`](../app/services/industry_template_mapping_seeder.rb) → seed new template across industries.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C153.create` | [`IndustryTemplateMappingSeeder`](../app/services/industry_template_mapping_seeder.rb) → seed new template across industries |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0537 | `POST` | `/:customer_id/admin/maintenance/platform/industry_templates/new_template_seed(.:format)` | `create` | `C153.create` |

#### C154 — `admin/maintenance/platform/industry_templates`

Controller source: `app/controllers/admin/maintenance/platform/industry_templates_controller.rb`; superclass `ApplicationController`.
Family reference: **PAGE**. [`IndustryTemplateMapping`](../app/models/industry_template_mapping.rb) / [`PageLayoutTemplates`](../app/services/page_layout_templates.rb) + [`Customer`](../app/models/customer.rb) industry groups.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C154.index` | industry mappings/template assignment views |
| `C154.edit` | industry mappings/template assignment views |
| `C154.show` | industry mappings/template assignment views |
| `C154.update` | transactional mapping replace/save |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0538 | `GET` | `/:customer_id/admin/maintenance/platform/industry_templates(.:format)` | `index` | `C154.index` |
| R0539 | `GET` | `/:customer_id/admin/maintenance/platform/industry_templates/:id/edit(.:format)` | `edit` | `C154.edit` |
| R0540 | `GET` | `/:customer_id/admin/maintenance/platform/industry_templates/:id(.:format)` | `show` | `C154.show` |
| R0541 | `PATCH` | `/:customer_id/admin/maintenance/platform/industry_templates/:id(.:format)` | `update` | `C154.update` |
| R0542 | `PUT` | `/:customer_id/admin/maintenance/platform/industry_templates/:id(.:format)` | `update` | `C154.update` |

#### C155 — `admin/maintenance/platform/code_generators/validations`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/validations_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::GeneratorValidator`](../app/services/code_generators/generator_validator.rb) → validation JSON.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C155.create` | [`CodeGenerators::GeneratorValidator`](../app/services/code_generators/generator_validator.rb) → validation JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0543 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators/:code_generator_slug/validation(.:format)` | `create` | `C155.create` |

#### C156 — `admin/maintenance/platform/code_generators/previews`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/previews_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) → registered generator instance preview → preview template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C156.show` | [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) → registered generator instance preview → preview template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0544 | `GET` | `/:customer_id/admin/maintenance/platform/code_generators/:code_generator_slug/preview(.:format)` | `show` | `C156.show` |

#### C157 — `admin/maintenance/platform/code_generators/test_runs`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/test_runs_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) → [`CodeGenerators::TestRunner`](../app/services/code_generators/test_runner.rb) → [`CodeGenerators::CodeIntrospector`](../app/services/code_generators/code_introspector.rb); highlights generated source (not emitted-step execution).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C157.create` | [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) → [`CodeGenerators::TestRunner`](../app/services/code_generators/test_runner.rb) → [`CodeGenerators::CodeIntrospector`](../app/services/code_generators/code_introspector.rb); highlights generated source (not emitted-step execution) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0545 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators/:code_generator_slug/test_run(.:format)` | `create` | `C157.create` |

#### C158 — `admin/maintenance/platform/code_generators/source_previews`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/source_previews_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::SourceAssembler`](../app/services/code_generators/source_assembler.rb) → Rouge source highlighting.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C158.create` | [`CodeGenerators::SourceAssembler`](../app/services/code_generators/source_assembler.rb) → Rouge source highlighting |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0546 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators/source_preview(.:format)` | `create` | `C158.create` |

#### C159 — `admin/maintenance/platform/code_generators`

Controller source: `app/controllers/admin/maintenance/platform/code_generators_controller.rb`; superclass `ApplicationController`.
Family reference: **GEN**. [`CodeGenerators::PathIdentity`](../app/services/code_generators/path_identity.rb) / [`CodeGenerators::GeneratorRegistry`](../app/services/code_generators/generator_registry.rb); registered source file.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C159.index` | [`CodeGenerators::IndexPresenter`](../app/services/code_generators/index_presenter.rb) → generator catalog |
| `C159.create` | [`CodeGenerators::SourceAssembler`](../app/services/code_generators/source_assembler.rb) / [`CodeGenerators::GeneratorValidator`](../app/services/code_generators/generator_validator.rb) → file publication → autoloader reload / registry load |
| `C159.new` | [`CodeGenerators::FormDataExtractor`](../app/services/code_generators/form_data_extractor.rb) → generator forms |
| `C159.edit` | [`CodeGenerators::FormDataExtractor`](../app/services/code_generators/form_data_extractor.rb) → generator forms |
| `C159.show` | source read + generator introspection → detail |
| `C159.update` | [`CodeGenerators::SourceAssembler`](../app/services/code_generators/source_assembler.rb) / [`CodeGenerators::GeneratorValidator`](../app/services/code_generators/generator_validator.rb) → file publication → autoloader reload / registry load |
| `C159.destroy` | registered source deletion → registry reload |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0547 | `GET` | `/:customer_id/admin/maintenance/platform/code_generators(.:format)` | `index` | `C159.index` |
| R0548 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators(.:format)` | `create` | `C159.create` |
| R0549 | `GET` | `/:customer_id/admin/maintenance/platform/code_generators/new(.:format)` | `new` | `C159.new` |
| R0550 | `GET` | `/:customer_id/admin/maintenance/platform/code_generators/:slug/edit(.:format)` | `edit` | `C159.edit` |
| R0551 | `GET` | `/:customer_id/admin/maintenance/platform/code_generators/:slug(.:format)` | `show` | `C159.show` |
| R0552 | `PATCH` | `/:customer_id/admin/maintenance/platform/code_generators/:slug(.:format)` | `update` | `C159.update` |
| R0553 | `PUT` | `/:customer_id/admin/maintenance/platform/code_generators/:slug(.:format)` | `update` | `C159.update` |
| R0554 | `DELETE` | `/:customer_id/admin/maintenance/platform/code_generators/:slug(.:format)` | `destroy` | `C159.destroy` |

#### C160 — `admin/maintenance/platform/code_generators/io_params`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/io_params_controller.rb`; superclass `ApplicationController`; includes `GeneratorIoIntrospection`.
Family reference: **GEN**. [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) step-action metadata.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C160.show` | [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) step-action metadata |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0555 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators/:generator_action/io_params(.:format)` | `show` | `C160.show` |

#### C161 — `admin/maintenance/platform/code_generators/element_type_io_params`

Controller source: `app/controllers/admin/maintenance/platform/code_generators/element_type_io_params_controller.rb`; superclass `ApplicationController`; includes `GeneratorIoIntrospection`.
Family reference: **GEN**. [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) element-type metadata.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C161.show` | [`GeneratorIoIntrospection`](../app/controllers/concerns/generator_io_introspection.rb) → [`CodeGenerators::IoExtractor`](../app/services/code_generators/io_extractor.rb) element-type metadata |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0556 | `POST` | `/:customer_id/admin/maintenance/platform/code_generators/element_types/:element_type/io_params(.:format)` | `show` | `C161.show` |

#### C162 — `admin/maintenance/platform/developer_docs`

Controller source: `app/controllers/admin/maintenance/platform/developer_docs_controller.rb`; superclass `ApplicationController`.
Family reference: **DOC**. [`DeveloperDocs::Catalog`](../app/services/developer_docs/catalog.rb) → [`DeveloperDocs::Repository`](../app/services/developer_docs/repository.rb) → [`DeveloperDocs::Renderer`](../app/services/developer_docs/renderer.rb) → sanitized Kramdown HTML/template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C162.index` | [`DeveloperDocs::Catalog`](../app/services/developer_docs/catalog.rb) → [`DeveloperDocs::Repository`](../app/services/developer_docs/repository.rb) → [`DeveloperDocs::Renderer`](../app/services/developer_docs/renderer.rb) → sanitized Kramdown HTML/template |
| `C162.show` | [`DeveloperDocs::Catalog`](../app/services/developer_docs/catalog.rb) → [`DeveloperDocs::Repository`](../app/services/developer_docs/repository.rb) → [`DeveloperDocs::Renderer`](../app/services/developer_docs/renderer.rb) → sanitized Kramdown HTML/template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0557 | `GET` | `/:customer_id/admin/maintenance/platform/developer_docs(.:format)` | `index` | `C162.index` |
| R0558 | `GET` | `/:customer_id/admin/maintenance/platform/developer_docs/:slug(.:format)` | `show` | `C162.show` |

#### C163 — `admin/maintenance/platform/customer_contexts`

Controller source: `app/controllers/admin/maintenance/platform/customer_contexts_controller.rb`; superclass `ApplicationController`.
Family reference: **APP**. platform [`Customer`](../app/models/customer.rb) context.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C163.update` | target customer lookup → URL-derived owner-context redirect |
| `C163.destroy` | clear_platform_owner_context → own-customer redirect |
| `C163.search` | customer search → JSON |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0559 | `PATCH` | `/:customer_id/admin/maintenance/platform/customer_context(.:format)` | `update` | `C163.update` |
| R0560 | `PUT` | `/:customer_id/admin/maintenance/platform/customer_context(.:format)` | `update` | `C163.update` |
| R0561 | `DELETE` | `/:customer_id/admin/maintenance/platform/customer_context(.:format)` | `destroy` | `C163.destroy` |
| R0562 | `GET` | `/:customer_id/admin/maintenance/platform/customer_context/search(.:format)` | `search` | `C163.search` |

### Admin module records and execution

**136 route entries · 39 controllers · 120 controller/action pairs.**

#### C164 — `admin/modules/authentication/users`

Controller source: `app/controllers/admin/modules/authentication/users_controller.rb`; superclass `ApplicationController`; includes `::Authentication::OwnerAccountProtectable`.
Family reference: **AUTH**. [`Authentication::OwnerAccountProtectable`](../app/controllers/concerns/authentication/owner_account_protectable.rb) → [`Authentication::User`](../app/models/authentication/user.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C164.trash` | [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → active/deleted user list |
| `C164.restore` | user restore |
| `C164.index` | [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → active/deleted user list |
| `C164.create` | [`Billing::Quota::Guard`](../app/services/billing/quota/guard.rb) → user save + [`UserRoles::Operation::Assign`](../app/concepts/user_roles/operation/assign.rb) |
| `C164.new` | user form |
| `C164.edit` | user form |
| `C164.show` | [`Authentication::UserDomainProfiles`](../app/services/authentication/user_domain_profiles.rb) → user/person profile detail |
| `C164.update` | [`Authentication::PasswordVerification`](../app/services/authentication/password_verification.rb) when self-edit → user save / [`UserRoles::Operation::Assign`](../app/concepts/user_roles/operation/assign.rb) / [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) |
| `C164.destroy` | soft-delete user → credential lifecycle |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0563 | `GET` | `/:customer_id/admin/modules/authentication/users/trash(.:format)` | `trash` | `C164.trash` |
| R0564 | `PATCH` | `/:customer_id/admin/modules/authentication/users/:id/restore(.:format)` | `restore` | `C164.restore` |
| R0570 | `GET` | `/:customer_id/admin/modules/authentication/users(.:format)` | `index` | `C164.index` |
| R0571 | `POST` | `/:customer_id/admin/modules/authentication/users(.:format)` | `create` | `C164.create` |
| R0572 | `GET` | `/:customer_id/admin/modules/authentication/users/new(.:format)` | `new` | `C164.new` |
| R0573 | `GET` | `/:customer_id/admin/modules/authentication/users/:id/edit(.:format)` | `edit` | `C164.edit` |
| R0574 | `GET` | `/:customer_id/admin/modules/authentication/users/:id(.:format)` | `show` | `C164.show` |
| R0575 | `PATCH` | `/:customer_id/admin/modules/authentication/users/:id(.:format)` | `update` | `C164.update` |
| R0576 | `PUT` | `/:customer_id/admin/modules/authentication/users/:id(.:format)` | `update` | `C164.update` |
| R0577 | `DELETE` | `/:customer_id/admin/modules/authentication/users/:id(.:format)` | `destroy` | `C164.destroy` |

#### C165 — `admin/modules/authentication/user_activations`

Controller source: `app/controllers/admin/modules/authentication/user_activations_controller.rb`; superclass `ApplicationController`; includes `::Authentication::OwnerAccountProtectable`.
Family reference: **AUTH**. [`Authentication::OwnerAccountProtectable`](../app/controllers/concerns/authentication/owner_account_protectable.rb) → [`Authentication::User`](../app/models/authentication/user.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C165.destroy` | deactivate user → credential revocation |
| `C165.create` | activate user |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0565 | `DELETE` | `/:customer_id/admin/modules/authentication/users/:user_id/activation(.:format)` | `destroy` | `C165.destroy` |
| R0566 | `POST` | `/:customer_id/admin/modules/authentication/users/:user_id/activation(.:format)` | `create` | `C165.create` |

#### C166 — `admin/modules/authentication/user_mfa_resets`

Controller source: `app/controllers/admin/modules/authentication/user_mfa_resets_controller.rb`; superclass `ApplicationController`; includes `::Authentication::OwnerAccountProtectable`.
Family reference: **AUTH**. [`Authentication::OwnerAccountProtectable`](../app/controllers/concerns/authentication/owner_account_protectable.rb) → [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → [`Authentication::User`](../app/models/authentication/user.rb).disable_mfa!.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C166.create` | [`Authentication::OwnerAccountProtectable`](../app/controllers/concerns/authentication/owner_account_protectable.rb) → [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) → [`Authentication::User`](../app/models/authentication/user.rb).disable_mfa! |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0567 | `POST` | `/:customer_id/admin/modules/authentication/users/:user_id/mfa_reset(.:format)` | `create` | `C166.create` |

#### C167 — `admin/modules/authentication/user_trusted_devices`

Controller source: `app/controllers/admin/modules/authentication/user_trusted_devices_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. tenant [`Authentication::User`](../app/models/authentication/user.rb) → [`Authentication::TrustedDevice`](../app/models/authentication/trusted_device.rb) association → destroy.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C167.destroy` | tenant [`Authentication::User`](../app/models/authentication/user.rb) → [`Authentication::TrustedDevice`](../app/models/authentication/trusted_device.rb) association → destroy |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0568 | `DELETE` | `/:customer_id/admin/modules/authentication/users/:user_id/trusted_devices/:id(.:format)` | `destroy` | `C167.destroy` |

#### C168 — `admin/modules/authentication/user_profiles`

Controller source: `app/controllers/admin/modules/authentication/user_profiles_controller.rb`; superclass `ApplicationController`.
Family reference: **ENTRY**. [`Authentication::User`](../app/models/authentication/user.rb) / [`EntityDomains::Catalog`](../app/services/entity_domains/catalog.rb) → [`People::Activities::CreateLinkedEntry`](../app/services/people/activities/create_linked_entry.rb) → [`Authentication::UserDomainProfiles`](../app/services/authentication/user_domain_profiles.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C168.create` | [`Authentication::User`](../app/models/authentication/user.rb) / [`EntityDomains::Catalog`](../app/services/entity_domains/catalog.rb) → [`People::Activities::CreateLinkedEntry`](../app/services/people/activities/create_linked_entry.rb) → [`Authentication::UserDomainProfiles`](../app/services/authentication/user_domain_profiles.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0569 | `POST` | `/:customer_id/admin/modules/authentication/users/:user_id/profiles(.:format)` | `create` | `C168.create` |

#### C169 — `admin/modules/authentication/events`

Controller source: `app/controllers/admin/modules/authentication/events_controller.rb`; superclass `ApplicationController`.
Family reference: **AUTH**. [`Authentication::Event`](../app/models/authentication/event.rb) → filters / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → audit-event list.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C169.index` | [`Authentication::Event`](../app/models/authentication/event.rb) → filters / [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → audit-event list |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0578 | `GET` | `/:customer_id/admin/modules/authentication/events(.:format)` | `index` | `C169.index` |

#### C170 — `admin/modules/emails/dashboard`

Controller source: `app/controllers/admin/modules/emails/dashboard_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::Analytics::DateRange`](../app/services/emails/analytics/date_range.rb) → [`Emails::DashboardStats`](../app/services/emails/dashboard_stats.rb) / [`Emails::Analytics::Report`](../app/services/emails/analytics/report.rb); CSV → [`Emails::Analytics::ExportCsv`](../app/services/emails/analytics/export_csv.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C170.show` | [`Emails::Analytics::DateRange`](../app/services/emails/analytics/date_range.rb) → [`Emails::DashboardStats`](../app/services/emails/dashboard_stats.rb) / [`Emails::Analytics::Report`](../app/services/emails/analytics/report.rb); CSV → [`Emails::Analytics::ExportCsv`](../app/services/emails/analytics/export_csv.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0579 | `GET` | `/:customer_id/admin/modules/emails/dashboard(.:format)` | `show` | `C170.show` |

#### C171 — `admin/modules/emails/health`

Controller source: `app/controllers/admin/modules/emails/health_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::Analytics::DateRange`](../app/services/emails/analytics/date_range.rb) → [`Emails::Analytics::Health`](../app/services/emails/analytics/health.rb) → health template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C171.index` | [`Emails::Analytics::DateRange`](../app/services/emails/analytics/date_range.rb) → [`Emails::Analytics::Health`](../app/services/emails/analytics/health.rb) → health template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0580 | `GET` | `/:customer_id/admin/modules/emails/health(.:format)` | `index` | `C171.index` |

#### C172 — `admin/modules/emails/template_versions`

Controller source: `app/controllers/admin/modules/emails/template_versions_controller.rb`; superclass `Admin::Maintenance::BaseVersionsController`.
Family reference: **DEF_MAIL**. BaseVersionsController → [`Emails::Template`](../app/models/emails/template.rb) / [`Emails::TemplateVersion`](../app/models/emails/template_version.rb) / [`Versionable`](../app/models/concerns/versionable.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C172.default` | inherited set_current_version! |
| `C172.index` | inherited version history/snapshot |
| `C172.create` | inherited restore_as_new! |
| `C172.edit` | template version editor |
| `C172.show` | inherited version history/snapshot |
| `C172.destroy` | inherited version deletion/content sweep |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0581 | `PUT` | `/:customer_id/admin/modules/emails/templates/:template_id/versions/:id/default(.:format)` | `default` | `C172.default` |
| R0582 | `GET` | `/:customer_id/admin/modules/emails/templates/:template_id/versions(.:format)` | `index` | `C172.index` |
| R0583 | `POST` | `/:customer_id/admin/modules/emails/templates/:template_id/versions(.:format)` | `create` | `C172.create` |
| R0584 | `GET` | `/:customer_id/admin/modules/emails/templates/:template_id/versions/:id/edit(.:format)` | `edit` | `C172.edit` |
| R0585 | `GET` | `/:customer_id/admin/modules/emails/templates/:template_id/versions/:id(.:format)` | `show` | `C172.show` |
| R0586 | `DELETE` | `/:customer_id/admin/modules/emails/templates/:template_id/versions/:id(.:format)` | `destroy` | `C172.destroy` |

#### C173 — `admin/modules/emails/templates`

Controller source: `app/controllers/admin/modules/emails/templates_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. customer [`Emails::Template`](../app/models/emails/template.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C173.status` | template status save |
| `C173.preview` | [`Emails::AuthorPreview`](../app/services/emails/author_preview.rb) (persisted or submitted draft) → HTML/JSON |
| `C173.test_send` | [`Emails::VariableContext`](../app/services/emails/variable_context.rb) → [`Emails::CompileTemplate`](../app/services/emails/compile_template.rb) / [`Emails::TemplateRenderer`](../app/services/emails/template_renderer.rb) → [`Emails::Gateway`](../app/services/emails/gateway.rb) → delivery pipeline |
| `C173.duplicate` | template copy/save |
| `C173.index` | [`Emails::TokenCatalog`](../app/services/emails/token_catalog.rb) / [`Emails::TemplateTokenCodec`](../app/services/emails/template_token_codec.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) |
| `C173.create` | permitted [`Emails::Template`](../app/models/emails/template.rb) scalar/rich-text/attachment save → version |
| `C173.new` | template/rich-text/attachment editor |
| `C173.edit` | template/rich-text/attachment editor |
| `C173.show` | [`Emails::AuthorPreview`](../app/services/emails/author_preview.rb) → detail template |
| `C173.update` | permitted [`Emails::Template`](../app/models/emails/template.rb) scalar/rich-text/attachment save → version |
| `C173.destroy` | template destroy/reference restriction |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0587 | `PATCH` | `/:customer_id/admin/modules/emails/templates/:id/status(.:format)` | `status` | `C173.status` |
| R0588 | `GET` | `/:customer_id/admin/modules/emails/templates/:id/preview(.:format)` | `preview` | `C173.preview` |
| R0589 | `POST` | `/:customer_id/admin/modules/emails/templates/:id/test_send(.:format)` | `test_send` | `C173.test_send` |
| R0590 | `POST` | `/:customer_id/admin/modules/emails/templates/:id/preview(.:format)` | `preview` | `C173.preview` |
| R0591 | `POST` | `/:customer_id/admin/modules/emails/templates/:id/duplicate(.:format)` | `duplicate` | `C173.duplicate` |
| R0592 | `POST` | `/:customer_id/admin/modules/emails/templates/test_send(.:format)` | `test_send` | `C173.test_send` |
| R0593 | `POST` | `/:customer_id/admin/modules/emails/templates/preview(.:format)` | `preview` | `C173.preview` |
| R0594 | `GET` | `/:customer_id/admin/modules/emails/templates(.:format)` | `index` | `C173.index` |
| R0595 | `POST` | `/:customer_id/admin/modules/emails/templates(.:format)` | `create` | `C173.create` |
| R0596 | `GET` | `/:customer_id/admin/modules/emails/templates/new(.:format)` | `new` | `C173.new` |
| R0597 | `GET` | `/:customer_id/admin/modules/emails/templates/:id/edit(.:format)` | `edit` | `C173.edit` |
| R0598 | `GET` | `/:customer_id/admin/modules/emails/templates/:id(.:format)` | `show` | `C173.show` |
| R0599 | `PATCH` | `/:customer_id/admin/modules/emails/templates/:id(.:format)` | `update` | `C173.update` |
| R0600 | `PUT` | `/:customer_id/admin/modules/emails/templates/:id(.:format)` | `update` | `C173.update` |
| R0601 | `DELETE` | `/:customer_id/admin/modules/emails/templates/:id(.:format)` | `destroy` | `C173.destroy` |

#### C174 — `admin/modules/emails/attachments`

Controller source: `app/controllers/admin/modules/emails/attachments_controller.rb`; superclass `ApplicationController`; includes `ActiveStorage::SetCurrent`.
Family reference: **MAIL**. customer ActiveStorage::Blob.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C174.create` | create_before_direct_upload! → signed service direct-upload URL/headers |
| `C174.show` | signed tenant blob lookup → inline attachment redirect |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0602 | `POST` | `/:customer_id/admin/modules/emails/attachments(.:format)` | `create` | `C174.create` |
| R0603 | `GET` | `/:customer_id/admin/modules/emails/attachments/:id(.:format)` | `show` | `C174.show` |

#### C175 — `admin/modules/emails/send_activity_deliveries`

Controller source: `app/controllers/admin/modules/emails/send_activity_deliveries_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::SendActivities::SendActivity`](../app/models/emails/send_activities/send_activity.rb) → [`Emails::SendActivities::StartSendActivity`](../app/services/emails/send_activities/start_send_activity.rb) → fanout job.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C175.create` | [`Emails::SendActivities::SendActivity`](../app/models/emails/send_activities/send_activity.rb) → [`Emails::SendActivities::StartSendActivity`](../app/services/emails/send_activities/start_send_activity.rb) → fanout job |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0604 | `POST` | `/:customer_id/admin/modules/emails/send_activities/:send_activity_id/delivery(.:format)` | `create` | `C175.create` |

#### C176 — `admin/modules/emails/send_activity_cancellations`

Controller source: `app/controllers/admin/modules/emails/send_activity_cancellations_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::SendActivities::SendActivity`](../app/models/emails/send_activities/send_activity.rb) cancellation → queued/in-flight delivery lifecycle.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C176.create` | [`Emails::SendActivities::SendActivity`](../app/models/emails/send_activities/send_activity.rb) cancellation → queued/in-flight delivery lifecycle |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0605 | `POST` | `/:customer_id/admin/modules/emails/send_activities/:send_activity_id/cancellation(.:format)` | `create` | `C176.create` |

#### C177 — `admin/modules/emails/send_activities`

Controller source: `app/controllers/admin/modules/emails/send_activities_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::SendActivities::SendActivity`](../app/models/emails/send_activities/send_activity.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C177.index` | newest activities/list/detail |
| `C177.create` | [`Emails::SendActivities::Build`](../app/services/emails/send_activities/build.rb) → activity schedule/audience save |
| `C177.new` | template/audience collections → send form |
| `C177.edit` | template/audience collections → send form |
| `C177.show` | newest activities/list/detail |
| `C177.update` | [`Emails::SendActivities::Build`](../app/services/emails/send_activities/build.rb) → activity schedule/audience save |
| `C177.destroy` | allowed-state activity deletion |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0606 | `GET` | `/:customer_id/admin/modules/emails/send_activities(.:format)` | `index` | `C177.index` |
| R0607 | `POST` | `/:customer_id/admin/modules/emails/send_activities(.:format)` | `create` | `C177.create` |
| R0608 | `GET` | `/:customer_id/admin/modules/emails/send_activities/new(.:format)` | `new` | `C177.new` |
| R0609 | `GET` | `/:customer_id/admin/modules/emails/send_activities/:id/edit(.:format)` | `edit` | `C177.edit` |
| R0610 | `GET` | `/:customer_id/admin/modules/emails/send_activities/:id(.:format)` | `show` | `C177.show` |
| R0611 | `PATCH` | `/:customer_id/admin/modules/emails/send_activities/:id(.:format)` | `update` | `C177.update` |
| R0612 | `PUT` | `/:customer_id/admin/modules/emails/send_activities/:id(.:format)` | `update` | `C177.update` |
| R0613 | `DELETE` | `/:customer_id/admin/modules/emails/send_activities/:id(.:format)` | `destroy` | `C177.destroy` |

#### C178 — `admin/modules/emails/lists`

Controller source: `app/controllers/admin/modules/emails/lists_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::Audience::List`](../app/models/emails/audience/list.rb) / [`Authentication::User`](../app/models/authentication/user.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C178.preview` | [`Emails::Audience::Contracts::SegmentRules`](../app/services/emails/audience/contracts/segment_rules.rb) → [`Emails::Audience::SegmentQuery`](../app/services/emails/audience/segment_query.rb) → sample recipients |
| `C178.index` | audience list/members/editor |
| `C178.create` | [`Emails::Audience::Contracts::SegmentRules`](../app/services/emails/audience/contracts/segment_rules.rb) → [`Emails::Audience::SaveList`](../app/services/emails/audience/save_list.rb) → membership sync |
| `C178.new` | audience list/members/editor |
| `C178.edit` | audience list/members/editor |
| `C178.show` | audience list/members/editor |
| `C178.update` | [`Emails::Audience::Contracts::SegmentRules`](../app/services/emails/audience/contracts/segment_rules.rb) → [`Emails::Audience::SaveList`](../app/services/emails/audience/save_list.rb) → membership sync |
| `C178.destroy` | list destroy/reference restriction |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0614 | `POST` | `/:customer_id/admin/modules/emails/lists/preview(.:format)` | `preview` | `C178.preview` |
| R0615 | `GET` | `/:customer_id/admin/modules/emails/lists(.:format)` | `index` | `C178.index` |
| R0616 | `POST` | `/:customer_id/admin/modules/emails/lists(.:format)` | `create` | `C178.create` |
| R0617 | `GET` | `/:customer_id/admin/modules/emails/lists/new(.:format)` | `new` | `C178.new` |
| R0618 | `GET` | `/:customer_id/admin/modules/emails/lists/:id/edit(.:format)` | `edit` | `C178.edit` |
| R0619 | `GET` | `/:customer_id/admin/modules/emails/lists/:id(.:format)` | `show` | `C178.show` |
| R0620 | `PATCH` | `/:customer_id/admin/modules/emails/lists/:id(.:format)` | `update` | `C178.update` |
| R0621 | `PUT` | `/:customer_id/admin/modules/emails/lists/:id(.:format)` | `update` | `C178.update` |
| R0622 | `DELETE` | `/:customer_id/admin/modules/emails/lists/:id(.:format)` | `destroy` | `C178.destroy` |

#### C179 — `admin/modules/emails/reports`

Controller source: `app/controllers/admin/modules/emails/reports_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. empty index → implicit email-report landing template; analytics reached by dashboard/health links.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C179.index` | empty index → implicit email-report landing template; analytics reached by dashboard/health links |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0623 | `GET` | `/:customer_id/admin/modules/emails/reports(.:format)` | `index` | `C179.index` |

#### C180 — `admin/modules/emails/deliverability`

Controller source: `app/controllers/admin/modules/emails/deliverability_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. empty index → implicit deliverability landing template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C180.index` | empty index → implicit deliverability landing template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0624 | `GET` | `/:customer_id/admin/modules/emails/deliverability(.:format)` | `index` | `C180.index` |

#### C181 — `admin/modules/emails/engagement`

Controller source: `app/controllers/admin/modules/emails/engagement_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. empty index → implicit engagement landing template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C181.index` | empty index → implicit engagement landing template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0625 | `GET` | `/:customer_id/admin/modules/emails/engagement(.:format)` | `index` | `C181.index` |

#### C182 — `admin/modules/emails/suppressions`

Controller source: `app/controllers/admin/modules/emails/suppressions_controller.rb`; superclass `ApplicationController`.
Family reference: **MAIL**. [`Emails::Suppression`](../app/models/emails/suppression.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C182.batch_unblock` | customer-scoped suppression row delete_all → redirect |
| `C182.index` | [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → filtered suppression list |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0626 | `DELETE` | `/:customer_id/admin/modules/emails/suppressions/batch_unblock(.:format)` | `batch_unblock` | `C182.batch_unblock` |
| R0627 | `GET` | `/:customer_id/admin/modules/emails/suppressions(.:format)` | `index` | `C182.index` |

#### C183 — `admin/modules/sms/entity_syncs`

Controller source: `app/controllers/admin/modules/sms/entity_syncs_controller.rb`; superclass `BaseController`.
Family reference: **SMS**. [`Sms::EntitySources`](../app/services/sms/entity_sources.rb) / [`Sms::FormValues`](../app/services/sms/form_values.rb) / [`Sms::RequestAttributes`](../app/services/sms/request_attributes.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C183.new` | source/form metadata |
| `C183.preview` | [`Sms::Contacts::SyncEntity`](../app/services/sms/contacts/sync_entity.rb) → preview or persisted contact synchronization |
| `C183.create` | [`Sms::Contacts::SyncEntity`](../app/services/sms/contacts/sync_entity.rb) → preview or persisted contact synchronization |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0628 | `GET` | `/:customer_id/admin/modules/sms/contacts/entity_sync/new(.:format)` | `new` | `C183.new` |
| R0629 | `POST` | `/:customer_id/admin/modules/sms/contacts/entity_sync/preview(.:format)` | `preview` | `C183.preview` |
| R0630 | `POST` | `/:customer_id/admin/modules/sms/contacts/entity_sync(.:format)` | `create` | `C183.create` |

#### C184 — `admin/modules/sms/contacts`

Controller source: `app/controllers/admin/modules/sms/contacts_controller.rb`; superclass `BaseController`.
Family reference: **SMS**. customer [`Sms::Contact`](../app/models/sms/contact.rb) + [`Sms::FormValues`](../app/services/sms/form_values.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C184.new` | contact browse/forms |
| `C184.edit` | contact browse/forms |
| `C184.index` | contact browse/forms |
| `C184.create` | [`Sms::Contacts::Save`](../app/services/sms/contacts/save.rb) → contacts/contracts |
| `C184.show` | [`Sms::Contacts::Eligibility`](../app/services/sms/contacts/eligibility.rb) / [`Sms::ConsentEvent`](../app/models/sms/consent_event.rb) → detail |
| `C184.update` | [`Sms::Contacts::Save`](../app/services/sms/contacts/save.rb) → contacts/contracts |
| `C184.destroy` | [`Sms::Contacts::Archive`](../app/services/sms/contacts/archive.rb) → archived contact |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0631 | `GET` | `/:customer_id/admin/modules/sms/contacts/new(.:format)` | `new` | `C184.new` |
| R0632 | `GET` | `/:customer_id/admin/modules/sms/contacts/:id/edit(.:format)` | `edit` | `C184.edit` |
| R0634 | `GET` | `/:customer_id/admin/modules/sms/contacts(.:format)` | `index` | `C184.index` |
| R0635 | `POST` | `/:customer_id/admin/modules/sms/contacts(.:format)` | `create` | `C184.create` |
| R0636 | `GET` | `/:customer_id/admin/modules/sms/contacts/:id(.:format)` | `show` | `C184.show` |
| R0637 | `PATCH` | `/:customer_id/admin/modules/sms/contacts/:id(.:format)` | `update` | `C184.update` |
| R0638 | `PUT` | `/:customer_id/admin/modules/sms/contacts/:id(.:format)` | `update` | `C184.update` |
| R0639 | `DELETE` | `/:customer_id/admin/modules/sms/contacts/:id(.:format)` | `destroy` | `C184.destroy` |

#### C185 — `admin/modules/sms/consent_events`

Controller source: `app/controllers/admin/modules/sms/consent_events_controller.rb`; superclass `ContactsController`.
Family reference: **SMS**. inherits ContactsController → [`Sms::Contact`](../app/models/sms/contact.rb) → [`Sms::Contacts::RecordConsent`](../app/services/sms/contacts/record_consent.rb) → [`Sms::ConsentEvent`](../app/models/sms/consent_event.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C185.create` | inherits ContactsController → [`Sms::Contact`](../app/models/sms/contact.rb) → [`Sms::Contacts::RecordConsent`](../app/services/sms/contacts/record_consent.rb) → [`Sms::ConsentEvent`](../app/models/sms/consent_event.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0633 | `POST` | `/:customer_id/admin/modules/sms/contacts/:contact_id/consent_events(.:format)` | `create` | `C185.create` |

#### C186 — `admin/modules/sms/segments`

Controller source: `app/controllers/admin/modules/sms/segments_controller.rb`; superclass `BaseController`.
Family reference: **SMS**. [`Sms::Audience::Segment`](../app/models/sms/audience/segment.rb) / [`Sms::Audience::FieldCatalog`](../app/services/sms/audience/field_catalog.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C186.preview` | [`Sms::Audience::Preview`](../app/services/sms/audience/preview.rb) → count/sample |
| `C186.new` | segment list/forms |
| `C186.edit` | segment list/forms |
| `C186.index` | segment list/forms |
| `C186.create` | [`Sms::Audience::SaveSegment`](../app/services/sms/audience/save_segment.rb) → segment/contracts |
| `C186.show` | [`Sms::Audience::Preview`](../app/services/sms/audience/preview.rb) → count/sample |
| `C186.update` | [`Sms::Audience::SaveSegment`](../app/services/sms/audience/save_segment.rb) → segment/contracts |
| `C186.destroy` | [`Sms::Audience::DeleteSegment`](../app/services/sms/audience/delete_segment.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0640 | `POST` | `/:customer_id/admin/modules/sms/segments/preview(.:format)` | `preview` | `C186.preview` |
| R0641 | `POST` | `/:customer_id/admin/modules/sms/segments/:id/preview(.:format)` | `preview` | `C186.preview` |
| R0642 | `GET` | `/:customer_id/admin/modules/sms/segments/new(.:format)` | `new` | `C186.new` |
| R0643 | `GET` | `/:customer_id/admin/modules/sms/segments/:id/edit(.:format)` | `edit` | `C186.edit` |
| R0644 | `GET` | `/:customer_id/admin/modules/sms/segments(.:format)` | `index` | `C186.index` |
| R0645 | `POST` | `/:customer_id/admin/modules/sms/segments(.:format)` | `create` | `C186.create` |
| R0646 | `GET` | `/:customer_id/admin/modules/sms/segments/:id(.:format)` | `show` | `C186.show` |
| R0647 | `PATCH` | `/:customer_id/admin/modules/sms/segments/:id(.:format)` | `update` | `C186.update` |
| R0648 | `PUT` | `/:customer_id/admin/modules/sms/segments/:id(.:format)` | `update` | `C186.update` |
| R0649 | `DELETE` | `/:customer_id/admin/modules/sms/segments/:id(.:format)` | `destroy` | `C186.destroy` |

#### C187 — `admin/modules/sms/campaigns`

Controller source: `app/controllers/admin/modules/sms/campaigns_controller.rb`; superclass `BaseController`.
Family reference: **SMS**. [`Sms::Campaign`](../app/models/sms/campaign.rb) / [`Sms::Template`](../app/models/sms/template.rb) / [`Sms::Audience::Segment`](../app/models/sms/audience/segment.rb) / [`Sms::Contact`](../app/models/sms/contact.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C187.preview` | [`Sms::Campaigns::Preview`](../app/services/sms/campaigns/preview.rb) (saved or draft) |
| `C187.new` | campaign list/forms |
| `C187.edit` | campaign list/forms |
| `C187.index` | campaign list/forms |
| `C187.create` | [`Sms::Campaigns::Save`](../app/services/sms/campaigns/save.rb) → campaign/contracts |
| `C187.show` | [`Sms::Campaigns::Preview`](../app/services/sms/campaigns/preview.rb) / [`Sms::Campaigns::Report`](../app/services/sms/campaigns/report.rb) |
| `C187.update` | [`Sms::Campaigns::Save`](../app/services/sms/campaigns/save.rb) → campaign/contracts |
| `C187.destroy` | [`Sms::Campaigns::DeleteDraft`](../app/services/sms/campaigns/delete_draft.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0650 | `POST` | `/:customer_id/admin/modules/sms/campaigns/preview(.:format)` | `preview` | `C187.preview` |
| R0651 | `POST` | `/:customer_id/admin/modules/sms/campaigns/:id/preview(.:format)` | `preview` | `C187.preview` |
| R0654 | `GET` | `/:customer_id/admin/modules/sms/campaigns/new(.:format)` | `new` | `C187.new` |
| R0655 | `GET` | `/:customer_id/admin/modules/sms/campaigns/:id/edit(.:format)` | `edit` | `C187.edit` |
| R0657 | `GET` | `/:customer_id/admin/modules/sms/campaigns(.:format)` | `index` | `C187.index` |
| R0658 | `POST` | `/:customer_id/admin/modules/sms/campaigns(.:format)` | `create` | `C187.create` |
| R0659 | `GET` | `/:customer_id/admin/modules/sms/campaigns/:id(.:format)` | `show` | `C187.show` |
| R0660 | `PATCH` | `/:customer_id/admin/modules/sms/campaigns/:id(.:format)` | `update` | `C187.update` |
| R0661 | `PUT` | `/:customer_id/admin/modules/sms/campaigns/:id(.:format)` | `update` | `C187.update` |
| R0662 | `DELETE` | `/:customer_id/admin/modules/sms/campaigns/:id(.:format)` | `destroy` | `C187.destroy` |

#### C188 — `admin/modules/sms/campaign_launches`

Controller source: `app/controllers/admin/modules/sms/campaign_launches_controller.rb`; superclass `CampaignsController`.
Family reference: **SMS**. inherits CampaignsController → [`Sms::Campaigns::Launch`](../app/services/sms/campaigns/launch.rb) → recipient snapshot/admission/dispatch.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C188.create` | inherits CampaignsController → [`Sms::Campaigns::Launch`](../app/services/sms/campaigns/launch.rb) → recipient snapshot/admission/dispatch |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0652 | `POST` | `/:customer_id/admin/modules/sms/campaigns/:id/launch(.:format)` | `create` | `C188.create` |

#### C189 — `admin/modules/sms/campaign_cancellations`

Controller source: `app/controllers/admin/modules/sms/campaign_cancellations_controller.rb`; superclass `CampaignsController`.
Family reference: **SMS**. inherits CampaignsController → [`Sms::Campaigns::Cancel`](../app/services/sms/campaigns/cancel.rb) → pending campaign recipients/messages.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C189.create` | inherits CampaignsController → [`Sms::Campaigns::Cancel`](../app/services/sms/campaigns/cancel.rb) → pending campaign recipients/messages |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0653 | `POST` | `/:customer_id/admin/modules/sms/campaigns/:id/cancel(.:format)` | `create` | `C189.create` |

#### C190 — `admin/modules/sms/campaign_reports`

Controller source: `app/controllers/admin/modules/sms/campaign_reports_controller.rb`; superclass `BaseController`.
Family reference: **SMS**. [`Sms::Campaign`](../app/models/sms/campaign.rb) / [`Sms::CampaignRecipient`](../app/models/sms/campaign_recipient.rb) / [`Sms::Message`](../app/models/sms/message.rb) → [`Sms::Campaigns::Report`](../app/services/sms/campaigns/report.rb); CSV → [`Sms::CampaignReportCsv`](../app/services/sms/campaign_report_csv.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C190.show` | [`Sms::Campaign`](../app/models/sms/campaign.rb) / [`Sms::CampaignRecipient`](../app/models/sms/campaign_recipient.rb) / [`Sms::Message`](../app/models/sms/message.rb) → [`Sms::Campaigns::Report`](../app/services/sms/campaigns/report.rb); CSV → [`Sms::CampaignReportCsv`](../app/services/sms/campaign_report_csv.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0656 | `GET` | `/:customer_id/admin/modules/sms/campaigns/:campaign_id/report(.:format)` | `show` | `C190.show` |

#### C191 — `admin/modules/sms/messages`

Controller source: `app/controllers/admin/modules/sms/messages_controller.rb`; superclass `ApplicationController`.
Family reference: **SMS**. [`Sms::Message`](../app/models/sms/message.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) list or message detail template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C191.index` | [`Sms::Message`](../app/models/sms/message.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) list or message detail template |
| `C191.show` | [`Sms::Message`](../app/models/sms/message.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) list or message detail template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0663 | `GET` | `/:customer_id/admin/modules/sms/messages(.:format)` | `index` | `C191.index` |
| R0664 | `GET` | `/:customer_id/admin/modules/sms/messages/:id(.:format)` | `show` | `C191.show` |

#### C192 — `admin/modules/sms/sends`

Controller source: `app/controllers/admin/modules/sms/sends_controller.rb`; superclass `ApplicationController`.
Family reference: **SMS**. [`Sms::SendStandards`](../app/services/sms/send_standards.rb) → [`Sms::Gateway`](../app/services/sms/gateway.rb) → contracts/send activity → admission/message/dispatch.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C192.create` | [`Sms::SendStandards`](../app/services/sms/send_standards.rb) → [`Sms::Gateway`](../app/services/sms/gateway.rb) → contracts/send activity → admission/message/dispatch |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0665 | `POST` | `/:customer_id/admin/modules/sms/sends(.:format)` | `create` | `C192.create` |

#### C193 — `admin/modules/sms/opt_outs`

Controller source: `app/controllers/admin/modules/sms/opt_outs_controller.rb`; superclass `ApplicationController`.
Family reference: **SMS**. [`Sms::OptOut`](../app/models/sms/opt_out.rb) / [`Sms::Message`](../app/models/sms/message.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → opt-out list.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C193.index` | [`Sms::OptOut`](../app/models/sms/opt_out.rb) / [`Sms::Message`](../app/models/sms/message.rb) → [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) → opt-out list |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0666 | `GET` | `/:customer_id/admin/modules/sms/opt_outs(.:format)` | `index` | `C193.index` |

#### C194 — `admin/modules/payments/refunds`

Controller source: `app/controllers/admin/modules/payments/refunds_controller.rb`; superclass `BaseController`.
Family reference: **PAY**. customer [`Payments::Payment`](../app/models/payments/payment.rb) → [`Payments::Activities::Refund`](../app/services/payments/activities/refund.rb) → [`Payments::Refund`](../app/models/payments/refund.rb) / gateway.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C194.create` | customer [`Payments::Payment`](../app/models/payments/payment.rb) → [`Payments::Activities::Refund`](../app/services/payments/activities/refund.rb) → [`Payments::Refund`](../app/models/payments/refund.rb) / gateway |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0667 | `POST` | `/:customer_id/admin/modules/payments/transactions/:transaction_id/refunds(.:format)` | `create` | `C194.create` |

#### C195 — `admin/modules/payments/transactions`

Controller source: `app/controllers/admin/modules/payments/transactions_controller.rb`; superclass `BaseController`.
Family reference: **PAY**. customer [`Payments::Payment`](../app/models/payments/payment.rb) / order/refunds → payment transaction list/detail component.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C195.index` | customer [`Payments::Payment`](../app/models/payments/payment.rb) / order/refunds → payment transaction list/detail component |
| `C195.show` | customer [`Payments::Payment`](../app/models/payments/payment.rb) / order/refunds → payment transaction list/detail component |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0668 | `GET` | `/:customer_id/admin/modules/payments/transactions(.:format)` | `index` | `C195.index` |
| R0669 | `GET` | `/:customer_id/admin/modules/payments/transactions/:id(.:format)` | `show` | `C195.show` |

#### C196 — `admin/modules/payments/reconciliations`

Controller source: `app/controllers/admin/modules/payments/reconciliations_controller.rb`; superclass `BaseController`.
Family reference: **PAY**. [`Payments::ReconciliationBill`](../app/models/payments/reconciliation_bill.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C196.download` | stored bill download |
| `C196.index` | bill list |
| `C196.show` | bill discrepancy/detail |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0670 | `GET` | `/:customer_id/admin/modules/payments/reconciliations/:id/download(.:format)` | `download` | `C196.download` |
| R0671 | `GET` | `/:customer_id/admin/modules/payments/reconciliations(.:format)` | `index` | `C196.index` |
| R0672 | `GET` | `/:customer_id/admin/modules/payments/reconciliations/:id(.:format)` | `show` | `C196.show` |

#### C197 — `admin/modules/payments/disputes`

Controller source: `app/controllers/admin/modules/payments/disputes_controller.rb`; superclass `BaseController`.
Family reference: **PAY**. customer [`Payments::Dispute`](../app/models/payments/dispute.rb) + [`Payments::Payment`](../app/models/payments/payment.rb) join → dispute list component.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C197.index` | customer [`Payments::Dispute`](../app/models/payments/dispute.rb) + [`Payments::Payment`](../app/models/payments/payment.rb) join → dispute list component |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0673 | `GET` | `/:customer_id/admin/modules/payments/disputes(.:format)` | `index` | `C197.index` |

#### C198 — `admin/modules/website/pages`

Controller source: `app/controllers/admin/modules/website/pages_controller.rb`; superclass `BaseController`; includes `Listable`.
Family reference: **WEB**. [`Websites::CurrentSite`](../app/controllers/concerns/websites/current_site.rb) → [`WebsitePage`](../app/models/website_page.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C198.index` | customer page list via [`ModuleEntriesResolver`](../app/services/module_entries_resolver.rb) |
| `C198.preview` | draft/saved page → [`Websites::Theme`](../app/services/websites/theme.rb) → website preview template/layout |
| `C198.reorder` | [`Websites::Activities::ReorderPages`](../app/services/websites/activities/reorder_pages.rb) |
| `C198.create` | [`Websites::Activities::SavePage`](../app/services/websites/activities/save_page.rb) → page/sections/version |
| `C198.new` | [`Websites::Catalog`](../app/services/websites/catalog.rb) → page editor |
| `C198.edit` | [`Websites::Catalog`](../app/services/websites/catalog.rb) → page editor |
| `C198.update` | [`Websites::Activities::SavePage`](../app/services/websites/activities/save_page.rb) → page/sections/version |
| `C198.destroy` | [`Websites::Activities::DestroyPage`](../app/services/websites/activities/destroy_page.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0674 | `GET` | `/:customer_id/admin/modules/website(.:format)` | `index` | `C198.index` |
| R0675 | `GET` | `/:customer_id/admin/modules/website/pages/:id/preview(.:format)` | `preview` | `C198.preview` |
| R0676 | `POST` | `/:customer_id/admin/modules/website/pages/:id/preview(.:format)` | `preview` | `C198.preview` |
| R0677 | `PATCH` | `/:customer_id/admin/modules/website/pages/reorder(.:format)` | `reorder` | `C198.reorder` |
| R0678 | `GET` | `/:customer_id/admin/modules/website/pages(.:format)` | `index` | `C198.index` |
| R0679 | `POST` | `/:customer_id/admin/modules/website/pages(.:format)` | `create` | `C198.create` |
| R0680 | `GET` | `/:customer_id/admin/modules/website/pages/new(.:format)` | `new` | `C198.new` |
| R0681 | `GET` | `/:customer_id/admin/modules/website/pages/:id/edit(.:format)` | `edit` | `C198.edit` |
| R0682 | `PATCH` | `/:customer_id/admin/modules/website/pages/:id(.:format)` | `update` | `C198.update` |
| R0683 | `PUT` | `/:customer_id/admin/modules/website/pages/:id(.:format)` | `update` | `C198.update` |
| R0684 | `DELETE` | `/:customer_id/admin/modules/website/pages/:id(.:format)` | `destroy` | `C198.destroy` |

#### C199 — `admin/modules/website/media`

Controller source: `app/controllers/admin/modules/website/media_controller.rb`; superclass `BaseController`.
Family reference: **WEB**. [`Websites::Activities::UploadMedia`](../app/services/websites/activities/upload_media.rb) → [`Websites::MediaPolicy`](../app/services/websites/media_policy.rb) / ActiveStorage::Blob.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C199.create` | [`Websites::Activities::UploadMedia`](../app/services/websites/activities/upload_media.rb) → [`Websites::MediaPolicy`](../app/services/websites/media_policy.rb) / ActiveStorage::Blob |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0685 | `POST` | `/:customer_id/admin/modules/website/media(.:format)` | `create` | `C199.create` |

#### C200 — `admin/modules/ai_assistant/transcriptions`

Controller source: `app/controllers/admin/modules/ai_assistant/transcriptions_controller.rb`; superclass `ApplicationController`; includes `::SpeechToText::TranscriptionEnqueueing`.
Family reference: **AI**. [`SpeechToText::TranscriptionEnqueueing`](../app/controllers/concerns/speech_to_text/transcription_enqueueing.rb) → [`SpeechToText::Activities::EnqueueTranscription`](../app/services/speech_to_text/activities/enqueue_transcription.rb) → clip/job.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C200.create` | [`SpeechToText::TranscriptionEnqueueing`](../app/controllers/concerns/speech_to_text/transcription_enqueueing.rb) → [`SpeechToText::Activities::EnqueueTranscription`](../app/services/speech_to_text/activities/enqueue_transcription.rb) → clip/job |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0686 | `POST` | `/:customer_id/admin/modules/ai_assistant/transcriptions(.:format)` | `create` | `C200.create` |

#### C201 — `admin/modules/ai_assistant/conversations`

Controller source: `app/controllers/admin/modules/ai_assistant/conversations_controller.rb`; superclass `ApplicationController`.
Family reference: **AI**. [`AiAssistant::Conversation`](../app/models/ai_assistant/conversation.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C201.archive` | [`AiAssistant::Activities::ArchiveConversation`](../app/services/ai_assistant/activities/archive_conversation.rb) |
| `C201.index` | [`AiAssistant::Activities::ListConversations`](../app/services/ai_assistant/activities/list_conversations.rb) |
| `C201.create` | [`AiAssistant::Activities::StartConversation`](../app/services/ai_assistant/activities/start_conversation.rb) |
| `C201.update` | [`AiAssistant::Activities::RenameConversation`](../app/services/ai_assistant/activities/rename_conversation.rb) |
| `C201.destroy` | [`AiAssistant::Activities::DeleteConversation`](../app/services/ai_assistant/activities/delete_conversation.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0687 | `POST` | `/:customer_id/admin/modules/ai_assistant/conversations/:id/archive(.:format)` | `archive` | `C201.archive` |
| R0688 | `GET` | `/:customer_id/admin/modules/ai_assistant/conversations(.:format)` | `index` | `C201.index` |
| R0689 | `POST` | `/:customer_id/admin/modules/ai_assistant/conversations(.:format)` | `create` | `C201.create` |
| R0690 | `PATCH` | `/:customer_id/admin/modules/ai_assistant/conversations/:id(.:format)` | `update` | `C201.update` |
| R0691 | `PUT` | `/:customer_id/admin/modules/ai_assistant/conversations/:id(.:format)` | `update` | `C201.update` |
| R0692 | `DELETE` | `/:customer_id/admin/modules/ai_assistant/conversations/:id(.:format)` | `destroy` | `C201.destroy` |

#### C202 — `admin/modules/ai_assistant/messages`

Controller source: `app/controllers/admin/modules/ai_assistant/messages_controller.rb`; superclass `ApplicationController`; includes `::AiAssistant::MessageSending`.
Family reference: **AI**. [`AiAssistant::MessageSending`](../app/controllers/concerns/ai_assistant/message_sending.rb) / [`AiAssistant::Message`](../app/models/ai_assistant/message.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C202.undo` | [`AiAssistant::Activities::UndoWebsiteReply`](../app/services/ai_assistant/activities/undo_website_reply.rb) → [`Websites::Assistant::Undo`](../app/services/websites/assistant/undo.rb) → [`AiAssistant::MessageComponent`](../app/components/ai_assistant/message_component.rb) |
| `C202.discard_proposal` | [`AiAssistant::Activities::DiscardProposal`](../app/services/ai_assistant/activities/discard_proposal.rb) → proposal state / [`AiAssistant::MessageComponent`](../app/components/ai_assistant/message_component.rb) |
| `C202.mentions` | [`AiAssistant::Activities::ListMentions`](../app/services/ai_assistant/activities/list_mentions.rb) |
| `C202.stop` | [`AiAssistant::Activities::CancelReply`](../app/services/ai_assistant/activities/cancel_reply.rb) |
| `C202.regenerate` | [`AiAssistant::Activities::RegenerateLast`](../app/services/ai_assistant/activities/regenerate_last.rb) → reply job |
| `C202.create` | [`AiAssistant::Activities::SendMessage`](../app/services/ai_assistant/activities/send_message.rb) → preflight + reply job |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0693 | `POST` | `/:customer_id/admin/modules/ai_assistant/messages/:id/undo(.:format)` | `undo` | `C202.undo` |
| R0694 | `POST` | `/:customer_id/admin/modules/ai_assistant/messages/:id/discard_proposal(.:format)` | `discard_proposal` | `C202.discard_proposal` |
| R0695 | `GET` | `/:customer_id/admin/modules/ai_assistant/messages/mentions(.:format)` | `mentions` | `C202.mentions` |
| R0696 | `POST` | `/:customer_id/admin/modules/ai_assistant/messages/stop(.:format)` | `stop` | `C202.stop` |
| R0697 | `POST` | `/:customer_id/admin/modules/ai_assistant/messages/regenerate(.:format)` | `regenerate` | `C202.regenerate` |
| R0698 | `POST` | `/:customer_id/admin/modules/ai_assistant/messages(.:format)` | `create` | `C202.create` |

### Member fixed and descriptor surfaces

**21 route entries · 10 controllers · 19 controller/action pairs.**

#### C203 — `member/dashboards`

Controller source: `app/controllers/member/dashboards_controller.rb`; superclass `BaseController`.
Family reference: **MEMBER**. Member::BaseController → current [`Authentication::User`](../app/models/authentication/user.rb) / [`Member::Navigation`](../app/services/member/navigation.rb); module state → dashboard template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C203.show` | Member::BaseController → current [`Authentication::User`](../app/models/authentication/user.rb) / [`Member::Navigation`](../app/services/member/navigation.rb); module state → dashboard template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0699 | `GET` | `/:customer_id/member(.:format)` | `show` | `C203.show` |

#### C204 — `member/profiles`

Controller source: `app/controllers/member/profiles_controller.rb`; superclass `BaseController`.
Family reference: **MEMBER**. current [`Authentication::User`](../app/models/authentication/user.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C204.edit` | [`Member::Profiles::UpdateContract`](../app/contracts/member/profiles/update_contract.rb) → profile form |
| `C204.show` | profile template |
| `C204.update` | [`Member::Profiles::UpdateContract`](../app/contracts/member/profiles/update_contract.rb) → current user save / [`Authentication::CredentialLifecycle`](../app/services/authentication/credential_lifecycle.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0700 | `GET` | `/:customer_id/member/profile/edit(.:format)` | `edit` | `C204.edit` |
| R0701 | `GET` | `/:customer_id/member/profile(.:format)` | `show` | `C204.show` |
| R0702 | `PATCH` | `/:customer_id/member/profile(.:format)` | `update` | `C204.update` |
| R0703 | `PUT` | `/:customer_id/member/profile(.:format)` | `update` | `C204.update` |

#### C205 — `member/mfa`

Controller source: `app/controllers/member/mfa_controller.rb`; superclass `BaseController`; includes `Authentication::MfaEnrollment`.
Family reference: **AUTH_MEMBER**. [`Authentication::MfaEnrollment`](../app/controllers/concerns/authentication/mfa_enrollment.rb) / current [`Authentication::User`](../app/models/authentication/user.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C205.setup` | GET enroll/QR template; POST [`Member::Mfa::Operation::Enable`](../app/concepts/member/mfa/operation/enable.rb) + [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) |
| `C205.destroy` | [`Member::Mfa::Operation::Disable`](../app/concepts/member/mfa/operation/disable.rb) + [`Authentication::MutationAudit`](../app/services/authentication/mutation_audit.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0704 | `GET` | `/:customer_id/member/security/mfa/setup(.:format)` | `setup` | `C205.setup` |
| R0705 | `POST` | `/:customer_id/member/security/mfa/setup(.:format)` | `setup` | `C205.setup` |
| R0706 | `DELETE` | `/:customer_id/member/security/mfa(.:format)` | `destroy` | `C205.destroy` |

#### C206 — `member/securities`

Controller source: `app/controllers/member/securities_controller.rb`; superclass `BaseController`.
Family reference: **AUTH_MEMBER**. current [`Authentication::User`](../app/models/authentication/user.rb) / trusted devices → security template.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C206.show` | current [`Authentication::User`](../app/models/authentication/user.rb) / trusted devices → security template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0707 | `GET` | `/:customer_id/member/security(.:format)` | `show` | `C206.show` |

#### C207 — `member/trusted_devices`

Controller source: `app/controllers/member/trusted_devices_controller.rb`; superclass `BaseController`.
Family reference: **AUTH_MEMBER**. current [`Authentication::User`](../app/models/authentication/user.rb) → owned [`Authentication::TrustedDevice`](../app/models/authentication/trusted_device.rb) → destroy.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C207.destroy` | current [`Authentication::User`](../app/models/authentication/user.rb) → owned [`Authentication::TrustedDevice`](../app/models/authentication/trusted_device.rb) → destroy |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0708 | `DELETE` | `/:customer_id/member/trusted_devices/:id(.:format)` | `destroy` | `C207.destroy` |

#### C208 — `member/pages`

Controller source: `app/controllers/member/pages_controller.rb`; superclass `BaseController`; includes `PageRendering`.
Family reference: **MEMBER_PAGE**. same-tenant read-preview opt-in → launched member-visible [`Page`](../app/models/page.rb) → [`Pages::Prefill`](../app/services/pages/prefill.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C208.show` | same-tenant read-preview opt-in → launched member-visible [`Page`](../app/models/page.rb) → [`Pages::Prefill`](../app/services/pages/prefill.rb) → [`PageRendering`](../app/controllers/concerns/page_rendering.rb) |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0709 | `GET` | `/:customer_id/member/pages/:id(.:format)` | `show` | `C208.show` |

#### C209 — `member/payments/payment_methods`

Controller source: `app/controllers/member/payments/payment_methods_controller.rb`; superclass `Member::BaseController`.
Family reference: **PAY_MEMBER**. owned [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) / [`Payments::CredentialResolver`](../app/services/payments/credential_resolver.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C209.setup_intent` | [`Payments::Activities::VaultCard`](../app/services/payments/activities/vault_card.rb) → provider setup intent |
| `C209.index` | [`Payments::Member::PaymentMethodsComponent`](../app/components/payments/member/payment_methods_component.rb) |
| `C209.create` | owned PSP-bound or pending [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) lookup → confirmation redirect; webhook supplies final card details |
| `C209.new` | redirect to index/card-entry component |
| `C209.destroy` | [`Payments::Gateway`](../app/services/payments/gateway.rb).detach_token → method mark_removed! |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0710 | `POST` | `/:customer_id/member/payments/payment_methods/setup_intent(.:format)` | `setup_intent` | `C209.setup_intent` |
| R0711 | `GET` | `/:customer_id/member/payments/payment_methods(.:format)` | `index` | `C209.index` |
| R0712 | `POST` | `/:customer_id/member/payments/payment_methods(.:format)` | `create` | `C209.create` |
| R0713 | `GET` | `/:customer_id/member/payments/payment_methods/new(.:format)` | `new` | `C209.new` |
| R0714 | `DELETE` | `/:customer_id/member/payments/payment_methods/:id(.:format)` | `destroy` | `C209.destroy` |

#### C210 — `member/payments/subscription_cancellations`

Controller source: `app/controllers/member/payments/subscription_cancellations_controller.rb`; superclass `Member::BaseController`.
Family reference: **PAY_MEMBER**. owned [`Payments::Subscription`](../app/models/payments/subscription.rb) → [`Payments::Activities::CancelSubscription`](../app/services/payments/activities/cancel_subscription.rb) → gateway/local cancellation.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C210.create` | owned [`Payments::Subscription`](../app/models/payments/subscription.rb) → [`Payments::Activities::CancelSubscription`](../app/services/payments/activities/cancel_subscription.rb) → gateway/local cancellation |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0715 | `POST` | `/:customer_id/member/payments/subscriptions/:subscription_id/cancellation(.:format)` | `create` | `C210.create` |

#### C211 — `member/payments/subscriptions`

Controller source: `app/controllers/member/payments/subscriptions_controller.rb`; superclass `Member::BaseController`.
Family reference: **PAY_MEMBER**. owned [`Payments::Subscription`](../app/models/payments/subscription.rb) through [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) → [`Payments::Member::SubscriptionsComponent`](../app/components/payments/member/subscriptions_component.rb); recovery [`Payments::Payment`](../app/models/payments/payment.rb) lookup.

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C211.index` | owned [`Payments::Subscription`](../app/models/payments/subscription.rb) through [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) → [`Payments::Member::SubscriptionsComponent`](../app/components/payments/member/subscriptions_component.rb); recovery [`Payments::Payment`](../app/models/payments/payment.rb) lookup |
| `C211.show` | owned [`Payments::Subscription`](../app/models/payments/subscription.rb) through [`Payments::PaymentMethod`](../app/models/payments/payment_method.rb) → [`Payments::Member::SubscriptionsComponent`](../app/components/payments/member/subscriptions_component.rb); recovery [`Payments::Payment`](../app/models/payments/payment.rb) lookup |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0716 | `GET` | `/:customer_id/member/payments/subscriptions(.:format)` | `index` | `C211.index` |
| R0717 | `GET` | `/:customer_id/member/payments/subscriptions/:id(.:format)` | `show` | `C211.show` |

#### C212 — `member/surfaces`

Controller source: `app/controllers/member/surfaces_controller.rb`; superclass `BaseController`.
Family reference: **MEMBER**. [`Member::Surfaces`](../app/services/member/surfaces.rb) → registered descriptor scope + [`People::Ownership`](../app/services/people/ownership.rb) / [`Member::EntitySurfaceBuilder`](../app/services/member/entity_surface_builder.rb).

| Source-chain ID | Action-specific principal trace |
|---|---|
| `C212.index` | [`Member::PageFilters`](../app/services/member/page_filters.rb) → scoped records / [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) → surface index template |
| `C212.show` | descriptor scope by :id → authorize_surface_record! → [`Entities::EntryDisplay`](../app/services/entities/entry_display.rb) → surface show template |

| Inventory entry | Verb | Exact declared path | Controller action | Source-chain ID |
|---|---|---|---|---|
| R0718 | `GET` | `/:customer_id/member/:key(.:format)` | `index` | `C212.index` |
| R0719 | `GET` | `/:customer_id/member/:key/:id(.:format)` | `show` | `C212.show` |

### Principal source-file index

Controller files are given in each controller section. This index resolves the downstream links used in the family and action-specific records; framework classes retain the installed-gem references above. It excludes the instructed template-body directory.

| Principal class/concern/service | Repository-relative source file |
|---|---|
| `Ability` | `app/models/ability.rb` |
| `AccessPoints::Catalog` | `app/services/access_points/catalog.rb` |
| `ActivityGenerator` | `app/services/activity_generator.rb` |
| `ActivityTracer` | `app/services/activity_tracer.rb` |
| `Admin::Domains::Directory` | `app/services/admin/domains/directory.rb` |
| `Admin::Domains::DirectoryComponent` | `app/components/admin/domains/directory_component.rb` |
| `Admin::Entities::ColumnsBuilder` | `app/services/admin/entities/columns_builder.rb` |
| `Admin::Entities::EntriesCsv` | `app/services/admin/entities/entries_csv.rb` |
| `Admin::Entities::FiltersBuilder` | `app/services/admin/entities/filters_builder.rb` |
| `Admin::Maintenance::SharedResourceMode` | `app/controllers/concerns/admin/maintenance/shared_resource_mode.rb` |
| `Admin::Pages::BrowseScope` | `app/services/admin/pages/browse_scope.rb` |
| `Admin::Pages::ColumnsBuilder` | `app/services/admin/pages/columns_builder.rb` |
| `Admin::Settings::MemberHubCardPresenter` | `app/presenters/admin/settings/member_hub_card_presenter.rb` |
| `Admin::Settings::MemberRowPresenter` | `app/presenters/admin/settings/member_row_presenter.rb` |
| `AiAssistant::Activities::ArchiveConversation` | `app/services/ai_assistant/activities/archive_conversation.rb` |
| `AiAssistant::Activities::CancelReply` | `app/services/ai_assistant/activities/cancel_reply.rb` |
| `AiAssistant::Activities::DeleteConversation` | `app/services/ai_assistant/activities/delete_conversation.rb` |
| `AiAssistant::Activities::DiscardProposal` | `app/services/ai_assistant/activities/discard_proposal.rb` |
| `AiAssistant::Activities::ListConversations` | `app/services/ai_assistant/activities/list_conversations.rb` |
| `AiAssistant::Activities::ListMentions` | `app/services/ai_assistant/activities/list_mentions.rb` |
| `AiAssistant::Activities::ListMessages` | `app/services/ai_assistant/activities/list_messages.rb` |
| `AiAssistant::Activities::Preflight` | `app/services/ai_assistant/activities/preflight.rb` |
| `AiAssistant::Activities::RegenerateLast` | `app/services/ai_assistant/activities/regenerate_last.rb` |
| `AiAssistant::Activities::RenameConversation` | `app/services/ai_assistant/activities/rename_conversation.rb` |
| `AiAssistant::Activities::Reply` | `app/services/ai_assistant/activities/reply.rb` |
| `AiAssistant::Activities::SendMessage` | `app/services/ai_assistant/activities/send_message.rb` |
| `AiAssistant::Activities::StartConversation` | `app/services/ai_assistant/activities/start_conversation.rb` |
| `AiAssistant::Activities::UndoWebsiteReply` | `app/services/ai_assistant/activities/undo_website_reply.rb` |
| `AiAssistant::Activities::UpdateProviderSettings` | `app/services/ai_assistant/activities/update_provider_settings.rb` |
| `AiAssistant::Assistant::ExecutionPolicy` | `app/services/ai_assistant/assistant/execution_policy.rb` |
| `AiAssistant::Assistant::GeneratePage` | `app/services/ai_assistant/assistant/generate_page.rb` |
| `AiAssistant::Assistant::GenerationWriteGuard` | `app/services/ai_assistant/assistant/generation_write_guard.rb` |
| `AiAssistant::Assistant::Tools::Session` | `app/services/ai_assistant/assistant/tools/session.rb` |
| `AiAssistant::Conversation` | `app/models/ai_assistant/conversation.rb` |
| `AiAssistant::Message` | `app/models/ai_assistant/message.rb` |
| `AiAssistant::MessageComponent` | `app/components/ai_assistant/message_component.rb` |
| `AiAssistant::MessageSending` | `app/controllers/concerns/ai_assistant/message_sending.rb` |
| `AiAssistant::ProviderSettings` | `app/models/ai_assistant/provider_settings.rb` |
| `AiAssistant::Providers` | `app/services/ai_assistant/providers.rb` |
| `AiAssistant::ReplyJob` | `app/jobs/ai_assistant/reply_job.rb` |
| `AiAssistant::TestConnectionJob` | `app/jobs/ai_assistant/test_connection_job.rb` |
| `Authentication::AuditLog` | `app/services/authentication/audit_log.rb` |
| `Authentication::ConsumeSignInLink` | `app/services/authentication/consume_sign_in_link.rb` |
| `Authentication::CredentialLifecycle` | `app/services/authentication/credential_lifecycle.rb` |
| `Authentication::CustomerSignup` | `app/services/authentication/customer_signup.rb` |
| `Authentication::CustomerSignupToken` | `app/services/authentication/customer_signup_token.rb` |
| `Authentication::EmailFloodThrottled` | `app/controllers/concerns/authentication/email_flood_throttled.rb` |
| `Authentication::Event` | `app/models/authentication/event.rb` |
| `Authentication::FinishesSignIn` | `app/controllers/concerns/authentication/finishes_sign_in.rb` |
| `Authentication::IssueCustomerSignup` | `app/services/authentication/issue_customer_signup.rb` |
| `Authentication::IssueSignInLink` | `app/services/authentication/issue_sign_in_link.rb` |
| `Authentication::IssuesSignInLink` | `app/controllers/concerns/authentication/issues_sign_in_link.rb` |
| `Authentication::LandingPath` | `app/services/authentication/landing_path.rb` |
| `Authentication::MfaEnrollment` | `app/controllers/concerns/authentication/mfa_enrollment.rb` |
| `Authentication::MfaObligation` | `app/services/authentication/mfa_obligation.rb` |
| `Authentication::MutationAudit` | `app/services/authentication/mutation_audit.rb` |
| `Authentication::NotifyExistingMember` | `app/services/authentication/notify_existing_member.rb` |
| `Authentication::OwnerAccountProtectable` | `app/controllers/concerns/authentication/owner_account_protectable.rb` |
| `Authentication::PasswordVerification` | `app/services/authentication/password_verification.rb` |
| `Authentication::PlatformSettings` | `app/models/authentication/platform_settings.rb` |
| `Authentication::RegisterMember` | `app/services/authentication/register_member.rb` |
| `Authentication::RequiresSignIn` | `app/controllers/concerns/authentication/requires_sign_in.rb` |
| `Authentication::Settings` | `app/services/authentication/settings.rb` |
| `Authentication::SignInFlow` | `app/services/authentication/sign_in_flow.rb` |
| `Authentication::Throttle` | `app/services/authentication/throttle.rb` |
| `Authentication::TrustedDevice` | `app/models/authentication/trusted_device.rb` |
| `Authentication::TrustedDeviceCookieable` | `app/controllers/concerns/authentication/trusted_device_cookieable.rb` |
| `Authentication::UniformTiming` | `app/services/authentication/uniform_timing.rb` |
| `Authentication::User` | `app/models/authentication/user.rb` |
| `Authentication::UserDomainProfiles` | `app/services/authentication/user_domain_profiles.rb` |
| `Billing::Activities::ApplyCoupon` | `app/services/billing/activities/apply_coupon.rb` |
| `Billing::Activities::AuthorizeInvoiceCollection` | `app/services/billing/activities/authorize_invoice_collection.rb` |
| `Billing::Activities::CancelPlanChange` | `app/services/billing/activities/cancel_plan_change.rb` |
| `Billing::Activities::CancelSubscription` | `app/services/billing/activities/cancel_subscription.rb` |
| `Billing::Activities::ChangePlan` | `app/services/billing/activities/change_plan.rb` |
| `Billing::Activities::CollectInvoice` | `app/services/billing/activities/collect_invoice.rb` |
| `Billing::Activities::MakeDefaultPaymentMethod` | `app/services/billing/activities/make_default_payment_method.rb` |
| `Billing::Activities::MarkInvoicePaid` | `app/services/billing/activities/mark_invoice_paid.rb` |
| `Billing::Activities::RemovePaymentMethod` | `app/services/billing/activities/remove_payment_method.rb` |
| `Billing::Activities::ResumeSubscription` | `app/services/billing/activities/resume_subscription.rb` |
| `Billing::Activities::SetUpPaymentMethod` | `app/services/billing/activities/set_up_payment_method.rb` |
| `Billing::Activities::Subscribe` | `app/services/billing/activities/subscribe.rb` |
| `Billing::Activities::UpdateSettings` | `app/services/billing/activities/update_settings.rb` |
| `Billing::Activities::VoidInvoice` | `app/services/billing/activities/void_invoice.rb` |
| `Billing::Catalog::ArchiveCoupon` | `app/services/billing/catalog/archive_coupon.rb` |
| `Billing::Catalog::ArchivePlan` | `app/services/billing/catalog/archive_plan.rb` |
| `Billing::Catalog::SaveCoupon` | `app/services/billing/catalog/save_coupon.rb` |
| `Billing::Catalog::SavePlan` | `app/services/billing/catalog/save_plan.rb` |
| `Billing::Catalog::UpdateCountableItems` | `app/services/billing/catalog/update_countable_items.rb` |
| `Billing::CollectionAttempt` | `app/models/billing/collection_attempt.rb` |
| `Billing::Collector` | `app/services/billing/collector.rb` |
| `Billing::Contracts::ChangePlan` | `app/services/billing/contracts/change_plan.rb` |
| `Billing::Contracts::Coupon` | `app/services/billing/contracts/coupon.rb` |
| `Billing::Contracts::PaymentMethod` | `app/services/billing/contracts/payment_method.rb` |
| `Billing::Contracts::Plan` | `app/services/billing/contracts/plan.rb` |
| `Billing::Contracts::Settings` | `app/services/billing/contracts/settings.rb` |
| `Billing::Contracts::Subscribe` | `app/services/billing/contracts/subscribe.rb` |
| `Billing::ControllerPresentation` | `app/controllers/concerns/billing/controller_presentation.rb` |
| `Billing::Countable::Registry` | `app/services/billing/countable/registry.rb` |
| `Billing::CountableItem` | `app/models/billing/countable_item.rb` |
| `Billing::Coupon` | `app/models/billing/coupon.rb` |
| `Billing::Entitlements` | `app/services/billing/entitlements.rb` |
| `Billing::Invoice` | `app/models/billing/invoice.rb` |
| `Billing::InvoicePaymentAction` | `app/services/billing/invoice_payment_action.rb` |
| `Billing::Pagination` | `app/controllers/concerns/billing/pagination.rb` |
| `Billing::PaymentAuthorization` | `app/services/billing/payment_authorization.rb` |
| `Billing::PaymentMethod` | `app/models/billing/payment_method.rb` |
| `Billing::Plan` | `app/models/billing/plan.rb` |
| `Billing::PlanChange` | `app/models/billing/plan_change.rb` |
| `Billing::PlanChangePolicy` | `app/services/billing/plan_change_policy.rb` |
| `Billing::Quota::Guard` | `app/services/billing/quota/guard.rb` |
| `Billing::Settings` | `app/models/billing/settings.rb` |
| `Billing::Subscription` | `app/models/billing/subscription.rb` |
| `Captcha::Activities::TestConnection` | `app/services/captcha/activities/test_connection.rb` |
| `Captcha::Activities::UpdateProviderSettings` | `app/services/captcha/activities/update_provider_settings.rb` |
| `Captcha::Activities::UpdateUrlThrottle` | `app/services/captcha/activities/update_url_throttle.rb` |
| `Captcha::Activities::Verify` | `app/services/captcha/activities/verify.rb` |
| `Captcha::Grant` | `app/services/captcha/grant.rb` |
| `Captcha::ProviderSettings` | `app/models/captcha/provider_settings.rb` |
| `Captcha::Providers` | `app/services/captcha/providers.rb` |
| `Captcha::RackGate` | `app/services/captcha/rack_gate.rb` |
| `Captcha::RequestPassage` | `app/services/captcha/request_passage.rb` |
| `Captcha::RequestReplayer` | `app/services/captcha/request_replayer.rb` |
| `Captcha::RequestSnapshot` | `app/services/captcha/request_snapshot.rb` |
| `Captcha::ReturnTo` | `app/services/captcha/return_to.rb` |
| `Captcha::SurfaceCatalog` | `app/services/captcha/surface_catalog.rb` |
| `Captcha::ThrottleRegistry` | `app/services/captcha/throttle_registry.rb` |
| `Captcha::UrlMatcher` | `app/services/captcha/url_matcher.rb` |
| `Captcha::VerificationContext` | `app/services/captcha/verification_context.rb` |
| `CodeGenerators::CodeIntrospector` | `app/services/code_generators/code_introspector.rb` |
| `CodeGenerators::FormDataExtractor` | `app/services/code_generators/form_data_extractor.rb` |
| `CodeGenerators::GeneratorInterface` | `app/services/code_generators/generator_interface.rb` |
| `CodeGenerators::GeneratorRegistry` | `app/services/code_generators/generator_registry.rb` |
| `CodeGenerators::GeneratorValidator` | `app/services/code_generators/generator_validator.rb` |
| `CodeGenerators::IndexPresenter` | `app/services/code_generators/index_presenter.rb` |
| `CodeGenerators::IoExtractor` | `app/services/code_generators/io_extractor.rb` |
| `CodeGenerators::PathIdentity` | `app/services/code_generators/path_identity.rb` |
| `CodeGenerators::ReferenceSources` | `app/services/code_generators/reference_sources.rb` |
| `CodeGenerators::SourceAssembler` | `app/services/code_generators/source_assembler.rb` |
| `CodeGenerators::TestRunner` | `app/services/code_generators/test_runner.rb` |
| `CompositePageRenderer` | `app/services/composite_page_renderer.rb` |
| `Constant` | `app/models/constant.rb` |
| `ConstantCustomerOverride` | `app/models/constant_customer_override.rb` |
| `ContextSanitizer` | `app/services/context_sanitizer.rb` |
| `ContractGenerator` | `app/services/contract_generator.rb` |
| `Current` | `app/models/current.rb` |
| `Customer` | `app/models/customer.rb` |
| `CustomerDocs::Catalog` | `app/services/customer_docs/catalog.rb` |
| `CustomerDocs::Repository` | `app/services/customer_docs/repository.rb` |
| `Customers::Purge` | `app/services/customers/purge.rb` |
| `Dashboard::Home` | `app/services/dashboard/home.rb` |
| `Dashboard::ModuleCards` | `app/services/dashboard/module_cards.rb` |
| `DashboardContext` | `app/services/dashboard_context.rb` |
| `DeveloperDocs::Catalog` | `app/services/developer_docs/catalog.rb` |
| `DeveloperDocs::Renderer` | `app/services/developer_docs/renderer.rb` |
| `DeveloperDocs::Repository` | `app/services/developer_docs/repository.rb` |
| `Email::Activities::AssignDelivery` | `app/services/email/activities/assign_delivery.rb` |
| `Email::Activities::SaveCredential` | `app/services/email/activities/save_credential.rb` |
| `Email::Contracts::Send` | `app/services/email/contracts/send.rb` |
| `Email::CredentialResolver` | `app/services/email/credential_resolver.rb` |
| `Email::Providers` | `app/services/email/providers.rb` |
| `Emails::Activities::Send` | `app/services/emails/activities/send.rb` |
| `Emails::Analytics::DateRange` | `app/services/emails/analytics/date_range.rb` |
| `Emails::Analytics::ExportCsv` | `app/services/emails/analytics/export_csv.rb` |
| `Emails::Analytics::Health` | `app/services/emails/analytics/health.rb` |
| `Emails::Analytics::Report` | `app/services/emails/analytics/report.rb` |
| `Emails::Audience::Contracts::SegmentRules` | `app/services/emails/audience/contracts/segment_rules.rb` |
| `Emails::Audience::List` | `app/models/emails/audience/list.rb` |
| `Emails::Audience::SaveList` | `app/services/emails/audience/save_list.rb` |
| `Emails::Audience::SegmentQuery` | `app/services/emails/audience/segment_query.rb` |
| `Emails::AuthorPreview` | `app/services/emails/author_preview.rb` |
| `Emails::BackendReceipt` | `app/models/emails/backend_receipt.rb` |
| `Emails::CompileTemplate` | `app/services/emails/compile_template.rb` |
| `Emails::Credential` | `app/models/emails/credential.rb` |
| `Emails::Cron::RecoverMessages` | `app/services/emails/cron/recover_messages.rb` |
| `Emails::DashboardStats` | `app/services/emails/dashboard_stats.rb` |
| `Emails::DeliverMessageJob` | `app/jobs/emails/deliver_message_job.rb` |
| `Emails::DeliveryHandoff` | `app/services/emails/delivery_handoff.rb` |
| `Emails::Gateway` | `app/services/emails/gateway.rb` |
| `Emails::Message` | `app/models/emails/message.rb` |
| `Emails::MessageAdmission` | `app/services/emails/message_admission.rb` |
| `Emails::MessageEvent` | `app/models/emails/message_event.rb` |
| `Emails::Quota` | `app/services/emails/quota.rb` |
| `Emails::ReceiptInbox` | `app/services/emails/receipt_inbox.rb` |
| `Emails::ReconcileMessagesJob` | `app/jobs/emails/reconcile_messages_job.rb` |
| `Emails::SendActivities::Build` | `app/services/emails/send_activities/build.rb` |
| `Emails::SendActivities::SendActivity` | `app/models/emails/send_activities/send_activity.rb` |
| `Emails::SendActivities::SendActivityJob` | `app/jobs/emails/send_activities/send_activity_job.rb` |
| `Emails::SendActivities::SendActivityUnsubscribe` | `app/services/emails/send_activities/send_activity_unsubscribe.rb` |
| `Emails::SendActivities::StartSendActivity` | `app/services/emails/send_activities/start_send_activity.rb` |
| `Emails::Suppression` | `app/models/emails/suppression.rb` |
| `Emails::Template` | `app/models/emails/template.rb` |
| `Emails::TemplateRenderer` | `app/services/emails/template_renderer.rb` |
| `Emails::TemplateToken` | `app/models/emails/template_token.rb` |
| `Emails::TemplateTokenCodec` | `app/services/emails/template_token_codec.rb` |
| `Emails::TemplateTokens::Operation::BulkCreate` | `app/concepts/emails/template_tokens/operation/bulk_create.rb` |
| `Emails::TemplateTokens::Operation::Destroy` | `app/concepts/emails/template_tokens/operation/destroy.rb` |
| `Emails::TemplateTokens::Operation::Update` | `app/concepts/emails/template_tokens/operation/update.rb` |
| `Emails::TemplateVersion` | `app/models/emails/template_version.rb` |
| `Emails::TokenCatalog` | `app/services/emails/token_catalog.rb` |
| `Emails::VariableContext` | `app/services/emails/variable_context.rb` |
| `Entities::Activities::CreateAssociationEntries` | `app/services/entities/activities/create_association_entries.rb` |
| `Entities::Activities::CreateEntry` | `app/services/entities/activities/create_entry.rb` |
| `Entities::Activities::EntryWriter` | `app/services/entities/activities/entry_writer.rb` |
| `Entities::Activities::UpdateAssociationEntry` | `app/services/entities/activities/update_association_entry.rb` |
| `Entities::Activities::UpdateEntry` | `app/services/entities/activities/update_entry.rb` |
| `Entities::Contracts::Definition` | `app/services/entities/contracts/definition.rb` |
| `Entities::DeleteEntry` | `app/services/entities/delete_entry.rb` |
| `Entities::DerivedExpressions` | `app/services/entities/derived_expressions.rb` |
| `Entities::DerivedValues` | `app/services/entities/derived_values.rb` |
| `Entities::EntryAssociations` | `app/services/entities/entry_associations.rb` |
| `Entities::EntryDisplay` | `app/services/entities/entry_display.rb` |
| `Entities::EntryForm` | `app/services/entities/entry_form.rb` |
| `Entities::PromoteVersion` | `app/services/entities/promote_version.rb` |
| `Entities::ReferenceOptions` | `app/services/entities/reference_options.rb` |
| `Entities::VersionHydrator` | `app/services/entities/version_hydrator.rb` |
| `Entity` | `app/models/entity.rb` |
| `EntityDefinitions::Capabilities` | `app/services/entity_definitions/capabilities.rb` |
| `EntityDefinitions::List` | `app/services/entity_definitions/list.rb` |
| `EntityDomain` | `app/models/entity_domain.rb` |
| `EntityDomainMembership` | `app/models/entity_domain_membership.rb` |
| `EntityDomainVisibility` | `app/services/entity_domain_visibility.rb` |
| `EntityDomains::Activities::Assign` | `app/services/entity_domains/activities/assign.rb` |
| `EntityDomains::Activities::Destroy` | `app/services/entity_domains/activities/destroy.rb` |
| `EntityDomains::Activities::Save` | `app/services/entity_domains/activities/save.rb` |
| `EntityDomains::Catalog` | `app/services/entity_domains/catalog.rb` |
| `EntityDomains::Layout` | `app/services/entity_domains/layout.rb` |
| `EntityEntry` | `app/models/entity_entry.rb` |
| `EntityEntryContract` | `app/contracts/entity_entry_contract.rb` |
| `EntityIndexSetting` | `app/models/entity_index_setting.rb` |
| `EntityIndexSettings::Operation::Update` | `app/concepts/entity_index_settings/operation/update.rb` |
| `EntityVersion` | `app/models/entity_version.rb` |
| `FeatureModules::CustomerAssignment` | `app/models/feature_modules/customer_assignment.rb` |
| `FeatureModules::ExitResolver` | `app/services/feature_modules/exit_resolver.rb` |
| `FeatureModules::HandoffCompletion` | `app/services/feature_modules/handoff_completion.rb` |
| `FeatureModules::Invocation` | `app/services/feature_modules/invocation.rb` |
| `FeatureModules::InvocationContext` | `app/controllers/concerns/feature_modules/invocation_context.rb` |
| `FeatureModules::Module` | `app/models/feature_modules/module.rb` |
| `FeatureModules::Payment::Provisioner` | `app/services/feature_modules/payment/provisioner.rb` |
| `FieldTemplate` | `app/models/field_template.rb` |
| `FieldTemplates::Create` | `app/services/field_templates/create.rb` |
| `FieldTemplates::Delete` | `app/services/field_templates/delete.rb` |
| `FieldTemplates::Update` | `app/services/field_templates/update.rb` |
| `Flowchart` | `app/models/flowchart.rb` |
| `FlowchartDocumenter` | `app/services/flowchart_documenter.rb` |
| `FlowchartInputOutputValidator` | `app/services/flowchart_input_output_validator.rb` |
| `FlowchartRuntime::Authentication` | `app/services/flowchart_runtime/authentication.rb` |
| `FlowchartRuntime::FormulaCompiler` | `app/services/flowchart_runtime/formula_compiler.rb` |
| `FlowchartRuntime::QueryBuilder` | `app/services/flowchart_runtime/query_builder.rb` |
| `FlowchartRuntime::WhereClauseBuilder` | `app/services/flowchart_runtime/where_clause_builder.rb` |
| `FlowchartServerValidator` | `app/services/flowchart_server_validator.rb` |
| `FlowchartVersion` | `app/models/flowchart_version.rb` |
| `GeneratorIoIntrospection` | `app/controllers/concerns/generator_io_introspection.rb` |
| `Help::Activities::AddMessage` | `app/services/help/activities/add_message.rb` |
| `Help::Activities::CreateRequest` | `app/services/help/activities/create_request.rb` |
| `Help::Activities::Resolve` | `app/services/help/activities/resolve.rb` |
| `Help::Activities::SendEmail` | `app/services/help/activities/send_email.rb` |
| `Help::AttachmentRules` | `app/services/help/attachment_rules.rb` |
| `IndustryTemplateMapping` | `app/models/industry_template_mapping.rb` |
| `IndustryTemplateMappingSeeder` | `app/services/industry_template_mapping_seeder.rb` |
| `Member::EntitySurfaceBuilder` | `app/services/member/entity_surface_builder.rb` |
| `Member::Mfa::Contracts::ResetRequest` | `app/concepts/member/mfa/contracts/reset_request.rb` |
| `Member::Mfa::Operation::ConsumeResetLink` | `app/concepts/member/mfa/operation/consume_reset_link.rb` |
| `Member::Mfa::Operation::Disable` | `app/concepts/member/mfa/operation/disable.rb` |
| `Member::Mfa::Operation::Enable` | `app/concepts/member/mfa/operation/enable.rb` |
| `Member::Mfa::Operation::RequestResetLink` | `app/concepts/member/mfa/operation/request_reset_link.rb` |
| `Member::Mfa::ResetToken` | `app/concepts/member/mfa/reset_token.rb` |
| `Member::Navigation` | `app/services/member/navigation.rb` |
| `Member::PageFilters` | `app/services/member/page_filters.rb` |
| `Member::Profiles::UpdateContract` | `app/contracts/member/profiles/update_contract.rb` |
| `Member::Settings::Operation::Update` | `app/concepts/member/settings/operation/update.rb` |
| `Member::Surfaces` | `app/services/member/surfaces.rb` |
| `ModelGenerator` | `app/services/model_generator.rb` |
| `ModuleEntriesResolver` | `app/services/module_entries_resolver.rb` |
| `ModuleModelDiscovery` | `app/services/module_model_discovery.rb` |
| `Notifications::Inbox` | `app/services/notifications/inbox.rb` |
| `Notifications::Stream` | `app/services/notifications/stream.rb` |
| `Oauth::AccessToken` | `app/models/oauth/access_token.rb` |
| `Oauth::AuthenticateResourceOwner` | `app/services/oauth/authenticate_resource_owner.rb` |
| `Oauth::AuthorizationCodeExchange` | `app/services/oauth/authorization_code_exchange.rb` |
| `Oauth::BearerAuthenticatable` | `app/controllers/concerns/oauth/bearer_authenticatable.rb` |
| `Oauth::Protocol` | `app/services/oauth/protocol.rb` |
| `Oauth::ServerMetadata` | `app/services/oauth/server_metadata.rb` |
| `Oauth::TokenIdentity` | `app/services/oauth/token_identity.rb` |
| `Oauth::Userinfo` | `app/services/oauth/userinfo.rb` |
| `Operations::Activities::Confirm` | `app/services/operations/activities/confirm.rb` |
| `Operations::Activities::Execute` | `app/services/operations/activities/execute.rb` |
| `Page` | `app/models/page.rb` |
| `PageContentGenerator` | `app/services/page_content_generator.rb` |
| `PageContentGenerator::DynamicOptionsResolver` | `app/services/page_content_generator/dynamic_options_resolver.rb` |
| `PageLaunchLifecycle` | `app/models/concerns/page_launch_lifecycle.rb` |
| `PageLayoutTemplates` | `app/services/page_layout_templates.rb` |
| `PageRendering` | `app/controllers/concerns/page_rendering.rb` |
| `PageShortcut` | `app/models/page_shortcut.rb` |
| `PageShortcuts::Activities::Destroy` | `app/services/page_shortcuts/activities/destroy.rb` |
| `PageShortcuts::Activities::Save` | `app/services/page_shortcuts/activities/save.rb` |
| `PageShortcuts::PathPolicy` | `app/services/page_shortcuts/path_policy.rb` |
| `PageShortcuts::PublicPath` | `app/services/page_shortcuts/public_path.rb` |
| `PageShortcuts::PublicPathContext` | `app/controllers/concerns/page_shortcuts/public_path_context.rb` |
| `PageShortcuts::Resolver` | `app/services/page_shortcuts/resolver.rb` |
| `PageShortcuts::RouteConstraint` | `app/controllers/concerns/page_shortcuts/route_constraint.rb` |
| `PageShortcuts::RouteContext` | `app/controllers/concerns/page_shortcuts/route_context.rb` |
| `PageShortcuts::TargetEligibility` | `app/services/page_shortcuts/target_eligibility.rb` |
| `PageTemplateApplier` | `app/services/page_template_applier.rb` |
| `PageVersion` | `app/models/page_version.rb` |
| `Pages::ActionResolver` | `app/services/pages/action_resolver.rb` |
| `Pages::Activities::CreateFromEntityVersion` | `app/services/pages/activities/create_from_entity_version.rb` |
| `Pages::AudienceGuard` | `app/services/pages/audience_guard.rb` |
| `Pages::ConfigurationComposer` | `app/services/pages/configuration_composer.rb` |
| `Pages::Continuation` | `app/services/pages/continuation.rb` |
| `Pages::FormHealth` | `app/services/pages/form_health.rb` |
| `Pages::FormParams` | `app/services/pages/form_params.rb` |
| `Pages::Prefill` | `app/services/pages/prefill.rb` |
| `Pages::PublicSubmission` | `app/services/pages/public_submission.rb` |
| `Pages::RulesEngine` | `app/services/pages/rules_engine.rb` |
| `Pages::VisibilityContract` | `app/contracts/pages/visibility_contract.rb` |
| `Payments::Activities::CancelSubscription` | `app/services/payments/activities/cancel_subscription.rb` |
| `Payments::Activities::Charge` | `app/services/payments/activities/charge.rb` |
| `Payments::Activities::HandleWebhook` | `app/services/payments/activities/handle_webhook.rb` |
| `Payments::Activities::PrepareAttempt` | `app/services/payments/activities/prepare_attempt.rb` |
| `Payments::Activities::Query` | `app/services/payments/activities/query.rb` |
| `Payments::Activities::Reconcile` | `app/services/payments/activities/reconcile.rb` |
| `Payments::Activities::Refund` | `app/services/payments/activities/refund.rb` |
| `Payments::Activities::VaultCard` | `app/services/payments/activities/vault_card.rb` |
| `Payments::Admin::GatewayConfigComponent` | `app/components/payments/admin/gateway_config_component.rb` |
| `Payments::Admin::GatewayGalleryComponent` | `app/components/payments/admin/gateway_gallery_component.rb` |
| `Payments::CheckoutComponent` | `app/components/payments/checkout_component.rb` |
| `Payments::Contracts::Charge` | `app/services/payments/contracts/charge.rb` |
| `Payments::CredentialResolver` | `app/services/payments/credential_resolver.rb` |
| `Payments::Cron::DownloadBills` | `app/services/payments/cron/download_bills.rb` |
| `Payments::DefaultGateway` | `app/models/payments/default_gateway.rb` |
| `Payments::Dispute` | `app/models/payments/dispute.rb` |
| `Payments::EligibleGateways` | `app/services/payments/eligible_gateways.rb` |
| `Payments::Gateway` | `app/services/payments/gateway.rb` |
| `Payments::Gateways` | `app/services/payments/gateways.rb` |
| `Payments::HandoffCompletion` | `app/services/payments/handoff_completion.rb` |
| `Payments::HandoffEntryComponent` | `app/components/payments/handoff_entry_component.rb` |
| `Payments::Member::PaymentMethodsComponent` | `app/components/payments/member/payment_methods_component.rb` |
| `Payments::Member::SubscriptionsComponent` | `app/components/payments/member/subscriptions_component.rb` |
| `Payments::MerchantAccount` | `app/models/payments/merchant_account.rb` |
| `Payments::Order` | `app/models/payments/order.rb` |
| `Payments::Payment` | `app/models/payments/payment.rb` |
| `Payments::PaymentMethod` | `app/models/payments/payment_method.rb` |
| `Payments::PlatformGateway` | `app/models/payments/platform_gateway.rb` |
| `Payments::ProcessWebhookEventJob` | `app/jobs/payments/process_webhook_event_job.rb` |
| `Payments::ReconciliationBill` | `app/models/payments/reconciliation_bill.rb` |
| `Payments::Refund` | `app/models/payments/refund.rb` |
| `Payments::ResultComponent` | `app/components/payments/result_component.rb` |
| `Payments::SetDefaultGateway` | `app/services/payments/set_default_gateway.rb` |
| `Payments::Subscription` | `app/models/payments/subscription.rb` |
| `Payments::WebhookDispatcher` | `app/services/payments/webhook_dispatcher.rb` |
| `Payments::WebhookEvent` | `app/models/payments/webhook_event.rb` |
| `People::Activities::CreateLinkedEntry` | `app/services/people/activities/create_linked_entry.rb` |
| `People::Link` | `app/services/people/link.rb` |
| `People::Ownership` | `app/services/people/ownership.rb` |
| `Platform::AnnouncementBannerComponent` | `app/components/platform/announcement_banner_component.rb` |
| `PlatformAnnouncement` | `app/models/platform_announcement.rb` |
| `PlatformAnnouncementDismissal` | `app/models/platform_announcement_dismissal.rb` |
| `PlatformAnnouncementRead` | `app/models/platform_announcement_read.rb` |
| `PlatformAnnouncements::Activities::Save` | `app/services/platform_announcements/activities/save.rb` |
| `PlatformAnnouncements::InboxResolver` | `app/services/platform_announcements/inbox_resolver.rb` |
| `PlatformAnnouncements::Resolver` | `app/services/platform_announcements/resolver.rb` |
| `PlatformAnnouncements::TargetRules` | `app/services/platform_announcements/target_rules.rb` |
| `Role` | `app/models/role.rb` |
| `RoleGrants::Operation::Update` | `app/concepts/role_grants/operation/update.rb` |
| `Roles::Operation::Create` | `app/concepts/roles/operation/create.rb` |
| `Roles::Operation::Destroy` | `app/concepts/roles/operation/destroy.rb` |
| `Roles::Operation::Update` | `app/concepts/roles/operation/update.rb` |
| `SafeReturnTo` | `app/controllers/concerns/safe_return_to.rb` |
| `SearchQuery` | `app/services/search_query.rb` |
| `SetLocale` | `app/controllers/concerns/set_locale.rb` |
| `SettingsContributor` | `app/services/settings_contributor.rb` |
| `Sms::Activities::AssignDelivery` | `app/services/sms/activities/assign_delivery.rb` |
| `Sms::Activities::Send` | `app/services/sms/activities/send.rb` |
| `Sms::Adapters` | `app/services/sms/adapters.rb` |
| `Sms::Audience::DeleteSegment` | `app/services/sms/audience/delete_segment.rb` |
| `Sms::Audience::FieldCatalog` | `app/services/sms/audience/field_catalog.rb` |
| `Sms::Audience::Preview` | `app/services/sms/audience/preview.rb` |
| `Sms::Audience::SaveSegment` | `app/services/sms/audience/save_segment.rb` |
| `Sms::Audience::Segment` | `app/models/sms/audience/segment.rb` |
| `Sms::BackendReceipt` | `app/models/sms/backend_receipt.rb` |
| `Sms::Campaign` | `app/models/sms/campaign.rb` |
| `Sms::CampaignRecipient` | `app/models/sms/campaign_recipient.rb` |
| `Sms::CampaignReportCsv` | `app/services/sms/campaign_report_csv.rb` |
| `Sms::Campaigns::Cancel` | `app/services/sms/campaigns/cancel.rb` |
| `Sms::Campaigns::DeleteDraft` | `app/services/sms/campaigns/delete_draft.rb` |
| `Sms::Campaigns::Launch` | `app/services/sms/campaigns/launch.rb` |
| `Sms::Campaigns::Preview` | `app/services/sms/campaigns/preview.rb` |
| `Sms::Campaigns::Report` | `app/services/sms/campaigns/report.rb` |
| `Sms::Campaigns::ReviewToken` | `app/services/sms/campaigns/review_token.rb` |
| `Sms::Campaigns::Run` | `app/services/sms/campaigns/run.rb` |
| `Sms::Campaigns::RunJob` | `app/jobs/sms/campaigns/run_job.rb` |
| `Sms::Campaigns::Save` | `app/services/sms/campaigns/save.rb` |
| `Sms::Campaigns::SchedulerJob` | `app/jobs/sms/campaigns/scheduler_job.rb` |
| `Sms::Campaigns::Snapshot` | `app/services/sms/campaigns/snapshot.rb` |
| `Sms::Campaigns::Unsubscribe` | `app/services/sms/campaigns/unsubscribe.rb` |
| `Sms::ConsentEvent` | `app/models/sms/consent_event.rb` |
| `Sms::Contact` | `app/models/sms/contact.rb` |
| `Sms::Contacts::Archive` | `app/services/sms/contacts/archive.rb` |
| `Sms::Contacts::Eligibility` | `app/services/sms/contacts/eligibility.rb` |
| `Sms::Contacts::RecordConsent` | `app/services/sms/contacts/record_consent.rb` |
| `Sms::Contacts::Save` | `app/services/sms/contacts/save.rb` |
| `Sms::Contacts::SyncEntity` | `app/services/sms/contacts/sync_entity.rb` |
| `Sms::Contracts::ConsentEvent` | `app/services/sms/contracts/consent_event.rb` |
| `Sms::Contracts::Contact` | `app/services/sms/contracts/contact.rb` |
| `Sms::Contracts::EntitySync` | `app/services/sms/contracts/entity_sync.rb` |
| `Sms::Contracts::Segment` | `app/services/sms/contracts/segment.rb` |
| `Sms::Contracts::Send` | `app/services/sms/contracts/send.rb` |
| `Sms::Credential` | `app/models/sms/credential.rb` |
| `Sms::CredentialResolver` | `app/services/sms/credential_resolver.rb` |
| `Sms::Cron::ReconcileMessages` | `app/services/sms/cron/reconcile_messages.rb` |
| `Sms::DeliverMessageJob` | `app/jobs/sms/deliver_message_job.rb` |
| `Sms::DeliveryHandoff` | `app/services/sms/delivery_handoff.rb` |
| `Sms::DeliveryProjection` | `app/services/sms/delivery_projection.rb` |
| `Sms::DispatchLimiter` | `app/services/sms/dispatch_limiter.rb` |
| `Sms::EntitySources` | `app/services/sms/entity_sources.rb` |
| `Sms::FormValues` | `app/services/sms/form_values.rb` |
| `Sms::Gateway` | `app/services/sms/gateway.rb` |
| `Sms::Message` | `app/models/sms/message.rb` |
| `Sms::MessageAdmission` | `app/services/sms/message_admission.rb` |
| `Sms::OptOut` | `app/models/sms/opt_out.rb` |
| `Sms::PlatformCredentialSave` | `app/services/sms/platform_credential_save.rb` |
| `Sms::PlatformParameters` | `app/controllers/concerns/sms/platform_parameters.rb` |
| `Sms::Quota` | `app/services/sms/quota.rb` |
| `Sms::ReceiptInbox` | `app/services/sms/receipt_inbox.rb` |
| `Sms::ReconcileMessagesJob` | `app/jobs/sms/reconcile_messages_job.rb` |
| `Sms::RequestAttributes` | `app/services/sms/request_attributes.rb` |
| `Sms::SendStandards` | `app/services/sms/send_standards.rb` |
| `Sms::Template` | `app/models/sms/template.rb` |
| `SoftDeletable` | `app/models/concerns/soft_deletable.rb` |
| `SoftDeletableController` | `app/controllers/concerns/soft_deletable_controller.rb` |
| `SpeechToText::Activities::EnqueueTranscription` | `app/services/speech_to_text/activities/enqueue_transcription.rb` |
| `SpeechToText::Activities::ShowTranscription` | `app/services/speech_to_text/activities/show_transcription.rb` |
| `SpeechToText::Activities::Transcribe` | `app/services/speech_to_text/activities/transcribe.rb` |
| `SpeechToText::AudioProbe` | `app/services/speech_to_text/audio_probe.rb` |
| `SpeechToText::Clip` | `app/models/speech_to_text/clip.rb` |
| `SpeechToText::TranscribeJob` | `app/jobs/speech_to_text/transcribe_job.rb` |
| `SpeechToText::TranscriptionEnqueueing` | `app/controllers/concerns/speech_to_text/transcription_enqueueing.rb` |
| `SupportTicket` | `app/models/support_ticket.rb` |
| `SupportTicketMessage` | `app/models/support_ticket_message.rb` |
| `SupportTicketRead` | `app/models/support_ticket_read.rb` |
| `TemplateFieldExtractor` | `app/services/template_field_extractor.rb` |
| `TemplatePreviewBuilder` | `app/services/template_preview_builder.rb` |
| `ThemeResolver` | `app/components/concerns/theme_resolver.rb` |
| `UserRoles::AssignmentPolicy` | `app/services/user_roles/assignment_policy.rb` |
| `UserRoles::Operation::Assign` | `app/concepts/user_roles/operation/assign.rb` |
| `UsersRole` | `app/models/users_role.rb` |
| `Versionable` | `app/models/concerns/versionable.rb` |
| `WebhookCredentialBinding` | `app/services/webhook_credential_binding.rb` |
| `Website` | `app/models/website.rb` |
| `WebsiteLayout` | `app/models/website_layout.rb` |
| `WebsitePage` | `app/models/website_page.rb` |
| `WebsiteSkeleton` | `app/models/website_skeleton.rb` |
| `Websites::Activities::DestroyPage` | `app/services/websites/activities/destroy_page.rb` |
| `Websites::Activities::ReorderPages` | `app/services/websites/activities/reorder_pages.rb` |
| `Websites::Activities::ReplaceSkeleton` | `app/services/websites/activities/replace_skeleton.rb` |
| `Websites::Activities::SaveLayout` | `app/services/websites/activities/save_layout.rb` |
| `Websites::Activities::SavePage` | `app/services/websites/activities/save_page.rb` |
| `Websites::Activities::SaveSite` | `app/services/websites/activities/save_site.rb` |
| `Websites::Activities::SaveSkeleton` | `app/services/websites/activities/save_skeleton.rb` |
| `Websites::Activities::UploadMedia` | `app/services/websites/activities/upload_media.rb` |
| `Websites::Assistant::Processor` | `app/services/websites/assistant/processor.rb` |
| `Websites::Assistant::Undo` | `app/services/websites/assistant/undo.rb` |
| `Websites::Catalog` | `app/services/websites/catalog.rb` |
| `Websites::CatalogPreview` | `app/controllers/concerns/websites/catalog_preview.rb` |
| `Websites::CurrentSite` | `app/controllers/concerns/websites/current_site.rb` |
| `Websites::HomeSiteLocalization` | `app/services/websites/home_site_localization.rb` |
| `Websites::MediaPolicy` | `app/services/websites/media_policy.rb` |
| `Websites::Theme` | `app/services/websites/theme.rb` |

### Appendix coverage verification

- Inventory ledger: **724 exact route entries**; each R-number occurs once and matches its JSON verb/path/controller/action, including the single `PUT|PATCH` entry.
- Routed controller identifiers: **212**, each present verbatim in a backticked controller heading; all application controller files resolve and Rails Health is the documented gem exception.
- Action source records: **545 unique controller/action pairs**; every ledger source-chain ID resolves to the matching controller/action record, and every record has a nonempty principal trace.
- Missing controllers, controller/action pairs and route entries: **0 / 0 / 0**; unexpected or duplicate ledger entries: **0**.
- Exactness check compares route records in original JSON order by R-number, so identical verb/path entries with different root destinations are retained. Format suffixes, nested parameter names, remounts, aliases and installed Devise/Doorkeeper expansion are included without macro inference.
- Commands used for this append: `python /tmp/opencode/route_appendix_probe.py` (static controller summary/original-prefix hash); `python /tmp/opencode/route_appendix_build.py` (scratch candidate and manifest); `python /tmp/opencode/route_appendix_verify.py` (JSON-to-Markdown coverage, source references and original-prefix hash); `bundle exec ruby /tmp/opencode/route_appendix_markdown_check.rb doc/route-audit-findings.md` (GFM table shape/visible verb check); `git diff --stat -- doc/route-audit-findings.md`; `git status --short`. Repository publication is through `apply_patch`.
- Verification is static/documentary. The original findings prefix is preserved byte-for-byte. No provider, database, server or application-test execution is represented by these checks.

<!-- route-appendix-publication: verified -->
