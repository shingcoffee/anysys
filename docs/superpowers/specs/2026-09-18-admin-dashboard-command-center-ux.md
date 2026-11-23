# Admin Home command center — UX spec

Date: 2026-09-18
Audience: frontend developer. Implement ViewComponent + Tailwind + Stimulus only. There is no React shadcn in the runtime.

Product brief: locked (Admin Home command center). This spec is the layout/interaction source of truth for `GET /:cid/admin/dashboard`.

Visual language: quiet SaaS command center using **existing Anysys admin tokens** — not a new palette, not glassmorphism, not charts, not new fonts. Map shadcn Card anatomy onto project ViewComponents.

Follows sibling surfaces:

- `app/components/admin/dashboard/workspace_component.*` (composer)
- `app/components/landing_header_component.*`
- `app/components/landing_stats_card_component.*`
- `app/components/card_component.*` (`.card` / `.card-header`)
- `app/components/quick_action_card_component.*`
- `app/components/admin/maintenance/platform/module_catalog_component.*` (module icon wells)
- `Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS`

Do **not** change member dashboard, Settings catalog, Maintenance / Modules, platform Module Settings, or the AI Assistant page. Do **not** embed a composer. Do **not** show flowchart chrome or the word “flowchart”.

All new copy: I18n `en` + `zh-CN`. English value = the string that would otherwise have been hard-coded. Reuse an existing key when the English is already keyed. Never bake `t()` into a Ruby constant.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Audience | Change |
|---|---|---|---|---|---|
| A | Admin Home (command center) | **admin** (top-level Home; not a module area) | `GET /:cid/admin/dashboard` | `admin` or `owner` (existing admin GET guard) | Restyle + add module cards, recents, hide Getting started at 100%, module-aware quick actions |
| — | AI Assistant | admin | `GET /:cid/admin/assistant` | same | **Link only** from Home when `ai_assistant` is available. Do not restyle or embed. |
| — | Module entries / settings destinations | Modules or Settings | locked primaries/secondaries below | same | **Link only.** Do not restyle those pages. |
| — | Maintenance / Modules | Maintenance/Modules | `GET /:cid/admin/maintenance/modules` | same | Metrics tile + optional “Enable module” action. Do not restyle. |

Out of scope (no new surfaces):

- Member dashboard / any `/:cid/member/` URL
- Public checkout (`/:cid/payments/checkout/start`)
- Platform `/:cid/admin/maintenance/module_settings`
- Flowchart editor, grants, or the word “flowchart”
- New routes, charts, activity feed, per-user layout customization

Chrome (unchanged):

```
+------------------------------------------------------------------+
| [announcement / context banners if present]                      |
+------------------------------------------------------------------+
| Topbar (search, locale, notifications, user)                     |
+------------------------------------------------------------------+
| Home | AI Assistant | Entities | Pages | Modules | Settings | …  |
+------------------------------------------------------------------+
| <main>  — no left SidebarComponent (ShellComponent omits it on   |
|           :home). Padded admin default — not :edge.              |
+------------------------------------------------------------------+
```

No `AdminPageComponent` breadcrumbs. Home stays a top-level landing surface.

---

## 2. Layout spec — Surface A (Admin Home)

**Composer:** `Admin::Dashboard::WorkspaceComponent`  
**Controller:** `Admin::DashboardsController#show` (`dashboard_menu_item :home`)  
**Page stack:** `flex flex-col gap-6` (generous, matches today’s workspace). No `space-y-*`.

### Vertical order (locked)

1. Welcome header
2. Snapshot metrics (4 tiles)
3. Enabled-module cards
4. Getting started — **omit the entire block when all 4 items are done**
5. Recent pages (5) + recent entities (5)
6. Module-aware quick actions (cap 8)

### ASCII — desktop (`lg+`, ~1100px content)

```
<main, padded :full>
+--------------------------------------------------------------------------+
| Welcome back, {first_name}                            [customer.name]    |
| {long date}                                                              |
+--------------------------------------------------------------------------+
| +------------------+ +------------------+ +------------------+ +--------+|
| | [icon] ENTITIES  | | [icon] PAGES     | | [icon] MODULES   | | [icon] ||
| | 12               | | 8                | | 4                | | USERS  ||
| |                  | | 3 launched       | |                  | | 6      ||
| +------------------+ +------------------+ +------------------+ +--------+|
| grid-cols-2  →  lg:grid-cols-4                                           |
+--------------------------------------------------------------------------+
| Enabled modules                                                          |
| Jump into features turned on for this organization.                      |
| +------------------------+ +------------------------+ +------------------+|
| | [well] User Auth       | | [well] Email           | | [well] Payments  ||
| | Manage users and …     | | Templates, lists, …    | | Transactions, …  ||
| | [Users] [Security Log] | | [Email Templates]      | | [Transactions]   ||
| |         [Sign up]      | | [Send Activity][Audience]| | [Subscriptions]  ||
| +------------------------+ +------------------------+ +------------------+|
| +------------------------+ +------------------------+ +------------------+|
| | [well] SMS             | | [well] Captcha         | | [well] AI Assist ||
| | Messages, opt-outs, …  | | Protect public forms.  | | Open the admin … ||
| | [Messages] [Opt-outs]  | | [Open settings]        | | [Open assistant] ||
| | [Daily cap]            | |                        | | [Settings]       ||
| +------------------------+ +------------------------+ +------------------+|
| grid-cols-1 / md:grid-cols-2 / lg:grid-cols-3                            |
+--------------------------------------------------------------------------+
| Getting started                                      2 of 4 complete     |
| ████████░░░░                                                             |
| ● Create your first entity                                               |
| ○ Launch a page                                                          |
| …  (THIS WHOLE CARD IS ABSENT when 4/4 done)                             |
+-------------------------------------+------------------------------------+
| Recent pages              [View all]| Recent entities          [View all]|
| ----------------------------------- | ---------------------------------- |
| Contact form          [Live]     >  | Members                            |
| Welcome page          [Draft]    >  | Invoices                           |
| … up to 5                           | … up to 5                          |
|  -- or compact empty + CTA --       |  -- or compact empty + CTA --      |
+-------------------------------------+------------------------------------+
| Quick actions                                                            |
| [icon] Create entity            >   [icon] New page                   >  |
|        Set up a new data type              Bind a form to an entity      |
| [icon] Invite user              >   [icon] Email Templates            >  |
| … up to 8 rows, 2-col on lg                                              |
+--------------------------------------------------------------------------+
</main>
```

### ASCII — mobile stacking (`< md`)

```
<main, padded>
| Welcome back, {first_name}                 [badge] |
| {long date}                                        |
| +----------------------+ +----------------------+  |
| | [icon] ENTITIES  {n} | | [icon] PAGES {n}     |  |
| +----------------------+ +----------------------+  |
| | [icon] MODULES   {n} | | [icon] USERS {n}     |  |
| +----------------------+ +----------------------+  |
| Enabled modules                                    |
| [User Authentication card, full width]             |
| [Email card]                                       |
| … one column                                       |
| Getting started (if incomplete)                    |
| Recent pages (full width)                          |
| Recent entities (full width, below pages)          |
| Quick actions (single column, compact rows)        |
</main>
```

**Breakpoints**

| Region | `< md` | `md` | `lg+` |
|---|---|---|---|
| Page stack | `flex flex-col gap-6` | same | same |
| Metrics | `grid-cols-2 gap-3` | same | `lg:grid-cols-4 lg:gap-4` |
| Module cards | `grid-cols-1 gap-4` | `md:grid-cols-2` | `lg:grid-cols-3` |
| Recents | `grid-cols-1 gap-6` (pages then entities) | same | `lg:grid-cols-2` |
| Quick actions inside card | 1 col | 1 col | `lg:grid-cols-2` |
| Module card footer | `flex-col` (buttons stretch full width) | `sm:flex-row sm:flex-wrap` | same |

Touch targets: module footer buttons and recents rows `min-h-10`; `pointer-coarse:min-h-11` if the row is a plain link.

---

### 2.1 Header

**Reuse:** `LandingHeaderComponent` (welcome `chrome.landing_header.welcome`, `l(Date.current, format: :long)`, `BadgeComponent` `variant: :default` `size: :md` with `customer.name`).

**Modest polish (allowed, keep structure):**

- Keep `flex flex-wrap items-start justify-between gap-3` (or `items-center` if the badge sits optically better against the two-line block).
- Do not add a product subtitle, tenant id, or second badge.
- Do not introduce a new component.

**Data:** `user.first_name`, `Date.current`, `customer.name`.

**Actions:** none. Not a link.

**Empty / loading / error:** always rendered. No skeleton. Auth errors never reach this component.

---

### 2.2 Snapshot metrics

**Region:** `<section aria-labelledby="dashboard-overview-title">` with `h2` `sr-only` using existing `admin_misc.dashboard.snapshot`.

**Tiles:** four, always, even when counts are `0`.

| Tile | Value | Sub | Icon | href |
|---|---|---|---|---|
| Entities | `LandingStats[:entities]` | — | `WorkspaceComponent::ICONS[:entities]` | `admin_entities_path` |
| Pages | `pages[:total]` | `admin_misc.dashboard.pages_sub_label` (`%{count}` = launched) | `ICONS[:pages]` | `admin_pages_path` |
| Modules | `modules_enabled` (assignment count, unchanged) | — | `ICONS[:modules]` | `admin_maintenance_modules_path` |
| Users | `users` (active) | — | `ICONS[:users]` | `admin_modules_authentication_users_path` |

Labels: existing `admin_misc.dashboard.stats.*`.

**Visual (beautify; icons were defined but unused in ERB):**

Each tile is a **single** `<a>` (no nested buttons). Card-like, not `.stat-card` custom chrome on Home — use utilities so Home matches `CardComponent` / listed tokens:

```
flex flex-col gap-2 rounded-xl bg-surface px-4 py-4 no-underline
ring-1 ring-border-subtle shadow-xs transition-base
hover:bg-accent-subtle hover:ring-accent-muted
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2
```

Inner:

```
[ size-9 rounded-lg bg-accent-subtle ]  icon SVG size-4 text-accent  (aria-hidden)
label: text-[11px] font-medium uppercase tracking-wider text-text-muted
value: text-2xl font-semibold tabular-nums tracking-tight text-text-primary
sub:   text-[11px] text-text-muted   (pages only)
```

Icon well sits **above** the label (not a left-aligned compact row) so the four-up grid stays tall enough to read as cards. On the 2-col phone grid, keep the same anatomy.

**Reuse:** prefer `LandingStatsCardComponent` **only if** it is updated to this anatomy (optional `href:`, always pass `icon:`, Home-density, no new CSS class). Otherwise compose the tile in `WorkspaceComponent` ERB. Do not ship Home tiles without icons.

**Actions:** the tile is the primary (and only) action. No secondary. No destructive.

**Empty:** `0` is a valid number, still clickable.  
**Loading:** server-rendered.  
**Error:** none local to this region.

---

### 2.3 Enabled-module cards

**Region:** `<section aria-labelledby="dashboard-modules-title">`.

**Visible heading + description** (not sr-only — this is the command-center body):

- Title: `admin_misc.dashboard.modules.title` → `Enabled modules`
- Description: `admin_misc.dashboard.modules.description` → `Jump into features turned on for this organization.`

**Source:** `FeatureModules::Module.available_for_customer(customer_id).by_name`.  
Disabled / unassigned optional modules: **no card**. Authentication is required → at least one card on a healthy tenant.

**Card anatomy (shadcn → ViewComponent):**

| shadcn | Anysys |
|---|---|
| `Card` | `CardComponent` `variant: :default` `padding: :none` |
| `CardHeader` | existing `.card-header` strip **or** `px-6 pt-5 pb-3` with icon + title + description |
| `CardTitle` | `h3` `text-sm font-semibold text-text-primary` = `fm.display_name` |
| `CardDescription` | `p` `text-xs leading-relaxed text-text-muted line-clamp-2` = Home blurb (dashboard i18n, not vendor internals) |
| `CardContent` | omit if header already holds title+blurb (preferred: header-only body) |
| `CardFooter` | `flex flex-col gap-2 border-t border-border-subtle px-6 py-3 sm:flex-row sm:flex-wrap sm:items-center` |

**The card is not a link.** Footer buttons are the hit targets (avoids nested interactive content).

**Header row:**

```
[ size-9 rounded-lg {module_color_classes} ]  heroicon path from MODULE_ICON_PATHS
  fallback DEFAULT_MODULE_ICON_PATH for unknown keys
title + blurb
```

Tint the **icon well only** with existing `ModuleSettingsHelper#module_color_classes` (already used on Settings catalog / platform module catalog). Card body stays `bg-surface`. Do not rainbow the whole tile. Unknown future keys: `bg-surface-active text-text-secondary`.

**Blurbs** (Home-purpose, not settings-catalog copy — those are settings-only):

| key | en | zh-CN |
|---|---|---|
| authentication | Manage users and sign-in for this organization. | 管理本组织的用户与登录。 |
| email | Templates, lists, and send activity. | 模板、受众名单与发送记录。 |
| payment | Transactions, subscriptions, and merchant accounts. | 交易、订阅与商户账户。 |
| sms | Messages, opt-outs, and send limits. | 短信、退订与发送上限。 |
| captcha | Protect public forms with captcha. | 用验证码保护公开表单。 |
| ai_assistant | Open the admin assistant and customer settings. | 打开管理端助手并查看本组织设置。 |
| fallback | `%{name} is on for this organization.` | 本组织已启用%{name}。 |

**Primary / secondary destinations (locked)**

Footer: **primary** `ButtonComponent` `variant: :primary` `size: :sm` `tag: :a`; **up to two secondaries** `variant: :secondary` `size: :sm` `tag: :a`. No third control. No kebab. No destructive.

If primary path cannot be resolved: **omit the primary button** (never a dead `#` or 404). If no actions at all: omit `CardFooter`.

| Module | Primary (label → path) | Secondary 1 | Secondary 2 |
|---|---|---|---|
| authentication | Users → `/:cid/admin/modules/authentication/users` | Security Log → `…/modules/authentication/events` | Sign up → `…/settings/modules/authentication/sign_up` |
| email | Email Templates → `/:cid/admin/modules/emails/templates` | Send Activity → `…/modules/emails/send_activities` | Audience → `…/modules/emails/lists` |
| payment | Transactions → `/:cid/admin/modules/payments/transactions` | Subscriptions → `…/modules/payments/subscriptions` | Merchant Accounts → `…/settings/modules/payments/merchant_accounts` |
| sms | SMS Messages → `/:cid/admin/modules/sms/messages` | Opt-outs → `…/modules/sms/opt_outs` | Daily cap → `/:cid/admin/settings/modules/sms` (existing generic module config) |
| captcha | Open settings → `/:cid/admin/settings/modules/captcha` | — | — |
| ai_assistant | Open assistant → `/:cid/admin/assistant` | Settings → `/:cid/admin/settings/modules/ai_assistant` | — |
| unknown future | first sidebar **entries** path, else first **settings** path | next entries/settings path if any | next if any |

**Label reuse:** use `feature_modules.<key>.entries.*` / `.settings.*` / `.titles.*` when the English matches (Users, Security Log, Sign up, Email Templates, Send Activity, Audience, Transactions, Subscriptions, Merchant Accounts, SMS Messages, Opt-outs, Daily cap). New Home-only keys: `Open settings`, `Open assistant`. AI secondary reuses `chrome.menu_bar.items.settings` (`Settings`).

**Forbidden hrefs on these cards:** public/member checkout; platform `/admin/maintenance/module_settings`; flowchart paths; `javascript:`.

**AI card:** navigation only. Must **not** mount `data-controller="ai-assistant"`, composer, artifact pane, or assistant offline empty copy.

**Empty:** if the collection is somehow empty, omit the whole section (heading included). Do not show a giant empty card. Today authentication keeps this from happening.

**Loading / error:** server-rendered; no vendor calls.

---

### 2.4 Getting started

**Show when** `setup_done_count < 4`.  
**Hide when** all four predicates are true — **no title, no progress, no list, no empty-success illustration.** Completing the last item is a full GET refresh, not client hide. No Stimulus.

Predicates (unchanged):

| Item | Done when | href |
|---|---|---|
| Create your first entity | `entities > 0` | `new_admin_maintenance_entity_path` |
| Launch a page | `pages.launched > 0` | `admin_pages_path` |
| Enable a module | `modules_enabled` assignment count `> 0` (optional modules, not merely mandatory auth) | `admin_maintenance_modules_path` |
| Invite a teammate | `users > 1` | `new_admin_modules_authentication_user_path` |

**Visual:** one `CardComponent` `padding: :md`, full width (no longer paired in a 2-col with quick actions). Keep today’s checklist language and progress:

- Title `admin_misc.dashboard.setup.title`
- Progress `admin_misc.dashboard.setup.progress`
- `role="progressbar"` track `h-1.5 rounded-full bg-surface-active`, fill `bg-accent`
- Done: success check circle + `text-text-muted` label
- Undone: empty circle `border-border-strong` + `text-text-primary` / hover accent
- Row is a link with `rounded-lg px-1 py-1.5 hover:bg-accent-subtle` and the same focus ring as metrics

**Actions:** each row is primary for that item. No page-level CTA. No destructive.

---

### 2.5 Recent pages + recent entities

**Region:** `grid grid-cols-1 gap-6 lg:grid-cols-2 lg:items-start`.

Two sibling cards. Neither list may include another tenant’s **owned** rows. Shared (`customer_id` NULL) rows **may** appear. Do not badge them “Shared” (extra concept on Home). Do not show timestamps (PO: name + launched state only).

#### Recent pages

- Query intent: `Page.accessible` for the URL tenant, exclude inactive/soft-deleted the same way admin browse already does, `order(updated_at: :desc)`, `limit 5`.
- Row: `page.name` (`truncate`) + `BadgeComponent` `size: :sm`
  - launched → `variant: :success`, label `common.labels.live` (`Live`)
  - not launched → `variant: :default`, label `common.labels.draft` (`Draft`)
- Row href: existing `admin_page_path(cid, page)` (ops show / manage access — not maintenance editor, not public UUID).
- Header: title `Recent pages` + ghost `ButtonComponent` `variant: :ghost` `size: :sm` `tag: :a` “View all” → `admin_pages_path`.
- Empty: **compact** inside the card (see 2.5.1). CTA: `admin_misc.pages.empty_action` (`New page`) → `new_admin_maintenance_page_path`. Keep “View all” in the header.

#### Recent entities

- Query intent: non-bridge entities this tenant can browse (tenant-owned + shared), same non-bridge rule as `LandingStats`, exclude inactive/soft-deleted / default visible scope, `updated_at desc`, `limit 5`.
- Row label: `display_label.presence || name`.
- Row href: `admin_entity_path(cid, entity)` (browse entries).
- Header: `Recent entities` + “View all” → `admin_entities_path`.
- Empty CTA: `admin_misc.entities.create_entity` (`Create Entity`) → `new_admin_maintenance_entity_path`.

**Row chrome (both lists):**

```
<a class="group flex items-center gap-3 px-4 py-3 no-underline transition-base
          hover:bg-accent-subtle
          focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent
          focus-visible:ring-inset">
  <span class="min-w-0 flex-1 truncate text-sm font-medium text-text-primary group-hover:text-accent">
    {name}
  </span>
  {optional badge}
  <svg chevron size-4 text-border-strong group-hover:text-accent aria-hidden>
</a>
```

Separate rows with `divide-y divide-border-subtle`. Do not use `Admin::Pages::OpsTableComponent` or `Admin::CardTableComponent` (too heavy: filters, selection, kebab).

#### 2.5.1 Compact empty (required)

Do **not** render default `EmptyStateComponent` (`py-16` centered illustration). On Home that empty would dominate the two-up recents row.

Preferred:

- Add optional `compact: true` to `EmptyStateComponent` **or** compose a quiet region in the recents card:
  - container: `px-4 py-6` (not `py-16`)
  - no 64px icon well (optional `size-8` muted document icon, or no icon)
  - title: `text-sm font-medium text-text-primary`
  - description: `text-xs text-text-muted` (one line)
  - CTA: `ButtonComponent` `variant: :secondary` `size: :sm` **or** a text link `text-sm font-medium text-accent`

Copy:

| List | Title (en) | Description (en) | CTA |
|---|---|---|---|
| Pages | No pages yet | Pages you create will show up here. | New page |
| Entities | No entities yet | Create an entity to start capturing records. | Create Entity |

zh-CN:

- 暂无页面 / 创建的页面会显示在这里。 / 新建页面
- 暂无实体 / 创建实体后即可开始录入数据。 / 创建实体

Reuse `admin_misc.pages.empty_title` (`No pages yet`) and `admin_misc.entities.empty_title` (`No entities defined yet`) **only if** you accept the existing English byte-for-byte. Prefer the shorter Home strings above if those existing strings are too long for a compact well (`No entities defined yet` is wordy). New keys under `admin_misc.dashboard.recents.*` are expected.

---

### 2.6 Module-aware quick actions

**Region:** one `CardComponent` `padding: :none`, full width, **after** recents.

- Header: existing `admin_misc.dashboard.quick_actions` in `.card-header` / `px-6 py-4`.
- Body: `lg:grid lg:grid-cols-2`. Each cell is `QuickActionCardComponent` with **`compact: true`** (eight items must not become a tall novel). `hover:bg-accent-subtle` already on the component.
- Cap **8**. No “see more”. No overflow menu.

**Composition (locked product rules — visual order = this list order):**

1. Always: Create entity, New page, Invite user (existing paths + `admin_misc.dashboard.actions.*`).
2. Enable module **only if** at least one platform-active, non-required module is not in `available_for_customer`. Else omit.
3. Then at most **one extra per enabled module other than authentication**, `by_name`, using the **same primary destinations as the module cards**.
4. If still under 8: second extras in the same module order — email send activity, payment merchant accounts, SMS opt-outs. Authentication does not add a second extra (invite already covers it).

**Icons:**

- Core four: existing `ACTION_ICONS` (`create_entity`, `new_page`, `enable_module`, `invite_user`).
- Module extras: `MODULE_ICON_PATHS[key]` (same paths as module cards).

**Labels for extras:** same as the module-card control they clone (Email Templates, Transactions, SMS Messages, Open settings, Open assistant, Send Activity, Merchant Accounts, Opt-outs). Descriptions: short dashboard i18n (`Open {destination} for this organization.` / 为本组织打开{destination}。) — or reuse the module blurb if it still reads as a shortcut.

**Forbidden:** flowchart editor/maintenance, platform module settings, member URLs, public checkout.

**Empty:** the three core actions always exist → this card always renders. Never an empty quick-actions card.

---

### 2.7 Empty / loading / error (page-level)

| State | Treatment |
|---|---|
| Fresh tenant (zeros, auth-only) | Header + 0-count metrics + authentication module card + Getting started 0/4 + compact recents empties + quick actions including Enable module |
| Mature tenant (4/4 setup, modules on, recents full) | No Getting started. Module grid + recents + quick actions (Enable module hidden if nothing left to enable) |
| Loading | First paint is the HTML response. **No Skeleton, no Stimulus spinner** |
| Anonymous / member / cross-tenant admin | Existing admin GET / tenant guards. Home does not design a 403 card |
| Owner on `/:cid/admin/dashboard` | Identical layout; data is **that** `:cid` only |
| Vendor-down | Home never calls vendors. No error banner |
| Unknown module without a path | Card with name + blurb, no footer |

Do **not** render on Home: composer, `SpeechToText::AssistantPanelComponent`, artifact pane, `data-dashboard-region="chat"`, `data-controller="ai-assistant"`.

---

## 3. Interaction flow

All destinations are existing GET/new paths. Home itself is read-only.

### Story 1 — professional workspace

1. Sign in as `admin` or `owner` → land on `GET /:cid/admin/dashboard` (or open Home in the top menu).
2. Page paints in the locked vertical order, padded admin main, Home tab current, no sidebar.
3. Resize to phone: metrics stay 2-up; modules, recents, actions stack.
4. **Failure:** unauthenticated / `member` → existing deny (redirect or 403). No Home-specific flash.

### Story 2 — module cards

1. Home shows one card per `available_for_customer` module, `by_name`.
2. Click primary → that module’s locked primary URL.
3. Click a secondary → locked secondary URL.
4. Captcha primary → Settings / Captcha (never platform Module Settings).
5. AI primary → `/admin/assistant` (full Assistant page). Home does not open a drawer/composer.
6. Payment primary → transactions (never checkout start).
7. **Failure / unknown module:** no primary button if no path; card still visible.
8. Disabled module: no card.

### Story 3 — recents

1. Click a page row → `admin_page_path`.
2. Click a entity row → `admin_entity_path`.
3. Header “View all” → pages index / entities index.
4. Empty list: compact empty + CTA to new page / new entity.
5. **Failure:** other-tenant owned rows never listed. Soft-deleted/bridge excluded.

### Story 4 — hide Getting started

1. Incomplete: section visible; click a pending row → existing setup href.
2. Complete last item on the destination page; return to Home (navigation or refresh).
3. Getting started is gone. Metrics / modules / recents / actions remain.
4. No client-only hide; no toast required.

### Story 5 — quick actions

1. Click a compact row → its path.
2. Enable module appears only when something remains to enable; click → Maintenance / Modules.
3. After enabling all optional modules, refresh: Enable module row gone; extras still capped at 8.
4. **Failure:** no action points at flowchart, platform module settings, member, or checkout.

### Story 6 — owner on a tenant URL

1. Owner opens `/81721200/admin/dashboard` vs `/OTHER/admin/dashboard`.
2. Each shows that URL tenant’s modules, stats, recents, actions.
3. No flowchart wording, no platform Module Settings shortcut, no other-tenant rows.

### Story 7 — snapshot metrics

1. Click Entities / Pages / Modules / Users tiles → existing index paths.
2. Counts match `LandingStats` today. Icons visible. Focus ring visible on keyboard tab.

### Keyboard / a11y

- Tab order: header (non-tab) → metric links (4) → module footer buttons → setup rows (if any) → recents header link + rows → quick action links.
- `:focus-visible` ring `ring-2 ring-accent ring-offset-2` on metric tiles; `ring-inset` acceptable on dense recents rows. Global `:focus-visible` outline already exists — do not remove it; extra ring on large tiles is required for WCAG 2.4.7.
- Contrast: `text-text-primary` on `bg-surface`; `text-text-muted` only for supporting copy; accent text on `bg-accent-subtle` wells already used in admin.
- Icons: SVG heroicons (`stroke-width` 1.5–1.75), `aria-hidden="true"`. No emoji.
- Sections have `aria-labelledby` pointing at visible (or sr-only for metrics) `h2`. Module card titles are `h3`.
- Progressbar keeps `aria-valuenow/min/max`.

---

## 4. Component reuse map

| Piece | Reuse | New | Props / notes |
|---|---|---|---|
| Page composer | `Admin::Dashboard::WorkspaceComponent` | — | Extend assigns: modules, recent pages, recent entities, setup visibility, actions (already) |
| Welcome | `LandingHeaderComponent` | — | `customer:`, `user:` |
| Customer name | `BadgeComponent` | — | already inside header |
| Metric tiles | `LandingStatsCardComponent` **if** updated to Home anatomy + `href` + icons; else inline in workspace | — | Must show `ICONS` |
| Module section | `CardComponent` per module | **`Admin::Dashboard::ModuleCardComponent`** | `name`, `blurb`, `icon_path`, `icon_well_classes`, `primary:` `{label, href}?`, `secondaries:` array size 0–2 |
| Getting started | existing workspace checklist + `CardComponent` | optional extract `Admin::Dashboard::GettingStartedComponent` | Omit at 100% |
| Recents | `CardComponent` + `BadgeComponent` + `ButtonComponent` (View all / empty CTA) | **`Admin::Dashboard::RecentListComponent`** | `title`, `view_all_href`, `view_all_label`, `rows:` `{label, href, badge: {variant, label}?}`, `empty:` `{title, description, action_label, action_href}` |
| Compact empty | `EmptyStateComponent` **only with `compact: true`** | compact flag on EmptyState **or** inline in RecentList | Never default `py-16` on Home |
| Quick actions | `CardComponent` + `QuickActionCardComponent` `compact: true` | — | `label`, `description`, `path`, `icon` |
| Footer/header actions | `ButtonComponent` `primary` / `secondary` / `ghost` `size: :sm` `tag: :a` | — | `href:` |
| Module icons/tints | `ModuleSettingsHelper` constants | — | Do not duplicate path strings; include the helper in the new module card |

**Do not reuse:** `Admin::Maintenance::Platform::ModuleCatalogComponent` (platform owner directory, whole-card link, status badges, module key chip). `Emails::MetricCardComponent` (left border accent). `EmptyStateComponent` default density. `Admin::Pages::OpsTableComponent`.

**Stimulus:** **none.** Server-rendered links only. Do not add a dashboard controller.

---

## 5. Tailwind & Stimulus notes

### Tokens (use these; do not invent)

- Surfaces: `bg-surface`, `bg-canvas` (page), `bg-accent-subtle`, `bg-surface-active` (progress track)
- Text: `text-text-primary`, `text-text-muted`, `text-accent` (hover labels)
- Lines: `ring-1 ring-border-subtle`, `border-border-subtle`, `hover:ring-accent-muted`
- Elevation: `shadow-xs`, `rounded-xl`, `rounded-lg` (icon wells)
- Motion: `transition-base`
- Type: existing scale — metric value `text-2xl font-semibold tabular-nums`; section `h2` `text-sm font-semibold`; blurbs `text-xs leading-relaxed`
- Spacing: page `gap-6`; module grid `gap-4`; icon well `size-9`; no `space-y-*` / `space-x-*` (use `flex` + `gap-*`); equal box → `size-*`

### shadcn mapping (do not add React)

- Card = `CardComponent` + `.card-header` + padded body + bordered footer with `ButtonComponent`s
- Badge = `BadgeComponent`
- Button variants: primary / secondary / ghost (no outline class — project uses `btn-secondary`)
- Empty = compact empty, not shadcn `Empty` React
- No `Chart`, `HoverCard`, `Command`, `Skeleton` on this page

### Stimulus

**None required. None allowed for the locked behavior.** Copy stays in ERB `t()`.

### I18n (new keys under `admin_misc.dashboard`)

Keep existing `stats.*`, `snapshot`, `quick_actions`, `setup.*`, `actions.{create_entity,new_page,enable_module,invite_user}.*`.

Add (en shown; zh-CN in parity):

```yaml
modules:
  title: "Enabled modules"
  description: "Jump into features turned on for this organization."
  blurbs:
    authentication: "Manage users and sign-in for this organization."
    email: "Templates, lists, and send activity."
    payment: "Transactions, subscriptions, and merchant accounts."
    sms: "Messages, opt-outs, and send limits."
    captcha: "Protect public forms with captcha."
    ai_assistant: "Open the admin assistant and customer settings."
    fallback: "%{name} is on for this organization."
  actions:
    open_settings: "Open settings"
    open_assistant: "Open assistant"
recents:
  pages_title: "Recent pages"
  entities_title: "Recent entities"
  view_all: "View all"
  pages_empty_title: "No pages yet"
  pages_empty_description: "Pages you create will show up here."
  entities_empty_title: "No entities yet"
  entities_empty_description: "Create an entity to start capturing records."
```

zh-CN:

- 已启用的模块 / 进入本组织已开启的功能。
- 最近页面 / 最近实体 / 查看全部
- 打开设置 / 打开助手

Do not add keys that duplicate `feature_modules.*.entries|settings|titles` or `common.labels.live|draft`.

### Explicit non-goals (visual)

- No new fonts, no Inter override, no glassmorphism, no gradients, no charts, no sparklines, no emoji, no custom CSS file, no `.stat-card` requirement on Home
- No bento “hero” spanning two rows
- No pinning / drag-reorder
- No flowchart wording anywhere in copy or `aria-label`s

---

## Frontend implementation notes (non-visual)

Workspace will need extra assigns from `DashboardsController#show` (modules, recents, possibly pre-built action list). That is backend’s slice. UX only requires the regions above to be present in the right order with the right empty rules.

`LandingStats` count semantics stay unchanged.
