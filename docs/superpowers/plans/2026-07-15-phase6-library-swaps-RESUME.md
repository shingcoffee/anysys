# Phase 6 (library swaps) — COMPLETE 2026-07-15

(This file was the mid-phase resume state after the session limit killed the swap subagents;
kept as the phase record. Main plan: 2026-07-15-codebase-simplification-refactor.md.)

## Final outcomes
- **Stripe gateway → official `stripe` gem 19.3** ✅ DONE (main session completed the dead agent's
  half-migration: detach_token/fetch_payment_method/ping converted, missing client/stripe_call/
  as_hash/create_payment_intent helpers written, webhook verify now Stripe::Webhook::Signature with
  the pre-gem "stale"/"bad signature" taxonomy preserved, per-tenant StripeClient — no global key,
  config/initializers/stripe.rb pins gem timeouts to the payments transport budget 5s/30s).
  Spec delta: 2 assertions updated (gem form-encodes brackets literally vs %5B). Evidence:
  stripe gateway 52/52, + handle_webhook + requests/payments = 215 examples, 0 failures.
- **Twilio adapter → official `twilio-ruby` 7.10** ✅ DONE (dead agent's code was complete:
  per-tenant REST client w/ matched timeouts, Security::RequestValidator webhook check).
  Evidence: spec/services/sms = 193 examples, 0 failures, zero spec edits.
- **PayPal** ✅ HOLD finalized: header comment now cites the 2026-07-15 SDK evaluation
  (paypal-server-sdk 2.3 lacks notifications/verify-webhook-signature; deprecated legacy SDKs);
  paypal-server-sdk REMOVED from Gemfile (was added speculatively, unused). 48 examples green.
- **FormulaCompiler → Dentaku parser** ❌ REJECTED ON EVIDENCE: dentaku 3.5.7's parser type-checks
  arithmetic at parse time — `name + "x"` and `"a" + "b"` raise Dentaku::ParseError, but this
  grammar validly compiles both to SQL today. Swap = breaking existing user formulas ("no feature
  loss" outranks "no hand-rolled"). Evaluation documented in the file's NOTE comment.
- Alipay / WeChat Pay / Aliyun: stay on stdlib OpenSSL (user-confirmed; no maintained gems / no gem at all).

## Verification
rubocop clean on touched files; zeitwerk:check "All is good!"; full parallel:spec run at completion
(see session log — expect ~13.8k examples / 0 failures modulo the known responsive_drawer/passwords
parallel-load flakes, which pass in isolation).
