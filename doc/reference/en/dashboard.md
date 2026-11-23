---
title: "Dashboard"
summary: "The admin home assembles metrics, module cards, and the sidebar from the customer's enabled modules."
---

## Summary

The admin home is `GET /:customer_id/admin/dashboard`. It is an admin-or-owner page, not a platform-owner page. `Admin::DashboardsController#show` asks `Dashboard::Home` for one `Result`: counts, module cards, setup steps, recent pages, recent entities, and shortcut actions. The sidebar around that page is a different object. `SidebarContributor.registry` asks five contributors for nodes, and each contributor decides what the current user may see.

The member home is a separate controller, `Member::DashboardsController`, on `/:customer_id/member`. It is not this result object.

## Flow

```text
GET /:cid/admin/dashboard
        |
        v
RouteAuthorization  (admin or owner)
        |
        v
Admin::DashboardsController#show
        |
        v
Dashboard::Home.call(customer:)
        |
        +-- LandingStats.for(customer)
        +-- Dashboard::ModuleCards.call(customer:)
        |
        v
Result
  metrics | modules | setup_items | recent_pages | recent_entities | actions

Sidebar (every admin layout)
        |
        v
SidebarContributor.registry
  EntitiesContributor
  PagesContributor
  ModulesContributor
  SettingsContributor
  MaintenanceContributor   (platform leaves only for platform_owner? on 81721200)
```

## Implementation

`Dashboard::Home#call` loads `LandingStats` and `ModuleCards`, then builds the result in one place. Metrics link to the domains page (`/:cid/admin/domains`), the page index, maintenance modules, and authentication users. Labels are `I18n.t` keys under `admin_misc.dashboard`, not strings frozen in the result.

`Dashboard::ModuleCards` knows the seven feature modules. `SECTIONS` places each key in `:records`, `:communication`, or `:growth`. `KNOWN` holds the primary path, secondary paths, and settings path as lambdas of the customer id. A module that is not enabled for the customer is not offered as a card. The card's primary link is the entries surface; the settings path is the customer settings surface. That is the same split described on the [system map](system-map).

Shortcut actions (`create_entity`, `new_page`, `enable_module`, `invite_user`) are only included when that destination exists for this customer. Secondary shortcuts for email, payment, and SMS are listed in `SECONDARY_ACTIONS` and included when that module card exists.

Recent pages and entities are `Dashboard::RecentItem` values (`name`, `href`, `badge`, `updated_at`). `updated_at` is the record's own timestamp; `Admin::Dashboard::RecentListComponent` renders it as a relative "Updated … ago" line through `admin_misc.domains.directory.updated` and `chrome.admin_table.time_ago`, and omits the line when the value is nil.

### Layout

`Admin::Dashboard::WorkspaceComponent` lays the page out top to bottom:

1. **Header** — `LandingHeaderComponent` renders an elevated `rounded-2xl` surface banner with a soft accent glow, showing the customer name pill and calendar date above the welcome title, plus the `admin_misc.dashboard.subtitle` line. Its block content holds the header actions: `WorkspaceComponent::HEADER_ACTION_KEYS` (`new_page`, then `create_entity` as the primary button) are taken out of `actions` and rendered here.
2. **Stat cards** — one `rounded-2xl` link card per metric (`data-dashboard-metric="<key>"`), themed via `WorkspaceComponent::METRIC_THEMES` (top accent bar and semantic icon well), with label, delimited value (nil renders as 0), optional `sub_label` status indicator, and a footer showing `admin_misc.dashboard.stats.view`. Two columns on phones, four from `xl`.
3. **Main grid** — `data-dashboard-region="recents"` holds the two `RecentListComponent` cards (side by side at `md` and from `xl`, stacked at `lg`), each with a tinted header icon, count chip, and evenly distributed rows. Beside it from `lg`, `aside[data-dashboard-region="rail"]` holds Getting started (only while setup is incomplete) and Quick actions (the actions not promoted to the header, rendered via compact `QuickActionCardComponent` with semantic `ACTION_ICON_CLASSES`, two columns at `md`). The rail is omitted when it would be empty. Below `lg` it follows the recents.
4. **Enabled modules** — section icon, count badge, a View all link to `/:cid/admin/modules`, and compact `ModuleCardComponent` cards (one to four columns) with an active status dot. The default card variant renders the primary link as an accent pill (`data-module-link="primary"`) and secondaries as outlined pills (`data-module-link="secondary"`); the `:rich` hub variant is unchanged.

The page has no Stimulus controller.

### Shared admin page header

`AdminPageComponent` provides the shared breadcrumb/title/action shell. When it has a title and the view has not already set a document title, it copies that heading into `content_for :title` (tags stripped) so the browser tab matches the page. Pages without a title keep the dashboard layout fallback, Dashboard. Its optional `wrap_actions: true` keeps title and actions stacked below `lg`, then permits a wrapping row at `lg`. Actions occupy full width and stack on phones; from `sm` they use a wrapping row, and from `lg` the action container becomes auto-width. The default is `wrap_actions: false`. The entity entries browser opts into `wrap_title: true, wrap_actions: true`, with primary **Create Entry** before secondary **Export CSV** and `min-h-11 w-full sm:w-auto` action classes. Creation and row/drawer **Edit** target full-page `_top` navigation. The new and edit forms use the default full width with `wrap_title: true` and the entity icon tile, mirroring the admin page form (`/:cid/admin/pages/:page_id/form`): one `card` holding a centered `max-w-4xl` panel; see [Entity builder](entity-builder) for its schema and write boundary.

`SidebarContributor.registry` is an explicit array, not `descendants`. Order is entities, pages, modules, settings, maintenance. When the Maintenance section is used, `MaintenanceContributor#contribute` adds customer profile, constants, modules, entities, and pages. It adds flowcharts only when `FlowchartVisibility.allowed?`. It adds the Platform section only when `customer_id` is `81721200` and `current_user.platform_owner?`. The developer reference leaf is in that platform section.

`SettingsContributor` gives accepted generic module aliases exact `match_paths` on their canonical task leaf: `/modules/email` and `/modules/emails` select Email limit, `/modules/sms` selects Text message limit, `/modules/ai_assistants` selects AI assistant, and `/modules/authentications` selects Account security, all under `/:cid/admin/settings`. Canonical links keep their existing destinations. Exact aliases do not capture deeper pages: template tokens, roles and other specific settings retain their own single active item through the shared `SidebarNodeComponent.selected_key` matching used by every settings menu. The overview breadcrumb is the current unlinked Settings label; child pages link back to the settings overview, with one settings-page wrapper and one H1.

`SettingsContributor#decorate` appends these aliases to the contributed node's original `match_paths`; it preserves its permission key, canonical path and existing active-navigation matches. `#module_description(fm)` resolves `admin_settings.catalog.modules.<key>` at call time and supplies the already localized `admin_settings.catalog.modules.fallback` with `name: fm.display_name` as the default. Future modules therefore retain a useful localized description without a per-module translation. `spec/services/settings_contributor_spec.rb` covers fallback descriptions, future contributions/permission filtering and the exact single-active-leaf matrix; the paired navigation browser contract below remains in place.

The shared settings request spec checks the desktop full sidebar, mobile drawer and settings dialog as three **full task menus**. The collapsed icon rail also has the Settings accessible name, but its group buttons expand sections instead of duplicating every leaf link. The helper excludes only the rail's stable `[data-sidebar-collapsible-target="rail"]` wrapper; a separate assertion checks its SMS section control and active styling. Full-menu destination, deep-link, alias, future-module and authorization assertions remain in place.

### Customer settings browser verification

`spec/e2e/customer_settings_support.js` scopes the shell to `#main-content` and the settings H1 outside `[data-settings-page]`. Website preview cards can contain their own headings and nested `main` elements; they are not the settings header. Document/main overflow and visible control bounds remain checked, including after disclosures open. The navigation inventory preserves actual GET query inputs such as billing `plan_code` and sort direction; only `locale` is replaced by the English/Chinese matrix value. Visits wait for DOM content and fonts, and interactive checks wait for their actual mounted Stimulus controller. The native settings dialog checks modal state, background focus isolation, Escape/focus return and completed destination navigation.

The separate test-database exporter, `spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb`, renders authorized same-tenant admin responses through normal factories, validations and provisioners. It produces 24 JSON files: `role-edit`, `role-grants`, `token-edit`, `website-footer`, `invoice-list`, `invoice-detail`, `invoice-download`, `payment-providers`, `payment-sandbox`, `payment-production`, `public-protection`, and `user-access`, each in `en` and `zh-CN`. Run it through `node spec/e2e/helpers/bootstrap.js export` with a prepared, dedicated `storage/e2e*.sqlite3` test database; unset an inherited browser-only `RUBYOPT` preload first. The browser helper validates provenance and locale, serves `text/html; charset=utf-8`, and verifies `document.characterSet` is UTF-8. Exported tenant IDs resolve only to registered exported responses; all browser writes are intercepted at context level.

Scenarios follow the actual settings contract: reserved member grants remain locked while label/action/granted filters work; AI language and account security require explicit Save; email/SMS limits are platform-managed; personalization creation uses `email-template-token-bulk` and its translated count value. Populated payment fixtures make Stripe platform-available before provisioning both tenant modes, then exercise toggle rollback, saved-connection feedback, credential Save and environment navigation. Public-protection fixtures use a normally validated tenant-owned public Page. User access retains exactly one of the three reserved roles in the intercepted payload. See [Access grants](access-grants), [Payments](payments), [Captcha](captcha), and [Email](email).

On 2026-10-12 the exporter passed **14 examples, 0 failures** and all three customer-settings browser specs passed **64 cases, 0 failures, 0 skips**, using four workers. This includes the 36 previously failing settings variants. Evidence is in `docs/audits/2026-10-12-settings-browser-followup.md` and `/tmp/opencode/settings-followup.json`. The later parallel RSpec suite on 2026-10-12 passed **25,266 examples, 0 failures**; it does not replace the browser evidence above. `SETTINGS_BROWSER_ARTIFACTS` chooses a fresh screenshot/inventory directory without changing the export directory.

The shared top menu (`MenuRegistry`, `MenuBarComponent` and the mobile `DrawerComponent`) places **Users**, **Payments** and a **Communication** disclosure immediately after AI Assistant. Users opens `/:cid/admin/modules/authentication/users`; Payments opens `/:cid/admin/modules/payments/transactions`. Communication offers Email (`/:cid/admin/modules/emails/send_activities`) and SMS (`/:cid/admin/modules/sms/campaigns`). These are shortcuts to existing admin routes, not new routes or sidebar areas. The registry filters shortcuts by admin-or-owner role and the **URL customer's** available modules: authentication for Users, payment for Payments, and email and/or sms for Communication. An unavailable child is omitted and Communication disappears when neither child is available. On a matching module page the shortcut is highlighted instead of Modules; the module sidebar still uses its existing section. The left sidebar starts collapsed for every highlighted top-menu item except Modules, Communication, Entities, Settings, and Maintenance, which start expanded. Expanding or collapsing is remembered for the browser session, separately for each top-menu item. The desktop disclosure uses the shared positioned-menu controller so the dropdown stays visible inside the horizontally scrolling top bar, and the mobile drawer exposes the same permitted links.

`spec/e2e/top_navigation.app.spec.js` checks English/Chinese desktop menus at 768/1440px and the mobile drawer at 390px. It finishes initial importmap loading, waits for the actual `menu-placement` controller and fonts, and verifies fixed positioning and viewport/trigger bounds before clicking Communication → Email. The click must produce a completed same-origin GET with status 200, reach the real destination URL, finish Turbo loading/preview rendering and select the expected menu item. The 90-second journey budget covers shared-server startup; geometry and active-link assertions remain required. See [customer documentation](customer-documentation) for the paired reader checks.

The top-level **Content** disclosure offers **Forms** (`/:cid/admin/pages`) and, when Website is enabled for the URL customer, **Website Pages** (`/:cid/admin/modules/website`). The Forms list displays **All Forms**, calls each row a **Form**, and uses form wording in its sidebar, search, and empty states. Website list and editor actions still live under the module namespace; their URLs activate Content → Website Pages in the desktop menu and mobile drawer, while the module sidebar remains the record navigation. The Forms sidebar contains only form records. The internal Content menu key remains `:pages`. The desktop menu and mobile drawer show the translated Content label. Collapsing the left sidebar keeps that name as the icon rail's accessible name; each destination stays an icon with its label in a tooltip, and a group icon expands the full sidebar with that group open.

The Forms and Entities sidebars use the same searchable layout as Modules and Settings (`SidebarComponent::SEARCHABLE_MENU_ITEMS`, `SidebarNodeComponent::SOFT_MENU_ITEMS`). A **Search Forms…** / **Search Entities…** field filters rows on the client through the `list-filter` controller. A parent entity stays visible when one of its children matches, and its group opens while the query is active. When nothing matches, the menu-specific `chrome.sidebar.search_empty_titles.*` message is shown. Unlike Settings and Modules, these two sidebars still appear at the `md` breakpoint. `PagesContributor` puts the cross-entity views (**All Forms**, then **Uncategorized** when orphan forms exist, which has its own tray icon) first, followed by the entities under a **By entity** heading (a `section_root` `SidebarNode`; the collapsed rail shows a divider instead). `EntitiesContributor` lists only domains under a **Business areas** heading, with no overview link: one node per domain, tinted with its colour, linking to `/:cid/admin/domains/:key` and holding its entities, with ungrouped entities under **Other**, or the entities flat under **Record types** when the customer has no domains. A group with children opens when it or one of its children is the selected row (`SidebarNodeComponent#open?`), so only the shown domain (the first one on `/:cid/admin/domains`) is expanded. A nested row shows a small tile only when it carries a `tone`, so Settings and Modules sub-menus stay text-only; `SidebarTone` resolves `domain.<color>` and `entity.<color>` tones, and any other tone falls back to `module_color_classes`. A tile without an icon shows the node's `monogram`. The menu itself is labelled **Domains**. Numeric badges appear as a quiet trailing count: dimmed at zero, accent on the selected row. Text badges stay pills. Record names truncate on one line, with the full name in the `title` tooltip. On a searchable menu, the collapsed icon rail adds a search control (`sidebar-collapsible#expandSearch`) that expands the full sidebar and focuses its search field.

Collapse / expand: the `sidebar-collapsible` controller only flips `data-state` (`expanded` / `collapsed`) on the wrapper. Its width animates over 200ms between the icon rail (4.25rem) and the sidebar's breakpoint widths (`SidebarComponent.expanded_shell_classes`), and the two panels crossfade (honouring `prefers-reduced-motion`). The hidden panel is `inert`. Triggers: the header buttons and ⌘B / Ctrl+B (ignored while typing in inputs, textareas or rich-text editors). The buttons show double chevrons (`SidebarToggleIconComponent`) pointing the way the sidebar will move: « collapses the open sidebar and » expands the icon rail. The sidebar border is not clickable or draggable, so the sidebar never collapses by accident. Button tooltips show the shortcut (`chrome.sidebar.shortcut`). When the focused panel hides, focus moves to the toggle in the panel that appears. The state is stored per top-menu item in the session cookie `sidebar_state_<menu key>`, so the server renders it directly and full page loads never flash; the controller re-reads the cookie on connect to stay in sync with Turbo snapshots. The mobile drawer renders the same searchable `SidebarComponent` for Forms and Entities.

The dashboard chrome uses a logo-only top-left link without a tile, border, wordmark, or customer name, centered search on large screens, and compact actions at smaller widths. The desktop menu (`nav[data-menu-bar]`) is a white tab bar beneath the topbar: each destination is an icon-led tab with a soft hover background, and the active one gets primary text, an accent icon and an accent underline. Grouped destinations (Communication, Content) open a positioned panel where each child shows an icon tile, its label and a one-line description from `chrome.menu_bar.descriptions` (set through `MenuItem#description_key`). Primary destinations scroll horizontally when they do not fit, with a right-edge fade below `xl` to show more items are available. Settings and the owner-only Maintenance link stay pinned on the right after a divider (`[data-menu-bar-utility]`); below `xl` they show only their icons, with the label kept as a tooltip and screen-reader text. On phones, the same menu items appear in an icon-led drawer with expandable groups and direct links to each section's landing page. Labels come from `chrome` in both locales.

`Branding::SapphireLogoComponent` renders the shared faceted Sapphire mark in the violet family of the platform site's primary action (`#7f22fe`), preserving the original paths and per-render gradient IDs. The topbar and mobile drawer show the bare mark without accompanying wording; the topbar link keeps a translated accessible dashboard name. The public/auth shell uses the same mark and the `chrome.topbar.brand_name` translation for its accessible name; `/icon.svg` and `/icon.png` carry the matching violet browser and touch icons. The platform marketing site for customer `81721200` uses the same mark in its header and footer, hidden from the accessibility tree because the saved site name is already visible text.

`MenuRegistry` offers **Maintenance** in the desktop menu and mobile drawer only when `current_user.platform_owner?` is true (including when the owner is viewing another customer's dashboard). Customer admins, including admins of customer `81721200`, never see this menu entry. This is navigation visibility: tenant maintenance URLs and their existing authorization rules are unchanged; see [Tenancy and roles](tenancy-and-roles).

The chrome's `HelpMenuComponent` offers **Documentation** when the user is an admin or owner and a customer id is present. It opens `admin_help_docs_path(customer_id)` (`/:cid/admin/help/docs`) within the app, with translated customer-guide wording under `chrome.help_menu.docs`. The customer reader uses the dashboard shell, centralized role and tenant authorization, and `private, no-store` HTML responses. This Help entry serves operational guides; the developer reference leaf stays in the owner-only Platform section. See [customer documentation](customer-documentation) and [support tickets](support-tickets).

## Where to pay attention

`spec/system/search_palette_spec.rb` scopes interactions to the visible responsive `inline-search` instance. Opening waits positively for the visible input beneath an expanded panel; Capybara's bounded synchronization retries the click only while that instance's trigger remains visible. A hidden-panel absence check alone is insufficient because Capybara normally excludes hidden elements. The real-browser checks retain live result navigation and Escape collapse, without fixed sleeps or a missing-browser skip.

### Route audit: navigation and Forms operations

`EntityAssociationGraph` retains cyclic relationships and adds roots for otherwise unreachable components; `EntitiesContributor` stops revisiting ancestors. Legacy cycles therefore do not exhaust the stack or hide the entire component. Controller tenant/module guards still decide access independently of menu visibility.

Forms batches at `PATCH /:cid/admin/pages/batch` allow activate/deactivate/launch/take_offline only, validate ID shape, select unique matched owned rows and transact validated lifecycle calls. Reactivation includes inactive rows and revalidates a previously launched form. One failure rolls back the selection; JSON is 422, HTML an alert, success counts actual unique matches. Shared globals are not batch-mutated.

`uncategorized.html` selects the uncategorized branch. Every Forms index selection and sidebar count uses `Admin::Pages::BrowseScope.call(customer_id:, entity_id: nil, uncategorized: false)`. Lists/badges share effective customer override bindings and stale/bridge/headless classification; another tenant independently retains its global fallback. See [Entity builder](entity-builder), [Page rendering](page-rendering), [Shared resources](shared-resources).

:::note
Graph/sidebar, effective list/count and page-batch APIs are source-documented. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**, and the configured Vitest coverage run passed **6,956 tests** at 100% lines and branches. Rendered mobile and locale checks of this reader remain a separate browser run.
:::

:::attention
`SidebarContributor.registry` is hand-written. A new contributor that is not appended there never runs, even if the class exists. Platform-only leaves belong inside the `platform_owner?` branch of `MaintenanceContributor`, not in a contributor that every tenant admin receives.
:::

:::attention
`Dashboard::ModuleCards::KNOWN` paths are the real entry URLs. Adding a module registration without a `KNOWN` entry means the module can be enabled and still be missing from the home cards. The path lambdas must stay on the four module surfaces; do not point a card at `/admin/maintenance/platform`.
:::

:::attention
Home metrics and card labels are translated at call time through `I18n.t`. Do not store an already-translated string on a constant. `METRIC_ICONS` and `ACTION_ICONS` are SVG paths, not user-facing copy.
:::

## Key code

```ruby
# app/controllers/admin/dashboards_controller.rb
def show
  @home = ::Dashboard::Home.call(customer: current_customer)
end
```

```ruby
# app/services/dashboard/home.rb
def call
  stats = LandingStats.for(@customer).to_h
  modules = ModuleCards.call(customer: @customer)
  Result.new(
    metrics: metrics(stats),
    modules: modules,
    setup_items: setup_items(stats),
    recent_pages: recent_pages,
    recent_entities: recent_entities,
    actions: actions(modules)
  )
end
```

```ruby
# app/services/sidebar_contributor.rb
def self.registry
  [
    EntitiesContributor,
    PagesContributor,
    ModulesContributor,
    SettingsContributor,
    MaintenanceContributor
  ]
end
```
