# Captcha Protected public pages + skip — implementation plan

> Execute in this session. Do **not** git commit.

**Goal:** Two-column transfer list is the source of truth for whether a platform form or shared public page is captcha-protected or skipped.

**Architecture:** `skipped` on `captcha_url_throttles`; matcher returns a skipped rule that the rack gate passes through; UI splits identities into Protected vs Skip with per-row PATCH.

**Tech Stack:** Rails 8.1.2, ViewComponent, Stimulus, Reform, RSpec, Vitest.

## Global Constraints

- Roles owner/admin/member only. I18n en + zh-CN. Tailwind + Stimulus + ViewComponent. No git commit.

## Tasks

1. Migration `skipped` boolean default false null false; factory; Registry Record/Rule + `display_for`.
2. UrlMatcher: `skip?` only `/captcha/challenge`; `rule_from_row` includes `skipped`; skipped rows do not fall through to default.
3. RackGate: pass through when `rule.skipped`.
4. UpdateUrlThrottle + contract: accept `skipped`; preserve rate on skip; default rate on first skip of an unconfigured identity.
5. Surfaces/pages controllers permit `skipped` and pass it through.
6. Rewrite ProtectedPagesComponent + locales; Stimulus `captcha_page_list_controller.js` at 100% Vitest.
7. Specs: matcher, gate, activity, request (owner skip + tenant denied), component.
