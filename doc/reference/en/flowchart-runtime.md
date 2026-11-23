---
title: "Flowchart runtime"
summary: "A saved flowchart compiles to one Railway step per canvas box, with Routes signals, a collect_errors failure track, merge reads through Outputs, and a CANVAS map the tracer uses. Steps call FlowchartRuntime helpers within a 10-second run deadline, report failures through Step.fail, and can shape the submission outcome."
---

## Summary

There is no canvas interpreter. `Flowchart` `before_save :generate_activity` stores Ruby source in the `activity` column. `ActivityGenerator#generate` returns that source, a subclass of `Trailblazer::Activity::Railway` with one `step` per box, `Routes` signals for decisions and loop exits, `fail :collect_errors`, and an embedded `CANVAS` map. On submit, `Pages::PublicSubmission` loads the source with `ActivityClassBuilder` and runs it through `ActivityTracer#call(input, trace: false)` (plain `activity_class.call`, no trace). The editor test panel uses the same tracer with tracing on (`Trailblazer::Developer::Trace.invoke`). Step bodies call `FlowchartRuntime` helpers: record steps go through `FlowchartRuntime::Entries`, and every failure goes through `FlowchartRuntime::Step.fail`, which writes a translated message to `ctx[:errors]` and a structured entry to `ctx[:error_details]`. A step can also write `ctx[:submission_outcome]`, which decides where the submitter lands and whether a payment handoff starts. See [flowchart-builder](flowchart-builder), [code-generators](code-generators), [flowchart-step-actions](flowchart-step-actions), and [page-rendering](page-rendering).

## Flow

```text
Flowchart save
        |
        |  before_save :generate_activity
        |  skip when override_customer_id is present
        v
ActivityGenerator#generate
        |
        |  nil if name blank or elements empty
        |  else Trailblazer::Activity::Railway source
        v
flowcharts.activity

POST /:cid/page/:uuid
        |
        v
PublicPagesController#submit
        |
        v
Pages::PublicSubmission#execute_activity
        |
        |  Authentication::PasswordEffects.transaction
        v
ActivityTracer#call(ctx, trace: false)
        |
        |  ActivityClassBuilder#build_activity_class
        |    DynamicClassLoader#load_into
        |    Module#module_eval(activity source)
        v
activity_class.call([input, {}])
        |
        |  step methods call FlowchartRuntime::Entries.scope(ctx) and FlowchartRuntime::*
        v
Result success? / signal / ctx / submission_outcome
        |
        |  success + new primary entry + bridge sections
        v
Pages::BridgeEntries (same savepoint)
        |
        |  submission_outcome.handoff (payment) -> FeatureModules::Invocation.begin!(module_key: "payment")
        |  else page.handoff?                   -> FeatureModules::Invocation.begin!
        v
redirect: handoff URL > outcome page > default post-submit path
```

The editor test panel POSTs to `FlowchartTracesController#create`, which calls `ActivityTracer#call(input)` (trace on) and adds `FlowchartRuntime::QueryLogger.capture`. Traced and untraced runs both execute inside `FlowchartRuntime::RunContext.with_deadline(10)` and `Timeout.timeout(10)` (`ActivityTracer::EXECUTION_TIMEOUT_SECONDS`). A timeout is a failed `Result`. The transaction rolls back unless `trace.success?`.

## Implementation

`ActivityGenerator#initialize` reads `flowchart.elements` and `flowchart.connections`, sets `@bound_entity` to `flowchart.entity`, and builds `DynamicClassLoader.new(bound_entity)`. `generate` returns nil when `flowchart.name` is blank or `elements` is empty. Structure errors that are an invalid loop raise `ActivityGenerator::Error` with code `:invalid_loop_topology`. Unsupported structural types raise `:unsupported_structural_element`. Any other structure failure is logged and `generate` returns nil. A successful generate walks the graph depth-first via `CodeGenerators::GeneratorRegistry` and emits one `Trailblazer::Activity::Railway` class.

`Flowchart#generate_activity` assigns `self.activity` from `generate`. It returns first when `override_customer_id` is present, so a tenant override of a shared flowchart does not replace the global source. See [shared-resources](shared-resources). `ActivityGenerator::Error` re-raises in test and, elsewhere, leaves the previous `activity` value. Other `StandardError`s re-raise in test and, elsewhere, store a comment beginning `# ActivityGenerator failed:`.

`Pages::PublicSubmission` reads `configuration_json["form_settings"]["flowchart_id"]`. It loads `Flowchart.accessible.referenceable` (`status: :launched`). A blank `activity` returns an `:invalid` result with HTTP status `:unprocessable_entity`. The page entity is required. A customer-owned flowchart whose `entity_id` differs from the page entity returns `:invalid`. A shared flowchart has `entity_id` nil (`Flowchart#entity_binding_based_on_shared_identity`), so that mismatch check does not apply. The context hash is described under "Context contract" below.

`ActivityClassBuilder#build_activity_class` creates an anonymous module, calls `DynamicClassLoader#load_into`, `module_eval`s each subflow `activity` string once (`loaded_ids` skips a child that is already in the namespace — two references to one subflow do not re-eval `CANVAS`), then `module_eval`s the main source. The new constant that subclasses `Trailblazer::Activity::Railway` is the class that runs. `DynamicClassLoader` builds accessors from `entity.property_schema_json` and a contract from `EntityEntryContract.build_for` when an entity is present. With a nil entity it defines `BlueprintEntity` and `BlueprintEntityContract`. Record steps in the generated source use the page entity at runtime through `FlowchartRuntime::Entries`, including `new_model` (`Entries.scope(ctx).new(customer_id: ctx[:customer_id])`).

`FlowchartRuntime` is the set of helpers those generated methods call (`app/services/flowchart_runtime/`). The Phase 3 contracts are described in the subsections below: `Step`, `RunContext`, `Entries`, `Http`, and the helpers behind the new actions. Other helpers include `QueryBuilder`, `Authentication.session` / `.password`, `Jwt`, `Invocable.service!` / `.job!`, `ConditionInput.compare`, `Token`, `Crypto`, `SandboxPath`, `Errors.collect`, `Outputs.latest` / `.view`, and `Loop` / `LoopState` / `ExecutedOutputs`. `Invocable` resolves allow-listed class names and permits a method only when it is defined under `app/` (not Object / Kernel / BasicObject / Module / Class). It rejects ActiveRecord model classes and destructive methods (`delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection`). `SERVICE_NAMESPACES` includes `FeatureModules`, so an invoke-service step may call a class in that namespace. There is no generated step that calls `FeatureModules::Invocation`; `request_payment` only parks a handoff in `ctx[:submission_outcome]`, and the controller starts it (see "Submission outcome"). See [module-framework](module-framework).

`ActivityTracer#call` converts `input[:params]` to a `HashWithIndifferentAccess` before execution, so emitted readers (`ctx[:params][:amount]`) work for public submissions (string keys) and the admin test runner alike. The editor test runner (`FlowchartTracesController#create`) seeds the same runtime keys as `Pages::PublicSubmission#build_context` after the posted input (`bound_entity` is the traced flowchart's entity, or nil when the flowchart is shared and has none) and runs every trace inside `ActiveRecord::Base.transaction(requires_new: true)` that always rolls back. Database writes from the test run do not persist; emails, webhooks, and cache writes are not suppressed. Success is `signal.to_h[:semantic] == :success`. `PublicSubmission` treats a non-success signal, a tracer error, or a raised exception as `:failed`. On success it returns `ctx[:model]` when that value is an `EntityEntry`.

Decision and loop conditions that use `> >= < <=` emit `FlowchartRuntime::ConditionInput.compare`. Both sides must be finite Numeric or numeric strings (`"150" > 100` is true). A non-numeric side, or a non-finite coerced value (`Infinity`, `NaN`, overflow such as `1e309`), makes the comparison false. Unsupported operators raise `ArgumentError`. Equality and string operators stay Ruby operators.

`authorize` checks the value of `userExpression` (default `current_user`) only when it is an `Authentication::User`; otherwise it uses `FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`. The Hash that `load_current_user` writes never grants access. A denial fails with `authorize.denied`. `send_template_email` resolves the customer from `ctx[:customer_id]`. `EntityEntryContract` passes Integer values to `length_minimum` / `length_maximum`.

### Generated class shape

Each canvas box that is not Start and not a stepless End becomes one Railway step and one `def <name>(ctx, **)`. The body is the action's emitted code and nothing else: there is no step-level condition, retry or timeout wrapper, and no lambda around the action. An empty Process box emits `true`.

Decisions declare one `Routes::<Decision>::<Branch>` signal per outgoing connection, in `fromPort` order, and wire each with `Output(signal, :semantic) => Id(...)`. The unused default success output is `Output(:success) => Track(:failure)`, so a decision that returns no branch signal fails loudly. `routeBy: condition` emits a ternary that returns the Yes signal or the No (else Otherwise) signal; `routeBy: value` emits `case <subject>.to_s` / `when` / `else`, where `else` is the Otherwise branch (empty `matchValue`), else the last branch.

An End whose `responseType` is `none` has no step; incoming edges wire to `End(:success)`. An End whose `responseType` is `value` is a step that writes `returnValue` to `ctx[:response]` and then succeeds. Every End is a success terminus.

A Subflow is `step Subprocess(<ChildActivity>), id: :<name>` with the same wiring rules. Two references to one child get distinct step ids. `generate_body` on `SubflowGenerator` is nil — the orchestrator emits the `Subprocess` declaration.

The class embeds `CANVAS = { steps:, routes:, ends: }.freeze`. `steps` maps every step id to its element id. `routes` maps each decision (or loop `:done`) semantic to its connection id. `ends` maps a step's output semantic to the stepless End element it reaches. `routes` and `ends` are omitted when empty. The tracer and diagram read this map from the class that ran.

```ruby
# frozen_string_literal: true
#
# Generated from flowchart #99 "Two Level". Do not edit; regenerate it from the flowchart editor.
# No bound entity
class TwoLevelActivity < Trailblazer::Activity::Railway
  CANVAS = {
    steps: { is_vip: "outer", is_rush: "inner", fast_path: "fast", slow_path: "slow", standard_path: "standard" },
    routes: { is_vip: { yes: "c2", no: "c3" }, is_rush: { yes: "c4", no: "c5" } },
    ends: { fast_path: { success: "end_ok" }, slow_path: { success: "end_ok" }, standard_path: { success: "end_other" } }
  }.freeze

  module Routes
    module IsVip
      Yes = Class.new(Trailblazer::Activity::Signal)
      No = Class.new(Trailblazer::Activity::Signal)
    end
    module IsRush
      Yes = Class.new(Trailblazer::Activity::Signal)
      No = Class.new(Trailblazer::Activity::Signal)
    end
  end

  step :is_vip,
    Output(Routes::IsVip::Yes, :yes) => Id(:is_rush),
    Output(Routes::IsVip::No, :no) => Id(:standard_path),
    Output(:success) => Track(:failure)
  step :is_rush,
    magnetic_to: nil,
    Output(Routes::IsRush::Yes, :yes) => Id(:fast_path),
    Output(Routes::IsRush::No, :no) => Id(:slow_path),
    Output(:success) => Track(:failure)
  step :fast_path, magnetic_to: nil, Output(:success) => End(:success)
  step :slow_path, magnetic_to: nil, Output(:success) => End(:success)
  step :standard_path, magnetic_to: nil
  fail :collect_errors

  # Is Vip
  def is_vip(ctx, **)
    (!!ctx.dig(:vip)) ? Routes::IsVip::Yes : Routes::IsVip::No
  end
  # …
end
```

Header, naming, and wiring rules live on [code-generators](code-generators).

### Errors contract

Every generated class ends with `fail :collect_errors`:

```ruby
def collect_errors(ctx, **)
  ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
end
```

`FlowchartRuntime::Errors.collect(ctx)` returns the unique messages already in `ctx[:errors]` (written by `Step.fail` or a child flow) followed by the full messages of every top-level ctx value that responds to `errors.full_messages` (Reform contracts, Active Model records).

### Step failures

`FlowchartRuntime::Step` is the only failure path generated steps use:

- `Step.fail(ctx, code, field: nil, **details)` appends `I18n.t("flowchart_runtime.errors.#{code}", **details)` to `ctx[:errors]` (deduplicated) and `{ "code", "field", "details" }` (details stringified) to `ctx[:error_details]`, then returns `false` so the Railway step fails. Codes are generic (`record_not_found`, `record_invalid`, `record_not_destroyed`, `record_busy`, `timed_out`, `transport_error`, `http_status`, `circuit_open`, `rate_limited`, `duplicate_request`, `invalid_json`, `business_error`, `unknown_attribute`, `blocked_destination`, `loop_limit`) or action-scoped (`register_member.public_only`, `register_member.person_entity_required`, `register_member.signup_disabled`, `register_member.unavailable`, `send_sms.quota`, `refund_payment.not_found`, …).
- `Step.fail_message(ctx, localized, code: :business_error, field: nil)` uses an author-written `{ "en", "zh-CN" }` message (`fail_with_error`), resolved with `LocalizedText.resolve` for the request locale.
- `Step.attempt(ctx, code, *error_classes) { … }` rescues only the listed classes, fails with `reason:` set to the demodulized class name, and stores the exception message as `"diagnostic"` on the last `error_details` entry. The diagnostic is for traces and logs; the flash shows only the translated message.
- `Step.dig(value, *keys)` is the nested read that `input` paths compile to: indifferent Hash keys, Integer indexes into Arrays, `nil` on any miss.

`ctx[:error_details]` appears in the test-run JSON `context` (sanitized and redacted); it never reaches the public flash.

### Run deadline

`FlowchartRuntime::RunContext` is a `CurrentAttributes` deadline. `ActivityTracer` sets it with `with_deadline(10)`; `RunContext.remaining` returns the seconds left (10 when no deadline is set, e.g. in a unit test). HTTP helpers clip their timeouts to it. Step actions must not call `Timeout.timeout` or `sleep` themselves (BodyLint, see [code-generators](code-generators)).

### Context contract

A run starts with `ConfigSchema::SEEDED_KEYS`. `Pages::PublicSubmission#build_context` seeds `params` (the primary entity's flat attributes after `FormParams.permit_parts` and `Pages::AudienceGuard`), `association_params` (bridge sections keyed by section slug, only when the form declares bridge fields), `bound_entity` (the page entity), `customer_id`, `authentication` (`FlowchartRuntime::Authentication.from_request`), `current_user_id`, `current_user_role`, `audience`, `device_type` (nil values dropped) and `current_person_ids` (`{ "<person entity id>" => entry_id }` from `People::Ownership.person_entry_ids` for a same-tenant viewer; `{}` for anonymous, unlinked, or other-tenant viewers), then `request_ip` (`Current.ip_address`), `user_agent`, `locale`, `request_id`, `identity` and `continuation`. `ActivityTracer#call` merges `flowchart_id: flowchart.id` into every run, overriding any posted value. `FlowchartTracesController#create` seeds the same keys for test runs (`request.remote_ip`, `request.request_id`).

`ctx[:identity]` is a string-keyed hash of the identity fields (`People::IDENTITY_KEYS`: `first_name`, `last_name`, `email`) whose `source: "identity"` field is placed on the page. `FormParams.permit_identity` allows it only for a person-entity page and only for the public and admin audiences; members get `{}`. Unknown keys (including `identity[password]`) are dropped. Identity never enters `ctx[:params]`. Generic record steps (`save_model`, `Entries.assign`, `ActivitySteps::PopulatePrimary`) never write those keys; only `FlowchartRuntime::Registration` copies them onto an unlinked person entry.

`ctx[:continuation]` is symbol-keyed `{ action_key:, prefill: }` or nil. `Pages::Continuation.verify` reads posted `_continuation` (purpose `page_continuation`, 3 days). The token carries no URL and no customer id. Tampered, expired, wrong-purpose or oversized tokens verify to nil; the submission still succeeds. See [Page rendering](page-rendering).

An `output` field may not name a seeded key or `errors`, `error_details`, `submission_outcome`, `result` (`OUTPUT_RESERVED`); `submission_outcome` is written by `set_submission_outcome`, `request_payment`, and `register_member` (preset `registration_pending` only when none is already set). An `input` path may not start at `errors`, `error_details`, `submission_outcome` or `result`.

### Records

`FlowchartRuntime::Entries` is the record helper:

- `scope(ctx)` — `EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)` for `ctx[:bound_entity]`, `EntityEntry.none` when nothing is bound. `scope_for(ctx, entity)` does the same for another entity after `EntityResolver.accessible?`, else raises `Entries::Error`. These scopes are **not** passed through `People::Ownership`: a capacity check must count every enrollment.
- `find_current_person(ctx, entity_id:)` — the viewer's linked entry of the bound person entity. Reads only `ctx[:current_person_ids]` (`{ "<person entity id>" => entry_id }`), never params. Returns the entry when it still exists in the run tenant and belongs to the bound entity. Returns nil when the bound entity is not a person entity, the map is missing, or nothing is linked. `find_model` with `findBy: current_person` calls this and fails `record_not_found` on nil.
- `find_by` / `where` — `id` is a column predicate; other keys use `json_extract` on `data.<slug>` (validated by `JsonPathValidator`). An unknown slug raises `Entries::UnknownAttribute`.
- `assign(entry, attributes, strict: false)` — writes only writable attribute slugs; `INTERNAL_COLUMNS` (`id customer_id entity_id entity_version_number user_id data created_at updated_at`) are ignored, and `strict: true` raises on an unknown key.
- `save(ctx, entry)` — refuses an entry of another customer; on validation failure appends `errors.full_messages` to `ctx[:errors]` with a `record_invalid` detail and returns false.
- `upsert(ctx, match:, attributes:)` — takes a single-attempt `Lock` on a tenant-scoped key for the match digest (else `record_busy`) and returns `[entry, created]`.
- `destroy(ctx, entry)` (`record_not_destroyed`) and `archive(ctx, entry, field:, by_field:)` (stamps `Time.current` and `current_user_id`).
- `query`, `tally`, `aggregate`, `filter` and `where_attributes` back the query actions.

#### Shared model and contract write boundaries

`EntityEntry.build_for(entity)` skips schema slugs matching `EntityEntry.column_names + %w[entity customer]`, preserving authoritative AR columns and those associations. Calculated/Computed schema accessors have readers without generated writers. Anonymous runtime subclasses return `EntityEntry.model_name` for Rails/I18n validation errors and `RecordInvalid`, while retaining the parent's table and STI identity. This is the runtime factory guard, not a change to the separate `ModelGenerator`/`attribute_accessor` DSL.

`EntityEntryContract.build_for(entity, audience: nil, writable_slugs: nil)` retains declared property readers and the existing audience-scoped validators. Only `presence` (and `acceptance`) can reject a blank value: every other validator gets `allow_blank: true` (`ValidatorRegistry::REQUIRING_VALIDATIONS`), so an optional number, list choice or email may stay empty and is checked only when filled. `schema_property_options` marks `type: "Calculated"`, `type: "Computed"`, or `storage: "computed"` properties with Reform 2.6's **`writeable: false, parse: false`**. `parse: false` ignores submitted values; `writeable: false` prevents `sync` and `save` from invoking model setters, so derived values are not persisted into `data`. It does not calculate a missing value or remove its validation: an applicable validator can still reject the model-derived/current value.

A non-nil `writable_slugs` allowlist (normalized to strings by the factory) applies the same flags to every excluded property, retaining existing values and preventing hidden nil keys from blanket syncing. With `nil`, ordinary properties retain their normal deserialization/sync behavior; the audience scopes validation and does not itself impose this write allowlist. `ContractGenerator.new(entity, writable_slugs: nil)` calls the same option helper and emits these exact flags through `property_accessor(name, validates: nil, **property_options)`, retaining audience validation guards.

Direct admin **Create Entry** calls `Entities::Activities::CreateEntry` with an admin contract and the form's write allowlist. It resolves the customer's effective schema and saves one primary tenant entry in its own savepoint, with no derived writes, bridge entries or base-model writes. It does not invoke flowchart execution or `ActivitySteps::SaveAll`; that latter helper retains its separate primary-plus-bridge transaction. HTTP endpoints, defaults, supported controls and authorization are described on [Entity builder](entity-builder).

### Runtime helpers behind the step actions

- `CurrentUser.load(ctx)` — a frozen Hash `{ id, email, name, role, person_entries }` for `ctx[:current_user_id]` within `ctx[:customer_id]`, or nil. `person_entries` is `{ "<person entity id>" => entry_id }` from `People::Ownership.person_entry_ids` (same map as `ctx[:current_person_ids]`). `load_current_user` writes it to `ctx[:current_user]`. The Hash never grants access (`authorize` treats it as no principal).
- `QueryBuilder.for_entity(entity, customer_id:, scope:)` — optional `scope:` replaces the default tenant relation. Page lists and query option sources pass `People::Ownership.scope`. Flowchart callers never pass it, so query / count / aggregate steps see every tenant row.
- `Constants.options(ctx, id)` / `label(ctx, id, value)` — read a Constant's options for `ctx[:customer_id]` (never `Current`). A shared constant uses that customer's `ConstantCustomerOverride` when present; another tenant's constant raises `Constants::Error`. Used by `read_setting`.
- `LocalizedText.resolve(value, locale:)` — picks the locale's text, falling back to `en`.
- `Payments.request(ctx, amount:, currency:, subject:)` — see "Submission outcome". Fails with `request_payment.invalid_order` (no customer, blank subject, non-positive amount after `Payments::Money.normalize`) or `request_payment.module_disabled` (Payment module missing, without handoff, or disabled for the customer).
- `Payments.refund(ctx, payment:, amount:, reason:)` — the payment must belong to the run's customer (else `refund_payment.not_found`); runs `Payments::Activities::Refund` under `Current.set(customer:)`. `RefundNotAllowed` maps to `refund_payment.<code>` (`not_captured`, `non_positive`, `exceeds_remainder`, `billing_collection`); other payment errors to `refund_payment.failed`.
- `Sequence.next(ctx, name:, period:, prefix:, padding:)` — per-customer counter in `flowchart_sequences`; `period` `never`, `year` (bucket `%Y`) or `month` (bucket `%Y-%m`); padding 1–12 (default 6). The row is created with `create_or_find_by!` and incremented with an `UPDATE … last_value + 1` inside a transaction.
- `RateLimiter.allow?(ctx, name, capacity:, window:)` — fixed-window counter keyed by customer, name, window length and the current window start, on `Authentication::Throttle#hit!` (an atomic increment in the shared cache store), so concurrent runs cannot both take the last slot. It never sleeps; `rate_limiter` fails with `rate_limited` or skips per `onExceed`. Blank names and non-positive `capacity` / `window` raise `RateLimiter::Error`.
- `Notifications.create(ctx, recipient:, title:, body:, page_id:)` — the recipient must be an `Authentication::User` of the customer (else `create_notification.recipient_not_found`); a page is kept only when launched and owned or shared.
- `Audit.write(ctx, event_type:, …, severity:)` — severities `debug info warn error critical`; inserts a `flowchart_audit_events` row (with `ctx[:flowchart_id]`) when `customer_id` is present and logs an `[AUDIT]` JSON line. The row is part of the run's transaction and rolls back with it.
- `SmsDelivery.deliver(ctx, customer:, to:, template_key:, vars:, idempotency_key:)` — see "SMS sends".
- `Document.pdf(title:, body:, filename:, rows:, columns:, customer_id:)` — renders with Prawn (`##` lines become headings, rows become a ` | ` table), stores an ActiveStorage blob with `customer_id` metadata, and returns `{ blob_id, signed_id, filename, content_type, byte_size, checksum, customer_id }`. Errors raise `Document::Error`, which `generate_document` wraps in `Step.attempt`. The CJK font is used only when the content contains CJK; see [flowchart-step-actions](flowchart-step-actions) for the font fallback.
- `Authentication.token(raw:, expected:, type: "bearer")` and `api_key(raw:, expected:)` — constant-time matches used by `authenticate`.
- `Registration.call(ctx, person:)` — the `register_member` helper. Rule order: (1) fail `register_member.public_only` unless `ctx[:audience]` is public; (2) fail `register_member.person_entity_required` unless the bound entity is a person entity; (3) fail `register_member.signup_disabled` unless the authentication module is enabled and `Authentication::Settings#signup_enabled?` (the step gates this; `RegisterMember` itself does not); (4) invalid identity (presence/format; uniqueness `:taken` is ignored so a live address never fails here) → `record_invalid` like `save_model`; (5) when the normalized email belongs to any existing user, save nothing — if that user is a confirmed active member of this tenant, issue a sign-in link (counted against the sign-in link page's per-address flood bucket; once it trips, no email is sent) and record a continuation-only claim, otherwise do nothing (an unconfirmed member's original claim is left untouched); result `{ "status" => "existing" }`; (6) otherwise register a passwordless unconfirmed member, save the person entry with identity in its `data` and `user_id` nil, record a claim with `created_user: true`; result `{ "status" => "created" }`; (7) a full member quota saves nothing and answers like (5) with `{ "status" => "existing" }` (logged as a warning); a missing customer → `register_member.unavailable`; (8) set submission outcome preset `registration_pending` unless the flowchart already set one. The browser sees the same flash for `created` and `existing`. The existing-address branch goes through `Authentication::NotifyExistingMember`, shared with the sign-up form. Before the email lookup the step stores `ctx[:uniform_timing_started_at]`; `Pages::PublicSubmission` pads the response with `Authentication::UniformTiming` once the submission transaction has committed, so the three branches take the same minimum time (see [Authentication](authentication)). Do **not** branch on `registration.status` — that would reveal which emails have accounts.

### Submission outcome

`ctx[:submission_outcome]` is the only channel from a run back to the page controller. `set_submission_outcome` writes `preset` (`submitted`, `saved`, `thank_you`, `custom`), an optional localized `message` (required for `custom`), `flash` (`notice` / `alert`) and `target` (`{ type: "form" }` or `{ type: "page", page_id }`), keeping any `handoff` already present. `request_payment` adds `handoff: { module_key: "payment", input: { amount, currency, subject } }`. `register_member` sets preset `registration_pending` unless a preset is already present; that value is not in the `set_submission_outcome` enum. `Pages::PublicSubmission::Result#submission_outcome` returns it deep-stringified, and the block given to `PublicSubmission.call` receives `(entry, outcome)` inside the business savepoint.

`PublicPagesController#submit` applies it in this order:

1. **Payment handoff** — `outcome.handoff.module_key == "payment"` → `FeatureModules::Invocation.begin!(module_key: "payment", input: handoff["input"], …)`. Checkout (`Payments::CheckoutsController`) then creates the order; the run itself creates none.
2. **Page handoff** — otherwise, when `Page#handoff?` (`form_settings.after_submit == "handoff"`), `start_page_handoff`.
3. **Outcome page** — with no handoff URL, `target.type == "page"` redirects to that page when it is launched, belongs to the current customer and is visible to the viewer; otherwise it is ignored.
4. **Default** — `post_submit_path`.

The flash is `public_views.flash.response_submitted` (notice) when no preset is set. With a preset it is the localized `message`, else `public_views.flash.outcomes.<preset>` (falling back to `response_submitted`), shown as an alert when `flash == "alert"`.

### Runtime tables

Migration `20261019133000_create_flowchart_runtime_tables` adds three tenant-scoped tables (models `FlowchartSequence`, `FlowchartAuditEvent`, `FlowchartNotification`, all `TenantScoped`):

| Table | Columns | Written by |
|-------|---------|------------|
| `flowchart_sequences` | `customer_id`, `name`, `period`, `last_value` (default 0); unique `(customer_id, name, period)` | `next_sequence_number` |
| `flowchart_audit_events` | `customer_id`, `flowchart_id`, `event_type`, `resource_type`, `resource_id` (string), `actor_user_id`, `ip`, `user_agent`, `severity` (default `info`), `metadata` (JSON), `created_at` | `audit_log` |
| `flowchart_notifications` | `customer_id`, `user_id`, `title` (JSON), `body` (JSON), `page_id`, `read_at`, timestamps | `create_notification` |

No screen reads audit events or notifications yet.

A public submit that ends on the failure track redirects with `public_views.flash.response_save_error` filled with those collected strings (`to_sentence` in the request locale). With no collected messages, or when the run raised, the generic `common.errors.dynamic.activity_execution_failed` stays. Exception text never reaches the flash. The test-run JSON includes `errors` (`ctx[:errors]`, strings, non-blank, unique).

### HTTP helper

`FlowchartRuntime::Http.request` is the outbound HTTP path for flowchart steps (`api_call`, `send_webhook`, `download_file`, `ai_inference`, `currency_convert`, `geolocation_lookup`). It calls `OutboundHttp.request` with `public_only: true` — or `OutboundHttp.stream` when `max_bytes` is set, so an oversized body aborts mid-transfer instead of being buffered whole; the only exemption is `ai_inference` with the `ollama` provider, whose endpoint is the fixed local constant `FlowchartRuntime::Ai::OLLAMA_URL` (never step input).

Signature: `Http.request(ctx, method, url, headers:, query:, body:, form:, open_timeout: 3, read_timeout: 7, retries: 0, breaker: nil, follow_redirects: false, max_redirects: 3, max_bytes: nil, public_only: true)`. A 2xx returns the response; every other outcome returns `Step.fail`:

- **Timeouts** — `open_timeout` / `read_timeout` come from the step's `connectTimeout` / `readTimeout` and are clipped to `RunContext.remaining`. With less than 1 second left before the first attempt the step fails with `timed_out`.
- **Transport retry** — `retries` (from `retryAttempts` when `retryOnTransportError` is on; capped at 2 extra attempts) applies only to `OutboundHttp::TransportError`, immediately (no backoff), and only while at least 1 second remains. The editor allows it only for idempotent requests (see [code-generators](code-generators)). An HTTP status is never retried.
- **Circuit breaker** — with `breaker: { name:, threshold:, reset_seconds: }`, `CircuitBreaker.evaluate` keyed by customer and name gates the call; an open breaker fails with `circuit_open` (`name`). Transport errors, 5xx responses and oversize bodies count as failures; a 2xx counts as success.
- **Status and transport** — a non-2xx fails with `http_status` (`status`); invalid requests, redirect errors, transport errors after retries and bodies over `max_bytes` fail with `transport_error` (`reason`). The `max_bytes` cap is checked per chunk while streaming (`OutboundHttp::ResponseTooLargeError`, reason `ResponseTooLargeError`).

#### Public-address guard

Before the initial URL and every followed redirect hop, `OutboundHttp.request` and `OutboundHttp.stream` (both with `public_only: true`) parse the URI, requires `http` or `https`, resolves the host (`Resolv.getaddresses`, including literal IPs), and raises `OutboundHttp::BlockedDestinationError` when there are no addresses or any address is not public unicast. Blocked ranges include loopback, RFC1918 private, link-local (including the EC2 metadata address `169.254.169.254`), unspecified and IPv4-compatible IPv6 (`0.0.0.0` / `::/96`), multicast, CGNAT `100.64.0.0/10`, `0.0.0.0/8`, `192.0.0.0/24`, `198.18.0.0/15`, `240.0.0.0/4`, broadcast `255.255.255.255`, IPv6 unique-local `fc00::/7`, IPv4-mapped IPv6 whose embedded IPv4 is non-public, and NAT64 `64:ff9b::/96`. `Http.request` maps that error to `Step.fail(ctx, :blocked_destination)` (`flowchart_runtime.errors.blocked_destination`) with no retry and no circuit-breaker failure. Allowed hops pin the TCP connection to a validated public IP (`Net::HTTP#ipaddr=`) so DNS rebinding cannot retarget the socket after the check. Payment, SMS, captcha, and other vendor callers omit `public_only` and are unchanged.

### Merge reads

Writers on exclusive branches share one ctx key. `ConflictResolver` renames an element's output only when another writer of the same key is an ancestor (loop back-edges excluded). A read of `ctx[:pin]` without an explicit input override or tombstone picks the producer that actually ran: one candidate uses that candidate's effective key; several use the latest candidate's key when that candidate dominates the reader; otherwise the read compiles to `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b, …)` (first present key, including an explicit `nil`). `ctx.dig` / `fetch` / `key?` use `FlowchartRuntime::Outputs.view(ctx, :pin, …)` as the receiver so Hash semantics stay. Implied `FlowchartRuntime::Entries.scope(ctx)` reads are not rewritten.

```ruby
  def merge(ctx, **)
    ctx[:summary] = "{{status}}/{{reviewer}}".gsub("{{status}}") { (FlowchartRuntime::Outputs.latest(ctx, :status_ff6b, :status) || '').to_s }.gsub("{{reviewer}}") { (ctx[:reviewer] || '').to_s }
    true
  end
```

`status` is seeded before the decision and overwritten on one branch (`status_ff6b`); exclusive `reviewer` writers keep the shared key. See [code-generators](code-generators) for the resolver and rewriter contracts.

### Tracer

`ActivityTracer` maps circuit node ids to canvas elements through `<ActivityClass>::CANVAS`. It does not re-run the generator. A traced run of a class without `CANVAS` is refused with `flowchart_elements.trace.errors.must_regenerate`. Each listed node is `{ id, element_id, label, status, signal, branch, ctx_snapshot }`. `branch` is present only for a route signal (connection label, else the semantic). `ctx_snapshot` is best-effort (capped, redacted; `ContextSanitizer` drops every `_`-prefixed key). Status: Right → `success`, Left → `failure`, a route signal → `success` with `branch`. `trace_nodes` holds at most `ActivityTracer::MAX_TRACE_NODES` (500) nodes in execution order; `Result#truncated` and the traces JSON `trace_truncated` report a cut list.

`Result#error` is a translated generic message (`flowchart_elements.trace.errors.no_activity_code`, `failed_to_build`, `execution_failed`, `timed_out`, `must_regenerate`). Exception class and message go to the log only, never to the traces JSON.

`collect_errors` and a child flow's own terminals are omitted. `Start.default` carries the canvas Start element id. `End.success` carries the reached End: via `CANVAS[:ends]` for a stepless End, or the last executed step when that step is an End that writes a response. An End-with-response step is omitted from `trace_nodes` on success so the element appears once as `End.success`; a failing End step stays visible. Terminal labels are translated (`flowchart_elements.trace.*`). A step that raises keeps a partial trace; the raised step is marked `failure`.

Public submissions call `ActivityTracer#call(input, trace: false)`: `activity_class.call` inside the timeout, empty `trace_nodes`, no `CANVAS` requirement. Owner test runs keep the trace.

`ActivityDiagramGenerator` also reads `CANVAS`. It labels decision edges with the branch label, omits a decision's unused default success/failure edges, draws an End-with-response as one terminal carrying that End's label, and strips Mermaid-significant characters (control characters, brackets, quotes, pipes, `;`, `#`, backticks, `&`, `%%`, `:::`) from labels.

### Loops

The excerpts in this subsection follow the current loop generator (`LoopGenerator` plus `FlowchartRuntime::Loop` / `LoopState` / `ExecutedOutputs`). Re-sync them if the header method body or write helpers change.

The loop header is an ordinary step. The body is declared immediately after it. Each body tail wires `Output(:success) => Id(:<loop>)`. The header's Done signal wires to the exit:

```ruby
  step :init_total
  step :each_item, Output(Routes::EachItem::Done, :done) => Id(:report)
  step :add_item, Output(:success) => Id(:each_item)
  step :report, magnetic_to: nil
  fail :collect_errors
```

`CANVAS[:routes]` records the header's `:done` connection. Iteration state lives under one short key (`:_each_item`, `:_repeat`, … — `:_<step_name>`). `FlowchartRuntime::Loop.enter(ctx, :_<method>, execution: "_loop_io", pins: [...], initializers: {...})` creates it; `Loop.leave` deletes it and returns nil so the method can return `Routes::<Loop>::Done`. `collect_errors` also deletes the key so a reused ctx cannot leak. Slot keys derive from the header method name (`:_loop_each_item_total`).

A header with a canvas body is a straight sequence: leave, fail at the limit, or start one more pass, then return `true`. A real in-header `loop do` / `while` exists only for an empty-body loop (header to End). A canvas-body **for_each** that skips items uses `while (<skipWhen>)` to advance (or leave, or fail at the limit), not an outer iteration loop.

```ruby
  def repeat(ctx, **)
    # While loop with max iterations safety limit
    state = FlowchartRuntime::Loop.enter(ctx, :_repeat) { { count: 0 } }
    ctx[:_loop_iteration_count] = state[:count]
    return FlowchartRuntime::Loop.leave(ctx, :_repeat, {}) || Routes::Repeat::Done unless (FlowchartRuntime::ConditionInput.compare(ctx.dig(:count), "<", 3))
    return FlowchartRuntime::Loop.fail_limit(ctx, :_repeat, max: 5, exports: {}) if state[:count] >= 5
    state[:count] += 1
    ctx[:_loop_iteration_count] = state[:count]
    true
  end

  def collect_errors(ctx, **)
    ctx.delete(:_repeat)
    ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
  end
```

A for-each header over `items` with a Skip item when row (`ctx.item` is empty) and the default limit:

```ruby
    state = FlowchartRuntime::Loop.enter(ctx, :_each_item) { { items: Array(ctx[:items]), index: 0, count: 0 } }
    ctx[:_loop_iteration_count] = state[:count]
    return FlowchartRuntime::Loop.leave(ctx, :_each_item, {}) || Routes::EachItem::Done if state[:index] >= state[:items].size
    return FlowchartRuntime::Loop.fail_limit(ctx, :_each_item, max: 100, exports: {}) if state[:index] >= 100
    item = state[:items][state[:index]]
    index = state[:index]
    state[:index] += 1
    ctx[:item] = item
    ctx[:index] = index
    while (ctx.dig(:item).blank?)
      # same leave / fail_limit / bind lines for the next item
    end
    state[:count] += 1
    ctx[:_loop_iteration_count] = state[:count]
    true
```

Provenance-free writes stay `ctx[:pin] = value` (`item`, `index`, `_loop_iteration_count`). Tracked loop data uses `FlowchartRuntime::LoopState.write(ctx, :pin, value, slot:, producer:)` and `FlowchartRuntime::ExecutedOutputs.fetch(ctx, :pin, candidates: [...])`. `itemVariable` / `indexVariable` may not be `state` or `ctx` (`flowchart_elements.loop.errors.reserved_header_local`) and may not be the same name (`colliding_loop_variables`).

Semantics (fields are listed on [Flowchart builder](flowchart-builder)):

- **while** (`loopType: while`) checks `condition` before each pass and leaves on Done when it is false. With `runOnceFirst` the first pass runs without the check (`started`); the condition and the limit apply from the next visit on.
- **for_each** wraps `collection` with `Array()`, writes `itemVariable` / `indexVariable` to `ctx`, and walks every item. `skipWhen` skips the current item; skipped items still advance the index. `collectInto` appends each processed (not skipped) item to that ctx array.
- `stopWhen` (both types) leaves on Done when it becomes true. It is checked after the limit.
- **Limit.** `maxIterations` is 1–10,000, default 100 for both types; a blank or zero value uses 100 and `LoopGenerator::MAX_LOOP_ITERATIONS` caps it at 10,000. A while loop fails when its condition still holds after `maxIterations` passes. A for-each loop fails when items remain after `maxIterations` indexes (skipped items count); a collection exactly `maxIterations` long finishes normally. The collection is never truncated.
- **Failing at the limit.** `FlowchartRuntime::Loop.fail_limit(ctx, key, max:, exports:)` leaves the loop (publishes its exports and deletes the state key), then returns `Step.fail(ctx, :loop_limit, max:)`. The header step fails, `ctx[:errors]` gets `flowchart_runtime.errors.loop_limit` ("The loop stopped after %{max} passes without finishing."), and the run ends on the failure track. A false condition, an exhausted collection or a true `stopWhen` leave on Done instead.
- `ctx[:_loop_iteration_count]` is the completed-pass count of the loop that ran most recently (for for_each, processed items only). It is one shared ctx key, not renamed per loop: `ActivityGenerator::ElementIoIndex::RUNTIME_PIN` keeps it (and the `_route_N` keys) out of producer outputs, so `ConflictResolver` never suffixes it. After two sequential loops it holds the second loop's count; read it inside the loop or copy it right after.

Loop-region reads use execution provenance so a value read inside or after the loop is the most recent write that actually ran. Loop-free elements keep B2 `Outputs.latest` reads. Generated source references `FlowchartRuntime::`, not `ActivityGenerator::`.

A traced three-item for_each lists the header and body once per item: `Start.default`, `repeat`, `work`, `repeat`, `work`, `repeat`, `work`, `repeat`, `after`, `End.success`. Public submissions stay untraced.

### SMS sends (send_sms)

The `send_sms` step action replaced the SMS channel of the old notify action. It reads `templateKey` (reference to a platform SMS template), `to` (default `model.phone`), `vars` (literal keys → expression values) and optional `idempotencyKey`, and calls `FlowchartRuntime::SmsDelivery.deliver(ctx, customer:, to:, template_key:, vars:, idempotency_key:)`. That helper calls `FlowchartRuntime::Sms.send_template`, which delegates to `Sms::Gateway.send` with the same module gate, phone normalization, variable validation, suppression, quota and tenant idempotency policy as other callers. Credentials and sender configuration never come from the step or the request.

```ruby
message = FlowchartRuntime::Sms.send_template(
  customer: customer,
  to: "+8613800138000",
  template_key: "verify_code",
  vars: { "code" => "1234" },
  idempotency_key: "verification-42"
)
```

On success the step writes the `Sms::Message` id to `resultVar` (default `sms_message_id`). Acceptance is not delivery: any returned message whose status is not `suppressed` takes the success track, and the step never waits for a receipt. Failures go through `Step.fail` with `send_sms.*` codes: `suppressed` (`Sms::Errors::Suppressed`, or a returned message whose status is `suppressed`), `quota` (`RateLimited`, `DailyCapExceeded`), `credentials_missing`, `module_disabled`, `idempotency_conflict`, `marketing_ineligible`, `template_missing`, `api_error`, `invalid_number` / `template_missing` / `provider_code_missing` / `invalid_vars` (from `TemplateVarsInvalid`, chosen by matching its message text), and `failed` for any other `Sms::Errors::Error`. A genuine replay with the same idempotency key returns the same row.

Inside public submission the SMS admission participates in the business savepoint. A failed later step or rejected handoff rolls back the queued row and no delivery is enqueued. On success, the job handoff waits for the outermost commit; enqueue failure leaves a durable row for recurring recovery. The default expiry is one hour; `send_sms` has no expiry field. No vendor call runs in the step.

After dispatch, the worker may retry only fenced ledger-completion writes, at most three attempts per transition for statement/connection failures; it never repeats the vendor send. Ambiguous partial responses can retain a validated vendor ID and response/audit hash for unknown-state query or early-receipt correlation. Reconciliation's grace/maximum age uses the dispatch timestamp with historical acceptance/admission fallbacks. These background facts do not change an already-returned workflow success into proof of delivery; review the recorded message and receipts. See [SMS](sms) for the delivery clock and completion contract.

SMS outcomes, ambiguity and `Sms::Errors` do not trigger cross-channel fallback. An admitted message or uncertain external attempt must not cause a second notification through another channel. See [SMS](sms), [Background jobs](background-jobs) and [Flowchart step actions](flowchart-step-actions) for the `send_sms` fields and asynchronous status handling.

## Where to pay attention

### Route audit: effective definition and subflow invariants

`Pages::PublicSubmission::RuntimeFlowchart` pins `resolved_current_version` configuration. For a shared override it compiles through a request-local RuntimeGenerator into the anonymous execution namespace, never mutating global `activity`, versions or heads. Ordinary global/owned definitions retain stored source. Runtime child lookup requires accessible launched flowcharts and applies each child's effective definition; missing/offline/foreign children, cycles or depth 32 fail closed. Builder authoring is outside this route audit.

`ActivityTracer` applies the same facade to direct executions. An unpublished owner-preview parent uses `RuntimeFlowchart.new(record, preview: true)` to retain its prepared definition; its children still require tenant accessibility, publication and effective versions. Diagram/introspection use of ActivityClassBuilder remains a separate boundary. `extended_model` provides approved metadata, not a base-record write capability: generated record steps create/validate/save EntityEntry, and legacy routing/assignment/persistence helpers reject base inputs and non-EntityEntry ActiveRecord targets.

Business execution and successful handoff preparation share a `requires_new` savepoint containing PasswordEffects. A failed tracer or rejected handoff rolls back create/update and invocation state together. Warden-derived authentication remains request-local; context user IDs are metadata. See [Page rendering](page-rendering), [Module framework](module-framework), [Shared resources](shared-resources).

`ActivitySteps::SaveAll.call(ctx, **)` also uses a new savepoint for its primary EntityEntry and bridge saves. A rejected base-model target or a false Reform `save` returns failure; a later bridge validation failure rolls back both the primary and any earlier bridge writes. Callers pass `ctx` as a positional hash. Runtime child-lookup specs construct the real RuntimeFlowchart facade rather than declaring unsupported methods on a verifying double. Nested-loop validation asserts the localized `code_generator_validation.loop_topology.nested_loop` message.

:::note
The 2026-10-11 targeted runtime verification passed 508 examples across 28 files, including tenant/global override execution, owner previews, launched-child accessibility, real SaveAll persistence/rollback and failed public-submission handoffs. The dedicated database was `storage/runtime_final_verify.sqlite3`; exact commands and results are recorded in `docs/audits/2026-10-11-rspec-verification.md` and `/tmp/opencode/runtime_final_verify.log`.
:::

:::attention
`ActivityGenerator#generate` returns nil when `flowchart.name` is blank or `elements` is empty, and also returns nil for a structure validation failure that is not a loop-topology or unsupported-element error. `Flowchart#generate_activity` assigns that nil, which clears `activity`. `Pages::PublicSubmission#validation_error` then rejects the submit because `@flowchart.activity.blank?`.
:::

:::attention
Override saves leave global compiled source intact. Public submission passes RuntimeFlowchart to ActivityTracer, so both executable source and trace labels follow the effective override; it no longer executes the global class for that override.
:::

:::attention
`ActivityClassBuilder#build_activity_class` passes `flowchart.entity` to `DynamicClassLoader`. A shared flowchart cannot store `entity_id`, so the loader defines `BlueprintEntity`. Persistence steps use `ctx[:bound_entity]`, which `Pages::PublicSubmission#build_context` sets to the page's entity. `EntityEntry.build_for` is the factory those steps call.
:::

:::attention
`FlowchartRuntime::Invocable` refuses arbitrary `const_get`. `method!` allows only application-defined methods under `app/` and rejects ActiveRecord classes plus destructive methods. `InvokeServiceGenerator` checks the same at authoring time. `SERVICE_NAMESPACES` lists `Sms`, `Emails`, `Payments`, `Captcha`, `FeatureModules`, `Member`, and `Billing`. Page handoff is `FeatureModules::Invocation.begin!` in `PublicPagesController#start_page_handoff`, after `ActivityTracer` returns success.
:::

:::attention
`ActivityTracer#call` gives every run indifferent-access `params`. Decision/loop `> >= < <=` comparisons go through `ConditionInput.compare` and treat non-finite numbers as non-numeric. `authorize` checks an `Authentication::User` or the session facade, never a loaded user Hash; `send_template_email` reads `ctx[:customer_id]`.
:::

:::attention
Flowchart runtime never calls `People::Ownership.scope`. `QueryBuilder.for_entity` without `scope:` still returns every tenant row. A capacity or duplicate check that used the member row scope would under-count. Trusted person identity comes from `ctx[:current_person_ids]` via `find_current_person`, never from params. Sign-up identity is `ctx[:identity]`, never `ctx[:params]`.
:::

:::attention
Do not branch the flowchart on `registration.status`. `created` and `existing` share the same `registration_pending` flash so a visitor cannot tell whether an email already has an account.
:::

:::attention
The launch-time input/output check reads its implicit keys from `config/flowchart_validation.yml` (`implicit_context_keys`), not from `ConfigSchema::SEEDED_KEYS`. The list carries every `SEEDED_KEYS` entry plus `current_user` (optional: `authorize` falls back to the session user when it is nil) and `current_customer`. Keep the two lists in step: an `audit_log` step left on its defaults (`ipAddress: request_ip`, `userAgent: user_agent`) passes the launch check only because `request_ip` and `user_agent` are listed.
:::

:::attention
`Step.attempt` rescues only the classes the generator lists. An unexpected exception still escapes the step; `ActivityTracer` turns it into the generic `execution_failed` result and the public flash shows `common.errors.dynamic.activity_execution_failed`. Exception messages reach `error_details[].diagnostic` and the log, never the flash.
:::

:::attention
`ActivityTracer` aborts at `EXECUTION_TIMEOUT_SECONDS` (10) and sets the same `RunContext` deadline for HTTP helpers. `Pages::PublicSubmission#execute_activity` runs `ActivityTracer#call(ctx, trace: false)` inside `Authentication::PasswordEffects.transaction` and raises `ActiveRecord::Rollback` unless `trace.success?` and the bridge rows saved.

Bridge rows are written by the runtime, not by generated steps. After a successful run whose `ctx[:model]` is an `EntityEntry` of the page entity created in this submission (`previously_new_record?`), `Pages::BridgeEntries` writes one row per bridge section in the same savepoint. The bridge entity is resolved from the page entity's `associations_list` by bridge id or `SectionSlug`, among the tenant's and shared entities. A section is skipped when every target reference (a bridge `EntityReference` to another entity) is blank. `EntityEntryContract` checks each target reference: every id must be a record of the target entity in this customer, otherwise the row fails with `common.errors.dynamic.association_target_missing` and the submission rolls back. The reference back to the primary entry is stored as its id string and is never read from the submission. The row is validated with `EntityEntryContract.build_for(bridge, audience:, writable_slugs:)`. Any rejection returns its messages, rolls back the primary entry and the handoff, and surfaces as `:failed` with those messages. An update flowchart's existing entry gets no new bridge rows. A failure-track run with collected `ctx[:errors]` fills the flash; a raise or empty list uses the generic activity-failed text. `FlowchartRuntime::Authentication.from_request` reads Warden's user and is request-local. `current_user_id` in the context is metadata.
:::

## Key code

```ruby
# app/contracts/entity_entry_contract.rb
    def schema_property_options(attr, writable_slugs: nil)
      derived = %w[Calculated Computed].include?(attr["type"]) || attr["storage"] == "computed"
      excluded = writable_slugs && !writable_slugs.include?(attr["name_slug"].to_s)
      # Reform 2.6 uses :writeable for model sync and :parse for deserialization.
      derived || excluded ? { writeable: false, parse: false } : {}
    end
```

```ruby
# app/services/activity_generator.rb
  def generate
    return nil if flowchart.name.blank? || elements.empty?
```

```ruby
# app/models/flowchart.rb
  def generate_activity
    # `activity` is a compiled column on the parent row. A tenant override
    # must not overwrite the global default; runtime still reads this column.
    return if override_customer_id.present?

    self.activity = ActivityGenerator.new(self).generate
  rescue ActivityGenerator::Error => e
    # Invalid generator config must never wipe a prior activity or persist a
    # failure stub as activity source. Raise in test; elsewhere leave the
    # previous activity untouched so the configuration edit can still save.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator::Error: #{e.message}")
  rescue StandardError => e
    # Unexpected codegen bugs must never block save — otherwise the user loses
    # in-progress edits. Preserve the raise in test so we still catch
    # regressions; elsewhere annotate the activity field and move on.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator raised: #{e.class}: #{e.message}")
    self.activity = "# ActivityGenerator failed: #{e.class}: #{e.message}"
  end
```

```ruby
# app/services/pages/public_submission.rb
          trace = ActivityTracer.new(@flowchart).call(ctx, trace: false)
```

```ruby
# app/services/activity_tracer.rb
    if trace
      execute_with_trace(activity_class, input)
    else
      execute_without_trace(activity_class, input)
    end
```

```ruby
# app/services/activity_tracer.rb
          Trailblazer::Developer::Trace.invoke(
            activity_class,
            [input, { stack: stack }]
          )
```

```ruby
# app/services/pages/public_submission.rb
    def build_context
      prepare_input unless defined?(@guard_result)
      # The boundary-supplied authentication object is the session credential.
      # current_user_id/current_user_role remain metadata, never proof of login.
      # current_person_ids is the same-tenant viewer's linked person entries only.
      {
        params:             @primary,
        association_params: @bridge_sections.presence,
        bound_entity:       @entity,
        customer_id:        @customer_id,
        authentication:     @authentication,
        current_user_id:    @current_user&.id,
        current_user_role:  @current_user&.primary_role_key,
        audience:           audience,
        device_type:        Pages::DeviceType.call(@user_agent),
        current_person_ids: current_person_ids,
        identity:           @identity || {}
      }.compact.merge(
        request_ip: Current.ip_address,
        user_agent: @user_agent,
        locale: I18n.locale.to_s,
        request_id: Current.request_id,
        continuation: verified_continuation
      )
    end
```

```ruby
# app/services/flowchart_runtime/step.rb
    def fail(ctx, code, field: nil, **details)
      raise Error, "error code is required" if code.to_s.strip.empty?

      append(
        ctx,
        I18n.t("flowchart_runtime.errors.#{code}", **details),
        code,
        field,
        details
      )
      false
    end
```

```ruby
# app/controllers/public_pages_controller.rb
  def start_submission_handoff(entry, outcome)
    if payment_handoff?(outcome)
      start_payment_handoff(entry, outcome)
    elsif @page.handoff?
      start_page_handoff(entry)
    end
  end

  def complete_submission(handoff_url, result)
    return redirect_to(handoff_url) if handoff_url

    outcome = result.submission_outcome || {}
    path = outcome_page_path(outcome) || post_submit_path
    type, text = outcome_flash(outcome)
    redirect_to path, type => text
  end
```

```ruby
# app/services/flowchart_runtime/errors.rb
    def collect(ctx)
      existing = Array(ctx[:errors]).map { |message| message.to_s }.reject(&:empty?)
      extras = ctx.each_with_object([]) do |(key, value), messages|
        next if key == :errors
        next unless value.respond_to?(:errors)

        errors = value.errors
        next unless errors.respond_to?(:full_messages)

        messages.concat(Array(errors.full_messages).map { |message| message.to_s })
      end
      (existing + extras).uniq
    end
```

```ruby
# app/services/flowchart_runtime/outputs.rb
    def latest(ctx, *keys)
      keys.each do |key|
        return ctx[key] if ctx.key?(key)
      end
      nil
    end

    def view(ctx, pin, *keys)
      pin = pin.to_sym
      keys.each do |key|
        return { pin => ctx[key] } if ctx.key?(key)
      end
      {}
    end
```

```ruby
# app/services/concerns/activity_class_builder.rb
    namespace.module_eval(activity_code)

    # Find the NEWLY defined activity class (not pre-existing subflow classes)
    new_constants = namespace.constants - existing_constants.to_a
    new_constants
      .map { |c| namespace.const_get(c) }
      .find { |k| trailblazer_activity?(k) }
```

```ruby
# app/services/flowchart_runtime/entries.rb
    def scope(ctx)
      entity = ctx[:bound_entity]
      return EntityEntry.none unless entity

      EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)
    end
```

```ruby
# app/services/flowchart_runtime/condition_input.rb
    def compare(left, operator, right)
      op = operator.to_s
      unless %w[> >= < <=].include?(op)
        raise ArgumentError, "unsupported comparison operator: #{op.inspect}"
      end
```

```ruby
# app/services/dynamic_class_loader.rb
  def load_into(namespace)
    if entity.present?
      build_entity_model(namespace)
      build_entity_contract(namespace)
    else
      build_blueprint_model(namespace)
      build_blueprint_contract(namespace)
    end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/new_model_generator.rb
              assign(:resultVar, "FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")
```
