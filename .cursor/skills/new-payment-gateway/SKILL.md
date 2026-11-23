---
name: new-payment-gateway
description: Use when adding a new payment vendor (Stripe, PayPal, etc) to anysys. Enforces the single-file rule from AGENTS.md — only app/services/payments/gateways/<vendor>.rb is created, no schema/controller/view changes. Drives a focused PO → brainstorm → spec → plan → build → review pipeline (UX phase usually skipped since the Settings UI is auto-generated).
---

# Adding a New Payment Gateway

Triggers: "add a new payment gateway", "add Stripe / PayPal / etc as a payment vendor".

## The single-file rule (from AGENTS.md)

The Payment module is vendor-agnostic by design. To add a new gateway, the **only** required change is a single new file at `app/services/payments/gateways/<vendor>.rb`. Do NOT change schema, controllers, the Settings UI, or the webhook dispatcher — they pick the new gateway up automatically.

## What the new file must declare

```ruby
module Payments
  module Gateways
    class <Vendor> < Base
      class << self
        def key                = "<vendor>"
        def display_name       = "<Vendor>"
        def credential_fields
          [
            { name: :api_key,    label: "API Key",    type: :password, encrypted: true },
            { name: :public_key, label: "Public Key", type: :string,   encrypted: false }
          ]
        end
        def supported_flows    = [:qr, :h5]   # subset of [:qr, :h5, :jsapi]
        def jsapi_user_agent_pattern = nil   # optional regex for in-app browser routing

        def extract_merchant_id(headers, body)
          # parse the webhook body to identify the tenant
          # runs BEFORE signature verification — must not trust crypto here
        end
      end

      # Implement all of these — read vendor credentials with `account.credential(:key)`
      def charge(...);              end
      def query(...);               end
      def refund(...);              end
      def close(...);               end
      def subscribe(...);           end
      def cancel_subscription(...); end
      def charge_subscription(...); end
      def download_bill(...);       end
      def verify_notification(...); end
    end
  end
end

Payments::Gateways::<Vendor>.register!
```

## Forbidden

- Migrations under `db/migrate/`
- Controller changes
- Settings UI form changes (the form is generated from `credential_fields`)
- Webhook dispatcher changes
- New typed columns on `payment_merchant_accounts` — vendor-specific config goes in the encrypted `credentials` JSON blob

Dispatch every Task / SDLC subagent with no `model` argument (or `model: inherit`) so they stay on Grok 4.6.

## SDLC pipeline (compact)

### Phase 0 — Product owner

Dispatch `anysys-product-owner` to extract: which flows are needed (`:qr` / `:h5` / `:jsapi`), what credentials the vendor requires, the webhook merchant-id extraction shape, the failure modes (declined, network error, invalid signature). Output is a tight requirements brief.

### Phase 1 — Brainstorm + spec

Run `superpowers:brainstorming` using the PO brief. Write `docs/superpowers/specs/YYYY-MM-DD-<vendor>-payment-gateway-design.md`.

### Phase 2 — UX design (skip unless in-page widget)

Skip if the vendor only does redirect-based or QR-code flows (the Settings UI is auto-generated from `credential_fields`). Dispatch `anysys-ux-designer` only if there's a JSAPI/in-page widget.

### Phase 3 — Plan + build

`superpowers:writing-plans`, then dispatch in parallel where possible:
- `T-gateway`: `app/services/payments/gateways/<vendor>.rb` → `anysys-backend-developer` (treat the gateway class as the business surface)
- `T-stimulus` (only if vendor has an in-page widget): `app/javascript/controllers/payments_<vendor>_<flow>_controller.js` → `anysys-frontend-developer`
- `T-spec`: `spec/services/payments/gateways/<vendor>_spec.rb` → `anysys-qa-engineer`

### Phase 4 — Verify

Dispatch `anysys-release-engineer` to run the gateway spec and (if widget) hit the checkout page in the browser.

### Phase 5 — Review (parallel)

Dispatch `anysys-tech-lead` and `anysys-code-reviewer`. Tech-lead specifically confirms `Payment / Captcha single-file rule` — diff is limited to the gateway file (+ optional Stimulus controller) and its spec.

### Phase 6 — Hand back to user

User commits manually.

## Common pitfalls

- Adding a migration. The provisioner auto-creates the merchant_account row — never write a per-vendor migration.
- Adding a column to `payment_merchant_accounts`. Use the encrypted `credentials` JSON blob.
- Forgetting `register!` at the end of the class body — the gateway will not appear in the Settings dropdown.
- Putting `register!` inside `class << self` — it must be at module-body level.
