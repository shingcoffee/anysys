# Email Module — Mailchimp IA + Visual Polish Design

**Date:** 2026-07-24  
**Status:** Approved (Approach 1; sections 1–4 locked)  
**Scope:** Admin Email module layout, IA, and UI/UX convention fixes; Figma-first polish inside shared AdminPage chrome

## Goal

Bring the Email module in line with industry ESP conventions (Mailchimp-style peer areas) and fix concrete IA/labeling/UX defects verified in the live UI, then polish Email-specific surfaces in Figma without forking the admin shell.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Scope | Full redesign path: IA reshape + Figma polish (user option C) |
| IA model | Mailchimp-style peers: Audience / Send Activities / Content / Analytics |
| Approach | **1 — IA-first, then Figma polish** |
| Send Activities gate | **Removed** — when Email is enabled, all peers always available |
| Settings | Remove from Email sidebar; only under `/:cid/admin/settings/modules/emails` |
| Messages | Under **Content** as a tab with Templates (always when Email is enabled) |
| Recurrence | Presets only: None / Daily / Weekly / Monthly (RRULE stored under the hood) |
| Analytics tabs | **Overview \| Health** (always when Email enabled) |
| Visual depth | Shared AdminPage / AdminTable / Tabs chrome; Figma refreshes Email-specific patterns only |

## Clarifications (self-review)

- `FeatureModules::Email::Registration.entry_path` remains templates (Content default).
- `retired` DB/status value unchanged; UI string becomes Archived via locale.
- Settings module_key stays `email`; URL segment is plural `emails` via existing settings conventions.

## Problems verified (live UI)

| Severity | Finding |
|----------|---------|
| High | Suppressions page title/breadcrumb say **Settings** while Audience is selected |
| High | Messages activity log orphaned from Email sidebar IA |
| Medium | Page titles use parent sidebar label (e.g. Templates titled **Campaigns**) |
| Medium | Templates nested under Campaigns (transactional + marketing conflated) |
| Medium | Campaign wizard exposes raw RRULE string input |
| Medium | Analytics Overview vs Reports duplicate KPI/sparkline pattern |
| Medium | Stale pruned leftovers (locale keys; orphan view dirs: tags, streams, automations, …) |
| Medium | Settings contribution hardcodes `/settings/modules/email` (singular) while SettingsContributor pluralizes to `emails` |
| Lower | Campaign show not on AdminPage chrome; “Set retired” wording; pipe-separated row actions |

## Target IA

### Sidebar (Modules → Email)

| Email enabled | Entries (order) | Default landing |
|---------------------|-----------------|-----------------|
| (always) | Audience · Send Activities · Content · Analytics | Content → Templates |

**No Settings entry** under Modules → Email.

### In-page tabs

| Sidebar entry | Tabs | Notes |
|---------------|------|--------|
| **Content** | Templates · Messages | Page title = active tab |
| **Audience** | Contacts · Lists · Suppressions | Suppressions labeled correctly |
| **Send Activities** | *(none — list is the surface)* | Wizard is create/edit only |
| **Analytics** | Overview · Health | Only when campaigns on |

### Settings relocation

- Customer config (`daily_send_cap`) only via top nav **Settings → Email**.
- Canonical path: `/:cid/admin/settings/modules/emails` (plural, consistent with `SettingsContributor` / Payments-style pluralization). Fix registration hardcode of singular `/email`.
- Label daily cap as a general send cap (applies to transactional), not “Campaign daily cap” only.
- Platform SMTP/Postmark credentials remain under Maintenance / Platform / Module Settings (unchanged).

### Route map

Keep resources under `/:cid/admin/modules/emails/`:

| Area | Paths |
|------|--------|
| Content | `/templates`, `/messages` |
| Audience | `/contacts`, `/lists`, `/suppressions` |
| Send Activities | `/send_activities` (+ delivery/pause/cancellation member resources) |
| Analytics Overview | `/dashboard` (existing); redirect `/reports` → Overview |
| Analytics Health | `/health` (new); redirect `/deliverability`, `/engagement` → Health |

Copy rule: breadcrumb + `AdminPage` title reflect the **active tab**, not the parent sidebar label.

## Surface designs

### Content — Templates

- Keep list + Versions modal + guarded status transitions on the list.
- Status wording: i18n labels use Draft / Active / Archived (map existing `retired` status value to “Archived” in UI only — no schema rename in this work).
- Edit remains composer-only (Compose / Preview / Test) inside AdminPage.
- Figma: primary action, row actions as button group or overflow menu (not pipe-separated text), empty states aligned with other module tables.
- Templates remain available for transactional send when campaigns are off.

### Content — Messages

- Include in Content tabs; sidebar highlights Content on `/messages`.
- Keep index + show (status, events).
- v1: search-only is acceptable; optional status filter chips if low cost.
- Empty state may link to Templates (sends remain API/campaign-driven — no free-form compose CTA).

### Campaigns — list & show

- List is the Campaigns entry surface (no sibling tabs).
- Show migrates to full AdminPage chrome (replace one-off breadcrumbs layout).
- Keep stats + Send / Pause / Resume / Cancel; Figma groups primary vs secondary actions.

### Campaigns — wizard

- Steps unchanged: Setup → Audience → Content → Review.
- Stepper/form tokens aligned to admin design system where touched.
- **Recurrence:** `<select>` None / Daily / Weekly / Monthly → persist RRULE. Mapping:
  - None → blank / nil
  - Daily → `FREQ=DAILY;INTERVAL=1`
  - Weekly → `FREQ=WEEKLY;INTERVAL=1`
  - Monthly → `FREQ=MONTHLY;INTERVAL=1`
  No custom RRULE field.
- Audience: list picker only. Content: active template picker.

### Audience

- Contacts · Lists · Suppressions.
- Suppressions: title/breadcrumbs Audience / Suppressions; bulk unblock; Figma toolbar placement.
- Lists: static/dynamic + segment builder + preview; columns Name / Type / Audience / Description / Updated (remove stale Status from registration `lists_entry_config` if still present).
- Contacts: index + show; no tags.

### Analytics (campaigns on only)

- Sidebar label **Analytics** (replaces Overview).
- **Overview:** KPI strip (sent/delivered/bounced/opened/clicked; suppress/unsub secondary), one trend block, campaigns table; CSV export; date range. Absorbs Dashboard + Reports.
- **Health:** bounce/complaint/suppressed/failed KPIs, failure-code breakdown, recent suppressions, top links + devices. Absorbs Deliverability + Engagement.
- Date range on both tabs where applicable.

### Public / platform

- Unsubscribe, open/click tracking, webhooks: behavior unchanged (optional light token cleanup only if touched).
- No preference center / signup forms (already pruned).

## Visual (Figma)

Use `anysys-ux-designer` + Figma plugin **before** implementing polish. Stay on shared AdminPage / AdminTable / Emails::TabsComponent.

Email-specific patterns to design/refresh:

1. Tab bars + title/breadcrumb pairing  
2. KPI / Health metric cards (one shared component; reduce one-off card markup)  
3. Campaign wizard stepper + form spacing  
4. Template composer workspace  
5. Table empty states + row actions  
6. Suppressions bulk toolbar  

**Out of visual scope:** new Email page shell, custom fonts, new color system.

## Delivery order

1. IA: sidebar registration, tabs partials, titles/breadcrumbs, Settings path, Messages under Content, campaigns/analytics gating  
2. Analytics merge (Overview \| Health) + redirects from old analytics URLs  
3. Recurrence presets (wizard + any legacy form)  
4. Figma → implement polish on listed surfaces  
5. Prune stale locales / orphan view directories from removed shells  
6. Specs + Playwright/browser smoke  

## Testing

- Request / routing / registration specs: sidebar entries for both `campaigns_enabled` modes; Content includes Messages; no Settings sidebar entry; Settings URL `…/modules/emails`  
- Suppressions page title/breadcrumb  
- Analytics redirects; Health surface  
- Recurrence preset → RRULE persistence  
- Vitest 100% if Stimulus changes (presets may be server-only)  
- Browser smoke: campaigns on/off sidebars, Content tabs, Analytics tabs, Settings path  

## Non-goals

- New providers, Contact model rebuild, preference center, streams/tags/automations  
- Full custom Email visual system  
- Platform credential UX redesign  
- Changing public unsubscribe compliance flow beyond incidental polish  

## Success criteria

- Sidebar matches gated Mailchimp IA; Settings only under Settings → Email (`…/modules/emails`)  
- Suppressions never titled Settings; Messages under Content with correct sidebar highlight  
- Page titles match active tabs  
- Analytics is Overview \| Health only when campaigns on; old analytics URLs redirect  
- Recurrence is presets only (no RRULE text field in UI)  
- Figma-aligned polish on listed surfaces; email-module RSpec green; Vitest 100% if JS touched  

## Related specs

- `2026-07-24-email-module-lean-esp-design.md` (prune / suppressions / lists)  
- `2026-07-24-email-tags-template-settings-versionable-design.md` (tags removed; template list status/versions)  
