# Platform Announcements Implementation Plan

> Execute via anysys SDLC subagents. Do **not** git commit. Do **not** add four-area module surfaces.

**Goal:** Platform owner can publish bilingual, severity-coded notices to all or selected customers; tenant admins see a dismissible top-most banner on the admin dashboard.

**Architecture:** Platform-global `PlatformAnnouncement` + targeting join; Reform contract + `Save` activity; Resolver for live rows; owner CRUD under `/admin/maintenance/platform/announcements`; session dismiss POST on tenant admin URL; `Platform::AnnouncementBannerComponent` as first child of `ShellComponent`.

**Tech Stack:** Rails 8.1.2, Reform + PORO `.call` Result (match `Captcha::Activities::UpdateProviderSettings`), ViewComponent, Tailwind, Stimulus, RSpec, Vitest.

## Global Constraints

- Inherit Grok 4.6 — do not switch models
- No hard-coded user-facing strings; `en` + `zh-CN` in parity
- Roles: only owner / admin / member; owner email + customer 81721200 unchanged
- URLs: CRUD is admin platform namespace; dismiss is admin (not platform prefix)
- `platform_announcements` has **no** `customer_id` (platform catalog, same as `billing_plans`)
- `platform_announcement_targets.customer_id` is required and indexed
- Do not git commit
- Do not wire the topbar notifications bell
- Do not create Modules / Settings / Maintenance-toggle surfaces
- Stimulus UI text: English `default:` + server `data-*-value`
- Follow spec: `docs/platform-announcements-design.md`

## File map

See design spec. Key create/modify paths are listed per task below.

---

### Task T-model (backend)

Build model + migration + Reform contract + Save activity + Resolver + factories + specs.

`Save.call(record:, params:)` params:

```ruby
{
  title:, body_en:, body_zh:, severity:, link_url:, status:, audience:,
  starts_at:, ends_at:, customer_ids: [] # ignored unless audience=selected
}
```

`Save` validates via contract, then transaction: persist announcement, `targets.delete_all`, insert selected customer ids when `audience=selected`.

`Resolver.for_customer(customer_id, dismissed_ids: [], now: Time.current)` returns live undismissed rows, newest first. An `audience: all` row must include a customer created after it was published.

Verify: `bundle exec rspec spec/models/platform_announcement_spec.rb spec/models/platform_announcement_target_spec.rb spec/services/platform_announcements/`

Do not edit views, routes, or controllers.

---

### Task T-ux

Write `docs/platform-announcements-ux.md` (not under docs/superpowers — that path is cursorignored).

Surfaces (not a feature module):

1. Owner CRUD index/new/edit/show — Maintenance / Platform, sibling of Customers
2. Customer picker on the form
3. Top-most admin chrome banner + `+N more` + dismiss

Reuse: `AdminPageComponent`, `AdminTableComponent`, `AlertComponent` tokens, `Platform::ContextBannerComponent` strip pattern, `ShellComponent`.

New: `Platform::AnnouncementBannerComponent`, `Platform::AnnouncementCustomerPickerComponent`, `Admin::Maintenance::Platform::AnnouncementFormComponent`.

shadcn: compose Alert severity as a full-width strip. Tailwind only.

---

### Task T-routes (security)

- Platform `resources :announcements` next to customers
- Tenant-admin (NOT platform scope): `resources :platform_announcement_dismissals, only: [:create]`
- CRUD controller uses `Save`; dismissals append to session only if Resolver includes the id
- Ability `:"platform_announcements"`; sidebar leaf after customers
- Thin views rendering the named components
- Auth matrix request specs

Do not edit models/migrations/components/JS.

---

### Task T-component (frontend)

Banner first in `shell_component.html.erb`. Form + picker. Stimulus filter 100% Vitest. I18n keys from spec. `<details>` for +N more.

---

### Task T-qa

Gap coverage: session dismiss, +N more next, owner-acting-as, schedule window, selected isolation, all-includes-new-customer.

---

### Task T-release

Targeted RSpec + smoke.

---

### Task T-review

Tech-lead + code-reviewer. This is platform maintenance + chrome, **not** a four-area module — do not fail for missing Modules/Settings/toggle.
