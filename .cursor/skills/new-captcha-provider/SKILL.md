---
name: new-captcha-provider
description: Use when adding a new captcha vendor (Turnstile, hCaptcha, etc) to anysys. Enforces the single-file rule from AGENTS.md — only app/services/captcha/providers/<vendor>.rb is created, no schema/controller/view changes. Drives the same compact SDLC pipeline as new-payment-gateway.
---

# Adding a New Captcha Provider

Triggers: "add a new captcha provider", "add Turnstile / hCaptcha / etc".

## The single-file rule (from AGENTS.md)

The Captcha module is vendor-agnostic. The **only** required change is a single new file at `app/services/captcha/providers/<vendor>.rb`.

## What the new file must declare

```ruby
module Captcha
  module Providers
    class <Vendor> < Base
      class << self
        def key          = "<vendor>"
        def display_name = "<Vendor>"
        def config_fields
          [
            { name: :site_key,   label: "Site Key",   type: :string,   default: "" },
            { name: :secret_key, label: "Secret Key", type: :password, default: "" }
          ]
        end

        def configured?(settings)
          settings.config_value(:site_key).present? &&
            settings.config_value(:secret_key).present?
        end

        # Optional: returns Stimulus + SDK metadata for in-page widget
        def widget(settings)
          {
            stimulus_controller: "captcha-<vendor>",
            sdk_url: "https://...",
            data: { "site-key" => settings.config_value(:site_key) }
          }
        end
      end

      def verify(verify_param:)
        # call vendor API
        { outcome: :success, http_status: 200, raw: response_body }
        # outcome ∈ [:success, :invalid, :configuration_error, :unreachable]
      end
    end
  end
end

Captcha::Providers::<Vendor>.register!
# Captcha::Providers::<Vendor>.default!  # optional, if this should become the default
```

## Forbidden

- Migrations under `db/migrate/`
- Controller changes, platform settings UI changes
- Stimulus rendering layer changes
- New typed columns on `captcha_provider_settings` — vendor config goes in the JSON blob

Dispatch every Task / SDLC subagent with no `model` argument (or `model: inherit`) so they stay on Grok 4.6.

## SDLC pipeline (compact)

Same as `new-payment-gateway` — see that skill for the detailed PO → brainstorm → spec → (UX if widget) → plan → build → verify → review → user-commits flow.

Lane mapping for this skill:
- `T-provider`: `app/services/captcha/providers/<vendor>.rb` → `anysys-backend-developer`
- `T-stimulus` (only if widget): `app/javascript/controllers/captcha_<vendor>_controller.js` → `anysys-frontend-developer`
- `T-spec`: `spec/services/captcha/providers/<vendor>_spec.rb` → `anysys-qa-engineer`
- Verify: `anysys-release-engineer`
- Review: `anysys-tech-lead` + `anysys-code-reviewer` in parallel

## Common pitfalls

- Forgetting `register!` (provider won't appear in the platform owner's UI dropdown)
- Putting `register!` inside `class << self` — it must be at module-body level
- Adding a per-vendor migration — `Captcha::ProviderSettings.for_provider(key)` auto-creates the row
