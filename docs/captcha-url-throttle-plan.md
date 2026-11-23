# Captcha URL throttle — implementation plan

> Execute in this session. Do **not** git commit.

**Goal:** Rate-limit public page and platform-form URLs per IP; captcha only after the limit; resume the original request including file POSTs.

**Architecture:** `rack-attack` front gate + `captcha_url_throttles` + cached matcher + public challenge + one-time POST snapshot/replay.

**Tech Stack:** Rails 8.1.2, rack-attack, Solid Cache / MemoryStore in test, ViewComponent, Stimulus, Reform, RSpec.

## Global Constraints

- Roles: owner / admin / member only. I18n en + zh-CN. Tailwind + Stimulus + ViewComponent. Grok 4.6.
- Public challenge URL. Admin settings under Settings / Captcha and Maintenance / Platform / Module Settings.
- Prefer rack-attack; do not hand-roll the counter. No widget on target pages.

## File ownership

**Backend:** Gemfile `rack-attack`; migration; `Captcha::UrlThrottle`; `Captcha::ThrottlePresets`; `Captcha::UrlMatcher`; `Captcha::ThrottleRegistry` (cache); `Captcha::Grant`; `Captcha::RequestSnapshot`; `Captcha::RequestReplayer`; activities `UpdateUrlThrottle`; contracts `UrlThrottle`; retire toggle activities for enforcement; model/activity/contract specs.

**Security:** `config/initializers/rack_attack.rb`; `Captcha::RackGate`; `Captcha::ChallengesController`; routes; pages/surfaces/shared-page controllers; `CaptchaProtectable` stop verifying target POSTs; remove `protect_with_captcha` from public pages and platform forms; request/routing specs.

**Frontend:** `Captcha::ThrottlePickerComponent` + Stimulus `captcha_throttle_picker_controller.js` (100% Vitest); rewrite platform `ProtectedPagesComponent` and customer `StatusComponent`; shared-pages card; `Captcha::ChallengeComponent`; strip widgets from forms; remove page-builder captcha toggle; locales.

## APIs (lock)

```
Captcha::ThrottlePresets::DEFAULT_LIMIT = 100
Captcha::ThrottlePresets::DEFAULT_PERIOD = 5.minutes
Captcha::ThrottlePresets::EVERY_HIT_GRANT = 5.minutes
Captcha::ThrottlePresets::SETTINGS_CACHE_TTL = 60.seconds
Captcha::ThrottlePresets::SNAPSHOT_TTL = 10.minutes
Captcha::ThrottlePresets::MAX_FILE_BYTES = 5.megabytes

Captcha::UrlMatcher.match(path) # => Rule(limit_count:, period_seconds:, every_hit:, pattern:, fail_closed:) or nil
Captcha::ThrottleRegistry.rules / .bust!
Captcha::Grant.store(ip:, pattern:, ttl:) / .active?(ip:, pattern:)
Captcha::RequestSnapshot.capture(request) / .take!(token, ip:)
Captcha::Activities::UpdateUrlThrottle.call(match_kind:, url_pattern:, preset:, limit_count:, period_minutes:, customer_id:, surface_key:, page:)
```

Routes:

```
GET/POST /captcha/challenge
PATCH /:cid/admin/maintenance/platform/module_settings/captcha/surfaces
PATCH /:cid/admin/maintenance/platform/module_settings/captcha/pages/:id
PATCH /:cid/admin/settings/modules/captcha/pages/:id
```

Do not commit.
