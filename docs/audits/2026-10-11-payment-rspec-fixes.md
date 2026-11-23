# Payment RSpec failure follow-up — 2026-10-11

## Result

**549 targeted examples, 0 failures.** This resolves the payment selectors in groups 11–14 of [the original full-suite verification](2026-10-11-rspec-verification.md). The original 442-failure full-suite result remains historical evidence; the full suite was not rerun and no subagents were launched.

The first targeted run after the reported-failure fixes passed **526 examples, 0 failures**. Added regression cases cover header lookup, unique signed-event authentication, historical label/mode drift, offline evidence repair and production assets/runtime configuration. Newly authored config fixtures initially exposed a partial Rake module, a false-value probe bug and a dangling fixture tenant; these were corrected and the final expanded targeted run passed.

## Source fixes and legitimate fixture changes

1. Stripe retry classification uses the official `StripeResponseHeaders#[]` API, which is case-insensitive. No unsupported `any?`/enumeration is required. Decline/authentication/read failures retain their intended Payments error types; retry-directed/5xx/429/timeouts remain uncertain.
2. `CredentialResolver.for_payment(..., historical: true)` resolves the exact pinned account row with tenant/provider checks and allows mutable label/mode changes. `historical: false` preserves strict write-snapshot validation, and new facade writes still require active/configured/platform-available credentials. No current-account substitution or request-time legacy binding is added.
3. Known stored PSP operations are authoritative only when they have a committed snapshot. Missing/ambiguous local evidence is a controlled credentials rejection requiring offline repair. No-metadata Stripe request fixtures now create real `PrepareAttempt` snapshots. Uncorrelated signed events may authenticate a unique retained account via the official Stripe signature verifier; IDs alone, invalid signatures and shared-secret ambiguity are not proof.
4. A Billing SetupIntent confirmed through a disabled historical account can activate its method while remaining non-default and not charge-ready. The fixture now asserts readiness failure instead of authorizing collection under a disabled account.
5. Checkout consent is tested on the gateway-selection form, then explicitly POSTed before intent creation. The widget is checked for absence of a later editable consent field; the stored attempt preserves the staged consent.
6. Dummy-key asset compilation has an explicit `assets-build.invalid` metadata origin only when the sole top-level task is `assets:precompile`. Runtime, migrations and mixed tasks still require the actual production host. Production configuration tests evaluate the config in an isolated DSL probe, without production boot or network.

## Database and commands

The parent `storage/` directory was verified before creating the disposable database. All checks used `RAILS_ENV=test`, `TEST_DATABASE=storage/payment_verify.sqlite3`, and unset `SKIP_AUTH`. Development/production databases were not migrated or repaired.

```bash
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/payment_verify.sqlite3 bundle exec rails db:schema:load
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/payment_verify.sqlite3 bundle exec rails db:migrate:up VERSION=20261011190000
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/payment_verify.sqlite3 bundle exec rails payments:historical_bindings:preflight
```

The migration and CLI preflight ran on the empty isolated database with **0 payment rows, 0 event rows and 0 unresolved bindings**. Fixture-based migration/repair examples separately exercise deterministic legacy records, atomic rejection, native vendor evidence and preservation of money/status/identifiers.

Final RSpec command:

```bash
env -u SKIP_AUTH RAILS_ENV=test TEST_DATABASE=storage/payment_verify.sqlite3 bundle exec rspec \
  spec/services/payments/gateways \
  spec/services/payments/gateway_spec.rb \
  spec/services/payments/credential_resolver_spec.rb \
  spec/services/payments/errors_spec.rb \
  spec/services/payments/historical_binding_backfill_spec.rb \
  spec/services/payments/activities/historical_operations_spec.rb \
  spec/services/payments/activities/billing_integration_spec.rb \
  spec/services/payments/activities/retry_age_spec.rb \
  spec/requests/payments/webhooks_stripe_spec.rb \
  spec/requests/payments/checkouts_spec.rb \
  spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb \
  spec/system/payments/admin_gateway_settings_spec.rb \
  spec/config/canonical_url_options_spec.rb
```

Result: **549 examples, 0 failures**, 28.96 seconds of examples. Existing Rack `unprocessable_entity` deprecation messages were emitted; they were not failures.

## Historical data migration / review High 4–5

Added distinct data-only migration **20261011190000**, backed by versioned `db/data_migrations/payment_historical_bindings_v1.rb`, and CLI tasks `payments:historical_bindings:preflight` / `:apply`. It does not modify Billing A's lifecycle migration or financial state.

- Evidence must contain an explicit retained account ID, or a unique provider/merchant ID coupled to recorded operation IDs or the persisted verified ledger signer.
- Tenant/provider conflicts, inconsistent references, unknown signers, missing event IDs and contradictory old verification envelopes are reported and rejected.
- A sole account under a tenant/provider never authorizes a guess. All unresolved rows are reported before any apply writes; evidence changed after preflight aborts the transaction.
- Repair only adds identity to `_attempt` or `_anysys_verification`. Money, status, timestamps, order/trade/refund numbers and other payload data are retained. It does not authorize reconstruction/replay of old financial writes.
- Existing key material/routing evidence cannot be recreated if discarded. Actual deployment data must be preflighted and unresolved records reconciled from explicit authoritative PSP/ledger evidence externally. No automatic runtime compatibility path exists.

**Schema:** no columns, indexes, constraints or tables added by this migration. The test migration's normal schema dump advanced `db/schema.rb`'s version marker to `2026_10_11_190000`. Existing unrelated schema work was retained.

## Documentation and remaining scope

Updated both `doc/reference/en/payments.md` and `doc/reference/zh-CN/payments.md` for historical-read/write semantics, signed-account routing, pre-intent consent/default readiness, the offline repair workflow and assets-only configuration. No failing test was skipped or deleted.

No production data preflight, real PSP call, Docker image build, full-suite rerun or concurrency/deployment proof is claimed. Historical credential-version retention remains outside this change. Other feature-area failures in the original report remain with their owners.
