# Payment/email controller integration — 2026-10-11

## Evidence and ownership

This security-engineer follow-up owns RC-02, RC-03, RC-05, RC-09 and RC-16 from the [route manifest](2026-10-11-route-audit-manifest.md). The payment activity handoff explicitly permitted the exact verified-account/payment-binding functions. Other payment activities, historical Gateway write selection, billing controllers/services, authentication/core/captcha and gateway implementations remain with their integration owners.

The findings below were confirmed by reading the current controller/model/job/service chains, then patched. Regression specs are authored; no RSpec, full suite, subagents, application runners, migrations, provider HTTP or browser journeys were run. Ruby syntax/diff checks are recorded separately and do not establish runtime correctness or production concurrency.

## Assigned finding reconciliation

| Finding | Confirmed prior source path | Implemented source disposition |
| --- | --- | --- |
| RC-02 | `HandleWebhook.verified_account` rejected today's changed merchant label; `signing_matches_payment?` compared the committed attempt to that label; the job consumed normal nil returns | Exact verified account ID/provider lookup now raises a retryable credentials error when unavailable. Payment/refund binding uses that row ID plus existing provider/customer checks, without consulting today's routing label. Previously verified evidence can settle after label edits/disablement. The event job claims a ten-minute metadata lease in a short lock, releases the transaction before handler/provider HTTP, then conditionally completes with the same token. Handler errors release claims; expired claims recover; old workers cannot clear/complete replacement claims or dead-letter processed events. |
| RC-03 | Email/SMS `verified_*` returned the first verifying mode; exact inbox credential correlation stranded the other mode's receipt | Both controllers verify all retained candidates, resolve every event before mutation, and use recorded vendor ID/credential ID/mode plus recipient identity. Signed Twilio AccountSid and SES sending-account/topic identity are checked. A unique unknown-event identity is persisted; unresolved shared-key ambiguity returns 409 with no arbitrarily pinned inbox row. Request-mode hints are ignored. Inbox correlation rechecks recorded mode/recipient. |
| RC-05 | Merchant strong params permitted all vendors, while shared attributes were computed by subtracting only the chosen vendor's keys | `SHARED_ATTRIBUTES` is an explicit typed whitelist; blob attributes are sliced separately. Credential permission uses the actual persisted provider on update and selected provider on create. Forged provider/mode or another vendor's keys cannot become typed model attributes. |
| RC-09 | `RefreshStats.sent_count` included pending, queued and failed rows | Sent counts only sent/delivered/bounced/complained; materialized/pending/queued/failed/suppressed remain separate counters. Existing unrelated statistics are preserved. |
| RC-16 | Invalid Reform input returned the original token and the controller mounted it without submitted values | Controller passes unsaved submitted values separately through editor/form components. The form retains label/entity/slug, including escaped invalid selections, while displaying backend model errors. Rejected values are not synced to the persisted token. |

All five are **source-remediated / runtime-unverified**. Original audit reports remain historical evidence; this reconciliation supersedes the corresponding outstanding descriptions.

## Regression homes

- Payment job/event: `spec/jobs/payments/process_webhook_event_job_spec.rb`, `spec/models/payments/webhook_event_spec.rb` — merchant edits after verification, missing account retry, handler transaction depth, overlapping claim, error release, expiry takeover and stale-worker/dead-letter protection.
- Payment binding/settings: `spec/services/payments/activities/handle_webhook_spec.rb`, `spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb` — exact historical account/provider/customer isolation and foreign vendor parameter slicing.
- Receipt ingress: `spec/requests/emails/webhooks_spec.rb`, `spec/requests/sms/webhooks_spec.rb`, `spec/services/webhook_credential_binding_spec.rb` — shared secrets/topics, recorded second-mode identity, early ambiguity, authenticated sender mismatch, recipients, recorded-mode mismatch, inbound actual-contact identity and unique unmatched durability.
- Campaign statistics: `spec/services/emails/send_activities/refresh_stats_spec.rb` — accepted-send versus materialization/queue/failure states and campaign scoping.
- Invalid form: `spec/requests/admin/settings/modules/emails/template_tokens_spec.rb` — submitted overlong label/entity/slug at 422, escaped invalid selections, unchanged stored values.

## Concrete other-owner integration dependencies

1. The Gateway owner's concurrent historical-write fix is now present: `Payments::Gateway.charge` and `.charge_token` validate the payment/order and use `gateway_for_payment(..., historical: false)`, preserving committed account selection while retaining new-write eligibility. The charge IP also comes from `_attempt`. This earlier handoff is **closed in current source**, not an outstanding blocker. Query/refund/close likewise use `gateway_for_payment`.
2. `Payments::CredentialResolver.for_payment` still requires current merchant_id/mode to equal `_attempt`; `by_merchant_id` routes a newly arriving notification by today's label. This follow-up repairs already-verified queued settlement; it does not provide old-label routing/key history for notifications first arriving after destructive rotation.
3. `Billing::PaymentAuthorization.validate_stripe_identity!` compares metadata merchant_id with the current merchant row. Billing authorization rotation policy remains B-owned; do not infer it is repaired by the general Payments binding fix.
4. The historical card-fetch interface is now implemented and wired: `Gateway.fetch_payment_method(..., merchant_account: signing_account, historical: true)` is called by setup/checkout backfill. The earlier missing-interface handoff is **closed in the current source**, not an outstanding blocker.
5. RC-06/RC-07/RC-08 have also been repaired by their other owners and were source-reconfirmed during this follow-up: SMS `SaveCredential` calls transactional `AssignDelivery.persist`; Aliyun's `unsupported_features` rejects campaign one-click and unsupported envelope/MIME features; `MessageAdmission` runs before quota/queueing, campaign Build/start uses the same capability check, and template test-send has controlled `UnsupportedMessage` feedback. Those implementations are **not attributed to this dispatch**. Their old outstanding descriptions were reconciled in the manifest; runtime remains unverified.

An ambiguous callback's 409 requires provider/intermediary redelivery after recorded identity exists or configuration is disambiguated. Known unique-account early callbacks remain durably accepted. Processing leases preserve at-least-once recovery, not vendor exactly-once guarantees.

## Documentation and checks

Paired `doc/reference/{en,zh-CN}/{payments,email,sms}.md` now describe the exact verified-account/lease boundary, all-candidate receipt resolution and 409 policy, merchant parameter slices, actual-send counters and invalid-form retention. They also correct the source-reconfirmed SMS assignment and Aliyun admission descriptions. The manifest distinguishes five owned fixes from three observed other-owner remediations; the remaining coordinator entries and route inventory are not recertified by this follow-up.

No new user-facing literal or translation key is required: error responses are controlled HTTP statuses, existing model errors/labels are reused, and submitted entity/slug values are escaped data.

Validation evidence: all 26 touched Ruby source/spec files passed `RubyVM::InstructionSequence.compile_file` (exit 0); scoped `git diff --check` passed (exit 0). The final merchant controller/request-spec edit was syntax-checked again. These are syntax/whitespace checks only; regression execution and lifecycle-migration/runtime validation remain pending.
