# RSpec completion verification — 2026-10-11

**FAIL: 25,053 examples, 442 failures across 121 failing files; 1,561 spec files dispatched to four workers.** One complete suite execution; no serial fallback or suite rerun. All four workers finished. No pending examples or errors outside examples were reported. Derived passing examples: 24,611.

## Commands and evidence

The initially requested command was executed:

```bash
unset TEST_DATABASE SKIP_AUTH && bin/rails parallel:prepare && bin/rails parallel:spec
```

It stopped in preparation, before any examples, because the default development database had three pending migrations: `20261011000100`, `20261011173041`, and `20261011184517`. The installed parallel tasks check pending migrations in the invoking Rails environment (`parallel_tests-5.7.0/lib/parallel_tests/tasks.rb:66,199,300`); this was a preparation failure, not unavailable parallel support.

The successful preparation and single full-suite execution used the final schema in the disposable worker databases:

```bash
unset TEST_DATABASE SKIP_AUTH && export RAILS_ENV=test && bin/rails parallel:load_schema && bin/rails parallel:prepare && bin/rails parallel:spec
```

`nproc` returned `4`. Both environment overrides were unset for preparation and testing. Schema version: `20261011184517` (`db/schema.rb:13`). The commands loaded test schemas; no development/production migration command was issued.

Complete raw stdout/stderr, saved automatically by the terminal tool without shell redirection:

`/home/ec2-user/.local/share/opencode/tool-output/tool_12bdddc3d001cia3UryrnDB3wk`

The raw log has 14,451 lines. Its four result sections and final aggregate are:

| Completion order | Examples | Failures | Raw log line |
| --- | ---: | ---: | ---: |
| 1 | 5,538 | 92 | 4597 |
| 2 | 5,925 | 145 | 8650 |
| 3 | 5,924 | 95 | 11442 |
| 4 | 7,666 | 110 | 14332 |
| Total | **25,053** | **442** | **14449** |

Parallel runner elapsed time: **770 seconds (12:50)**, log line 14451. Worker numbers are not printed with those result sections; completion order is not worker identity. Raw failed-example lists begin at lines **4599, 8652, 11444, 14334**.

## Area totals

Each failed example is counted once by its feature/spec area. Cross-area causes are described below; these totals are not independent root-cause counts. Harness here comprises the missing-Warden, runtime-flowchart double, and ambiguous Configure-link failures. Other mock/fixture failures retain their feature area.

| Area | Failures | Failing files |
| --- | ---: | ---: |
| Billing | 146 | 34 |
| Auth / OAuth | 32 | 11 |
| Payments | 23 | 8 |
| Email / SMS | 12 | 7 |
| Captcha | 5 | 4 |
| Core | 122 | 27 |
| Runtime / page rendering | 53 | 14 |
| Website | 6 | 4 |
| AI + STT | 37 | 8 |
| Harness | 6 | 4 |
| **Total** | **442** | **121** |

Failure-heading breakdown (top-level headings only; underlying causes are not double-counted): `NoMethodError` 117; `NameError` 50; `ArgumentError` 28; `ActionView::Template::Error` 27; `ActiveRecord::RecordInvalid` 11; `RecordNotFound` 7; `NotNullViolation` 6; `Payments::Errors::CredentialsMissing` 5; `RecordNotUnique` 3; `Payments::Errors::TenantNotFound` 2; `Capybara::Ambiguous` 2; `Devise::MissingWarden` 1; assertion/mock-expectation failures 183. Total: 442. Exceptions caught by an assertion are included in the assertion category.

## Grouped failure details

These are observed causes or expectation mismatches, not fixes. For boolean-only assertions where the log does not identify a deeper exception, that limitation is explicit. Representative selectors below are supplemented by the exhaustive inventory in the next section. `log:L` refers to the raw file above.

### Billing

1. **Reform form API mismatch (54 failures).** Opening coupon/plan/settings forms, subscription screens, or re-rendering rejected billing commands calls `form.attributes`, which these Reform contracts do not implement. Production triggers: `app/components/billing/admin/presentation.rb:34`, `customer_subscription_component.rb:60`, and `customer_subscription_component.html.erb:154`. Examples: `spec/components/billing/admin/coupon_form_component_spec.rb:125`, `spec/components/billing/admin/plan_form_component_spec.rb:116`, `spec/requests/admin/settings/modules/billing/cancellations_spec.rb:84`. First excerpt: `NoMethodError: undefined method 'attributes' for Billing::Contracts::Coupon` (log:560–568).
2. **ActiveModel constant shadowing (44 failures).** Plan validation/seeding/default replacement and countable-item updates resolve `ActiveModel` through the inherited `Reform::Form::ActiveModel`, then cannot find `Type`. Production triggers: `app/services/billing/contracts/plan.rb:74`, `app/services/billing/catalog/update_countable_items.rb:20,25`. Examples: `spec/models/billing/plan_spec.rb:77`, `spec/services/billing/contracts/plan_spec.rb:16`, `spec/services/billing/standard_plans_spec.rb:13`, `spec/services/billing/catalog/commands_spec.rb:52`. Excerpt: `NameError: uninitialized constant Reform::Form::ActiveModel::Type` (log:752–762).
3. **Collection invoked with a transaction open (16 failures).** Subscribe/change-plan/reenrollment paths reach the collector while its connection still reports a transaction, raising `collection must run after domain commit`. Production gate: `app/services/billing/collector.rb:24`; callback path: `app/services/billing/result.rb:39–41`. Transactional fixtures are relevant to interpreting this gate; the run does not establish that every occurrence reproduces without the fixture transaction. Examples: `spec/services/billing/activities/subscribe_spec.rb:15`, `spec/services/billing/activities/change_plan_spec.rb:9`, `spec/services/billing/lifecycle_integration_spec.rb:53`, `spec/requests/admin/settings/billing/subscriptions_spec.rb:134` (log:7797,13761).
4. **Lifecycle fixture/state mismatches.** Three presentation examples directly insert plan changes without required `period_end` (schema rejects them; log:831,12643,12742). Two invoice-download/print fixtures mutate issued financial terms, rejected by `app/models/billing/invoice.rb:67–69`. Three lifecycle examples create the pinned owner again and fail email uniqueness (`spec/services/billing/lifecycle_integration_spec.rb:8`; log:13810). Coupon/discount examples create a redemption but keep the association's earlier cached nil; `app/services/billing/activities/apply_coupon.rb:10,24–26` reads that association before creating its row. Selectors: platform `presentation_spec.rb:127`, tenant `presentation_spec.rb:70,134`, tenant `invoices_spec.rb:121`, `invoice_print_layout_spec.rb:11`, `apply_coupon_spec.rb:8,27`, `discounts_spec.rb:15`.
5. **Billing presentation/scope/mock expectations.** Invoice-table tests count two Uncollectible labels but the new filter adds a third (`spec/components/billing/admin/invoice_table_component_spec.rb:251`; log:4761). Invoice-detail doubles omit `errors`, now used by `app/components/billing/admin/presentation.rb:42` (three failures). Catalog expects Unlimited while missing limits display 0; fallback usage expects `12 / 10` but renders `— / 0`. Payment-method mocks expect `example.com`, while controller URLs use `www.example.com` (`payment_methods_controller.rb:34,89`; three failures, log:922–997). Other scope assertions receive 404 instead of 403 or 401 instead of 404. Countable-registry isolation expects 0 entities but gets 1. Alipay's negative partial-double expectation targets removed `post_json` (`spec/services/billing/providers/alipay_spec.rb:15`), failing before provider execution.

### Auth / OAuth

6. **Signup/admin creation denied before successful persistence.** Ordinary tenant signup and admin-created member examples receive 422, create no user, and send no confirmation email. The finite fallback is 0 when no valid free default exists (`app/services/billing/entitlements.rb:32–39`); create guards run in `app/controllers/admin/modules/authentication/users_controller.rb:89–99` and the registration create path. Selectors: `spec/requests/authentication/admin/users_spec.rb:218,224,236,242,248`, `spec/requests/authentication/registrations_spec.rb:44,56,70,83,95`, `spec/system/member/sign_up_spec.rb:25`. The nil-user failures are downstream of that denial (log:9089,12836).
7. **Quota expectations do not match accepted entitlement snapshots/member-role usage.** Five signup/admin quota examples expect no new user but one is persisted (log:9855,12869). Limits now come from the accepted subscription snapshot (`app/services/billing/entitlements.rb:42–45`), and member usage counts member assignments rather than every seeded admin. Selectors: admin users `:696,704,721`; registrations `:434,446`. These failures are preserved as quota regressions/expectation mismatches requiring review, not treated as passes.
8. **Auth API, role, labels, and navigation expectations.** Seven request assertions directly call protected Devise `controller.resource` and raise `NoMethodError` (passwords `:249`; registrations `:227,[1:5:3],[1:5:4],[1:5:5],:254,:269`; log:9813,12892). Two fixtures assign both admin and member, rejected by the single-reserved-role invariant (landing path `:26`, sign-in flow `:69`). Two translated grant-label examples have 145 descriptors but 144 unique names (`grant_route_label_spec.rb:20`, log:11545). Member security expects the old unscoped reset URL (`spec/system/member/security_spec.rb:16`).
9. **Idle-session enforcement.** After three idle minutes, the short-policy tenant session still redirects to its member area rather than `/auth/sign_in`. Selector: `spec/requests/authentication/tenant_security_policy_spec.rb:22`; assertion line 36 (log:1004). Production area: `Authentication::User::TenantSecurityPolicy` and Devise session timeout integration. The assertion alone does not identify which session timestamp/policy integration is responsible.
10. **InvalidGrant exception construction.** Stale authorization-code exchange and rollback tests raise `ArgumentError: wrong number of arguments (given 0, expected 1)` instead of `Doorkeeper::Errors::InvalidGrant`. Production trigger: `app/services/oauth/authorization_code_exchange.rb:16`; one rollback test independently raises the same class without its required argument at `spec/services/oauth/authorization_code_exchange_spec.rb:54`. Selectors: that file `:34,49`, `spec/requests/oauth/pkce_flow_spec.rb:398` (log:1353,13710).

### Payments

11. **Stripe SDK header interface (13 failures).** HTTP decline/authentication/retry/refund/query/settings errors call `any?` on `Stripe::StripeResponseHeaders`, which does not implement it. Production statement: `app/services/payments/gateways/stripe.rb:465` (trace reports :464). This masks ApiError/TransportError/OrderInFlight expectations and the billing authorization retry path. Selectors include `spec/services/payments/gateways/stripe_spec.rb:377,389,399,574,636`, its four HTTP-status examples at :408, `retry_age_spec.rb:72`, `billing_integration_spec.rb:51`, both gateway-settings examples `:246`. Excerpt: `undefined method 'any?' for Stripe::StripeResponseHeaders` (log:8395,14214).
12. **Historical/new-operation merchant binding.** Historical query/refund/close/reconcile examples cannot resolve the stored merchant identity and raise CredentialsMissing at `app/services/payments/credential_resolver.rb:70`. Billing setup rejects its requested account as unavailable for new operations at `app/services/payments/gateway.rb:179`. Selectors: `spec/services/payments/activities/historical_operations_spec.rb:27,40,56,65`; `spec/services/billing/activities/set_up_payment_method_spec.rb:9` (counted in Billing). Log:8349–8393,7845.
13. **Stripe webhook lookup precedes dispute/refund correlation.** Four no-metadata/no-Connect fixtures reach `app/services/payments/credential_resolver.rb:29` with blank merchant ID. Two expect SignatureInvalid but receive TenantNotFound; two intended valid events raise TenantNotFound. Selectors: `spec/requests/payments/webhooks_stripe_spec.rb:369,403,450,481` (log:1064–1116).
14. **Authorization/default and checkout expectations.** A verified SetupIntent on a disabled historical account activates the method but does not mark it default: readiness gates default assignment at `app/services/billing/payment_authorization.rb:133–139`; `spec/services/payments/activities/billing_integration_spec.rb:24` (log:8325). Checkout expects a save-card checkbox removed from the widget render: `spec/requests/payments/checkouts_spec.rb:341`, production `app/components/payments/widget_checkout_component.html.erb` (log:9873).

### Email / SMS

15. **Template-version payload violates body_html constraint.** Reloading/promoting a template head whose payload omits HTML writes nil into the non-null `email_templates.body_html` column. Production trigger: `app/models/emails/template.rb:128`; selectors: `spec/requests/admin/modules/emails/template_versions_spec.rb:75,108,200` (log:870–920).
16. **Delivery/reaper/race harness expectations.** Reconcile job expects one re-drive but enqueues none; the cron now requires an enabled Email module and evaluates deferral/dead-letter state at `app/services/emails/send_activities/cron/reconcile_send_activities.rb:13–27` (`reconcile_send_activities_job_spec.rb:16`). Scheduled dispatch loses sub-microsecond timestamp precision (`spec/services/emails/activities/send_spec.rb:204`, log:8187). Email's race spec permanently stubs `existing_message` to nil, including the rescue lookup, so RecordNotUnique re-raises at `app/services/emails/persist_message.rb:26–28` (`persist_message_spec.rb:37`). Two SMS synthetic-race tests similarly re-raise at `app/services/sms/activities/send.rb:102` (`send_spec.rb:88,284`; log:8545).
17. **Email list/template rendering expectations.** List and template row tests reject the present `menu-placement` controller. Template subtitle expects `{{First name}}`, and preview expects a cid blob URL replacement that is absent. Selectors: `spec/requests/admin/modules/emails/lists_spec.rb:32`, `templates_spec.rb:48,77,433`; production areas: their index components and template preview compilation (`log:5804,5809,7584,7589`). These are rendered-output mismatches; the log does not demonstrate a delivery failure.

### Captcha

18. **Aliyun fixture omits required identity credential.** Two settings tests submit scene/credentials without `prefix`; provider readiness now requires both scene and prefix (`app/services/captcha/providers/aliyun.rb:47–51`), so `ProviderSettings.active` is nil. Selectors: `spec/requests/admin/maintenance/platform/captcha/settings_spec.rb:83,88`; assertions :85,:97 (log:12525).
19. **Dotted alias and fail-open continuation expectations.** `/join.html` matching returns nil (`app/services/captcha/url_matcher.rb`; `spec/services/captcha/page_shortcut_matching_spec.rb:164`). The one-use GET continuation lacks `X-Captcha-Result: false` (`spec/requests/captcha/url_throttle_gate_spec.rb:165`); the public-page outage test expects a challenge redirect but gets 200 (`spec/requests/public_pages_captcha_spec.rb:82`). Production boundaries: `Captcha::UrlMatcher`, `Captcha::RackGate`, and `Captcha::RequestPassage`; evidence log:1014,1214,13726.

### Core

20. **Entity definition parameter enumeration (54 failures).** Entity create/update/shared-resource/shape/history/browser-save paths enumerate an `ActionController::Parameters` object using unsupported `each_with_object`. Production trigger: `app/controllers/admin/maintenance/entities_controller.rb:245`. Includes the route-audit malformed-body matrix and entity grouping browser error; representative selector `spec/requests/admin/maintenance/entities_spec.rb:144`, all inventory rows below retain exact selectors. Excerpt: `undefined method 'each_with_object' for ActionController::Parameters` (log:846,4907,11612,14247).
21. **Entity lineage/restoration status expectations.** Foreign historical lineage and tenant promotion of a shared default receive 422 where specs require 404 (`entities_route_audit_spec.rb:87`, `entity_lifecycle_route_audit_spec.rb:64`; log:5300,12420). Restoration collision reports success rather than no notice (`entities_route_audit_spec.rb:144`, log:4900). Production areas: `Admin::Maintenance::EntitiesController`, `EntityVersionsController`, and base restoration. These are distinct from the parameter exception.
22. **Page creation blocked by zero fallback quota.** Maintenance page-create examples create no page; entity-version generation returns explicit `error_code=:quota` and “limit of 0 Pages,” cascading to missing-page/version request assertions. Production gate: `app/services/pages/activities/create_from_entity_version.rb:35–37`, fallback `app/services/billing/entitlements.rb:32–39`. Selectors: all 17 failures in `spec/requests/admin/maintenance/pages_spec.rb`, five in `spec/requests/maintenance/entity_versions_spec.rb`, 13 in `spec/services/pages/activities/create_from_entity_version_spec.rb`. Excerpt log:1391–1458.
23. **Help constant namespace collision (6 failures).** Help email/ticket/reply/resolution controllers refer to `Help::Activities`, resolving `Admin::Help::Activities` rather than the top-level service namespace. Production triggers: `app/controllers/admin/help_emails_controller.rb:6`, `support_tickets_controller.rb:18`, `support_ticket_messages_controller.rb:9`, and platform support-message/resolution controllers :11. Selectors: `spec/requests/admin/help_emails_spec.rb:9`, tenant `support_tickets_spec.rb:40,47,80`, platform `support_tickets_spec.rb:57,66` (log:9010,12787).
24. **Core navigation, locales, and public tenancy expectations.** Developer-doc language links/denial redirects omit the expected locale query (developer docs `:41`, help docs two IDs at template :695). Module crumbs fail the expected tenant hub href (`page_component_spec.rb:33,64`, resolver `app/components/admin/modules/page_component.rb:54–63`). Shared settings shell order/details differ; dashboard action ordering and two Home-label assertions differ. Public shortcut signed-in foreign visitors now get 200 and a form write succeeds, while three tests require rejection (`page_shortcuts_spec.rb:211,224,396`); this follows public-route openness at `app/controllers/concerns/tenant_context.rb:165,200–208`. Member surface no longer retains the submitted blank sentinel (`member_surfaces_spec.rb:50`). Exact locations are below (log:1046,5791,9054,10687).
25. **Schema/JSON/announcement invariants.** Missing slugs/malformed attribute groups/association entries are rejected where older EntityEntry/schema tests permit them (contract `:343`, entity entry `:372`, schema validation `:195,201,294`). JsonSerializable expects [] but gets nil (`json_serializable_spec.rb:113`; getter default at `app/models/concerns/json_serializable.rb:44,68–69`). A scheduled announcement is retained where the test expects hard deletion (`platform_announcement_spec.rb:254`). Audience wildcard fixture fails provisioned email validation (`backend_audience_spec.rb:80`, production `app/services/feature_modules/authentication/provisioner.rb:31`). Invalid selected-rule message differs (`contracts/announcement_spec.rb:104`). Evidence log:764,4864–4884,8523,11363,11572–11596.

### Runtime / page rendering

26. **Field visibility boundary removes expected generated fields.** Bound fields without a matching visible accessible entity schema are omitted at `app/services/page_content_generator.rb:273–274`, via `app/services/pages/form_params.rb:38–45,119–124`. Generator/calculation/theme/safety/member-page tests consequently get empty form bodies or missing component/field-ID output. Four escaping tests additionally use a Page double missing the newly read `entity` method. Selectors include `spec/services/page_content_generator_spec.rb:36`, `page_content_generator_calculated_spec.rb:39`, `conditions_escape_spec.rb:61`, `spec/models/page_spec.rb:356`, `spec/requests/member/pages_spec.rb:148`, `spec/system/form_conditions_spec.rb:153` (log:8985,10798,13954).
27. **Ruby positional-hash/keyword invocation mismatch.** Ten calculation/rules examples call positional `values` APIs with keyword-style hashes, raising `(given 0, expected 1)` at `app/services/pages/rules_engine.rb:52,110`. SaveAll has the same mismatch for positional `ctx` at `app/services/activity_steps/save_all.rb:21`. Selectors: `spec/services/pages/rules_engine_runtime_spec.rb:10,16,25,32,43,49,58`, `rules_engine_spec.rb:145,229,566`, `spec/services/activity_steps/save_all_spec.rb:34` (log:1460,7779,8199).
28. **Runtime output/validation expectation drift.** Nested-loop validation emits localized “Nested loops are not supported,” not the internal `nested_loop` token (`spec/services/activity_generator_loop_integration_spec.rb:335`, log:13731). Composite width is responsive `col-span-12 md:col-span-6`, not `col-span-6` (`spec/integration/composite_page_integration_spec.rb:47`, log:8925). Public handoff rollback fixture writes `name` outside its entity data allowlist and is rejected before submission (`spec/requests/public_pages_submission_spec.rb:109`, log:10523).

### Website

29. **Media import lacks source bytes in this run.** Import of a generated image returns no blob, and disguised HTML returns generic upload failure instead of image-type rejection (`spec/services/websites/activities/import_media_spec.rb:18,139`; log:1514–1528). Production `app/services/websites/activities/import_media.rb:51,64–65` maps ActiveStorage::FileNotFoundError to that generic failure. Parallel storage interference is a possible follow-up, not proven by this log.
30. **Section-contract and public-guard mismatches.** SavePage overlay returns false after sanitization decorates incoming sections before the locked-section overlay (`app/services/websites/activities/save_page.rb:83–85,113–135`; `save_page_spec.rb:120`). Two assistant array-bound tests now also receive “Props must be valid JSON” from `app/services/websites/contracts/section.rb:35–39` / `PropSchema` bounds and `assistant/schema_validator.rb:264–268` (`schema_validator_spec.rb:234,243`). Signed-in foreign public website reads return 200 under the public tenancy policy instead of redirect (`spec/requests/websites/public_pages_spec.rb:145`, `TenantContext:165`; log:7774,11373,14232).

### AI + STT

31. **AI entity/page generation and pending-reply expectations.** AI entity writes and their page/flowchart follow-ons fail under zero entity/page fallback limits; observed messages say “limit of 0 Entities” and expected writes/effects are absent. Production writer path: `app/services/entity_definitions/persist.rb:79–90`, page quota gate `CreateFromEntityVersion:35–37`. One EntityReference error assertion expects the class token rather than the new localized bridge-only message; update/self-repair assertions also differ. All 34 failing AI definition/reply/generate-page/session examples are retained below. Desktop message polling separately expects `pending_reply=true` but gets false (`spec/requests/admin/assistant/messages_spec.rb:81`, log:4886). Evidence log:1118–1174,1277–1289,10706–10796. Not every boolean-only AI assertion supplies a more specific cause in the log.
32. **STT retention and localized availability.** Finished-clip pruning checks `updated_at`, whereas the failing example makes only creation age old (`app/jobs/speech_to_text/prune_clips_job.rb:23`; `spec/jobs/speech_to_text/prune_clips_job_spec.rb:51`, log:747). Disabled-module enqueue error does not contain the older “not available” phrase (`spec/services/speech_to_text/activities/enqueue_transcription_spec.rb:86`, log:11368); this is wording delivery, not an audio-provider exception.

### Harness

33. **Missing request context, invalid doubles, and ambiguous selectors (6 failures).** Component flow editor link reads `helpers.current_user` without Warden (`app/components/page_builder/flow_item_component.rb:38`; `spec/components/page_builder/flows_section_component_spec.rb:112`). Three child-lookup tests construct a verifying RuntimeFlowchart double with an unsupported `id` method (`spec/services/concerns/activity_class_builder_spec.rb:82`; examples :87,:93,:100). Two system tests find two visible Configure links in their broad section scopes (`spec/system/admin/settings/member_entities_spec.rb:11`, `members_spec.rb:16`; assertions :18,:21). Evidence log:732,8157,8569,14239. No examples were skipped or deleted.

## Exhaustive failed-example inventory

Paths are repository-relative. Append each selector to its file for the exact selector printed by RSpec; bracket IDs distinguish generated examples sharing one source line. The last column provides that shared example definition line where RSpec printed IDs instead of line numbers. This inventory contains **all 442 selectors in all 121 failing files**; it is not a sampled list.

### Billing — 146

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 13 | `spec/components/billing/admin/coupon_form_component_spec.rb` | `:125, :46, :50, :54, :58, :62, :66, :70, :76, :85, :89, :93, :109` | |
| 1 | `spec/components/billing/admin/customer_subscription_component_spec.rb` | `:63` | |
| 3 | `spec/components/billing/admin/invoice_detail_component_spec.rb` | `:282, :150, :240` | |
| 7 | `spec/components/billing/admin/invoice_table_component_spec.rb` | `[1:14], [1:15], [1:16], [1:17], [1:18], [1:19], [1:20]` | 251 |
| 1 | `spec/components/billing/admin/plan_catalog_component_spec.rb` | `:179` | |
| 11 | `spec/components/billing/admin/plan_form_component_spec.rb` | `:116, :41, :47, :51, :58, :62, :71, :75, :80, :91, :110` | |
| 3 | `spec/components/billing/admin/settings_form_component_spec.rb` | `:9, :17, :32` | |
| 1 | `spec/models/billing/plan_spec.rb` | `:77` | |
| 3 | `spec/models/customer_spec.rb` | `:472, :482, :495` | |
| 2 | `spec/requests/admin/maintenance/platform/billing/countable_items_spec.rb` | `:34, :51` | |
| 2 | `spec/requests/admin/maintenance/platform/billing/coupons_spec.rb` | `:174, :79` | |
| 1 | `spec/requests/admin/maintenance/platform/billing/invoices_spec.rb` | `:26` | |
| 6 | `spec/requests/admin/maintenance/platform/billing/plans_spec.rb` | `:191, :80, :103, :122, :142, :155` | |
| 1 | `spec/requests/admin/maintenance/platform/billing/presentation_spec.rb` | `:127` | |
| 14 | `spec/requests/admin/maintenance/platform/billing/settings_spec.rb` | `:73, :116, :122, :128, [1:6:2:8], [1:6:2:9], [1:6:2:10], [1:6:2:11], [1:6:2:12], [1:6:2:13], [1:6:2:14], [1:6:2:15], [1:6:2:16], :150` | 135 for IDs |
| 1 | `spec/requests/admin/settings/billing/invoice_print_layout_spec.rb` | `:11` | |
| 1 | `spec/requests/admin/settings/billing/invoices_spec.rb` | `:121` | |
| 4 | `spec/requests/admin/settings/billing/payment_methods_spec.rb` | `:274, :145, :176, :257` | |
| 8 | `spec/requests/admin/settings/billing/presentation_spec.rb` | `:22, :45, :53, :70, :80, :90, :146, :134` | |
| 5 | `spec/requests/admin/settings/billing/subscriptions_spec.rb` | `:95, :118, :134, :152, :166` | |
| 1 | `spec/requests/admin/settings/modules/billing/cancellations_spec.rb` | `:84` | |
| 2 | `spec/services/billing/activities/apply_coupon_spec.rb` | `:8, :27` | |
| 4 | `spec/services/billing/activities/change_plan_spec.rb` | `:9, :21, :35, :58` | |
| 1 | `spec/services/billing/activities/set_up_payment_method_spec.rb` | `:9` | |
| 4 | `spec/services/billing/activities/subscribe_spec.rb` | `:15, :38, :48, :68` | |
| 4 | `spec/services/billing/catalog/commands_spec.rb` | `:5, :16, :31, :52` | |
| 10 | `spec/services/billing/contracts/plan_spec.rb` | `:16, :20, :26, :32, :38, :43, :49, :54, :60, :65` | |
| 1 | `spec/services/billing/countable/registry_spec.rb` | `:19` | |
| 1 | `spec/services/billing/discounts_spec.rb` | `:15` | |
| 9 | `spec/services/billing/lifecycle_integration_spec.rb` | `:24, :41, :53, :63, :75, :118, :129, :138, :191` | |
| 1 | `spec/services/billing/onboarding_spec.rb` | `:12` | |
| 1 | `spec/services/billing/providers/alipay_spec.rb` | `:8` | |
| 2 | `spec/services/billing/quota_spec.rb` | `:13, :26` | |
| 17 | `spec/services/billing/standard_plans_spec.rb` | `:13, :18, :26, :34, :42, :47, :52, :60, :68, :75, :83, :89, :95, :101, :111, :120, :133` | |

### Auth / OAuth — 32

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 2 | `spec/components/admin/settings/modules/authentication/grant_route_label_spec.rb` | `[1:1:2], [1:2:2]` | 20 |
| 8 | `spec/requests/authentication/admin/users_spec.rb` | `:218, :224, :236, :242, :248, :696, :704, :721` | |
| 1 | `spec/requests/authentication/passwords_spec.rb` | `:249` | |
| 13 | `spec/requests/authentication/registrations_spec.rb` | `:44, :56, :70, :83, :95, :227, [1:5:3], [1:5:4], [1:5:5], :254, :269, :434, :446` | 240 for IDs |
| 1 | `spec/requests/authentication/tenant_security_policy_spec.rb` | `:22` | |
| 1 | `spec/requests/oauth/pkce_flow_spec.rb` | `:398` | |
| 1 | `spec/services/authentication/landing_path_spec.rb` | `:26` | |
| 1 | `spec/services/authentication/sign_in_flow_spec.rb` | `:69` | |
| 2 | `spec/services/oauth/authorization_code_exchange_spec.rb` | `:34, :49` | |
| 1 | `spec/system/member/security_spec.rb` | `:16` | |
| 1 | `spec/system/member/sign_up_spec.rb` | `:25` | |

### Payments — 23

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb` | `:246` | |
| 1 | `spec/requests/payments/checkouts_spec.rb` | `:341` | |
| 4 | `spec/requests/payments/webhooks_stripe_spec.rb` | `:369, :403, :450, :481` | |
| 2 | `spec/services/payments/activities/billing_integration_spec.rb` | `:24, :51` | |
| 4 | `spec/services/payments/activities/historical_operations_spec.rb` | `:27, :40, :56, :65` | |
| 1 | `spec/services/payments/activities/retry_age_spec.rb` | `:72` | |
| 9 | `spec/services/payments/gateways/stripe_spec.rb` | `:377, :389, :399, [1:6:7], [1:6:8], [1:6:9], [1:6:10], :574, :636` | 408 for IDs |
| 1 | `spec/system/payments/admin_gateway_settings_spec.rb` | `:246` | |

### Email / SMS — 12

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/jobs/emails/send_activities/reconcile_send_activities_job_spec.rb` | `:16` | |
| 1 | `spec/requests/admin/modules/emails/lists_spec.rb` | `:32` | |
| 3 | `spec/requests/admin/modules/emails/template_versions_spec.rb` | `:75, :108, :200` | |
| 3 | `spec/requests/admin/modules/emails/templates_spec.rb` | `:48, :77, :433` | |
| 1 | `spec/services/emails/activities/send_spec.rb` | `:204` | |
| 1 | `spec/services/emails/persist_message_spec.rb` | `:37` | |
| 2 | `spec/services/sms/activities/send_spec.rb` | `:88, :284` | |

### Captcha — 5

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 2 | `spec/requests/admin/maintenance/platform/captcha/settings_spec.rb` | `:83, :88` | |
| 1 | `spec/requests/captcha/url_throttle_gate_spec.rb` | `:165` | |
| 1 | `spec/requests/public_pages_captcha_spec.rb` | `:82` | |
| 1 | `spec/services/captcha/page_shortcut_matching_spec.rb` | `:164` | |

### Core — 122

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 2 | `spec/components/admin/modules/page_component_spec.rb` | `:33, :64` | |
| 1 | `spec/contracts/entity_entry_contract_spec.rb` | `:343` | |
| 3 | `spec/models/concerns/entity_schema_validation_spec.rb` | `:195, :201, :294` | |
| 1 | `spec/models/concerns/json_serializable_spec.rb` | `:113` | |
| 1 | `spec/models/entity_entry_spec.rb` | `:372` | |
| 1 | `spec/models/platform_announcement_spec.rb` | `:254` | |
| 2 | `spec/requests/admin/help/docs_spec.rb` | `[1:12:1], [1:12:3]` | 695 |
| 1 | `spec/requests/admin/help_emails_spec.rb` | `:9` | |
| 19 | `spec/requests/admin/maintenance/entities_route_audit_spec.rb` | `:144, [1:1:1], [1:1:2], [1:1:3], [1:1:4], [1:1:5], [1:1:6], [1:1:7], [1:1:8], [1:1:9], [1:1:10], [1:1:11], [1:1:12], [1:1:13], [1:1:14], [1:1:15], :33, :65, :87` | 20 for IDs |
| 34 | `spec/requests/admin/maintenance/entities_spec.rb` | `:144, :153, :167, :177, :186, :196, :207, :216, :230, :238, :245, :255, :267, :277, :286, :516, :537, :637, :645, :656, :674, :688, :721, :742, :750, :759, :772, :780, :814, :823, :837, :848, :856, :866` | |
| 1 | `spec/requests/admin/maintenance/entity_lifecycle_route_audit_spec.rb` | `:64` | |
| 17 | `spec/requests/admin/maintenance/pages_spec.rb` | `:287, :298, :312, :330, :340, :351, :363, :376, :388, :400, :414, :421, :430, :441, :492, :502, :512` | |
| 1 | `spec/requests/admin/maintenance/platform/developer_docs_spec.rb` | `:41` | |
| 1 | `spec/requests/admin/maintenance/platform/shared_resources_spec.rb` | `:154` | |
| 2 | `spec/requests/admin/maintenance/platform/support_tickets_spec.rb` | `:57, :66` | |
| 1 | `spec/requests/admin/settings/member_surfaces_spec.rb` | `:50` | |
| 3 | `spec/requests/admin/settings/shared_shell_spec.rb` | `:94, [1:2:1], [1:3:1]` | 120 for IDs |
| 3 | `spec/requests/admin/support_tickets_spec.rb` | `:40, :47, :80` | |
| 1 | `spec/requests/core_route_audit_spec.rb` | `:13` | |
| 5 | `spec/requests/maintenance/entity_versions_spec.rb` | `:281, :293, :307, :315, :363` | |
| 3 | `spec/requests/page_shortcuts_spec.rb` | `:211, :224, :396` | |
| 1 | `spec/services/dashboard/home_spec.rb` | `:217` | |
| 13 | `spec/services/pages/activities/create_from_entity_version_spec.rb` | `:19, :35, :53, :89, :118, :160, :182, :209, :218, :232, :243, :251, :294` | |
| 1 | `spec/services/platform_announcements/backend_audience_spec.rb` | `:80` | |
| 1 | `spec/services/platform_announcements/contracts/announcement_spec.rb` | `:104` | |
| 1 | `spec/system/entities_attribute_grouping_spec.rb` | `:56` | |
| 2 | `spec/system/menu_navigation_spec.rb` | `:29, :43` | |

### Runtime / page rendering — 53

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/integration/composite_page_integration_spec.rb` | `:47` | |
| 1 | `spec/models/page_spec.rb` | `:356` | |
| 1 | `spec/requests/member/pages_spec.rb` | `:148` | |
| 1 | `spec/requests/public_pages_submission_spec.rb` | `:109` | |
| 1 | `spec/services/activity_generator_loop_integration_spec.rb` | `:335` | |
| 1 | `spec/services/activity_steps/save_all_spec.rb` | `:34` | |
| 4 | `spec/services/page_content_generator/conditions_escape_spec.rb` | `:61, :68, :74, :78` | |
| 3 | `spec/services/page_content_generator_calculated_spec.rb` | `:39, :45, :51` | |
| 2 | `spec/services/page_content_generator_safety_spec.rb` | `:93, :129` | |
| 21 | `spec/services/page_content_generator_spec.rb` | `:36, :44, :50, :118, :129, :140, :151, :162, :173, :191, :209, :222, :233, :297, :696, :738, :879, :1063, :1112, :1191, :1307` | |
| 6 | `spec/services/page_content_generator_theme_propagation_spec.rb` | `:118, :122, :126, :172, :182, :280` | |
| 7 | `spec/services/pages/rules_engine_runtime_spec.rb` | `:10, :16, :25, :32, :43, :49, :58` | |
| 3 | `spec/services/pages/rules_engine_spec.rb` | `:145, :229, :566` | |
| 1 | `spec/system/form_conditions_spec.rb` | `:153` | |

### Website — 6

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/requests/websites/public_pages_spec.rb` | `:145` | |
| 2 | `spec/services/websites/activities/import_media_spec.rb` | `:18, :139` | |
| 1 | `spec/services/websites/activities/save_page_spec.rb` | `:120` | |
| 2 | `spec/services/websites/assistant/schema_validator_spec.rb` | `:234, :243` | |

### AI + STT — 37

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/jobs/speech_to_text/prune_clips_job_spec.rb` | `:51` | |
| 1 | `spec/requests/admin/assistant/messages_spec.rb` | `:81` | |
| 6 | `spec/services/ai_assistant/activities/reply_spec.rb` | `:512, :533, :742, :782, :852, :862` | |
| 2 | `spec/services/ai_assistant/assistant/generate_page_spec.rb` | `:14, :39` | |
| 2 | `spec/services/ai_assistant/assistant/tools/session_spec.rb` | `:62, :79` | |
| 12 | `spec/services/entity_definitions/assistant/processor_spec.rb` | `:30, :69, :156, :164, :261, :397, :412, :464, :489, :518, :542, :562` | |
| 12 | `spec/services/entity_definitions/persist_spec.rb` | `:16, :54, :108, :132, :294, :309, :363, :371, :393, :405, :411, :439` | |
| 1 | `spec/services/speech_to_text/activities/enqueue_transcription_spec.rb` | `:86` | |

### Harness — 6

| Count | File | Selectors | Shared definition line |
| ---: | --- | --- | --- |
| 1 | `spec/components/page_builder/flows_section_component_spec.rb` | `:112` | |
| 3 | `spec/services/concerns/activity_class_builder_spec.rb` | `:87, :93, :100` | |
| 1 | `spec/system/admin/settings/member_entities_spec.rb` | `:11` | |
| 1 | `spec/system/admin/settings/members_spec.rb` | `:16` | |

## Release result

**Full RSpec gate: FAIL.** The only authored file in this verification is this report. Production/spec changes, schema regeneration, asset rebuild, standalone server restart/smoke, Vitest, and Playwright were outside this requested RSpec-only verification. Existing RSpec system specs did execute as part of the full suite. Test-generated logs/status/storage/screenshots remain normal run artifacts. No failing test was skipped, deleted, or changed to force green.

## Subsequent Billing A targeted verification

The original **25,053 examples / 442 failures** result above remains the full-suite evidence. Billing A subsequently fixed its namespace/callback/coupon-cache and quota-root causes and ran only isolated targeted scopes; the latest results are **375 A/consumer examples, 0 failures**, **176 signup/admin/entity/page quota-root examples, 0 failures**, and **90 entity/AI/countable examples, 0 failures**. Scopes overlap and are not a new full-suite aggregate. Real committed transaction/draft-loss and delayed zero-grace regressions are included. Commands, intermediate failures, the test-only migration prerequisite and the separately B-owned deadline/draft collection wiring are recorded in [Billing A targeted fixes](2026-10-11-billing-a-verification-fixes.md). No full suite was rerun by that dispatch.

## Core follow-up: groups 20, 21, 23, 24

The historical full-suite result above is unchanged. A subsequent core/security repair used a dedicated schema-loaded database, with SKIP_AUTH unset. No full-suite rerun or subagents were used.

Parent verification and isolated setup:

```bash
ls storage
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/core_verify.sqlite3 bin/rails db:schema:load
```

Both commands exited 0. The schema command loaded only the explicitly selected disposable test database, not development or production.

### Repairs and verified expectations

* **Group 20:** Deep structural checks moved out of the controller into `Entities::Contracts::Definition < Reform::Form`. The controller converts explicitly whitelisted JSON bags with `permit!.to_h`; the shared contract enumerates a real Hash with `each_pair`. `Entities::PromoteVersion` reuses this contract before existing semantic validation and bridge reconciliation. Controller/history/promotion and malformed-body cases remain meaningful; no invalid case was removed.
* **Group 21:** Scoped foreign version/tenant attempts retain 404 without promotion or head mutation. Negative multi-request specs first establish their Devise test session on an allowed response; an initial exception-handled 404 otherwise consumes queued test sign-in without establishing the next request's session. Restoration preconditions now verify the stored slug and actual soft-delete return/status. Rails preserves the hyphen in `Restore-collision`; `Restore!collision` creates the intended same-slug conflict. The real failure returns an alert, no success notice, and leaves the record inactive. Generic restoration source already checked the real return and was preserved.
* **Group 23:** Five admin/platform Help calls explicitly resolve `::Help::Activities`, avoiding the `Admin::Help` controller namespace. Email, tenant request/reply and platform reply/resolution requests pass.
* **Group 24:** Locale navigation links and hidden search-locale fields remain asserted. Search form action comparison uses its logical path rather than inheriting a controller-specific URL-helper default query. Authorization denial asserts the intentional assistant destination, not an unrelated helper-added locale query. Settings shell tests cover the existing nested disclosure structure and current module ordering. Menu tests inspect localized keyed destinations rather than whitespace-sensitive `>Home<` fragments or the retired Pages label. Dashboard tests explicitly seed the module catalog their fixtures require and expect only available secondary destinations. Member display tests confirm cleaned selections without retaining the submitted empty sentinel, while preserving locked choices.
* **Public tenancy:** Shortcut tests now verify intended cross-tenant public website/Page GET and form POST, public audience and privileged-field filtering. Protected/narrower resource rejection remains covered. The public-audience regression file also verifies canonical/alias reads and writes, same-tenant/fixed-owner positives, options, composite values and retained-entry handoff filtering.
* **Browser:** The real Chrome entity grouping system file ran all three examples; save/reload persistence succeeded. No builder source or routes were edited.

The first post-enumeration subset exposed the separate zero-fallback quota dependency. A's concurrent entitlement fix supplied the finite unconfigured starter fallback before the final run; ordinary core entity creation then passed without weakening quota guards or stubbing them. Builder-only page-create quota failures and other full-suite areas remain their assigned owners' verification work.

### Exact final passing command

```bash
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/core_verify.sqlite3 bundle exec rspec spec/services/entities/contracts/definition_spec.rb spec/services/entities/promote_version_spec.rb spec/requests/admin/maintenance/entities_spec.rb spec/requests/admin/maintenance/entities_route_audit_spec.rb spec/requests/admin/maintenance/entity_lifecycle_route_audit_spec.rb spec/requests/admin/maintenance/platform/shared_resources_spec.rb spec/requests/core_route_audit_spec.rb spec/requests/admin/help_emails_spec.rb spec/requests/admin/support_tickets_spec.rb spec/requests/admin/maintenance/platform/support_tickets_spec.rb spec/components/admin/modules/page_component_spec.rb spec/requests/admin/maintenance/platform/developer_docs_spec.rb spec/requests/admin/help/docs_spec.rb spec/requests/admin/settings/shared_shell_spec.rb spec/requests/admin/settings/member_surfaces_spec.rb spec/requests/page_shortcuts_spec.rb spec/services/dashboard/home_spec.rb spec/system/menu_navigation_spec.rb spec/system/entities_attribute_grouping_spec.rb spec/requests/admin/pages_route_audit_spec.rb spec/requests/admin/maintenance/platform/core_mutations_route_audit_spec.rb spec/requests/public_pages_tenant_audience_spec.rb spec/requests/formatted_webhook_routes_spec.rb
```

**Exit 0: 554 examples, 0 failures, no pending examples.** Execution: 1 minute 41.33 seconds; load: 2.43 seconds. The 23-file cohort includes request, component, service/contract and system coverage. Scoped `git diff --check` also exited 0. Earlier diagnostic subsets failed and were used to identify the fixes; the result above is the final combined verification after those changes.

### Remaining boundaries

This targeted pass does not turn the original 442-failure full run into a passing full-suite gate. Group 22 builder quota cases, group 25 backend model/JSON/announcement policy cases, unrelated rootless-dashboard behavior, and other assigned feature failures were not repaired or certified by this lane. The owner coordinator should reconcile the historical inventory with each lane's exact passing subset. Paired reference docs remain coordinator-owned; no test was skipped/deleted and no builder source, full suite, migrations or standalone server restart was run by this follow-up.

## Auth follow-up verification — groups 6–10

**Targeted auth gate: PASS — 332 examples, 0 failures across 14 files.** This is
a subsequent scoped remediation/verification pass, not another full-suite run.
The original 442-failure inventory above remains the historical full-suite result.

### Source-confirmed corrections

- Groups 6–7: Core A supplied the finite built-in Starter fallback. Auth quota
  fixtures now accept explicit subscription snapshots and count actual member
  assignments; seeded administrators do not spend member capacity. Lock-recheck
  examples start with an available final slot and insert a competing member before
  admission. Snapshot isolation remains covered when catalog limits later differ.
- Group 8: Request specs inspect protected Devise resources with `send(:resource)`;
  production does not expose the accessor. Invalid dual-reserved fixtures were
  replaced with real member-to-admin assignment operations. Member security links
  to authenticated `/auth/edit`. Plan-change cancellation and invoice-payment
  grant descriptors use existing EN/zh-CN action keys and have unique labels.
- Group 9: Real scoped sessions already had `last_request_at`; installed Devise
  clears authentication on timeout, then retries the attempted GET before the next
  request reaches sign-in. The regression now checks timestamps, `:timeout`, the
  logged-out scope and that complete journey. Cookie tracking and stateless bearer
  callbacks remain separately covered; no global timeout policy was changed.
- Group 10: Exchange and missing-owner refresh guards construct response-bearing
  Doorkeeper InvalidGrant errors. Regressions verify structured HTTP 400 responses
  for stale/revoked, expired and owner-unresolved codes, and owner-unresolved refresh;
  rejected exchanges issue no token and rollback coverage remains intact.

### Isolated database preparation

Parent directory was verified with `ls -ld storage`. The auth verification uses
only `storage/auth_verify.sqlite3`; SKIP_AUTH and parallel-worker overrides are
removed from each command.

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/auth_verify.sqlite3 bin/rails db:schema:load
```

Preparation exited 0. After the primary run, another lane added data migration
`20261011190000`; the first adjacent run stopped in schema maintenance before any
examples. That data migration was applied only to the isolated auth database,
without a schema dump or development/production database command:

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/auth_verify.sqlite3 bin/rails runner 'ActiveRecord::Base.connection_pool.migration_context.run(:up, 20261011190000)'
```

It exited 0 and reported zero payments/events scanned or changed, zero unresolved.

### Successful primary run

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/auth_verify.sqlite3 bundle exec rspec \
  spec/components/admin/settings/modules/authentication/grant_route_label_spec.rb \
  spec/requests/authentication/admin/users_spec.rb \
  spec/requests/authentication/passwords_spec.rb \
  spec/requests/authentication/registrations_spec.rb \
  spec/requests/authentication/tenant_security_policy_spec.rb \
  spec/requests/oauth/pkce_flow_spec.rb \
  spec/services/authentication/landing_path_spec.rb \
  spec/services/authentication/sign_in_flow_spec.rb \
  spec/services/oauth/authorization_code_exchange_spec.rb \
  spec/system/member/security_spec.rb \
  spec/system/member/sign_up_spec.rb
```

**Exit 0: 280 examples, 0 failures.** RSpec elapsed: 21.69 seconds; load: 2.86
seconds. Includes the two original system files and added protocol/snapshot checks.

### Successful adjacent run

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/auth_verify.sqlite3 bundle exec rspec \
  spec/requests/authentication/sessions_spec.rb \
  spec/requests/oauth/bearer_authenticatable_spec.rb \
  spec/models/authentication/user_tenant_security_policy_spec.rb
```

**Exit 0: 52 examples, 0 failures.** RSpec elapsed: 4.78 seconds; load: 2.45 seconds.

The initial narrow diagnostics reproduced three failures in 14 examples, then
three in 12 examples; these preceded the fixes and are not passing evidence.
All commands/results are captured in this auth session's terminal tool outputs.
No full suite, subagents, development/production migrations, compatibility shims,
or production exposure of protected controller helpers were used. Paired OAuth,
authentication and access-grant reference pages describe the corrected contracts.

## Messaging follow-up — groups 15–17

**PASS: 388 examples, 0 failures across 16 targeted files.** All seven originally failing messaging files were included. The full-suite result above remains the historical full-suite result; this follow-up did not run the full suite, parallel workers, or subagents. No examples were skipped or deleted.

### Isolated setup and execution evidence

`storage` and `/tmp/opencode` were verified with `ls -ld` before creating the disposable database/logs. The database was absent before setup. The final schema was loaded only into `storage/message_verify.sqlite3`:

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/message_verify.sqlite3 bin/rails db:schema:load
```

Preparation exited 0. The seven-file baseline reproduced **248 examples, 12 failures** in 35.88 seconds. After remediation, the first expanded run passed **383 examples, 0 failures** in 41.79 seconds. The migration preflight's three focused examples also passed. Following the authored-markup and invalid-envelope regressions, the final authoritative run was:

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER RAILS_ENV=test TEST_DATABASE=storage/message_verify.sqlite3 bundle exec rspec \
  spec/jobs/emails/send_activities/reconcile_send_activities_job_spec.rb \
  spec/requests/admin/modules/emails/lists_spec.rb \
  spec/requests/admin/modules/emails/template_versions_spec.rb \
  spec/requests/admin/modules/emails/templates_spec.rb \
  spec/services/emails/activities/send_spec.rb \
  spec/services/emails/persist_message_spec.rb \
  spec/services/sms/activities/send_spec.rb \
  spec/models/emails/template_spec.rb \
  spec/services/emails/compile_template_spec.rb \
  spec/services/emails/author_preview_spec.rb \
  spec/services/emails/send_activities/send_activity_unsubscribe_spec.rb \
  spec/requests/emails/unsubscribes_spec.rb \
  spec/services/sms/backend_lifecycle_spec.rb \
  spec/services/emails/backend_quota_spec.rb \
  spec/jobs/emails/backend_delivery_lifecycle_spec.rb \
  spec/migrations/harden_email_sms_backend_lifecycle_spec.rb \
  --format progress --format documentation --out /tmp/opencode/message_verify_final.log
```

Exit 0: **388 examples, 0 failures**, 42.1 seconds of examples and 3.28 seconds of load time. Scoped `git diff --check` exited 0. Non-failing Rack `:unprocessable_entity` deprecation warnings remain in terminal output.

Logs:

- Baseline: `/tmp/opencode/message_verify_baseline.log` (248 / 12).
- First expanded verification: `/tmp/opencode/message_verify_targeted.log` (383 / 0).
- Migration preflight: `/tmp/opencode/message_verify_migration.log` (3 / 0).
- Final verification: `/tmp/opencode/message_verify_final.log` (388 / 0).

### Remediation and source/fixture classification

| Original group | Resolution |
| --- | --- |
| 15 — template head | Missing/null required definition strings normalize to empty strings; missing/null editor type uses the schema default `code`; nullable text remains null. Promotion/restoration still atomically applies the selected definition. Sparse/null snapshot and real image-version regressions prove head/scalar/Action Text consistency. |
| 16 — email persistence race | The synthetic lookup now misses once and sees the existing winner on rescue. Production performs one initial lookup and uncached tenant/key reloads, recovering only actual idempotency `:taken` validation errors. A real DB-index loser is exercised with the advisory uniqueness validator bypassed; unrelated validation/index errors propagate. |
| 16 — SMS persistence races | Winners are created outside the loser's savepoint; the old fixtures inserted and then rolled them back inside that savepoint. Synthetic reads model miss/miss/winner or miss/winner as appropriate. A real unique-index rejection reloads the actual winner without another vendor send. |
| 16 — scheduling precision | The fixture uses a microsecond-exact UTC time and verifies the persisted due instant plus queue handoff. The database truncation below microsecond precision is not a scheduling defect. |
| 16 — reconcile job | The end-to-end fixture explicitly enables Email. An additional disabled-module example proves that the intended gate still prevents re-drive. |
| 17 — labels and menus | Subtitles assert the current localized catalog label. Menu-placement exclusions are scoped to the table; existing dashboard menus are unrelated to compact row actions. UI implementation/styles were not changed. |
| 17 — CID preview | The baseline already emitted `<div><img src="cid:blob-1" alt="hero.png"></div>`; its blob was unowned, so the tenant-scoped browser rewrite correctly refused it. The fixture now stamps ownership. Added foreign-blob and image-head regressions preserve isolation, embeds, SGID identity, dimensions, filename, CID HTML and preview URLs. No permissive compiler transform was added. |

The obsolete template layout-unwrapping compatibility shim was removed. Authored `trix-content` classes and sibling markup round-trip intact through the canonical current snapshot. Unsubscribe confirmation no longer falls back to the current profile address; incomplete signed user/email/customer envelopes receive controlled 404 responses without suppression writes.

### Historical scheduling policy

The brand-new application does not introduce a runtime old-envelope compatibility path. Before lifecycle migration `20261011173041`, a queued email row has no authoritative primary-ledger due time. Production Solid Queue's `solid_queue_jobs` and `solid_queue_scheduled_executions` live in `production_queue.sqlite3`, and the old primary row has no persisted queue-job identity. Missing local scheduled-execution data cannot prove immediate delivery.

The migration therefore refuses existing queued rows before any schema mutation, preserving them for explicit schedule resolution/quarantine. It does not guess `created_at` as a historical schedule or import jobs from another database. Historical cross-database queue import and old-token compatibility are out of scope under the brand-new application policy. New admission paths persist `delivery_due_at`; future-due delivery/recovery behavior was included in the passing lifecycle specs. Fresh-outbox, unresolved-row refusal, and completed-row preflight cases pass.

Matching developer references were updated in both `doc/reference/en/email.md` / `zh-CN/email.md` and both SMS pages. Schema-load verification is not a production migration or live vendor/queue concurrency test.

## Runtime follow-up — groups 26–28 and harness 33

**PASS: 508 examples, 0 failures, no pending examples across 28 targeted files.** This fresh verification included all 14 originally failing runtime files, all four group-33 harness files, and ten adjacent runtime/parameter/persistence/public-audience/handoff files. The historical full-suite result above remains unchanged. No full suite or subagents were run.

### Isolated preparation and observed diagnostics

Parent verification and schema loading both exited 0:

```bash
ls storage
env -u SKIP_AUTH -u TEST_ENV_NUMBER TEST_DATABASE=storage/runtime_final_verify.sqlite3 RAILS_ENV=test bin/rails db:schema:load
```

Only the named disposable test database was loaded. `/tmp/opencode` was verified with `ls -ld /tmp/opencode` before creating the final log. Authentication bypass and parallel-worker overrides were unset for every test command.

- Initial 26-file cohort: **488 examples, 2 failures**, 16.16 seconds (load 3.18 seconds). The remaining failures were `spec/system/admin/settings/member_entities_spec.rb:11` and `spec/system/admin/settings/members_spec.rb:16`, both ambiguous Configure links. Existing runtime changes were inspected and executed rather than assuming the prior empty agent responses meant success.
- Six-file generator/selector diagnostic after strengthening fixtures: **126 examples, 2 failures**, 4.57 seconds (load 2.67 seconds). It identified that the first row scope stopped at the label wrapper; the final scope includes the action wrapper.
- Corrected selector and real SaveAll persistence subset: **20 examples, 0 failures**, 2.21 seconds (load 2.45 seconds).

These scopes overlap; they are diagnostics, not additional passing-example totals.

### Confirmed contracts and fixture corrections

| Group | Final verified result |
| --- | --- |
| 26 — field visibility | Generator component/theme/escaping fixtures now use the shared test-only `PageRuntimeHelpers#build_runtime_ui_page` with real tenant-owned entities, declared property slugs, types and nested-column schemas. An additional rendered positive verifies that a bound public field is enabled. Escaping now compiles and renders the bound input, preserving the hostile condition value as data. Unknown-type injection uses a valid schema slug so the fallback path actually runs. Hidden-dropdown tests assert that the select itself exists before checking that its options are absent. Calculation, member-page and system markup fixtures retain explicit accessible schemas. |
| 27 — positional hashes | Rules and SaveAll specs use explicit positional value/context hashes for APIs with keyword options; production signatures stay positional. Calculation regressions retain forged-target, dependency/cycle, hidden-intermediate and recursive namespace assertions. SaveAll uses EntityEntry/Reform fixtures, rejects base-record writes, fails on false contract saves and rolls back primary plus earlier bridge writes on a real later validation failure. Bridge-reference integration fixtures now share the same actual customer. |
| 28 — output and rollback | Loop validation expects the translated nested-loop message, including its existing locale regressions. Composite widths assert `col-span-12 md:col-span-6`. The handoff rollback update fixture declares its `name` attribute and proves the existing entry survives unchanged; unsupported base writes remain rejected. |
| 33 — harness | Flow component specs inject `current_user` on the ViewComponent test controller: the pinned owner receives editor links and a tenant admin does not. Child-lookup examples use a real RuntimeFlowchart facade and reject draft/foreign children while loading launched accessible children. Settings system tests choose the exact heading's row, then the Payments row's Display settings link; the complete rename/member-navigation journey passes. |

The existing production field/audience/base-write protections were exercised directly. Public tenant-audience request tests cover canonical/alias GET and POST, forged privileged fields/actor hints, narrower-surface rejection, dropdowns/composite values and retained-entry handoff filtering. Effective shared runtime overrides, owner previews and child definitions execute without replacing global artifacts. No production source change was needed in this fresh follow-up; authored changes are meaningful test fixtures/assertions and paired reference/audit documentation. No page/flowchart builder authoring source or ignored template directory was edited.

### Exact final passing command

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER TEST_DATABASE=storage/runtime_final_verify.sqlite3 RAILS_ENV=test bundle exec rspec \
  spec/integration/composite_page_integration_spec.rb \
  spec/models/page_spec.rb \
  spec/requests/member/pages_spec.rb \
  spec/requests/public_pages_submission_spec.rb \
  spec/services/activity_generator_loop_integration_spec.rb \
  spec/services/activity_steps/save_all_spec.rb \
  spec/services/page_content_generator/conditions_escape_spec.rb \
  spec/services/page_content_generator_calculated_spec.rb \
  spec/services/page_content_generator_safety_spec.rb \
  spec/services/page_content_generator_spec.rb \
  spec/services/page_content_generator_theme_propagation_spec.rb \
  spec/services/pages/rules_engine_runtime_spec.rb \
  spec/services/pages/rules_engine_spec.rb \
  spec/system/form_conditions_spec.rb \
  spec/components/page_builder/flows_section_component_spec.rb \
  spec/services/concerns/activity_class_builder_spec.rb \
  spec/system/admin/settings/member_entities_spec.rb \
  spec/system/admin/settings/members_spec.rb \
  spec/services/pages/runtime_flowchart_spec.rb \
  spec/services/pages/form_params_runtime_spec.rb \
  spec/services/page_content_generator_runtime_spec.rb \
  spec/services/activity_tracer_runtime_preview_spec.rb \
  spec/services/activity_steps/detect_and_route_params_spec.rb \
  spec/services/activity_steps/populate_primary_spec.rb \
  spec/services/pages/form_params_spec.rb \
  spec/services/pages/public_submission_spec.rb \
  spec/requests/public_pages_tenant_audience_spec.rb \
  spec/services/feature_modules/submission_handoff_spec.rb \
  --format progress --format documentation --out /tmp/opencode/runtime_final_verify.log
```

**Exit 0: 508 examples, 0 failures**, 22.03 seconds of examples and 3.5 seconds of load time. Final per-example documentation/profiling log: `/tmp/opencode/runtime_final_verify.log`. Existing anonymous `BlueprintEntity`/`BlueprintEntityContract` constant-reinitialization warnings were non-failing. The settings system journeys use RackTest; `form_conditions_spec.rb` checks configuration and generated markup, not browser JavaScript. The cohort does execute generated ERB and real activities/subflows, persisted records/savepoints and request submissions.

Scoped `git diff --check` for the touched specs/helper and paired reference/audit paths exited 0 after the final run. The final log independently records the 508/0 summary at lines 781–782.

No failures remain in this verified cohort. Paired `page-rendering.md` and `flowchart-runtime.md` reference pages now describe the fixture/boundary contracts and actual verification rather than claiming the regressions were only authored. The historical full-suite gate must still be reconciled with the other area owners' evidence.

## Eight-worker full-suite verification — 2026-10-12

**FAIL: 25,226 examples, 30 failures across five failing files; 1,576 spec files dispatched to eight workers.** All eight workers completed. There were **0 pending examples** and **0 errors outside examples**. Derived passing examples: **25,196**. This section records one newly requested complete execution after the targeted repairs; the original **25,053 / 442** evidence and all follow-up history above are preserved.

### Preparation and exact commands

Before loading schemas, `ls -ld storage /tmp/opencode` verified both parents. `nproc` returned **8**; `free -h` reported **15 GiB RAM**, approximately **13 GiB available**, and no swap. The pre-run process inventory showed no RSpec/Puma jobs. The source schema was **20261011190000** (`db/schema.rb:13`).

Initial schema loading exited successfully with no output:

```bash
env -u TEST_DATABASE -u SKIP_AUTH -u DATABASE_URL RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 bin/rails parallel:load_schema
```

Preparation and the single full-suite execution then used:

```bash
time env -u TEST_DATABASE -u SKIP_AUTH -u DATABASE_URL RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 bin/rails parallel:prepare && time env -u TEST_DATABASE -u SKIP_AUTH -u DATABASE_URL RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 bin/rails 'parallel:spec[,,--format progress --format json --out /tmp/opencode/rspec-full-20261012-worker-$TEST_ENV_NUMBER.json --no-color --backtrace]'
```

The task arguments add only official RSpec progress/JSON formatters, full backtraces and uncolored output; no test pattern/filter was supplied. `parallel_tests` substitutes each worker's `TEST_ENV_NUMBER` in its output filename. Worker 1 uses an empty suffix. Preparation succeeded in **15.453 seconds**; the spec command returned nonzero with `Tests Failed`. The parallel runner reported **374 seconds (6:14)**; shell wall time for the spec command, including Rails/task startup, was **377.598 seconds (6:17.598)**. Preparation plus spec-command shell wall time was **393.051 seconds (6:33.051)**, excluding the earlier initial schema load.

Only `storage/test.sqlite3` and `storage/test2.sqlite3` through `storage/test8.sqlite3` were selected. A post-run SQLite **read-only** query confirmed latest migration version **20261011190000** in all eight databases. The installed `parallel_tests` 5.7.0 `parallel:prepare` implementation checks pending migrations and invokes schema loading; it does not invoke a schema dump in this Rails/Ruby-schema branch. No development/browser database schema command or schema-dump command was issued.

### Complete logs and worker totals

Complete stdout/stderr was saved automatically by the terminal tool:

`/home/ec2-user/.local/share/opencode/tool-output/tool_12e4390aa001Zs6eS3jNWBpGhJ`

The raw log contains **5,278 lines**. Dispatch appears at line **5**, the aggregate at **5272**, runner elapsed time at **5274**, and shell spec-command wall time at **5276**. Each official JSON artifact contains every example's ID, definition file/line, status, duration and, for failures, exception class/message plus full backtrace. All eight JSON files parsed successfully; they contain **25,226 distinct example IDs**, matching the runner aggregate.

| Worker | TEST_ENV_NUMBER | Examples | Failures | Pending | Outside-example errors | RSpec duration (seconds) | JSON artifact | Raw summary line |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | empty | 2,851 | 0 | 0 | 0 | 270.979 | `/tmp/opencode/rspec-full-20261012-worker-.json` | 554 |
| 2 | 2 | 2,859 | 1 | 0 | 0 | 316.578 | `/tmp/opencode/rspec-full-20261012-worker-2.json` | 740 |
| 3 | 3 | 2,784 | 0 | 0 | 0 | 301.015 | `/tmp/opencode/rspec-full-20261012-worker-3.json` | 648 |
| 4 | 4 | 2,822 | 0 | 0 | 0 | 328.023 | `/tmp/opencode/rspec-full-20261012-worker-4.json` | 750 |
| 5 | 5 | 3,243 | 0 | 0 | 0 | 330.373 | `/tmp/opencode/rspec-full-20261012-worker-5.json` | 755 |
| 6 | 6 | 3,003 | 29 | 0 | 0 | 356.597 | `/tmp/opencode/rspec-full-20261012-worker-6.json` | 5231 |
| 7 | 7 | 3,094 | 0 | 0 | 0 | 313.458 | `/tmp/opencode/rspec-full-20261012-worker-7.json` | 653 |
| 8 | 8 | 4,570 | 0 | 0 | 0 | 362.335 | `/tmp/opencode/rspec-full-20261012-worker-8.json` | 5268 |
| **Total** | | **25,226** | **30** | **0** | **0** | | | **5272** |

Worker identity comes from its JSON filename, not stdout completion order. JSON RSpec durations exclude each process's spec-file loading time.

### Exhaustive current failure inventory

Append each selector to its repository-relative file. These rows contain **all 30 failed examples**, with their exact RSpec definition lines; the trace column identifies the failing fixture/assertion line. Full descriptions and unabridged traces are in the corresponding worker JSON and raw-log blocks.

| Worker | Count | File | Definition selectors | Root fixture/assertion trace | Raw failure-block start lines |
| --- | ---: | --- | --- | --- | --- |
| 2 | 1 | `spec/system/search_palette_spec.rb` | `:14` | `search_palette_spec.rb:20` | 659 |
| 6 | 1 | `spec/models/current_platform_owner_spec.rb` | `:17` | `current_platform_owner_spec.rb:6,18` | 761 |
| 6 | 1 | `spec/services/page_content_generator_composite_spec.rb` | `:22` | `page_content_generator_composite_spec.rb:36` | 916 |
| 6 | 7 | `spec/services/page_shortcuts/public_path_spec.rb` | `:25, :37, :48, :55, :64, :78, :90` | `public_path_spec.rb:6` | 1000, 1132, 1264, 1396, 1528, 1660, 1792 |
| 6 | 20 | `spec/services/websites/home_site_spec.rb` | `:322, :336, :350, :382, :408, :430, :440, :455, :472, :482, :492, :510, :526, :540, :548, :554, :564, :575, :595, :611` | `home_site_spec.rb:314` | 1924, 2089, 2254, 2419, 2584, 2749, 2914, 3079, 3244, 3409, 3574, 3739, 3904, 4069, 4234, 4399, 4564, 4729, 4894, 5062 |

### Observed root traces

1. **Duplicate platform-customer fixtures — 28 failures, worker 6.** All three affected files raise `ActiveRecord::RecordNotUnique`, caused by `SQLite3::ConstraintException: UNIQUE constraint failed: customers.id`. They explicitly create customer **81721200**: `current_platform_owner_spec.rb:6` (evaluated at :18), `public_path_spec.rb:6` (`let_it_be` setup, inherited by all seven failures), and `home_site_spec.rb:314` (`let!` setup, inherited by all 20 failures). The trace proceeds through FactoryBot creation, ActiveRecord `save!`/insert and `sqlite3-2.9.0/lib/sqlite3/statement.rb:125:in 'step'`. These examples fail during setup, before their intended domain assertions. The read-only post-run query found one platform-customer row in `storage/test6.sqlite3`, and none in the other seven worker databases. This establishes the duplicate-row failure and its worker-local persistence; the originating insert is not identified by these failure traces.
2. **Composite list output — one failure, worker 6.** `spec/services/page_content_generator_composite_spec.rb:22` fails its assertion at :36 with `RSpec::Expectations::ExpectationNotMetError`: generated HTML contains **“No records found”**, not **“Alice”**. The fixture creates a tenant entity/entry at :8–14 and generates its page at :18–19. Source inspection shows `PageContentGenerator#tenant_customer_id` prefers `Current.customer_id` over `page.customer_id` (`app/services/page_content_generator.rb:369–370`); composite generation forwards that tenant at :377. `CompositePageRenderer#resolve_entity` scopes the entity to the selected customer at :53–54 and its missing-entity path yields empty records at :58. The spec does not establish/reset `Current.customer`. The assertion trace does not record the runtime tenant or prove which earlier example supplied context, so the observed empty result remains a failing regression requiring isolation review.
3. **Browser inline search — one failure, worker 2.** `spec/system/search_palette_spec.rb:14` reaches :20 and raises `Capybara::ElementNotFound: Unable to find visible css "[data-inline-search-target='input']"`. Root frames are Capybara `finders.rb:312` (`synced_resolve`), `node/base.rb:84` (`synchronize`), `finders.rb:60` (`find`) and the spec assertion at :20. The saved screenshot shows the authenticated dashboard and collapsed search trigger. The adjacent Escape example at :28 **passed** in the same full run; no cause such as timing or failed Stimulus initialization is proven by this exception alone. Screenshot: `tmp/capybara/failures_r_spec_example_groups_dashboard_inline_search_expands__shows_live_results_for_a_matching_query__and_navigates_on_click_125.png`.

Exception totals independently computed from JSON: **28 RecordNotUnique**, **1 ExpectationNotMetError**, **1 ElementNotFound** = **30**.

### Reconciliation and final verification boundary

All **121 unique files** from the original exhaustive 442-failure inventory were present in the new JSON results and had **zero failures**: **2,566 current examples** in those files passed. This is file-level reconciliation against the historical inventory, not an assumption that changed example line numbers/IDs are identical. The five currently failing files were not in that original failing-file inventory.

The recently changed `spec/services/settings_contributor_spec.rb` passed **18 examples**, and `spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb` passed **8 examples** in ordinary suite mode; both ran on worker 4. This full RSpec run does not certify conditional exporter mode or the separate Playwright suite.

**Latest full RSpec gate: FAIL.** This dispatch authored only this appended audit section. No production/spec edits, skipped/deleted tests, serial full-suite fallback, automatic full-suite rerun, subagents, asset rebuild or standalone server restart were performed. The pre-existing deleted generator audit YAML was inspected as user work and was not modified/restored by this dispatch. Complete logs, worker totals, all failed locations and observed root traces are preserved for the parent coordinator's repair pass.

## Remaining-five QA/developer repair — 2026-10-12

**Targeted gate: PASS — 163 examples, 0 failures across 11 files.** A separate original-order browser predecessor chain passed **13 examples, 0 failures**. Both runs had zero pending examples and zero outside-example errors. These scopes overlap in the two search examples; their counts are not a new full-suite aggregate. The eight-worker **25,226 / 30** result above remains the latest complete-suite evidence.

### Reproduction and confirmed roots

The worker JSON lists examples in execution order. Neither artifact has a random seed, the retained command supplies no random-order option, and `spec/spec_helper.rb` intentionally retains defined order. Reproductions therefore use **`--order defined`**, preserving the relevant worker subsequences rather than inventing a seed.

1. **Committed platform-owner fixture leak: all 28 duplicate failures.** Worker 6 runs the five `Billing::FinalizeInvoiceJob` examples at JSON indexes 244–248, before the first duplicate at index 481. Its upgrade-recovery example calls `find_or_create_platform_owner` with `use_transactional_tests = false`. That helper creates customer 81721200 and its pinned owner outside fixture rollback; the file's cleanup originally deleted only the billed tenant and its billing rows. A read-only inspection of retained `storage/test6.sqlite3` found customer `Platform` created at `2026-10-12 03:56:33.168770`, the pinned owner, three reserved roles and its owner assignment, with no billing plans/settings/subscriptions remaining. A fresh six-file producer/consumer run reproduced **58 examples, 28 failures**, including every original duplicate selector. There are no migration specs in this worker's pre-duplicate subsequence; the leak is the explicitly committed owner fixture, not alternate migration connections, `let_it_be` rollback, StandardPlans or trial callbacks.
2. **Ambient tenant leak plus an implicit standalone render context.** The AI reply and cancellation specs assigned `Current.customer` directly without restoring it. The last reply example leaves its tenant in Current after fixture teardown. The sequence `reply_spec.rb:1107` → prompt/context → conditions escaping → composite reproduced **19 examples, 1 failure**: the original composite list returned “No records found” instead of “Alice.” The two intervening files use block-scoped context and restore the leaked incoming tenant. Reply/cancellation now wrap their entire example in `Current.set(customer:)`; composite specs explicitly scope the render tenant, viewer and shared-resource mode. Added real entity/entry cases prove public filtering, same-tenant admin visibility and empty results under a different active tenant. The runtime tenant-precedence and audience guards remain the exercised production behavior.
3. **Browser synchronization assertion defect.** The original `have_no_css("[data-inline-search-target='expanded'].hidden")` uses Capybara's visible-only default, so it can pass while the search is collapsed. The full-run screenshot shows exactly that state. `open_search` now scopes to the visible responsive controller, positively finds its expanded visible input, and uses Capybara's bounded synchronization to retry the opening click only while that instance's trigger remains visible. Results and Escape assertions stay within that instance. There are no fixed sleeps or missing-browser skip. Both real Chrome examples pass in the primary run and after the original worker-2 system predecessors. The original evidence does not distinguish a pre-connect click from another transient collapse; it does establish the vacuous assertion, now removed.
4. **Tracked report mutation by an existing script spec.** Inspection found `audit_generator_ui_spec.rb` deleting the repository audit YAML before invoking its writer. The test now supplies a per-example `Tempfile`, redirects only the child process's `OUTPUT_PATH`, runs the real report/writer and defect gate, and closes/unlinks the temporary file automatically. All 23 examples pass; both writer cases report 106 entries and zero defects. A post-run `git diff --exit-code` and scoped status confirm the tracked YAML has no change. No unknown artifact was reconstructed. The audit script and builder source were not edited.

### Authored files and documentation parity

- `spec/jobs/billing/finalize_invoice_job_spec.rb`: track explicitly owned platform customer/owner records and clean them after the real commit; reuse an existing owner without resetting its password.
- `spec/services/ai_assistant/activities/{cancel_reply,reply}_spec.rb`: block-scoped tenant lifecycle, including intentional cross-tenant examples.
- `spec/services/page_content_generator_composite_spec.rb`: explicit render context and two additional real tenant/audience regressions.
- `spec/system/search_palette_spec.rb`: scoped positive open wait, live result navigation and Escape restoration.
- `spec/scripts/audit_generator_ui_spec.rb`: disposable child-process audit output.
- Matching notes in **both** `doc/reference/en/` and `doc/reference/zh-CN/`: `tenancy-and-roles.md`, `page-rendering.md`, `dashboard.md`, `flowchart-builder.md`.

The fixed-ID consumers retain their explicit creation fixtures. No database-method mocks, global fixture auto-seeding or transaction-guard bypass was added. Existing unrelated working-tree edits, including the reply supersession regression, were preserved.

### Environment and exact commands

`ls -ld storage /tmp/opencode` confirmed both parents. Every Rails/RSpec command removes **DATABASE_URL, RUBYOPT, SKIP_AUTH, TEST_ENV_NUMBER and E2E_DATABASE_PATH** and selects only `storage/rspec_remaining_verify.sqlite3`. In particular, the original browser Ruby preload cannot redirect this run's database.

Initial preparation (exit 0):

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bin/rails db:schema:load
```

The two pre-fix reproductions used the same environment prefix:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bundle exec rspec spec/jobs/billing/finalize_invoice_job_spec.rb spec/models/current_platform_owner_spec.rb spec/services/page_content_generator_composite_spec.rb spec/services/page_shortcuts/public_path_spec.rb spec/services/websites/home_site_spec.rb spec/system/search_palette_spec.rb --order defined --format progress --format json --out /tmp/opencode/rspec-remaining-baseline.json

env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bundle exec rspec spec/services/ai_assistant/activities/reply_spec.rb:1107 spec/services/ai_assistant/assistant/prompt/context_spec.rb spec/services/page_content_generator/conditions_escape_spec.rb spec/services/page_content_generator_composite_spec.rb --order defined --format progress --format json --out /tmp/opencode/rspec-remaining-current-baseline.json
```

Before final verification, reloading schema over the deliberately contaminated database failed its customer-table drop with a foreign-key constraint, before examples. A combined `db:drop db:schema:load` invocation also retained the existing connection and failed. Resetting the disposable database and loading its schema in **separate Rails processes** succeeded:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bin/rails db:drop && env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bin/rails db:schema:load
```

Final primary command:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bundle exec rspec spec/jobs/billing/finalize_invoice_job_spec.rb spec/models/current_platform_owner_spec.rb spec/services/ai_assistant/activities/cancel_reply_spec.rb spec/services/ai_assistant/activities/reply_spec.rb spec/services/ai_assistant/assistant/prompt/context_spec.rb spec/services/page_content_generator/conditions_escape_spec.rb spec/services/page_content_generator_composite_spec.rb spec/services/page_shortcuts/public_path_spec.rb spec/services/websites/home_site_spec.rb spec/system/search_palette_spec.rb spec/scripts/audit_generator_ui_spec.rb --order defined --format progress --format json --out /tmp/opencode/rspec-remaining-targeted.json
```

**Exit 0: 163 examples, 0 failures.** RSpec duration **53.19 seconds**; load **5.28 seconds**. The five originally failing files contribute **55 passing examples**, including the two new composite regressions. The producer job contributes five, cancellation/reply eight/56, prompt/context 11, conditions escaping five and report harness 23.

Original worker-2 system predecessor chain:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bundle exec rspec spec/system/admin/maintenance/entity_form_identity_spec.rb spec/system/entities_attribute_grouping_spec.rb spec/system/feature_modules/exit_fallback_chain_spec.rb spec/system/payments/qr_checkout_spec.rb spec/system/search_palette_spec.rb --order defined --format progress --format json --out /tmp/opencode/rspec-remaining-browser-chain.json
```

**Exit 0: 13 examples, 0 failures.** RSpec duration **24.30 seconds**; load **4.33 seconds**. This verifies search after the preceding application/browser sessions in their retained order.

Post-primary database query:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_remaining_verify.sqlite3 bin/rails runner 'puts({database: ActiveRecord::Base.connection_db_config.database, platform_customers: Customer.unscoped.where(id: Authentication::User::PLATFORM_CUSTOMER_ID).count, customers: Customer.unscoped.count, owners: Authentication::User.unscoped.where(email: Authentication::User::PLATFORM_OWNER_EMAIL).count, roles: Role.unscoped.count, role_assignments: UsersRole.count, plans: Billing::Plan.count, settings: Billing::Settings.count, subscriptions: Billing::Subscription.count}.inspect)'
```

**Exit 0:** the selected database is `storage/rspec_remaining_verify.sqlite3`; **all eight counts are 0**. The committed producer fixture and its role graph no longer persist into consumers. Scoped `git diff --check` exited 0. JSON artifacts above preserve the exact example inventories and outcomes. This repair ran targeted scopes only; it makes no new full-suite release claim.

## Final eight-worker full-suite verification — 2026-10-12

**FAIL: 25,266 examples, 2 failures across two files; 1,576 spec files dispatched to eight workers.** All eight workers completed. **25,264 examples passed**, with **0 pending examples** and **0 errors outside examples**. This is the newly requested final complete-suite execution after the remaining-five and migration repairs. The earlier **25,226 / 30** and **25,053 / 442** full-run evidence remains intact above.

### Exact environment, preparation and execution

`ls -ld /home/ec2-user/anysys/storage /tmp/opencode` verified both parents before schema/log creation. The host had **8 cores**, **15 GiB RAM**, approximately **11 GiB available**, and no swap. The selected source schema remained **20261011190000** (`db/schema.rb:13`). Commands ran with explicit working directory `/home/ec2-user/anysys`, an absolute Rails executable and the requested environment cleanup; no browser environment file was sourced.

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:load_schema
```

Schema loading succeeded in **11.125 seconds**, followed by:

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:prepare && time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails 'parallel:spec[,,--format progress --format json --out /tmp/opencode/rspec-full-final-worker-$TEST_ENV_NUMBER.json --no-color --backtrace]'
```

Preparation succeeded in **11.200 seconds**. The complete spec command returned nonzero with `Tests Failed`; the runner reported **510 seconds (8:30)**. Shell spec-command wall time, including Rails/task startup, was **512.473 seconds (8:32.473)**. Initial schema loading plus preparation plus spec-command shell wall time totaled **534.798 seconds (8:54.798)**.

Only official formatter/backtrace options were added to `parallel:spec`; no test pattern/filter was supplied. The `rspec-full-final-worker-` prefix was verified absent before this execution. The worker databases use the configured `storage/test.sqlite3` and `storage/test2.sqlite3` through `storage/test8.sqlite3` paths. No development/browser database schema command or schema dump was issued.

### Complete log and eight-worker statistics

Complete terminal stdout/stderr:

`/home/ec2-user/.local/share/opencode/tool-output/tool_12e97628d001TTtxhN57N5FFBk`

The log has **844 lines**: dispatch at **5**, aggregate at **838**, runner elapsed time at **840**, and shell spec-command time at **842**. Official JSON artifacts below include every example and unabridged failure backtraces. All eight JSON files parsed successfully and contain **25,266 unique example IDs**, independently matching the runner aggregate.

| Worker | Examples | Failures | Pending | Outside-example errors | RSpec duration (seconds) | Official JSON artifact | Raw summary line |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | 2,700 | 1 | 0 | 0 | 437.213 | `/tmp/opencode/rspec-full-final-worker-.json` | 793 |
| 2 | 4,531 | 0 | 0 | 0 | 343.252 | `/tmp/opencode/rspec-full-final-worker-2.json` | 569 |
| 3 | 3,050 | 0 | 0 | 0 | 501.933 | `/tmp/opencode/rspec-full-final-worker-3.json` | 834 |
| 4 | 2,766 | 0 | 0 | 0 | 435.332 | `/tmp/opencode/rspec-full-final-worker-4.json` | 716 |
| 5 | 3,135 | 0 | 0 | 0 | 423.271 | `/tmp/opencode/rspec-full-final-worker-5.json` | 709 |
| 6 | 3,283 | 0 | 0 | 0 | 395.317 | `/tmp/opencode/rspec-full-final-worker-6.json` | 587 |
| 7 | 2,840 | 0 | 0 | 0 | 383.001 | `/tmp/opencode/rspec-full-final-worker-7.json` | 581 |
| 8 | 2,961 | 1 | 0 | 0 | 415.288 | `/tmp/opencode/rspec-full-final-worker-8.json` | 691 |
| **Total** | **25,266** | **2** | **0** | **0** | | | **838** |

Worker 1 has an empty `TEST_ENV_NUMBER`, hence `worker-.json`. JSON RSpec durations exclude spec-file loading time. Worker identity is taken from the formatter filenames rather than completion order.

### Exhaustive latest failure list and observed roots

1. **Worker 8 — `spec/models/authentication/user_identity_spec.rb:75`**, example ID `./spec/models/authentication/user_identity_spec.rb[1:2:4]`: “preserves passwordless creation and name-only updates.” The fixture at :76 calls `build(:user, password: nil, allow_blank_password: true)`; the assertion at **:77** raises `RSpec::Expectations::ExpectationNotMetError` because the built user has **`customer_id: nil`** and validation reports **`Customer can't be blank`**. The root assertion frame is `user_identity_spec.rb:77`; the complete expectation/RSpec trace is in worker 8 JSON. Raw failure block starts at **617**, exact rerun selector at **695**. The subsequent name-only update assertion at :78 is not reached.
2. **Worker 1 — `spec/services/developer_docs/repository_spec.rb:30`**, example ID `./spec/services/developer_docs/repository_spec.rb[1:3]`: “builds topic cards for every non-home page without using the contents query.” The assertion at **:40** expects `repository.page("overview", query: "missing query").groups` to be empty, but receives a nonempty `operations` group containing `customer-documentation`. Source inspection confirms that **`doc/reference/en/customer-documentation.md:228` now contains the literal phrase “missing query”** in its browser synchronization description; `DeveloperDocs::Repository#matches?` performs case-insensitive substring matching across title, summary and body (`app/services/developer_docs/repository.rb:188–191`). The formerly absent search term therefore matches real source content. The root assertion frame is `repository_spec.rb:40`; full backtrace is in worker 1 JSON. Raw failure block starts at **722**, exact rerun selector at **797**.

Both failures are `RSpec::Expectations::ExpectationNotMetError`. No failure was repaired or rerun by this verification dispatch.

### Previous-cohort reconciliation and final gate

The five files responsible for all 30 failures in the preceding full run now pass **55 current examples / 0 failures** in this complete execution:

| Previously failing file | Current passing examples |
| --- | ---: |
| `spec/system/search_palette_spec.rb` | 2 |
| `spec/models/current_platform_owner_spec.rb` | 6 |
| `spec/services/page_content_generator_composite_spec.rb` | 4 |
| `spec/services/page_shortcuts/public_path_spec.rb` | 7 |
| `spec/services/websites/home_site_spec.rb` | 36 |
| **Total** | **55** |

**Latest full RSpec gate: FAIL — 25,266 / 2.** This dispatch appended only this audit section. No application/spec content edits, subagents, test skips/deletions, serial full run, automatic full-suite rerun, asset rebuild or standalone server restart were performed. The tracked generator audit YAML was not modified/restored by this dispatch. The exact remaining selectors, worker statistics and complete logs are available for the parent coordinator.

## Last-two test-fixture repair — 2026-10-12

**Targeted gate: PASS — both failed selectors pass (2 examples / 0 failures), and the four-file adjacent cohort passes 141 examples / 0 failures in randomized order with seed 81721200.** Both passing runs have zero pending examples and zero outside-example errors. The two-selector run overlaps the cohort; these counts are not a new full-suite aggregate. The historical **25,266 / 2** complete execution remains the latest full-suite evidence.

### Reproduced causes and narrow changes

1. **Passwordless fixture had an unsaved customer association.** The original `build(:user, password: nil, allow_blank_password: true)` builds its `Customer` too. `RandomIdGeneratable` assigns the customer's ID in `before_create`, so that association has `new_record? == true`, `id == nil` and leaves the user with `customer_id == nil`. A fresh-process probe after `Current.reset` confirmed exactly that representation and only `customer_id: ["can't be blank"]` validation errors. This reproduces without leaked tenant/role state. `spec/models/authentication/user_identity_spec.rb` now builds the passwordless user with `customer: account.customer`, reusing this example's actual persisted account tenant. Passwordless validity and the subsequent name-only update remain asserted; mandatory tenant validation is unchanged.
2. **Negative search fixture became searchable prose.** `missing query` now legitimately occurs in the English customer-documentation article. The repository's substring search correctly returns that article. `spec/services/developer_docs/repository_spec.rb` now uses a deterministic namespaced nonce, checked absent from `doc/reference/**/*.md` and shorter than the 80-character query limit. The hub/card assertions, positive searches and navigation/cache isolation cases remain intact. No search implementation was changed.

The exact two original selectors reproduced **2 examples / 2 failures** before edits. Only these two spec lines were changed. Paired test-contract notes were added to `doc/reference/{en,zh-CN}/authentication.md` and `customer-documentation.md`; the nonce itself is not included in the searchable reference prose. No application source, global factory behavior, automatic tenant setup or database mocking was added.

### Isolated preparation and exact commands

`ls -ld storage /tmp/opencode` verified both parents, and directory inspection confirmed the new database path was absent before preparation. All commands remove the browser preload and competing database/auth/worker overrides:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_last_verify.sqlite3 bin/rails db:schema:load
```

Preparation exited 0. Pre-fix reproduction:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_last_verify.sqlite3 bundle exec rspec spec/models/authentication/user_identity_spec.rb:75 spec/services/developer_docs/repository_spec.rb:30 --order defined --format progress --format json --out /tmp/opencode/rspec-last-baseline.json
```

**Exit 1: 2 examples, 2 failures**, 0.37 seconds; load 2.65 seconds. The error messages match the full-run inventory above.

Exact failed-selector verification after the fixture/docs edits:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_last_verify.sqlite3 bundle exec rspec spec/models/authentication/user_identity_spec.rb:75 spec/services/developer_docs/repository_spec.rb:30 --order defined --format progress --format json --out /tmp/opencode/rspec-last-selectors.json
```

**Exit 0: 2 examples, 0 failures**, 0.59 seconds; load 2.28 seconds.

Full affected files plus adjacent authentication model/credential subset, mixed order:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_last_verify.sqlite3 bundle exec rspec spec/models/authentication/user_identity_spec.rb spec/services/developer_docs/repository_spec.rb spec/models/authentication/user_spec.rb spec/models/authentication/user_credential_revocation_spec.rb --order random --seed 81721200 --format progress --format json --out /tmp/opencode/rspec-last-adjacent.json
```

**Exit 0: 141 examples, 0 failures**, 9.02 seconds; load 2.59 seconds. Official JSON independently confirms:

| File | Examples | Failures |
| --- | ---: | ---: |
| `spec/models/authentication/user_identity_spec.rb` | 9 | 0 |
| `spec/services/developer_docs/repository_spec.rb` | 25 | 0 |
| `spec/models/authentication/user_spec.rb` | 90 | 0 |
| `spec/models/authentication/user_credential_revocation_spec.rb` | 17 | 0 |
| **Total** | **141** | **0** |

Post-run verification:

```bash
env -u DATABASE_URL -u RUBYOPT -u SKIP_AUTH -u TEST_ENV_NUMBER -u E2E_DATABASE_PATH RAILS_ENV=test TEST_DATABASE=storage/rspec_last_verify.sqlite3 bin/rails runner 'puts({database: ActiveRecord::Base.connection_db_config.database, customers: Customer.unscoped.count, users: Authentication::User.unscoped.count, roles: Role.unscoped.count, role_assignments: UsersRole.count}.inspect)'
```

**Exit 0:** selected database `storage/rspec_last_verify.sqlite3`; customers, users, roles and role assignments all **0**. Scoped `git diff --check` passed. The JSON paths above preserve both failing reproduction and actual passing inventories. This dispatch ran targeted scopes only and used no subagents or full-suite rerun.

## Completion eight-worker full-suite verification — 2026-10-12

**FAIL: 25,266 examples, 1 failure across one file; 1,576 spec files dispatched to eight workers.** All eight workers completed. **25,265 examples passed**, with **0 pending examples** and **0 errors outside examples**. This is one newly requested complete execution following the last-two fixture repairs. The historical **25,266 / 2**, **25,226 / 30** and **25,053 / 442** results remain preserved above.

### Exact commands and raw command timing

`storage` and `/tmp/opencode` were rechecked with `ls -ld` before loading schemas or creating formatter output. The unique `rspec-completion-worker-` prefix was verified absent. Commands used working directory `/home/ec2-user/anysys`, the absolute Rails executable and the same fully isolated environment cleanup. No browser environment file was sourced.

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:load_schema
```

Schema loading succeeded; raw shell timing: **`real 0m9.108s`**, `user 0m43.597s`, `sys 0m5.301s`. It was followed by:

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:prepare && time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails 'parallel:spec[,,--format progress --format json --out /tmp/opencode/rspec-completion-worker-$TEST_ENV_NUMBER.json --no-color --backtrace]'
```

Preparation succeeded with **`real 0m9.813s`**. The full spec command returned nonzero with `Tests Failed`. Parallel runner duration: **516 seconds (8:36)**. Raw spec-command shell timing: **`real 8m38.508s`**, `user 28m34.174s`, `sys 0m57.674s`. Combined initial schema-load, prepare and spec-command shell wall time: **537.429 seconds (8:57.429)**.

The task arguments add only official progress/JSON formatters, full backtraces and uncolored output; no test pattern/filter was supplied. The unset overrides leave the configured worker databases at `storage/test.sqlite3` and `storage/test2.sqlite3` through `storage/test8.sqlite3`. No development/browser database schema command or schema dump was issued.

### Complete output and all eight worker results

Complete stdout/stderr:

`/home/ec2-user/.local/share/opencode/tool-output/tool_12ebfb799001HA9lPLd4BvJwtk`

The raw log contains **778 lines**: dispatch at **5**, aggregate at **772**, runner elapsed time at **774**, and spec-command shell timing at **776–778**. Each official JSON artifact includes every example ID, source location, status and duration; worker 2 also contains the unabridged failure backtrace. All eight JSON files parsed successfully and contain **25,266 distinct example IDs**, matching the runner aggregate.

| Worker | Examples | Failures | Pending | Outside-example errors | RSpec duration (seconds) | Official JSON artifact | Raw summary line |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | 2,667 | 0 | 0 | 0 | 473.886 | `/tmp/opencode/rspec-completion-worker-.json` | 763 |
| 2 | 4,862 | 1 | 0 | 0 | 417.291 | `/tmp/opencode/rspec-completion-worker-2.json` | 731 |
| 3 | 2,746 | 0 | 0 | 0 | 508.463 | `/tmp/opencode/rspec-completion-worker-3.json` | 768 |
| 4 | 2,772 | 0 | 0 | 0 | 470.102 | `/tmp/opencode/rspec-completion-worker-4.json` | 758 |
| 5 | 2,887 | 0 | 0 | 0 | 425.976 | `/tmp/opencode/rspec-completion-worker-5.json` | 743 |
| 6 | 3,236 | 0 | 0 | 0 | 428.081 | `/tmp/opencode/rspec-completion-worker-6.json` | 748 |
| 7 | 3,047 | 0 | 0 | 0 | 403.456 | `/tmp/opencode/rspec-completion-worker-7.json` | 640 |
| 8 | 3,049 | 0 | 0 | 0 | 461.068 | `/tmp/opencode/rspec-completion-worker-8.json` | 753 |
| **Total** | **25,266** | **1** | **0** | **0** | | | **772** |

Worker 1 uses the empty `TEST_ENV_NUMBER` suffix. Worker identity comes from the formatter filename, not completion order. JSON RSpec durations exclude spec-file loading time.

### Sole failure: exact selector and observed root trace

- **Worker 2:** `spec/system/entities_attribute_grouping_spec.rb:56`, example ID `./spec/system/entities_attribute_grouping_spec.rb[1:1:1]` — “creates the group, shows the header, persists across page reload.”
- **Failing assertion:** `spec/system/entities_attribute_grouping_spec.rb:70`, `expect(toolbar).to have_text("2 selected")`.
- **Exception:** `RSpec::Expectations::ExpectationNotMetError` — `expected to find text "2 selected" in "1 selected\nMove to group ▾\nClear selection"`.
- The spec clicks the first-name and last-name attribute checkboxes at **:65–66**, then finds the visible grouping toolbar at :69. Its displayed selection count is one at the failed assertion. The group creation/save/reload portion is not reached. The other two grouping examples **passed** in the same full run. This trace establishes the browser selection mismatch; it does not establish a specific timing/controller cause.
- **Root trace frame:** `./spec/system/entities_attribute_grouping_spec.rb:70:in 'block (3 levels) in <main>'`. Complete expectation/Capybara/RSpec trace is preserved in `/tmp/opencode/rspec-completion-worker-2.json` and the raw failure block starting at **647**. Exact failed-selector output is at **735**.
- **Screenshot:** `tmp/capybara/failures_r_spec_example_groups_admin_maintenance_entity_attribute_inline_grouping_creating_a_new_group_and_assigning_attributes_creates_the_group__shows_the_header__persists_across_page_reload_976.png`.

### Last-two reconciliation and current gate

Both files from the previous **25,266 / 2** full-run failure list pass completely in this execution:

| Previously failing file | Examples | Failures |
| --- | ---: | ---: |
| `spec/models/authentication/user_identity_spec.rb` | 9 | 0 |
| `spec/services/developer_docs/repository_spec.rb` | 25 | 0 |
| **Total** | **34** | **0** |

**Latest full RSpec gate: FAIL — 25,266 / 1.** This verification dispatch appended only this audit section. No application/spec edits, subagents, skipped/deleted tests, serial full run, automatic full-suite retry, asset rebuild or standalone server restart were performed. Earlier JSON artifacts and historical reports remain preserved. The tracked generator audit YAML was not modified/restored by this dispatch. The remaining browser selector is returned to the parent with its exact observed evidence.

## 2026-10-12 — Final grouping system-spec readiness repair

**Targeted gate: PASS — all three grouping examples pass under three different randomized orders: 9 example executions, 0 failures, 0 pending, 0 outside-example errors.** This is a QA-harness repair in `spec/system/entities_attribute_grouping_spec.rb`, plus this report note. The historical **25,266 / 1** eight-worker result above remains the latest complete-suite evidence; no full suite was executed for this follow-up.

### Browser/runtime evidence and attribution

- Inspected the original worker-2 JSON/backtrace and screenshot `...persists_across_page_reload_976.png`. The screenshot shows **first-name and last-name native checkboxes both checked**, email unchecked, but the toolbar displaying **“1 selected”**. That is a DOM/application selection mismatch, rather than the second checkbox simply remaining unchecked.
- Inspected the server-rendered checkbox action (`change->entity-form#toggleAttributeSelection`), controller `connect()`, `GroupManager` selection handling, and `SchemaManager` regrouping. The selection handler updates its `Set` and toolbar synchronously from the native `checked` property. Group assignment moves the existing rows, clears selection, and synchronizes the form schema.
- Used `/tmp/opencode/grouping-runtime-trace.rb` to collect passive, document-start DOM/mutation observations, controller/row identities, and capture/bubble snapshots of trusted native mouse/input/change events. It does not invoke controller actions, write selection state, delay application initialization, or stub application behavior.
- The unmodified golden-path diagnostic passed **1 example / 0 failures** (`/tmp/opencode/grouping-runtime-observed.json`). Its initial document had all three unchecked rows at `DOMContentLoaded` (**1370.5 ms**) and `load` (**1383.5 ms**) while `getControllerForElementAndIdentifier(mount, "entity-form")` was still absent. The connected controller/managers were observed at **1479.1 ms**, about **95.6 ms after load**. Thus DOM visibility and even the browser load event are insufficient positive readiness conditions.
- The same diagnostic recorded trusted first-name `change` capture at **1569.5 ms**, followed by selected slugs `["first_name"]` and toolbar **“1 selected”** at bubble **1577.4 ms**. Last-name `change` capture at **1710.9 ms** was followed by `["first_name", "last_name"]` and **“2 selected”** at bubble **1711.5 ms**. Native checked states were respectively `[true, false, false]` and `[true, true, false]` for first-name/last-name/email. Controller and row identities remained stable through both selections.
- The repaired seed-81721200 run also collected passive traces: load occurred at **815.0 ms** with no controller; the connected controller was observed at **960.8 ms**. Both checkbox interactions occurred afterward, with trusted changes producing the same one-selection/two-selection transitions. Creation assigned both rows to one generated group and left email ungrouped; the reload preserved those group IDs. No browser error or unhandled-rejection records were observed.
- **Evidence boundary:** the readiness gap is directly observed, and connected selection/grouping works correctly. The isolated diagnostic did **not** reproduce the historical missed event, so it cannot prove precisely which historical click preceded action attachment. No business-source failure was found in these observations. The repair gates readiness and retains/asserts the actual behavioral outcomes, rather than accepting the mismatch.
- The first temporary trace setup attempt sent `Page.addScriptToEvaluateOnNewDocument` to the browser-level CDP client and failed before navigation with “wasn't found” (`/tmp/opencode/grouping-runtime-baseline.json`, 1 diagnostic setup failure). Correcting the temporary probe to the page-level CDP client enabled the observations above. This was a probe setup error, not an application result.

### Exact states awaited by the spec

1. On each edit-page visit, including the post-save reload, Capybara's **synchronized `find` filter** must find a live `entity-form` mount whose `window.Stimulus.getControllerForElementAndIdentifier` returns a controller with initialized grouping/attribute managers. A controller that never connects still fails at the normal Capybara timeout.
2. First-name uses idempotent Capybara **`check`**, then positively awaits its native `:checked` state and a visible toolbar with **“1 selected”**.
3. The second checkbox is reacquired by row slug. After its `check`, the spec positively awaits **“2 selected”**, both first-name/last-name native `:checked` states, and email's unchecked state. The original toolbar text assertion remains.
4. Save positively awaits the **exact show URL**, replacing a regex that also matched the still-current `/edit` URL. Reload reacquires rows and verifies the same non-empty group ID on both grouped rows, email ungrouped, and **“2 attributes”** on the header.
5. Actual browser `document.documentElement.scrollWidth <= window.innerWidth` is asserted after selection, with the dropdown/modal open, after group assignment, after save, after reload, after deletion, and after grouped-attribute editing. All checks passed at the configured **1400 × 1400** desktop viewport; this run does not claim additional viewport coverage.

**Driver constraint:** `Gemfile:138–140` explicitly replaces Selenium with Cuprite, and `spec/rails_helper.rb` selects Cuprite for JS system specs. `bundle exec ruby -e 'require "selenium-webdriver"'` raises `LoadError`, even though an unbundled system gem exists. Adding a Selenium dependency/driver would exceed the single-spec scope. The repair therefore uses the bundled mature Capybara synchronization mechanism with the requested positive Stimulus lookup; it does not depend on an out-of-bundle `Selenium::WebDriver::Wait`. No explicit sleeps, custom polling loops, example retries, new skips, direct selection writes, or application bypasses were added.

### Database isolation and exact commands

Before creating output/database files, `ls storage /tmp/opencode` verified both parent directories. The environment-key check found no inherited `DATABASE_URL`, `RUBYOPT`, `E2E*`, worker/parallel, `SKIP_AUTH`, `RAILS_ENV`, or `TEST_DATABASE` keys. Schema loading and verification used only `storage/grouping_final_verify.sqlite3`:

```bash
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 /home/ec2-user/anysys/bin/rails db:schema:load
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 /home/ec2-user/anysys/bin/rails runner 'c = ActiveRecord::Base.connection; puts "database=#{c.pool.db_config.database}; entities=#{c.data_source_exists?("entities")}; entity_versions=#{c.data_source_exists?("entity_versions")}; schema_version=#{c.select_value("SELECT MAX(version) FROM schema_migrations")}"'
```

Verified `database=storage/grouping_final_verify.sqlite3`, `entities=true`, `entity_versions=true`, and schema version **20261011190000**. The unmodified diagnostic used:

```bash
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 bundle exec rspec spec/system/entities_attribute_grouping_spec.rb:56 --require /tmp/opencode/grouping-runtime-trace.rb --format documentation --format json --out /tmp/opencode/grouping-runtime-observed.json --no-color
```

All three final whole-file runs used the same isolated database, sequentially. Only the first retained the passive tracing hook; the remaining two ran without it:

```bash
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u PARALLEL_TEST_PROCESSORS -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 bundle exec rspec spec/system/entities_attribute_grouping_spec.rb --seed 81721200 --require /tmp/opencode/grouping-runtime-trace.rb --format documentation --format json --out /tmp/opencode/grouping-final-seed-81721200.json --no-color
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u PARALLEL_TEST_PROCESSORS -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 bundle exec rspec spec/system/entities_attribute_grouping_spec.rb --seed 56 --format documentation --format json --out /tmp/opencode/grouping-final-seed-56.json --no-color
env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_ENV_NUMBER -u PARALLEL_TEST_PROCESSORS -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/grouping_final_verify.sqlite3 bundle exec rspec spec/system/entities_attribute_grouping_spec.rb --seed 25266 --format documentation --format json --out /tmp/opencode/grouping-final-seed-25266.json --no-color
```

| Seed | Order | Examples | Failures | Pending | Outside-example errors | RSpec duration |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 81721200 | create → edit → delete | 3 | 0 | 0 | 0 | 5.833 s |
| 56 | create → delete → edit | 3 | 0 | 0 | 0 | 5.615 s |
| 25266 | delete → edit → create | 3 | 0 | 0 | 0 | 5.782 s |
| **Total executions** | **3 unique examples** | **9** | **0** | **0** | **0** | |

Official JSON summaries and all three expected example IDs were independently parsed/checked for each seed. `ruby -c spec/system/entities_attribute_grouping_spec.rb` returned **Syntax OK**, and scoped `git diff --check` passed. Production builder/JS source and dependency files received no edits from this repair. Any subsequent full validation should be the user-directed eight-worker execution after this fix, not an automatic scoped-run retry promoted to a full-suite claim.

## Passing final eight-worker full-suite verification — 2026-10-12

**PASS: 25,266 examples, 0 failures; 1,576 spec files dispatched to eight workers.** All eight workers completed successfully. **0 pending examples** and **0 errors outside examples**. Every JSON example status is **passed**, and there are no failed files. This is the actual newly requested complete-suite execution after the grouping readiness repair. All earlier failing full-suite results, including **25,266 / 1** and **25,266 / 2**, remain preserved above as historical evidence.

### Exact isolated commands and timing

Before execution, `ls -ld /home/ec2-user/anysys/storage /tmp/opencode` verified both parents and the `rspec-final-pass-worker-` prefix was confirmed absent. Commands used working directory `/home/ec2-user/anysys`, the absolute Rails executable, all six requested unset overrides, `RAILS_ENV=test` and eight parallel workers. No browser environment file was sourced.

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:load_schema
```

Schema loading succeeded: **`real 0m9.426s`**, `user 0m44.376s`, `sys 0m5.308s`. Then:

```bash
time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails parallel:prepare && time env -u DATABASE_URL -u RUBYOPT -u E2E_DATABASE_PATH -u TEST_DATABASE -u TEST_ENV_NUMBER -u SKIP_AUTH RAILS_ENV=test PARALLEL_TEST_PROCESSORS=8 /home/ec2-user/anysys/bin/rails 'parallel:spec[,,--format progress --format json --out /tmp/opencode/rspec-final-pass-worker-$TEST_ENV_NUMBER.json --no-color --backtrace]'
```

Preparation succeeded with **`real 0m9.678s`**. The full spec command succeeded. Parallel runner duration: **543 seconds (9:03)**. Raw spec-command shell timing: **`real 9m6.249s`**, `user 28m35.227s`, `sys 0m55.680s`. Combined initial schema loading, preparation and spec-command shell wall time: **565.353 seconds (9:25.353)**.

Only official RSpec formatter/backtrace options were added; no test pattern/filter was supplied. The configured worker databases were `storage/test.sqlite3` and `storage/test2.sqlite3` through `storage/test8.sqlite3`. No development/browser database schema command or schema dump was issued.

### Complete logs and independently checked worker summaries

Complete terminal stdout/stderr:

`/home/ec2-user/.local/share/opencode/tool-output/tool_12ee8a7c0001a8pLrTTdmP5l4L`

The raw log contains **688 lines**: eight-worker/1,576-file dispatch at **5**, aggregate at **682**, runner elapsed time at **684**, and shell spec-command timing at **686–688**. All eight official JSON artifacts parsed successfully; they contain **25,266 distinct example IDs**, all with status `passed`, matching the terminal aggregate. Each worker independently reports zero failures, pending examples and outside-example errors.

| Worker | Examples | Failures | Pending | Outside-example errors | RSpec duration (seconds) | Official JSON artifact | Raw summary line |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| 1 | 3,082 | 0 | 0 | 0 | 427.301 | `/tmp/opencode/rspec-final-pass-worker-.json` | 564 |
| 2 | 2,702 | 0 | 0 | 0 | 398.036 | `/tmp/opencode/rspec-final-pass-worker-2.json` | 522 |
| 3 | 4,586 | 0 | 0 | 0 | 535.238 | `/tmp/opencode/rspec-final-pass-worker-3.json` | 679 |
| 4 | 3,058 | 0 | 0 | 0 | 384.559 | `/tmp/opencode/rspec-final-pass-worker-4.json` | 509 |
| 5 | 2,798 | 0 | 0 | 0 | 475.505 | `/tmp/opencode/rspec-final-pass-worker-5.json` | 673 |
| 6 | 3,051 | 0 | 0 | 0 | 409.165 | `/tmp/opencode/rspec-final-pass-worker-6.json` | 527 |
| 7 | 2,854 | 0 | 0 | 0 | 447.807 | `/tmp/opencode/rspec-final-pass-worker-7.json` | 570 |
| 8 | 3,135 | 0 | 0 | 0 | 448.001 | `/tmp/opencode/rspec-final-pass-worker-8.json` | 575 |
| **Total** | **25,266** | **0** | **0** | **0** | | | **682** |

Worker 1 uses the empty `TEST_ENV_NUMBER` suffix. Worker identity comes from its formatter filename. JSON RSpec durations exclude spec-file loading time; full-precision values remain in the official artifacts.

### Final repaired-cohort confirmation and source review

The previously failing grouping file passed all **three** examples on worker 4. The golden-path example retains ID `./spec/system/entities_attribute_grouping_spec.rb[1:1:1]` and now has definition line **73**; deletion/edit examples at **189** and **245** also passed. The complete file therefore passes inside the full-suite worker context, including selection, creation, save/reload persistence, deletion and grouped-attribute editing.

The last two fixture-repair files also pass completely: `spec/models/authentication/user_identity_spec.rb` **9 / 0**, and `spec/services/developer_docs/repository_spec.rb` **25 / 0**. These three final repaired files contribute **37 examples / 0 failures** within the passing aggregate.

Post-run scoped diff inspection recorded the existing parent changes: **four added lines** in `app/javascript/controllers/ai_assistant_controller.js` for the `conversationIdValueChanged` notification hook, and the grouping spec's QA changes (**46 insertions, 6 deletions**). These working-tree changes were preserved; this verification dispatch authored no application/JavaScript/spec edits. The source inspection is separate from the parent's earlier JavaScript test evidence.

**Latest full RSpec gate: PASS — 25,266 / 0.** This dispatch appended only this audit section. It ran one user-requested full eight-worker execution, with no automatic full-suite retry, serial fallback, subagents, skipped/deleted tests, asset rebuild or standalone server restart. Existing schema changes, the tracked generator audit YAML and all previous logs/reports were preserved. No remaining failed selectors were reported.
