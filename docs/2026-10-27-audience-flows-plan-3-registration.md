# Audience Flows — Plan 3: Public Registration and Hand-over

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to run this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Every task names its SDLC agent, the files it owns, the interfaces it consumes and produces, and its key test cases.

**Goal:** A visitor can register from a public page and continue the action as a member. The public Student page runs a flowchart with the new `register_member` step: it creates a passwordless, unconfirmed member and the visitor's Student entry, and records a pending claim. When the visitor confirms by email (on any device), the entry is linked to the new account and they land on the member page of the same action with their original choices prefilled.

**Architecture:** Sign-up logic moves into `Authentication::RegisterMember`, shared by the sign-up form and the step. Pending claims live in the database (`people_pending_claims`), so a confirmation opened on another device completes them. `Pages::Continuation` signs `{ action_key, prefill }` so the post-sign-in destination can only be an action-router path. Every fully established sign-in calls one `signed_in_destination(user)` method, which completes the claim.

**Tech Stack:** Rails 8.1.2, Devise (confirmable), Trailblazer activities, Solid Queue recurring jobs, RSpec.

**Spec:** [`docs/2026-10-27-audience-flows-design.md`](2026-10-27-audience-flows-design.md) §3.10, §4, §5, §6, §7.

**Sibling plans:** Plans 1 and 2 must be complete and green: this plan uses `People::Ownership`, `Pages::AudienceGuard`, exact audiences, `Pages::ActionResolver`, `Pages::ActionLink`, `Pages::ActionsController` and `Pages::Prefill`.

---

## Global Constraints

Same as Plan 1 (branch `main`, no commits, `model` omitted or `inherit`, I18n parity with `locale_parity`, no `t()` in constants, 100% Vitest on touched JS, docs in both locales, fail closed, ignore `app/services/page_layout_templates/templates/`). Plan-specific additions:

- **Isolated test databases:** `TEST_ENV_NUMBER=5<task number>` (Task 2 → `52`, Task 10 → `510`). Load the schema after Task 2's migration: `RAILS_ENV=test TEST_ENV_NUMBER=5N bin/rails db:schema:load`.
- **No account enumeration.** Every branch of `register_member` (new email, existing member, existing non-member, another tenant's user, quota exhausted) gives the browser the same redirect and flash. Specs assert the responses are identical.
- **Email goes through the existing paths.** New accounts get Devise's confirmation email after commit; existing members get `Authentication::IssueSignInLink`, which already applies the auth-module rules and the email flood throttle. No new mailer.
- **Auth-sensitive tasks** (1, 6, 7) are built by anysys-security-engineer, and Task 10's review includes a focused pass on them.

---

## Waves and file ownership

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 1 | 1 — `RegisterMember` | anysys-security-engineer | `app/services/authentication/register_member.rb`, `app/controllers/authentication/registrations_controller.rb`, `app/services/authentication/mutation_audit.rb` (nil request only), `spec/services/authentication/register_member_spec.rb`, `spec/requests/authentication/registrations_spec.rb` |
| 1 | 2 — Pending claims | anysys-backend-developer | migration, `db/schema.rb`, `app/models/people/pending_claim.rb`, `app/services/people/claim.rb`, `app/services/people/activities/complete_claim.rb`, `app/services/people/{link,activities/link}.rb`, `spec/factories/people_pending_claims.rb`, their specs |
| 1 | 3 — Identity fields (server) | anysys-backend-developer | `app/services/page_content_generator/form_fields.rb`, `app/services/pages/{form_params,public_submission,launch_checks}.rb`, `config/locales/maint_core.{en,zh-CN}.yml`, their specs |
| 2 | 4 — Identity fields (builder) | anysys-frontend-developer | `app/views/admin/maintenance/pages/_editor.html.erb` (Account group), `config/locales/maint_core.{en,zh-CN}.yml` (editor labels), `app/javascript/controllers/page_builder/field_manager/field_crud.js` and its test (only if it needs a change), editor render specs |
| 2 | 5 — `register_member` step | anysys-backend-developer | `app/services/code_generators/element_types/process/security/register_member_generator.rb`, `app/services/flowchart_runtime/registration.rb`, `app/services/flowchart_definitions/structure_schema.palette.json`, `spec/javascript/fixtures/action_catalog.sample.json`, `config/locales/flowchart_actions_security.{en,zh-CN}.yml`, `config/locales/public_views.{en,zh-CN}.yml`, their specs |
| 2 | 6 — Continuation | anysys-security-engineer | `app/services/pages/continuation.rb`, `app/controllers/pages/actions_controller.rb`, `app/controllers/public_pages_controller.rb`, `app/services/page_content_generator/form_fields.rb` (hidden field), `app/services/pages/public_submission.rb` (`ctx[:continuation]`), `spec/services/pages/continuation_spec.rb`, `spec/requests/pages/actions_spec.rb`, `spec/requests/public_pages_continuation_spec.rb` |
| 3 | 7 — Claim on sign-in | anysys-security-engineer | `app/controllers/concerns/authentication/finishes_sign_in.rb`, `app/controllers/authentication/{mfa_sessions,mfa_setups}_controller.rb`, `spec/requests/authentication/pending_claims_spec.rb`, the touched `spec/requests/authentication/*_spec.rb` |
| 3 | 8 — Claim expiry | anysys-backend-developer | `app/jobs/people/expire_pending_claims_job.rb`, `config/recurring.yml`, `spec/jobs/people/expire_pending_claims_job_spec.rb` |
| 4 | 9 — Docs | anysys-tech-lead (writes docs only) | `doc/reference/{en,zh-CN}/{authentication,person-linking,flowchart-step-actions,flowchart-runtime,page-builder,page-rendering,captcha,audience-flows}.md` |
| 5 | 10 — Verification and review | anysys-release-engineer, then anysys-tech-lead + anysys-code-reviewer in parallel | none (read-only) |

Files shared across waves (never within one): `maint_core.*.yml` (Task 3, then Task 4), and `form_fields.rb` and `public_submission.rb` (Task 3, then Task 6).

## Spec coverage

| Design section | Tasks |
|---|---|
| §3.10.1 `RegisterMember` | 1 |
| §3.10.2 Identity fields | 3, 4 |
| §3.10.3 `register_member` step | 5 |
| §3.10.4 `people_pending_claims` | 2 |
| §3.10.5 Continuation | 6 |
| §3.10.6 Claim on sign-in | 2, 7 |
| §3.10.7 Expiry | 8 |
| §4 Per-audience flowcharts (public flow) | 5, 9 |
| §5 Strings | 3, 4, 5 |
| §6 Documentation | 9 |
| §7 Test matrix (registration rows) | 1, 2, 5, 6, 7, 8, 10 |

---

## Task 1 — `RegisterMember`

**Agent:** anysys-security-engineer

**Files:**
- Create `app/services/authentication/register_member.rb`
- Modify `app/controllers/authentication/registrations_controller.rb` (`create` calls the service; `assign_member_role!` moves into it)
- Modify `app/services/authentication/mutation_audit.rb` only if `roles(..., request: nil)` doesn't already work
- Specs: create `spec/services/authentication/register_member_spec.rb`; `spec/requests/authentication/registrations_spec.rb` stays green

**Interfaces:**
- Produces: `Authentication::RegisterMember.call(customer:, attributes:, request: nil, passwordless: false) → Result(status:, user:, errors:)`. `status` ∈ `:created`, `:invalid`, `:quota_exceeded`. The customer row lock, `Billing::Quota::Guard.check(customer:, item_key: "member")`, the save and the member role run in one transaction; Devise sends the confirmation email after commit. `passwordless: true` sets `allow_blank_password`.

- [ ] **Step 1: Failing service spec** — creates an unconfirmed member with the member role; passwordless creates a user with no `encrypted_password`; quota exhausted → `:quota_exceeded` and no user; invalid attributes → `:invalid` with errors and no role row; the confirmation email is enqueued once, after commit; the quota guard is checked inside `customer.with_lock` (stub the guard to allow once and then deny, and assert the second call creates nothing).
- [ ] **Step 2: Implement**; the controller keeps its responses and flashes byte-identical (the request spec proves it).
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=51 bundle exec rspec spec/services/authentication/register_member_spec.rb spec/requests/authentication/registrations_spec.rb`.

---

## Task 2 — Pending claims

**Agent:** anysys-backend-developer

**Files:**
- Create `db/migrate/<timestamp>_create_people_pending_claims.rb`; regenerate `db/schema.rb`
- Create `app/models/people/pending_claim.rb` (thin: `self.table_name = "people_pending_claims"`, because `People` is a plain module with no table prefix; associations, `customer_id` scoping, `expired` scope), `app/services/people/claim.rb` (facade, like `People::Link`), `app/services/people/activities/complete_claim.rb` (Trailblazer Railway: find → check expiry and tenant → link → consume → build path), `spec/factories/people_pending_claims.rb`
- Modify `app/services/people/activities/link.rb` and `app/services/people/link.rb` (`event:` keyword, default `"person.linked"`)
- Specs: create `spec/models/people/pending_claim_spec.rb`, `spec/services/people/claim_spec.rb`, `spec/services/people/activities/complete_claim_spec.rb`; `spec/services/people/link_spec.rb`

**Interfaces:**
- Produces:
  - Table `people_pending_claims`: `customer_id` (not null, indexed), `user_id` (not null, unique, FK cascade), `entity_entry_id` (nullable, FK nullify), `continuation` (JSON, nullable), `created_user` (boolean, not null, default false), `expires_at` (not null, indexed), timestamps.
  - `People::Claim.record!(user:, entry: nil, continuation: nil, created_user:)` — upserts by `user_id`, `expires_at` = 3 days.
  - `People::Claim.complete!(user) → String | nil` — runs `People::Activities::CompleteClaim` under the customer lock: ignores an expired claim or one from another tenant; links the entry through `People::Link.link!(entry:, user_id:, actor: user, event: "person.claimed")` when it is unlinked and in the user's tenant; deletes the claim; returns `Pages::ActionLink.path(...)` built from the continuation, or nil.

- [ ] **Step 1: Failing specs** — record and upsert; complete links the entry and writes one `person.claimed` audit row with the user as actor; an entry linked meanwhile to someone else is skipped (claim consumed, no error); an entry deleted meanwhile (FK nullified) still returns the continuation; an expired claim returns nil and is left for the job; a user of another tenant never completes it; a second `complete!` returns nil.
- [ ] **Step 2: Implement**; `bin/rails db:migrate`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=52 bundle exec rspec spec/models/people spec/services/people`.

---

## Task 3 — Identity fields (server)

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/services/page_content_generator/form_fields.rb` (`source: "identity"` fields are named `identity[<key>]`; key ∈ `People::IDENTITY_KEYS`)
- Modify `app/services/pages/form_params.rb` (permit `identity` for the public and admin audiences only; unknown keys dropped)
- Modify `app/services/pages/public_submission.rb` (`ctx[:identity]`)
- Modify `app/services/pages/launch_checks.rb` (identity fields on a page whose entity isn't a person entity fail `identity_field_not_person`)
- Modify `config/locales/maint_core.{en,zh-CN}.yml` (`maint_core.errors.page_launch.identity_field_not_person`, text from design §5)
- Specs: `spec/services/pages/{form_params,public_submission,launch_checks}_spec.rb`, `spec/services/page_content_generator_safety_spec.rb`

- [ ] **Step 1: Failing specs** — an identity field renders as `identity[email]`; a public submission exposes `ctx[:identity]` with the three keys; a member submission drops `identity` entirely; an `identity[password]` key is dropped; a generic record step (`save_model`) never writes identity keys from `ctx[:identity]`; launch fails on a non-person page with an identity field.
- [ ] **Step 2: Implement**; `locale_parity maint_core`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=53 bundle exec rspec spec/services/pages spec/services/page_content_generator_safety_spec.rb`.

---

## Task 4 — Identity fields (builder)

**Agent:** anysys-frontend-developer

**Files:**
- Modify `app/views/admin/maintenance/pages/_editor.html.erb` (an "Account" sidebar group with First name, Last name and Email, rendered only when the bound entity is a person entity; items use the existing `field_sidebar_item` partial with `source: "identity"`)
- Modify `config/locales/maint_core.{en,zh-CN}.yml` (`maint_core.pages.editor.identity_group` "Account" / 「账号」, `identity_group_help` "Creates the member's sign-in account." / 「用于创建会员登录账号。」)
- `app/javascript/controllers/page_builder/field_manager/field_crud.js` already copies `data-source` generically; change it (and its Vitest file) only if an identity field needs special handling
- Specs: editor render examples in `spec/requests/admin/maintenance/pages_spec.rb`

- [ ] **Step 1: Failing specs** — the Account group renders for a Student page and not for a Course page; each item carries `data-source="identity"`.
- [ ] **Step 2: Implement**; `locale_parity maint_core`; if JS changed, `npx vitest run --coverage --config config/javascript/vitest.config.js spec/javascript/controllers/page_builder` → 100% lines and branches.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=54 bundle exec rspec spec/requests/admin/maintenance/pages_spec.rb`.

---

## Task 5 — `register_member` step

**Agent:** anysys-backend-developer

**Files:**
- Create `app/services/code_generators/element_types/process/security/register_member_generator.rb` (category `:security`, version `1.0.0`, `single_use: true, privileged: false` like the other security steps, config `personVar` default `model`, `resultVar` default `registration`)
- Create `app/services/flowchart_runtime/registration.rb` (`FlowchartRuntime::Registration.call(ctx, person:)`)
- Regenerate `app/services/flowchart_definitions/structure_schema.palette.json` (`bin/rails ai_assistant:flowchart_schema`) and `spec/javascript/fixtures/action_catalog.sample.json` (`bin/rails action_catalog:fixture`)
- Modify `config/locales/flowchart_actions_security.{en,zh-CN}.yml`: palette labels under `flowchart_actions.register_member` (`label`, `description`, `fields.personVar`, `fields.resultVar`), and the four runtime failures from design §5 under `flowchart_runtime.errors.register_member`, next to `authorize.denied`
- Modify `config/locales/public_views.{en,zh-CN}.yml` (`public_views.flash.outcomes.registration_pending`)
- Specs: create `spec/services/code_generators/element_types/process/security/register_member_generator_spec.rb`, `spec/services/flowchart_runtime/registration_spec.rb`, create `spec/requests/public_pages_registration_spec.rb`; the palette and conformance specs stay green

**Interfaces:**
- Consumes: Task 1 (`RegisterMember`), Task 2 (`Claim.record!`), Task 3 (`ctx[:identity]`), Task 6's `ctx[:continuation]` (nil until Task 6 lands; the runtime treats nil as "no continuation"), `Authentication::IssueSignInLink`, `Authentication::Settings#signup_enabled?`.
- Produces: `ctx[<resultVar>] = { "status" => "created" | "existing" }`; `ctx[:submission_outcome]` preset `registration_pending` unless the flowchart already set one.

- [ ] **Step 1: Failing runtime spec** — one example per rule in design §3.10.3, in order: `public_only` for member and admin runs; `person_entity_required`; `signup_disabled` when the module is off or registration isn't allowed; new email → passwordless unconfirmed member, person entry saved with identity in its data and no `user_id`, claim with `created_user: true`, the entry and the continuation, status `created`; existing active member of this tenant → nothing saved, `IssueSignInLink` enqueued, continuation-only claim, status `existing`; existing admin, owner, or another tenant's user → nothing saved, no email, no claim, status `existing`; quota exhausted → `unavailable`; outcome preset set only when absent.
- [ ] **Step 2: Failing request spec** — submitting a public Student page bound to a flowchart with `register_member` gives the same redirect and flash for a new email, an existing member's email and another tenant's email; `EntityEntry` and `Authentication::User` counts change only for the new email.
- [ ] **Step 3: Implement**; regenerate palette and fixture; `locale_parity flowchart_actions_security`; `locale_parity public_views`.
- [ ] **Step 4: Run** `TEST_ENV_NUMBER=55 bundle exec rspec spec/services/code_generators/element_types/process/security spec/services/flowchart_runtime/registration_spec.rb spec/requests/public_pages_registration_spec.rb spec/services/flowchart_definitions/assistant/schema_generator_spec.rb` and `npx vitest run --config config/javascript/vitest.config.js`.

---

## Task 6 — Continuation

**Agent:** anysys-security-engineer

**Files:**
- Create `app/services/pages/continuation.rb` (`sign(action_key:, prefill:)`, `verify(token) → { action_key:, prefill: } | nil`; Rails message verifier, purpose `page_continuation`, expires in 3 days; prefill re-filtered with the §3.2.5 limits on verify)
- Modify `app/controllers/pages/actions_controller.rb` (when it redirects to a public page and the action also has a member page, append `continuation=<signed>`)
- Modify `app/controllers/public_pages_controller.rb` (`show` verifies `params[:continuation]` and sets `@page_continuation`)
- Modify `app/services/page_content_generator/form_fields.rb` (hidden `_continuation` field next to `_page_id`, rendered only when `@page_continuation` is set)
- Modify `app/services/pages/public_submission.rb` (`ctx[:continuation]` from a verified `params[:_continuation]`; a tampered or expired value is nil, never an error)
- Specs: create `spec/services/pages/continuation_spec.rb`, `spec/requests/public_pages_continuation_spec.rb`; `spec/requests/pages/actions_spec.rb`

- [ ] **Step 1: Failing specs** — round trip; tampered, expired, wrong-purpose and oversized tokens verify to nil; the router adds a continuation only when the action has a member page; the public page renders the hidden field only for a valid token; the submission exposes it to the flowchart; a continuation can't name another tenant's action (the path is built for the page's own customer when the claim completes).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=56 bundle exec rspec spec/services/pages/continuation_spec.rb spec/requests/public_pages_continuation_spec.rb spec/requests/pages/actions_spec.rb`.

---

## Task 7 — Claim on sign-in

**Agent:** anysys-security-engineer

**Files:**
- Modify `app/controllers/concerns/authentication/finishes_sign_in.rb` (add `signed_in_destination(user)`: `safe_return_path_for(user, stored_location_for(:user)) || People::Claim.complete!(user) || default_signed_in_path_for(user)`; `after_sign_in_path_for` uses it)
- Modify `app/controllers/authentication/mfa_sessions_controller.rb` and `mfa_setups_controller.rb` (their success redirects use `signed_in_destination(current_user)`)
- Specs: create `spec/requests/authentication/pending_claims_spec.rb`; keep `spec/requests/authentication/{confirmations,sign_in_links,sessions,mfa_setups,mfa_sessions_trusted_device}_spec.rb` green

- [ ] **Step 1: Failing request specs** (end to end, each starting from a `register_member` submission):
  - New visitor confirms by email → signed in, the Student entry is linked, they land on the member Enroll page with the course preselected.
  - The confirmation link opened in a different session (no cookies from the registration) still completes the claim.
  - A member with MFA required: the claim isn't completed at the password step; it completes after the MFA step, and the redirect goes to the continuation.
  - An existing member signs in through the emailed link → lands on the continuation; nothing is linked.
  - A stored location (for example an OAuth authorize return) wins over the continuation; the claim is still consumed.
  - An expired claim is ignored; a claim for another tenant's user is never completed.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=57 bundle exec rspec spec/requests/authentication`.

---

## Task 8 — Claim expiry

**Agent:** anysys-backend-developer

**Files:**
- Create `app/jobs/people/expire_pending_claims_job.rb`, `spec/jobs/people/expire_pending_claims_job_spec.rb`
- Modify `config/recurring.yml` (a daily `people_expire_pending_claims` entry next to the other daily jobs)

- [ ] **Step 1: Failing spec** — deletes expired claims; for an expired `created_user` claim whose user is still unconfirmed, destroys the unclaimed entry and the user; keeps a user who has confirmed since; keeps an entry that has been linked; leaves unexpired claims alone; isolates tenants (one tenant's expiry never touches another's rows).
- [ ] **Step 2: Implement** (batches of 500; each claim in its own transaction under the customer lock).
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=58 bundle exec rspec spec/jobs/people`.

---

## Task 9 — Docs

**Agent:** anysys-tech-lead (docs only)

- [ ] `authentication` — `RegisterMember`, passwordless members created by the step, and the sign-in destination order.
- [ ] `person-linking` — pending claims, `person.claimed`, expiry.
- [ ] `flowchart-step-actions`, `flowchart-runtime` — `register_member` (config, statuses, failures, outcome preset), `ctx[:identity]`, `ctx[:continuation]`.
- [ ] `page-builder`, `page-rendering` — identity fields, the hidden continuation, and the recommendation to turn on captcha for public registration pages (cross-link `captcha`).
- [ ] `audience-flows` — the public half of the enrollment example end to end: public Student page → `register_member` → confirmation → member Enroll page.
- [ ] Both locales have the same sections and examples. `bundle exec rspec spec/services/developer_docs` is green.

---

## Task 10 — Verification and review

**Agent:** anysys-release-engineer, then anysys-tech-lead and anysys-code-reviewer in parallel.

- [ ] `bin/rails db:migrate` is clean; `bin/rails parallel:prepare && bin/rails parallel:spec` passes (paste the summary line).
- [ ] `npx vitest run --coverage --config config/javascript/vitest.config.js` — 100% lines and branches.
- [ ] `locale_parity` for `maint_core`, `flowchart_actions_security`, `public_views` prints nothing.
- [ ] Dev server smoke without `SKIP_AUTH` (it signs every request in as the tenant's first user, so anonymous and member paths can't be exercised): `rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000`. Signed out, open `/:cid/actions/enroll?prefill[course]=<id>`, register on the public Student page, open the confirmation email from the dev mailbox, and confirm you land on the member Enroll page with the course preselected and "My enrollments" empty until you submit.
- [ ] Reviews: tech-lead (AGENTS.md: three roles, member-only writes, I18n, docs) and code-reviewer with a focused pass on Tasks 1, 6 and 7: account enumeration through responses and timing, open redirect through the continuation, claim completion before MFA, cross-tenant claims, and the quota race. Fix findings in the owning task's files and re-run its specs.
