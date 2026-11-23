# Split AI Assistant from admin Home

Date: 2026-09-07

## Problem

Admin Home (`GET /:cid/admin/dashboard`) currently mixes the Gemini-style AI Assistant (chat, artifact pane, or Speech-to-text offline empty state) with dashboard snapshot stats, the getting-started checklist, and quick actions. Home does two jobs. The Assistant should live on its own top-level admin menu.

This is an admin-chrome relocation of an existing surface, not a new feature module.

## Decisions (locked)

- Approach: new `GET /:cid/admin/assistant` page + new top-nav item (not a dashboards-controller second action, not a mode flag on the current workspace).
- Top-nav order: **Home · AI Assistant · Entities · Pages · Modules · Settings · Maintenance**.
- Assistant URL: `/:cid/admin/assistant`.
- Left sidebar: omitted on Assistant, same as Home (chat needs the full canvas; Assistant has no sidebar tree).
- Post-login / MFA / registration / help-ticket fallbacks stay on Home (`admin_dashboard_path`).
- English menu label: **AI Assistant** (byte-identical to `speech_to_text.assistant.title`). zh-CN: **AI 助手** (same as that key).
- Controller class: `Admin::AssistantsController` (plural) so it does not collide with the existing `Admin::Assistant` PKCE namespace.

## Navigation and routing

Top admin bar is seven items. `MenuRegistry::ITEMS` inserts `:assistant` immediately after `:home`. `SidebarNode::MENU_ITEMS` gains `:assistant` in the same order.

| Menu | Path | Controller | `dashboard_menu_item` |
|------|------|------------|------------------------|
| Home | `GET /:cid/admin/dashboard` | `Admin::DashboardsController#show` | `:home` |
| AI Assistant | `GET /:cid/admin/assistant` | `Admin::AssistantsController#show` | `:assistant` |

Routes: add `resource :assistant, only: :show, controller: "assistants"` in the admin namespace **alongside** the existing `namespace :assistant` PKCE APIs (`/admin/assistant/messages`, `/admin/assistant/transcriptions`). The HTML show route must not replace those endpoints.

Cookie composer POSTs stay on `Admin::Modules::SpeechToText::MessagesController`; that controller switches from `dashboard_menu_item :home` to `:assistant`.

`ApplicationController::MENU_ITEM_BY_PATH_PREFIX` adds `"/assistant" => :assistant` so `/admin/assistant` and `/admin/assistant/messages` infer the Assistant tab.

Auth: the new page is under `/:cid/admin/`, so `RouteAuthorization` already requires admin or owner. Members and anonymous users are denied the same way as other admin pages. No extra `permitted_by` on the menu item (Home has none).

Speech-to-text module `entry_path` currently points at `/admin/dashboard` because that is where the assistant lived. Point it at `/admin/assistant` so Modules / Speech to text still opens the assistant. Default exit `customer_home` stays on the dashboard.

## Home after the split

`GET /:cid/admin/dashboard` remains Home.

**Remove** from Home: chat column, artifact pane, Speech-to-text offline empty state, and all assistant assigns (`@assistant_*`).

**Keep:** welcome header, customer badge, four metric cards (entities / pages / modules / users), getting-started checklist with progress, quick actions.

Layout: Home no longer needs the edge-to-edge chat canvas. Use the default padded dashboard main (`container_width` default, not `:edge`). `current_menu_item == :home` still omits the left sidebar.

Regions (desktop, stacked on mobile):

```
+--------------------------------------------------+
| Welcome back, {first_name}     [customer badge]  |
| {long date}                                      |
+--------------------------------------------------+
| [Entities] [Pages] [Modules] [Users]   (2×2 / 4) |
+------------------------+-------------------------+
| Getting started  n/4   | Quick actions           |
| progress bar           | Create entity           |
| checklist links        | New page                |
|                        | Enable module           |
|                        | Invite user             |
+------------------------+-------------------------+
```

Reuse existing `BadgeComponent`, metric link cards, setup list, and `QuickActionCardComponent` (non-compact now that the rail is gone). No new Stimulus controller.

## Assistant page

`GET /:cid/admin/assistant` is a dedicated workspace.

`Admin::AssistantsController#show` loads the current user's conversation the same way Home does today (`assistant_available?` = Speech-to-text module enabled for the customer **and** a generation provider configured).

Chrome: `dashboard_menu_item :assistant`, `content_for(:container_width, "edge")`. Update `ShellComponent#show_sidebar?` so `:assistant` also omits the sidebar (defense in depth with edge width).

When available: two-column layout — existing `SpeechToText::AssistantPanelComponent` (main, `flex-[2]`) + existing `SpeechToText::ArtifactPaneComponent` (rail, `flex-1`). Same `data-dashboard-region` attributes (`chat` / `overview`) so Turbo streams and e2e locators keep working.

When unavailable: full-canvas offline empty state (title `speech_to_text.assistant.title`, body + CTA). Move copy off `admin_misc.dashboard.assistant_offline.*` onto `speech_to_text.assistant.offline.*` and drop the “from this dashboard” wording:

- en body: `Enable Speech to text and configure a provider to chat with the AI Assistant.`
- en cta: `Open modules`
- zh-CN body: `启用语音转文字并配置服务商后，即可与 AI 助手对话。`
- zh-CN cta: `打开模块`

No new chat capabilities. Desktop PKCE APIs unchanged.

## Out of scope

- New feature-module surfaces (Settings / Maintenance toggle / Platform settings) for “Assistant”
- Member or public Assistant
- Changes to login/MFA/help-ticket redirects
- New conversations UI, models, tools, sharing
- Redesign of dashboard metrics or checklist content (only remove the assistant from that page)

## Testing

- Routing: `GET /:cid/admin/assistant` → `admin/assistants#show`; PKCE `/admin/assistant/messages` still routes as today.
- Request: admin 200 on Assistant and Home; Home body has stats/quick actions and does **not** include the composer or offline assistant empty state; Assistant body has the composer when configured and the offline empty state when not; prior messages render on Assistant, not Home.
- Auth: anonymous and member denied on `GET /:cid/admin/assistant`.
- Cross-tenant: admin of A cannot open B’s Assistant; owner can and sees only B’s conversation.
- MenuRegistry order includes `:assistant` after `:home`; i18n en/zh-CN present.
- SidebarNode accepts `:assistant`.
- Shell omits sidebar on `:assistant`.
- Speech-to-text `entry_path` is `/admin/assistant`.
- Playwright e2e that visit `/admin/dashboard` for the composer (`assistant_entity_create`, `speech_to_text_mic`) switch to `/admin/assistant`.
- Stale dashboard specs that expect the composer/offline empty state on Home are rewritten, not left failing.

## Success criteria

1. Admin top nav shows AI Assistant immediately after Home.
2. Home is dashboard-only.
3. `/admin/assistant` hosts chat + artifact (or the offline empty state).
4. Redirects still land on Home.
5. Existing assistant behavior (composer, streams, PKCE, per-user conversation) is unchanged aside from URL and menu highlight.
