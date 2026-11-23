# Split AI Assistant from admin Home — UX spec

Date: 2026-09-07
Audience: `admin` or `owner` (same-tenant admin; owner may cross tenants). Not a feature module. No Settings / Maintenance / member / public surfaces.

Source of truth for product decisions: `docs/2026-09-07-split-ai-assistant-from-home-design.md`.

This is admin chrome. Both surfaces live in the top admin menu, not the four module navigation areas.

---

## 1. Surface inventory

| Surface | URL | nav_area | Chrome |
|---|---|---|---|
| Home dashboard | `GET /:cid/admin/dashboard` | admin | Top menu, **Home** current. No left sidebar. Default padded main (`:full` admin default — **not** `:edge`). |
| AI Assistant | `GET /:cid/admin/assistant` | admin | Top menu, **AI Assistant** current. No left sidebar. Edge-to-edge canvas (`content_for(:container_width, "edge")`). |

Shared chrome (not new surfaces):

- Top menu bar gains a seventh item immediately after Home: **Home · AI Assistant · Entities · Pages · Modules · Settings · Maintenance**.
- Label i18n: `chrome.menu_bar.items.assistant` → en `AI Assistant` (byte-identical to `speech_to_text.assistant.title`) / zh-CN `AI 助手`.
- Mobile drawer lists the same seven items. No hamburger tree on either surface (sidebar omitted).
- Post-login / MFA / registration / help-ticket fallbacks stay on Home. Speech-to-text module `entry_path` opens Assistant.

Do **not** add Settings, Maintenance/Modules, or Maintenance/Platform surfaces for Assistant.

---

## 2. Layout spec per surface

### Shared chrome (both surfaces)

```
+------------------------------------------------------------------+
| [announcement / context banners if present]                      |
+------------------------------------------------------------------+
| Topbar (search, locale, notifications, user)                     |
+------------------------------------------------------------------+
| Home | AI Assistant | Entities | Pages | Modules | Settings | …  |
+------------------------------------------------------------------+
| <main>  — no left SidebarComponent                               |
|   Home: padded (px-3 sm:px-4 lg:px-8, py-8 lg:py-10)             |
|   Assistant: edge (flush, h-full canvas)                         |
+------------------------------------------------------------------+
```

`ShellComponent#show_sidebar?` must treat `:assistant` like `:home` (omit sidebar). Edge width is defense in depth on Assistant only.

No `AdminPageComponent` breadcrumbs on either page — both are top-level landing surfaces, same as today’s Home.

---

### Surface A — Home dashboard

**Component:** keep `Admin::Dashboard::WorkspaceComponent`, stripped of chat / artifact / offline empty / all `@assistant_*` assigns. Stop calling `content_for(:container_width, "edge")` so the shell uses the default padded admin main.

**Controller:** `Admin::DashboardsController#show`. `dashboard_menu_item :home`.

#### ASCII — desktop (≥ `lg`)

```
<main, padded :full>
+------------------------------------------------------------------+
| Welcome back, {first_name}                      [customer.name]  |
| {long date}                                                      |
+------------------------------------------------------------------+
| +------------+ +------------+ +------------+ +------------+      |
| | ENTITIES   | | PAGES      | | MODULES    | | USERS      |      |
| | {n}        | | {n}        | | {n}        | | {n}        |      |
| |            | | n launched | |            | |            |      |
| +------------+ +------------+ +------------+ +------------+      |
| grid-cols-2 (sm+) / lg:grid-cols-4                               |
+--------------------------------+---------------------------------+
| Getting started          2/4   | Quick actions                   |
| ████████░░░░                   |                                 |
| ● Create your first entity     | [icon] Create entity         >  |
| ● Launch a page                |      Set up a new data type     |
| ○ Enable a module              | [icon] New page              >  |
| ○ Invite a teammate            |      Bind a form to an entity   |
|                                | [icon] Enable module         >  |
|                                | [icon] Invite user           >  |
+--------------------------------+---------------------------------+
</main>
```

#### ASCII — mobile (< `lg`)

```
<main, padded>
| Welcome back, {first_name}          [badge] |
| {long date}                                 |
| +----------------+ +----------------+       |
| | ENTITIES  {n}  | | PAGES {n}      |       |
| +----------------+ +----------------+       |
| | MODULES   {n}  | | USERS {n}      |       |
| +----------------+ +----------------+       |
| Getting started  n/4                        |
| progress + checklist                        |
| Quick actions                               |
| non-compact stacked cards                   |
</main>
```

#### Regions and data

| Region | Source | Display |
|---|---|---|
| Header | `user.first_name`, `Date.current`, `customer.name` | Reuse `LandingHeaderComponent` (welcome `chrome.landing_header.welcome`, long date, `BadgeComponent` `variant: :default` `size: :md`). Do **not** keep the compact rail header from today’s workspace aside. |
| Metrics | `LandingStats` via `@stats` | Four link cards, same fields as today’s `metric_items`: entities → `admin_entities_path`; pages (+ `pages_sub_label`) → `admin_pages_path`; modules → `admin_maintenance_modules_path`; users → `admin_modules_authentication_users_path`. Labels: `admin_misc.dashboard.stats.*`. |
| Getting started | `setup_items` / `setup_done_count` / `setup_progress_percent` | Title `admin_misc.dashboard.setup.title`, progress `admin_misc.dashboard.setup.progress`, four checklist links (done = success check circle + muted label; undone = empty circle + primary label). Same hrefs as today. |
| Quick actions | `@actions` | Title `admin_misc.dashboard.quick_actions`. Four `QuickActionCardComponent` with **`compact: false`** (rail is gone; use the spacious variant). Keys: create_entity, new_page, enable_module, invite_user. Same icons as `ACTION_ICONS`. |

`admin_misc.dashboard.snapshot` may stay as an `sr-only` heading on the metrics region if useful for a11y; it is no longer a visible rail title.

#### Empty / loading / error

- **Empty:** not a blank page. Zero counts still render (`0` on metric cards, 0/4 progress, all checklist items undone). No Home-level empty illustration.
- **Loading:** server-rendered on first paint. No skeleton, no new Stimulus.
- **Error / denied:** existing admin auth (anonymous and `member` denied). Cross-tenant admin cannot open another customer’s Home. No Home-specific flash.
- **Do not render** on Home: composer, `SpeechToText::AssistantPanelComponent`, `SpeechToText::ArtifactPaneComponent`, offline assistant empty state, `data-dashboard-region="chat"`.

#### Actions

| Kind | Action | Placement |
|---|---|---|
| Primary (per card) | Navigate to metric href / setup href / quick-action path | The card or checklist row itself |
| Secondary | None at page level | — |
| Destructive | None | — |

No page-level CTA. The offline “Open modules” button **moves to Assistant**, not Home.

---

### Surface B — AI Assistant

**Component (new):** `Admin::Assistant::WorkspaceComponent`. Owns the edge canvas and the available / unavailable branch. Sets `content_for(:container_width, "edge")`.

**Controller:** `Admin::AssistantsController#show` (plural). `dashboard_menu_item :assistant`. Loads the current user’s conversation the same way Home does today (`assistant_available?` = Speech-to-text enabled **and** a generation provider configured).

Cookie composer POSTs stay on `Admin::Modules::SpeechToText::MessagesController`; that controller’s menu item becomes `:assistant`.

#### ASCII — available, desktop (`lg+`)

```
<main, edge, h-full, bg-canvas>
+-------------------------------------------+----------------------+
| [chat] flex-[2]                           | [overview] flex-1    |
| rounded-2xl border bg-surface             | rounded-2xl border   |
|                                           | bg-surface           |
| AssistantPanel header                     | ArtifactPane         |
| (icon + title + what)                     | Preview [kind badge] |
|                                           | label / iframe / Open|
| thread (greeting + prompts if empty,      | or empty caption     |
|  else MessageComponents)                  |                      |
|                                           | (artifact only — no  |
| composer (dictate + attach + send)        |  Home stats/setup)   |
| copy / regenerate / continue              |                      |
+-------------------------------------------+----------------------+
outer: flex h-full min-h-0 flex-col gap-3 overflow-y-auto
       bg-canvas p-3 lg:flex-row lg:overflow-hidden
```

Keep `data-dashboard-region="chat"` on the chat section and `data-dashboard-region="overview"` on the artifact aside so Turbo streams and Playwright locators stay valid.

Chat `aria-label`: `speech_to_text.assistant.title`.
Artifact `aria-label`: `speech_to_text.assistant.artifact.title` (do **not** reuse `admin_misc.dashboard.snapshot` — that label was for the Home rail).

#### ASCII — available, mobile

```
<main, edge>
| chat section  min-h-[70dvh]  (panel fills it) |
| artifact aside  full width below              |
stack: flex-col; same p-3 gap-3 rounded-2xl panes
```

#### ASCII — unavailable (module off or no generation provider)

Full-canvas empty, **one** pane (no artifact rail):

```
<main, edge>
+--------------------------------------------------+
|                  (centered)                      |
|              [accent chat icon]                  |
|              AI Assistant                        |
|  Enable Speech to text and configure a           |
|  provider to chat with the AI Assistant.         |
|              [ Open modules ]                    |
+--------------------------------------------------+
```

Reuse today’s offline markup tokens (`flex min-h-0 flex-1 flex-col items-center justify-center gap-5 px-6 py-16 text-center`, size-14 accent icon well, `text-3xl font-semibold` title). Title: `speech_to_text.assistant.title`. Body + CTA move off `admin_misc.dashboard.assistant_offline.*` onto `speech_to_text.assistant.offline.*` and drop “from this dashboard”:

| Key | en | zh-CN |
|---|---|---|
| `speech_to_text.assistant.offline.body` | `Enable Speech to text and configure a provider to chat with the AI Assistant.` | `启用语音转文字并配置服务商后，即可与 AI 助手对话。` |
| `speech_to_text.assistant.offline.cta` | `Open modules` | `打开模块` |

CTA is `ButtonComponent` `variant: :primary` `tag: :a` → `admin_maintenance_modules_path(customer.id)`.

On mobile the empty state still fills the edge canvas (`min-h-[70dvh]` on the single section so it does not collapse).

#### Empty / loading / error

- **Available + no messages:** `SpeechToText::AssistantPanelComponent` empty (greeting, how, try-prompt grid, optional recent chips). Unchanged.
- **Available + artifact unresolved:** `SpeechToText::ArtifactPaneComponent` empty caption. Unchanged.
- **Unavailable:** offline empty above. No composer, no artifact pane.
- **Loading:** first paint is server HTML. Streaming stays on existing Turbo + `speech-to-text-assistant` controller. No new Stimulus.
- **Vendor-down / reply failed:** existing panel copy (`speech_to_text.assistant.reply_failed`, status “Working…”, stop). Do not redesign.
- **Denied:** anonymous and `member` denied the same as other admin pages. Cross-tenant admin cannot open another customer’s Assistant; owner can and sees only that customer’s conversation.

#### Actions

| Kind | Action | Placement |
|---|---|---|
| Primary | Send / dictate / attach (existing panel) | Composer footer |
| Primary (offline) | Open modules | Centered CTA |
| Secondary | Copy, regenerate, continue last, Open artifact | Panel footer / artifact pane |
| Destructive | None at page level (stop generation is secondary/stop control, already in panel) | — |

No new chat capabilities. Desktop PKCE APIs unchanged (`/admin/assistant/messages`, `/admin/assistant/transcriptions`).

---

## 3. Interaction flow

### US-1 — Admin opens Home after the split

1. Start: sign-in / MFA / ticket fallback → `GET /:cid/admin/dashboard`.
2. Top nav **Home** is `aria-current="page"`. No sidebar. Main is padded.
3. User sees welcome, four metrics, getting started, quick actions.
4. Outcome: no composer, no artifact, no offline assistant empty state.
5. Click a metric / checklist / quick action → existing destination URL (unchanged).

Failure: unauthenticated or `member` → existing admin deny. Wrong tenant → deny (owner excepted).

### US-2 — Admin opens AI Assistant from the new top-nav item

1. Start: any admin page.
2. Click **AI Assistant** in the menu bar (or mobile drawer).
3. Navigate to `GET /:cid/admin/assistant`. Menu highlight moves to `:assistant`. Home highlight clears.
4. If available: chat + artifact (prior messages for this user/customer render here, not on Home).
5. If unavailable: offline empty + Open modules.

Failure: same auth/tenant rules as Home.

### US-3 — Admin chats (available)

1. Start: `GET /:cid/admin/assistant` with Speech-to-text on and generation provider configured.
2. Type or dictate → Enter / Send. Optional attach images. Optional prompt chip.
3. Outcome: existing stream into the thread; artifact pane updates when a record is applied.
4. URL stays `/admin/assistant`. Composer POST still hits Speech-to-text messages controller; Turbo streams still target `data-dashboard-region="chat"` / artifact ids.

Failure (vendor-down / invalid extract): existing in-thread error copy. User can retry. No redirect to Home.

### US-4 — Admin reaches Assistant from Modules / Speech to text

1. Start: Modules catalog or Speech-to-text entry.
2. Follow module `entry_path` → `GET /:cid/admin/assistant` (no longer `/admin/dashboard`).
3. Same available / unavailable branch as US-2.

### US-5 — Admin enables the module from the offline empty state

1. Start: Assistant unavailable empty.
2. Click **Open modules** → `GET /:cid/admin/maintenance/modules`.
3. Enable Speech to text and configure a generation provider (existing Maintenance flow).
4. Return via top nav **AI Assistant** → now available workspace.

Do not auto-redirect Home ↔ Assistant after enable.

### US-6 — Permission denied

1. Anonymous or `member` requests `GET /:cid/admin/assistant` (or Home).
2. Existing `RouteAuthorization` deny. No menu item for members (registry unchanged: no extra `permitted_by`; members never get the admin menu).

---

## 4. Component reuse map

| Piece | Reuse | Notes |
|---|---|---|
| App chrome | `ShellComponent`, `MenuBarComponent`, `TopbarComponent`, `DrawerComponent` | Insert `:assistant` after `:home` in `MenuRegistry::ITEMS` and `SidebarNode::MENU_ITEMS`. `show_sidebar?` false for `:home` **and** `:assistant`. |
| Home page | `Admin::Dashboard::WorkspaceComponent` (existing, slimmed) | Drop assistant props and edge width. |
| Home header | `LandingHeaderComponent` → `BadgeComponent` | Prefer this over re-implementing the compact rail header. |
| Home metrics | Inline link cards (same as today’s metric markup, scaled) | Optional wrap: none required. Do **not** invent a React/shadcn card. |
| Home getting started | Existing checklist markup, moved into a `CardComponent` (`variant: :default`, `padding: :md`) | Progress bar + list stay in the workspace ERB. |
| Home quick actions | `QuickActionCardComponent` `compact: false`, wrapped in `CardComponent` (`padding: :none` so cards own their hover rows) | Section title `text-sm font-semibold` in a `card-header`-equivalent `px-6 py-4` strip. |
| Assistant page | **New** `Admin::Assistant::WorkspaceComponent` | Only new ViewComponent. Props: `customer:`, `user:`, `assistant_available:`, `assistant_messages:`, `assistant_conversation:`. |
| Assistant chat | `SpeechToText::AssistantPanelComponent` | Unchanged API: `messages:`, `customer_id:`, `user_id:`, `user_name:`. |
| Assistant artifact | `SpeechToText::ArtifactPaneComponent` | Unchanged API: `conversation:`, `customer:`. Render **only** when available. |
| Offline CTA | `ButtonComponent` | `variant: :primary`, `tag: :a`. |
| Artifact kind / Home customer | `BadgeComponent` | Already used inside ArtifactPane and LandingHeader. |

**Do not build:** new Stimulus controller, new JS framework, custom CSS, shadcn React blocks, `AdminPageComponent` chrome for these two pages, Settings/Maintenance Assistant screens.

Home view (`admin/dashboards/show`) stops passing assistant assigns. New view `admin/assistants/show` renders `Admin::Assistant::WorkspaceComponent`.

---

## 5. Tailwind & Stimulus notes

### Tailwind (match existing admin tokens — no new utilities)

**Home (padded page):**

- Page stack: `flex flex-col gap-6` (shell already provides `py-8 lg:py-10` + `:full` horizontal padding).
- Metrics grid: `grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4`.
- Metric card: `group flex flex-col gap-1 rounded-xl bg-surface px-4 py-4 no-underline ring-1 ring-border-subtle shadow-xs transition-base hover:bg-accent-subtle hover:ring-accent-muted` (today’s rail card, padded up from `px-3 py-2.5`).
- Metric label: `text-[11px] font-medium uppercase tracking-wider text-text-muted`.
- Metric value: `text-2xl font-semibold tabular-nums tracking-tight text-text-primary` (one step up from today’s `text-xl` now that cards have room).
- Metric sub-label: `text-[11px] text-text-muted`.
- Two-column body: `grid grid-cols-1 gap-6 lg:grid-cols-2 lg:items-start`.
- Columns: `CardComponent` (`.card` = surface + `border-border-subtle` + radius-xl + shadow-sm). Do not use `rounded-2xl` edge-canvas panes on Home.
- Checklist hover: `hover:bg-accent-subtle`; done mark `bg-success-subtle text-success`; undone circle `border-border-strong`.
- Progress track: `h-1.5 overflow-hidden rounded-full bg-surface-active`; fill `bg-accent`.

**Assistant (edge canvas — copy today’s workspace shell):**

- Root: `flex h-full min-h-0 flex-col gap-3 overflow-y-auto bg-canvas p-3 lg:flex-row lg:overflow-hidden`.
- Chat pane: `relative flex min-h-[70dvh] min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-border-subtle bg-surface shadow-xs lg:min-h-0 lg:flex-[2]`.
- Artifact pane: `flex w-full shrink-0 flex-col overflow-hidden rounded-2xl border border-border-subtle bg-surface shadow-xs lg:min-w-0 lg:flex-1 lg:overflow-y-auto`.
- Offline icon well: `flex size-14 items-center justify-center rounded-2xl bg-accent-subtle text-accent ring-1 ring-accent/15`.
- Title: `text-3xl font-semibold tracking-tight text-text-primary`.
- Body: `text-body-sm text-text-muted`.

Do not introduce custom CSS or a second design system.

### Stimulus

- **No new controller.**
- Assistant available: existing `speech-to-text-assistant` (and nested dictate / stream) mounted by `AssistantPanelComponent`.
- Menu highlight: existing `menu-bar` + `data-menu-item-key`.
- Shell drawer: existing `drawer`.
- Home: no JS.

### i18n (frontend must add; UX lock)

| Key | en | zh-CN |
|---|---|---|
| `chrome.menu_bar.items.assistant` | `AI Assistant` | `AI 助手` |
| `speech_to_text.assistant.offline.body` | `Enable Speech to text and configure a provider to chat with the AI Assistant.` | `启用语音转文字并配置服务商后，即可与 AI 助手对话。` |
| `speech_to_text.assistant.offline.cta` | `Open modules` | `打开模块` |

Delete `admin_misc.dashboard.assistant_offline.*` after the move (both locales). All other Home / panel / artifact strings stay.

### Responsive checklist

- Home: 2-col metrics on narrow, 4-col at `lg`; setup above actions on narrow, side-by-side at `lg`.
- Assistant: stack chat then artifact on narrow; 2/3 + 1/3 row at `lg`. Offline empty stays centered at all widths.
- Menu bar hidden below `md`; drawer lists the new item.

---

## Implementation notes for frontend (non-layout)

These are already locked in the design doc; listed so the ViewComponent work does not fight routing:

- Route `resource :assistant, only: :show, controller: "assistants"` **alongside** existing `namespace :assistant` PKCE APIs.
- `ApplicationController::MENU_ITEM_BY_PATH_PREFIX` `"/assistant" => :assistant`.
- Playwright flows that opened `/admin/dashboard` for the composer move to `/admin/assistant`.
