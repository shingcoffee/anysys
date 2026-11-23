---
title: "Captcha"
summary: "One platform captcha provider and URL throttles that challenge a public path before the page is rendered."
---

## Summary

`FeatureModules::Captcha::Registration` (module key `captcha`) protects public HTML with a vendor widget and a front-of-stack throttle. Vendors are `Captcha::Providers` subclasses in `app/services/captcha/providers/`: `aliyun.rb` (`default!`), `turnstile.rb`, and `google_recaptcha_v3.rb`. A new vendor is that one file and `register!`. Vendor fields live in `Captcha::ProviderSettings#config`. The shared typed columns are `access_key_id`, encrypted `access_key_secret`, `enabled`, `fail_policy`, and `score_threshold`. There is no per-vendor migration.

`Captcha::ProviderSettings.active` is the single enabled and configured row. `Captcha::RackGate` counts requests with `Rack::Attack.cache` and redirects over-limit traffic to `Captcha::ChallengesController`. Passing the challenge stores `Captcha::Grant` for that IP and URL pattern.

## Configure captcha providers

At `/81721200/admin/maintenance/platform/module_settings/captcha/settings`, save the selected provider's keys and choose its **failure policy** (`open` or `closed`), run **Test connection**, then make that provider active. At most one provider can be active. Set platform protected paths at `.../captcha/surfaces` and shared pages at `.../captcha/pages`; customer-owned public pages are configured at `/:cid/admin/settings/modules/captcha`. With no fully configured active provider the Rack gate **fails open**, regardless of an individual rule's fail-closed flag. **Test connection** sends a fixed *invalid token* to the vendor and treats an `invalid` response as OK: it probes reachability and some credential errors, **not** a successful challenge, the scene ID, or the browser site-key/hostname pairing. Test a genuine browser challenge and verification on the actual hostname. These providers have no vendor webhook or redirect URI.

### Alibaba Cloud CAPTCHA 2.0 (`aliyun`)

1. [Activate CAPTCHA 2.0 and create a Web/H5 scenario](https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/quick-start); copy its **Scene ID**. Create a RAM AccessKey authorized for [server-side verification](https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/server-access). In the app enter **Access Key ID**, **Access Key Secret**, `scene_id`, and the **server** `endpoint` / `region` matching the instance (Shanghai: `captcha.cn-shanghai.aliyuncs.com` / `cn-shanghai`; Singapore: `captcha.ap-southeast-1.aliyuncs.com` / `ap-southeast-1`). Aliyun's **browser** `AliyunCaptchaConfig.region` is a *different format*: `cn` or `sgp`.
2. Enter the instance **identity prefix** in `prefix`. Readiness requires both `scene_id` and `prefix`, plus the credential pair; an enabled row without the prefix is unconfigured and `.active` returns nil. The V2 controller sets `AliyunCaptchaConfig` before SDK loading, calls `initAliyunCaptcha` with element/button selectors and `getInstance`, and resolves its callback from server `X-Captcha-Result` plus the Turbo submission outcome. Server region maps to browser `cn`/`sgp`; endpoint/region pairs are allowlisted. Embedded mode remains fixed. A genuine browser verification is still required; the sentinel probe does not establish that journey.

### Cloudflare Turnstile (`turnstile`)

1. In Cloudflare [Turnstile → Add widget](https://developers.cloudflare.com/turnstile/get-started/widget-management/dashboard/), select a widget mode and register the [hostnames](https://developers.cloudflare.com/turnstile/additional-configuration/hostname-management/) serving Anysys challenge pages (no scheme, port or path). Copy the vendor's **Site Key** and **Secret Key** into the identically named fields on the Anysys form (stored internally as `access_key_id` and `access_key_secret`).
2. Test every intended hostname. [Siteverify](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/) success must match the request hostname. The interstitial expects no action (nil/empty), matching the widget. Retain vendor hostname restrictions too.

### Google reCAPTCHA v3 (`google_recaptcha_v3`)

1. In the [reCAPTCHA admin console](https://developers.google.com/recaptcha/docs/v3), register **v3** keys and the hostnames serving the challenge (add `localhost` separately if used). Copy the vendor's **Site Key** and **Secret Key** into the identically named fields on the Anysys form (stored internally as `access_key_id` and `access_key_secret`); choose the app **score threshold** (a starting value is `0.5`, then tune against real traffic).
2. Test on the actual host. Google's [siteverify](https://developers.google.com/recaptcha/docs/verify) must return matching hostname/action and a finite numeric score in 0..1 meeting the threshold. The interstitial maps logical `access_challenge` to SDK action `submit`. Keep Google's domain validation enabled.

## Flow

```text
Request
        |
        v
CaptchaRackGateProxy -> Captcha::RackGate
        |  skip /captcha/challenge and one-click List-Unsubscribe
        |  eligible page alias -> trusted canonical throttle path
        |  Captcha::UrlMatcher.for_request
        |  Captcha::Grant.active? -> pass
        |  every_hit, or Rack::Attack.cache.count over limit
        |  ProviderSettings.active nil -> fail open
        v
302 /captcha/challenge?return_to=...
        |  POST/PUT/PATCH body kept in Captcha::RequestSnapshot
        v
Captcha::ChallengesController
        |  Captcha::WidgetComponent
        |  Captcha::Activities::Verify
        v
Captcha::Grant.store, then replay POST or redirect GET
```

`Captcha::Activities::Verify` resolves `ProviderSettings.active`, rejects a blank or replayed token (`Captcha::TokenReplay`), calls `provider.verify`, and applies `score_threshold` for `score_based?` vendors. Outcomes are `:success`, `:invalid`, `:replayed`, `:configuration_error`, `:unreachable`, and `:disabled`.

## Implementation

### One provider file

`Captcha::Providers::Base` requires `key`, `default_display_name`, `config_fields`, `configured?(settings)`, and `verify(context:)` returning `:outcome`, `:http_status`, `:raw`, and optional `:score` and `:hostname`. Outcomes from the vendor are `:success`, `:invalid`, `:configuration_error`, and `:unreachable`. `widget(settings)` returns Stimulus metadata for `Captcha::WidgetComponent`, or nil to skip the in-page widget. `register!` runs at the end of the class body. `Captcha::ProviderSettings.for_provider` creates the row on first access.

`enabled` is both the platform switch and the active-provider selector. `activate!` clears every other enabled row. `.active` returns the enabled row only when `configured?` is true. A missing or incomplete provider makes `Verify` return `:disabled`. `fail_policy` is `open` or `closed`.

`FeatureModules::Captcha::Provisioner.call` is nil. `deprovision` walks that customer's `Page` rows and deletes the `captcha` key from `configuration_json`. It does not delete `Captcha::UrlThrottle` rows.

### Rack gate and throttles

`config/initializers/captcha_rack_gate.rb` inserts `CaptchaRackGateProxy` and the outer `CaptchaResponseMarkerProxy`, and sets `Rack::Attack.enabled = false`, so only `Captcha::RackGate` uses the cache counter. `Captcha::UrlMatcher` picks the most specific stored row, then a public-page rule, then a `Captcha::SurfaceCatalog` template. Unmatched paths are not challenged. The only hard skip prefix is `/captcha/challenge`.

`Captcha::UrlMatcher.for_request(request)` resolves eligible [page shortcuts](page-shortcuts) through `PageShortcuts::Resolver` and matches the trusted target's `canonical_path`. Public `Page` aliases inherit their canonical UUID endpoint's policy on GET/HEAD/POST; website aliases inherit applicable canonical site-path policies on GET/HEAD only. A canonical skipped rule is honored, while a skipped alias rule cannot bypass an existing canonical policy. Counters and grants use the canonical rule's pattern, so switching between aliases and the canonical endpoint does not reset the throttle. Host and path choose the tenant; query/body `customer_id`, `uuid`, or slug values never choose a throttle destination. An unavailable alias does not borrow its former target's canonical policy.

Exact shortcut lookup uses the original path before known-route format normalization. `/join.html` may be a saved mapping to a different target from `/join`; its dot is part of the alias, not an inferred format. Without such a mapping, arbitrary dotted paths do not resolve to an undotted alias or automatic website slug. Known canonical page/surface paths such as `/auth/sign_in.json` retain their canonical throttle, so a format suffix cannot bypass protection.

The gate runs inside Rails' executor; the proxy still defers service loading until requests. It memoizes resolution only in the request environment for the later Journey constraints and does not mark a route as matched, inject parameters, or set `Current`. `Captcha::UrlMatcher.for_path(path, request:)` also gives challenge `return_to` validation the same host/mount-aware policy lookup. The challenge URL, return path and query remain the original alias. POST snapshots retain the original body, external path, `PATH_INFO`, and `SCRIPT_NAME`. Replay restores those paths and the original query, clears challenge parser/routing caches, and re-resolves the alias through normal tenant authorization and publication checks; `captcha.replay` skips only the repeated gate challenge. Snapshot tokens remain one-time and IP/path-bound.

Mounted applications prefix the challenge endpoint and snapshot-cookie scope with `SCRIPT_NAME`: under `/portal`, the redirect is `/portal/captcha/challenge?return_to=...`, and the HttpOnly snapshot cookie is scoped to `/portal/captcha/challenge`. The challenge deletes that same mounted cookie path after consumption. Return URLs retain `/portal` and the original query; replay restores router-relative `PATH_INFO` separately from `SCRIPT_NAME`, preserving both cookie delivery and the eventual mapped redirect.

`Captcha::SurfaceCatalog::LOCKED` includes sign-in, customer sign-up, password reset, confirmation, tenant sign-up, account edit, MFA setup/session/recovery, email unsubscribe, OAuth authorize, and payment checkout. Several of those are `fail_closed: true`. `Admin::Maintenance::Platform::Captcha::SurfacesController` writes a `template` throttle for `surface.path`. `PagesController` in the same namespace writes a `template` throttle for a shared public page at `/:customer_id/page/<public_uuid>`.

Customer page throttles are exact. `Admin::Settings::Modules::Captcha::PagesController` stores `/<customer_id>/page/<public_uuid>` through `Captcha::Activities::UpdateUrlThrottle` for a customer-owned page that includes `public` in its audience set (`page.visible_to?("public")` / `Page.for_audience("public")`), including a public-only page with admin off. `Captcha::ThrottleRegistry` caches `Captcha::UrlThrottle` rows and indexes `Page.for_audience("public")`. `skipped` rows pass through.

`RackGate` fail-opens when `ProviderSettings.active` is nil, and fail-opens if captcha processing itself raises. Its rescue does not cover the downstream application: controller/CSRF exceptions propagate normally and the application is never retried by the gate. It does not require the Captcha module to be enabled for the tenant; website-alias eligibility still checks the Website module's availability.

### Page flag and in-form verify

`Page#captcha_enabled?` reads `configuration_json["captcha"]["enabled"]`. `Admin::Maintenance::PagesController` permits `captcha_enabled`. `PublicPagesController` includes `CaptchaProtectable`. No production controller calls `protect_with_captcha`, so that `before_action` is not installed on page submit, sign-in, or sign-up. `CaptchaProtectable#captcha_required_for_request?` would require the captcha module for `:page_submit` and would require `Page#captcha_enabled?`. Platform auth actions (`sign_up`, `sign_in`, `password_reset`) with a blank customer id would require only `ProviderSettings.active`. That method runs only when a controller calls `protect_with_captcha`.

The challenge that does run is `Captcha::ChallengesController`, which calls `Captcha::Activities::Verify` with action `:access_challenge`. Widget rendering for the interstitial is `Captcha::WidgetComponent`. Public page HTML itself is [page rendering](page-rendering).

Public registration pages that collect First name / Last name / Email should have a URL throttle on `/:cid/page/<public_uuid>` (customer settings) and the page captcha flag on. The live challenge is still the Rack gate, not `protect_with_captcha`. See [Page builder](page-builder) (Account group) and [Audience flows](audience-flows) (public enrollment).

### Four surfaces

| Surface | Path | Controller |
| --- | --- | --- |
| Entries | none (`sidebar_contributions` entries are empty) | — |
| Customer settings | `/:cid/admin/settings/modules/captcha` | `Admin::Settings::Modules::Captcha::StatusController` (show); `PagesController` (throttle update). This route is declared ahead of generic `module_configs` |
| Enable / disable | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`, `ModuleEnablementsController` (`Provisioner.deprovision`) |
| Platform settings | `/:cid/admin/maintenance/platform/module_settings/captcha/settings`, `/surfaces`, `/pages` | `Admin::Maintenance::Platform::Captcha::SettingsController`, `SurfacesController`, `PagesController`; shared panes on `ModuleSettingsController` |

`StatusController` shows `ProviderSettings.active`, whether the module is enabled for the customer, and throttle display rows for that customer's public pages. The registration `entry_path` is this settings URL. There is no configuration schema, so the generic settings form has no captcha fields. `Admin::ModuleConfigsController` is not the captcha settings page.

## Where to pay attention

### Route audit: original-request and failure-policy invariants

`OriginalRequestVerifier` validates original-write CSRF/origin before snapshot admission and again before replay. One-use snapshots bind IP, session digest, origin, path and query. `RequestReplayer.call(env:, payload:)` restores original CSRF/origin headers/body, never manufactures an authenticity token, and preserves nested dispatch session changes. Invalid CSRF propagates rather than entering the fail-open rescue. Snapshot cookies are HttpOnly, mount-scoped and Secure on HTTPS.

Known optional-format paths inherit canonical throttles; arbitrary dotted aliases retain identity. Live failure handling respects surface fail-closed OR platform `fail_policy == closed`; a disabled or unconfigured provider still fails open. With a configured provider and a fail-open outage result, `RequestPassage` admits only the next exact GET, bound to session, origin, IP, path and query. That continuation carries `X-Captcha-Result: false` and does not mint a `Grant`; a later GET is challenged again while the provider remains configured. An unconfigured provider instead bypasses the gate directly, without entering challenge verification.

`CaptchaResponseMarkerProxy` wraps `Captcha::ResponseMarker` immediately before `Warden::Manager`, inside session middleware. `RackGate` records the consumed receipt's result in the request environment; the outer marker adds `X-Captcha-Result` and `Cache-Control: no-store` to the actual response, including redirects emitted by Warden's nonlocal authentication failure. Further same-origin redirects carry a result-only receipt (`allow: false`), never another outage bypass. The challenge uses a same-origin referrer policy and admits embedded payment browsers. See [Page shortcuts](page-shortcuts), [Authentication](authentication), [Payments](payments).

:::note
Regression specs cover replay/CSRF, vendor context, dotted alias routing, and one-use outage continuation across authentication redirects. Configuration probes are not complete challenge verification; real vendor browser journeys require their actual credentials and hostname.
:::

:::attention
A new vendor is one file under `app/services/captcha/providers/` subclassing `Captcha::Providers::Base` and calling `register!`. `Captcha::ProviderSettings.for_provider` creates the JSON row. Do not add a typed column. `ProviderSettings#activate!` is what sets `enabled` and clears every other enabled row. `ProviderSettings.active` still returns nil until `configured?` is true, and `Captcha::Activities::Verify` then returns `:disabled`.
:::

:::attention
`Captcha::RackGate` redirects to `/captcha/challenge` only after `Captcha::UrlMatcher` finds a rule that is not skipped and `Captcha::Grant.active?` is false. When `Captcha::ProviderSettings.active` is nil, or the gate raises, the request continues to the app. Captcha module enablement is not required per tenant. One-click `List-Unsubscribe` POSTs under `/unsubscribe/` skip the gate.
:::

:::attention
`PublicPagesController` includes `CaptchaProtectable` and never calls `protect_with_captcha`. A search of `app/` shows that class method only inside the concern. `Page#captcha_enabled?` is therefore not applied on submit by this controller. The live challenge for a public page is `Captcha::UrlThrottle` plus `Captcha::RackGate`. Customer throttles are exact paths from `Admin::Settings::Modules::Captcha::PagesController`. Shared-page throttles are templates from `Admin::Maintenance::Platform::Captcha::PagesController`.
:::

:::attention
`FeatureModules::Captcha::Provisioner.deprovision` deletes the `captcha` key on that customer's `Page#configuration_json` and leaves `Captcha::UrlThrottle` rows in place. `Captcha::SurfaceCatalog` throttles such as `/auth/sign_in` are platform URL rules. They stay after a single tenant disables the module. `Admin::Maintenance::Platform::Captcha::SurfacesController` is what updates those templates.
:::

## Key code

```ruby
# app/services/captcha/providers.rb
module Providers
  extend PluginRegistry.build(label: "captcha provider", dir: "app/services/captcha/providers")
end
```

```ruby
# app/models/captcha/provider_settings.rb
def self.active
  row = where(enabled: true).first
  row if row&.configured?
end
```

```ruby
# app/services/captcha/rack_gate.rb
rule = Captcha::UrlMatcher.for_request(req)
return if Captcha::Grant.active?(ip: ip, pattern: rule.pattern)

if rule.every_hit
  return challenge(req, rule) unless captcha_unavailable_fail_open?(rule)
```

```ruby
# config/initializers/captcha_rack_gate.rb
Rack::Attack.enabled = false

Rails.application.config.middleware.use CaptchaRackGateProxy
```

```ruby
# app/services/feature_modules/captcha/provisioner.rb
def self.deprovision(customer)
  Page.unscoped.where(customer_id: customer.id).find_each do |page|
    config = page.configuration_json
    next unless config.is_a?(Hash) && config.key?("captcha")
```
