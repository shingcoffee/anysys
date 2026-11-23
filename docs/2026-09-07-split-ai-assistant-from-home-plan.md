# Split AI Assistant from admin Home — Implementation Plan

> Inline execution in the parent session (tightly coupled chrome: menu, routes, controllers, components). Do not commit unless the user asks.

**Goal:** Move the admin AI Assistant off Home onto `GET /:cid/admin/assistant` with a new top-nav item immediately after Home.

**Architecture:** New `Admin::AssistantsController#show` + `Admin::Assistants::WorkspaceComponent`. Slim `Admin::Dashboard::WorkspaceComponent` to stats/setup/quick actions. Insert `:assistant` in `MenuRegistry` and `SidebarNode::MENU_ITEMS`. PKCE `/admin/assistant/messages` stays.

**Tech Stack:** Rails 8.1.2, ViewComponent, Tailwind, existing Speech-to-text assistant panel.

## Global Constraints

- I18n en + zh-CN; English values byte-identical to otherwise hard-coded strings.
- Admin URL under `/:cid/admin/`; RouteAuthorization admin/owner only.
- No new Stimulus. No custom CSS. No git commit.
- Controller: `Admin::AssistantsController` (plural) — do not collide with `Admin::Assistant` PKCE module.
- Workspace: `Admin::Assistants::WorkspaceComponent` (plural path).

## File map

Create:
- `app/controllers/admin/assistants_controller.rb`
- `app/views/admin/assistants/show.html.erb`
- `app/components/admin/assistants/workspace_component.rb`
- `app/components/admin/assistants/workspace_component.html.erb`
- `spec/requests/admin/assistants_spec.rb`
- `spec/components/admin/assistants/workspace_component_spec.rb`

Modify: routes, dashboards controller/view/component, menu registry, sidebar node, shell, application_controller prefix map, locales, STT registration `entry_path`, dashboard/menu/shell/routing specs, Playwright assistant URLs.

## Tasks

1. Routing + AssistantsController + strip DashboardsController assistant assigns
2. MenuRegistry / SidebarNode / Shell show_sidebar? / i18n / path inference
3. Home workspace slim + LandingHeader; Assistant workspace (chat+artifact / offline)
4. STT module entry_path → `/admin/assistant`
5. Rewrite stale specs; add request/component coverage; update e2e paths

Verify: `bundle exec rspec` on touched specs. Browser: Home has no composer; Assistant menu opens chat.
