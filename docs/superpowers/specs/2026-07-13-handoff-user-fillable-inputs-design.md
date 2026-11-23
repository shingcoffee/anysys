# User-Completable Module Handoff Inputs

**Date:** 2026-07-13
**Status:** Approved — ready for implementation planning
**Branch:** `feat/handoff-user-fillable-inputs`

## Problem

Today the page-builder → feature-module handoff is a **fully-resolved, author-mapped
baton pass**:

1. The page author maps *every required* module input at page-save time.
   `FeatureModuleHandoffContract#required_inputs_are_mapped` **blocks page save**
   when a required input is left unmapped.
2. On form submit, `InputMapper` → `Invocation.begin!` → `InputCaster` → contract
   validation → session, then a redirect to the module's `entry_path`.
3. The module's entry controller (e.g. `Payments::CheckoutsController#start`) reads
   the session `input` and **immediately materializes** its domain object, assuming
   the input is complete.

This is the strict iPaaS/Zapier model: anything required-but-unmapped fails at
*design time*. It cannot express the very common **prefilled-form-and-complete**
pattern (Stripe Checkout, Google Forms prefill, Typeform hidden fields, SAML JIT):
the page supplies what it knows, and the end user completes the rest on a
module-owned step.

## Goal

Let a module declare that specific inputs may be **completed by the end user** on a
module-owned entry page, pre-filled from whatever the author mapped. The author
maps what it can; the user fills the gaps. Preserve the existing trust model
exactly: money and other sensitive inputs stay author-controlled and are never
user-supplied.

**Non-goals:** runtime same-name auto-matching (pre-fill stays driven solely by the
author's explicit `input_mapping`); a brand-new demonstration module; any change to
modules that declare no user-fillable inputs.

## Decisions (from brainstorming)

- **Pre-fill source (Q1 = A):** the author's explicit `input_mapping` remains the
  *sole* trust boundary for pre-fill. No runtime same-name magic. The entry page
  only collects the unmapped gaps (and offers editable prefills for mapped
  user-fillable fields).
- **Field source policy (Q2 = A):** **author-only by default; opt in to
  `user_fillable`.** A forgotten annotation fails *safe* — it keeps today's strict
  "must be mapped" behavior, so there is no silent path for a sensitive field to
  become user-supplied. Least-privilege.
- **Mapped + user_fillable (Q3 = A):** combinable. A `user_fillable` field that the
  author *also* mapped shows up **pre-filled but editable**; the user may accept or
  override it. Such a field carries no server-side-resolved guarantee by
  definition — which is acceptable precisely because it is declared fillable.
- **Scope (Q4 = A + showcase):** ship the platform mechanism only, but use the
  **Payment module as a live showcase** by marking one non-critical field
  (`body`) as `user_fillable`. No new product module.
- **Showcase field:** **`body` only** (optional payment note/memo). Non-monetary,
  optional, already flows into `Payments::Order`. `amount_cents`, `currency`,
  `subject`, `expires_at`, `metadata` stay `author_only`.
- **Payment entry flow:** a **separate `#collect` / `#complete` step** (not folded
  into the existing checkout page), so order materialization stays atomic and the
  monetary-immutability-on-insert guarantee is untouched.

## Industry context

The proposal is the mainstream **hosted-checkout / prefilled-form** pattern:

| Pattern | Examples | Relationship |
| --- | --- | --- |
| Hosted-checkout prefill | Stripe Checkout, PayPal, Adyen HPP | Exactly this model — merchant passes line items server-side; customer fills their own details on the hosted step. |
| Prefilled-form deep links | Google Forms prefill, Typeform hidden fields, HubSpot/Calendly | Known values passed in; user completes the rest. |
| SSO attribute mapping + JIT | SAML/OIDC, Okta, Auth0 | IdP passes claims; missing required attributes prompt the user on first login. |
| iPaaS field mapping (today's model) | Zapier, Make, Workato | Required-unmapped fails at design time; no human-in-the-loop completion. |

We are moving from the strict iPaaS end to the hosted-checkout end, guarded by the
`author_only`-by-default source policy so the move is not a security regression.

## Architecture

### 1. Contract DSL — `source:`

`FeatureModules::BaseModule::ContractDsl#property` gains an optional `source:`
keyword. Default `:author_only`; the only other value is `:user_fillable`.

```ruby
# base_module.rb
def property(name, type: nil, source: nil, validates: nil, **_ignored)
  @properties << {
    name:     name.to_s,
    type:     type&.to_s,
    source:   (source || :author_only).to_s,
    validates: validates || {}
  }
end
```

`FeatureModules::HandoffField` carries the source and exposes predicates:

```ruby
@source = (definition[:source] || "author_only").to_s
def user_fillable? = @source == "user_fillable"
def author_only?   = !user_fillable?
```

`HandoffField#to_h` includes `source` so the platform "Integration Contract" card
and the page-builder mapping UI can badge fillable fields (badge/UI copy is a
nice-to-have, not required for this slice — but the datum is exposed).

Payment declares:

```ruby
property :body, type: :string, source: :user_fillable
```

### 2. Author-time contract relaxation

`FeatureModuleHandoffContract#required_inputs_are_mapped` iterates required fields
but now **skips `user_fillable?` fields** — only required `author_only` fields must
be mapped at page-save. Everything else in the contract is unchanged; a
`user_fillable` field *may* still be mapped (validated as today), which is the
editable-prefill case.

### 3. `FeatureModules::HandoffCompletion` — shared, security-critical core

A new service that owns the gap-collection semantics. Every module reuses it so the
mass-assignment guard and re-validation are implemented once.

- `user_fillable_fields(registration)` → the `HandoffField`s to render on the entry
  step. Mapped ones are prefilled from the current invocation `input`; unmapped ones
  are blank.
- `needs_completion?(invocation, registration)` → `true` iff the registration
  declares at least one `user_fillable` field. A module with none (Payment *without*
  the `body` change, and any other current module) → `false` → the legacy immediate
  path runs unchanged.
- `complete!(session:, user_params:, registration:)`:
  1. **Filter `user_params` to `user_fillable` field names only** — the
     mass-assignment guard. An injected `amount_cents` (or any `author_only`/unknown
     key) is dropped here.
  2. `FeatureModules::InputCaster.call` on the filtered params (typed coercion,
     enum case-normalization) — the same path `Invocation.begin!` uses.
  3. **Merge** the casted user values over the existing invocation `input`. User
     values override the mapped prefill *only for user_fillable fields*;
     `author_only` values already in the invocation are never touched.
  4. **Re-validate** the merged hash against `registration.input_contract_class`.
  5. On success: write the merged input back to `session[SESSION_KEY][:input]`
     (through the `Invocation` API — `Invocation` stays the sole owner of the
     session key). Return an ok result. On failure: return the contract errors for
     re-render; the session is left untouched.

`Invocation` gains a small writer (e.g. `Invocation.update_input!(session:, input:)`)
so `HandoffCompletion` never touches `session[SESSION_KEY]` directly, preserving the
"sole owner" invariant. The writer re-checks the tenant (like `current`) before
writing.

### 4. Payment integration — separate entry step

`Payments::CheckoutsController`:

- `#start`: if `HandoffCompletion.needs_completion?(invocation, registration)` →
  `redirect_to` the new `#collect`; else materialize the order and redirect to
  checkout **exactly as today**.
- `#collect` (GET): renders `Payments::HandoffEntryComponent` with the
  `user_fillable` fields (here `body`) prefilled from the invocation input, in the
  `payments_storefront` layout. Guards the same as `#start` (active `payment`
  invocation, tenant-checked).
- `#complete` (POST): calls `HandoffCompletion.complete!` with the submitted params.
  On success → materialize the order (now carrying the payer's `body`) and redirect
  to checkout. On failure → re-render `HandoffEntryComponent` with errors,
  `:unprocessable_entity`.

`build_order_from` is unchanged in shape: it still reads `body` from the (now merged)
invocation input. `amount_cents` / `currency` / `subject` continue to come from the
author's mapping, so the monetary fields remain authoritative and
immutable-on-insert. `set_or_build_order`'s refusal to accept amount/subject/body
from the anonymous checkout request is unchanged and still correct.

### 5. Frontend — `Payments::HandoffEntryComponent`

ViewComponent + ERB in the `payments_storefront` layout. Renders each
`user_fillable` field (here a single "Add a note (optional)" `textarea` bound to
`body`), a Continue button posting to `#complete`, and inline errors. Responsive
Tailwind only. Fully I18n — every label/placeholder/button/error keyed in both `en`
and `zh-CN` under the payments area locale files. **No Stimulus is expected** (plain
form POST); if any JS is introduced it ships with 100% Vitest lines+branches.

## Data flow

```
Page form submit
  → InputMapper (author input_mapping only)          [pre-fill source: author]
  → Invocation.begin! → InputCaster → input_contract  [author_only required must be mapped]
  → session[:input], redirect entry_path (#start)
      │
      ├─ needs_completion? == false ──► materialize order ──► checkout   (legacy, unchanged)
      │
      └─ needs_completion? == true  ──► #collect (GET)
             renders HandoffEntryComponent (body prefilled/blank)
               → #complete (POST)
                   HandoffCompletion.complete!
                     filter→fillable-only  [guard: injected amount_cents dropped]
                     InputCaster → merge over invocation input → re-validate
                     Invocation.update_input!(session, merged)
                       ├─ valid ──► materialize order (with body) ──► checkout
                       └─ invalid ─► re-render entry form + errors (422)
```

## Error handling

- **Injected author-only param** on `#complete` (e.g. `amount_cents`): dropped by
  the fillable-only filter; the order's amount comes from the author-mapped
  invocation value. Covered by a request spec.
- **Invalid user value** (e.g. an over-long `body`, or a fillable enum out of set):
  `complete!` returns contract errors; the entry form re-renders 422; the session
  `input` is not mutated.
- **No active / wrong-module / cross-tenant invocation** on `#collect`/`#complete`:
  same guards as `#start` — redirect to the tenant home / `head :forbidden`.
- **Module declares a `user_fillable` field but the author still maps it and the
  user blanks a *required* one:** re-validation fails → entry form re-renders. (For
  the showcase, `body` is optional, so this path is exercised only by specs using a
  test contract with a required fillable field.)

## Testing

- **`base_module_spec`** — `source:` defaults to `author_only`; `:user_fillable`
  round-trips to `HandoffField#user_fillable?`.
- **`handoff_field_spec`** — `source` / predicates / `to_h` include the source.
- **`feature_module_handoff_contract_spec`** — a required `user_fillable` field left
  unmapped **saves**; a required `author_only` field left unmapped **blocks**; a
  mapped `user_fillable` field still validates.
- **`handoff_completion_spec`** — mass-assignment guard (author_only + unknown keys
  dropped), casting, merge precedence (user over prefill; author_only untouched),
  re-validation success writes session, failure returns errors and leaves session
  intact, tenant re-check on write.
- **`payments/checkouts` request specs** — `#start` redirects to `#collect` when
  `body` is fillable; `#complete` merges the note into the materialized order;
  **an injected `amount_cents` on `#complete` is ignored** (order amount stays the
  author value); no-active-invocation and cross-tenant guards.
- **`Payments::HandoffEntryComponent` spec** — renders the fillable field prefilled,
  renders errors, all copy resolves in `en` and `zh-CN`.
- **JS** — none expected; if added, 100% Vitest lines+branches on the touched file.

## Files touched (anticipated)

- `app/services/feature_modules/base_module.rb` — `source:` in DSL.
- `app/services/feature_modules/handoff_field.rb` — `source` + predicates + `to_h`.
- `app/services/feature_modules/handoff_completion.rb` — **new** service.
- `app/services/feature_modules/invocation.rb` — `update_input!` writer.
- `app/contracts/feature_module_handoff_contract.rb` — relax required-mapping to
  author-only.
- `app/services/feature_modules/payment/registration.rb` — `body` user_fillable.
- `app/controllers/payments/checkouts_controller.rb` — `#collect` / `#complete`,
  `#start` branch.
- `app/components/payments/handoff_entry_component.{rb,html.erb}` — **new**.
- `config/routes.rb` — collect/complete routes under the checkout scope.
- `config/locales/comp_payments.{en,zh-CN}.yml` (+ any maint_core error keys) —
  new I18n keys, en/zh parity.
- Specs per the Testing section.
