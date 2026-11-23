# Get Help Redesign Implementation Plan

> **For agentic workers:** Execute inline in this session. Do not commit (AGENTS.md). User forbade confirmation gates.

**Goal:** Replace the admin Help menu with Notify owner (ticket + images), Email support (help@anysys.com), and Docs (https://docs.anysys.com), plus an owner queue and unified bell.

**Architecture:** Tenant-owned HelpRequest threads with ActiveStorage images; separate one-shot HelpMailer; Notifications::Inbox merges announcements + help rows.

**Tech Stack:** Rails 8.1.2, ViewComponent, Stimulus, Reform contracts, Activities, RSpec, Vitest, I18n en+zh-CN.

## Global Constraints

- No hard-coded user-facing strings; en and zh-CN in parity.
- Most models need customer_id (indexed). HelpRequest is tenant-owned.
- Admin URLs under /:cid/admin/; platform queue under /81721200/admin/maintenance/platform/.
- Auth at controller layer. Platform owner role only for lingercoffee@gmail.com / 81721200.
- Tailwind only, Stimulus only, ViewComponent for UI.
- Do not commit unless asked.

## File map

Create: migration, HelpRequest/Message/Read models, Help::Activities::{CreateRequest,AddMessage,Resolve,SendEmail}, Help::Contracts::{Request,Message,Email}, Help::AttachmentRules, Notifications::Inbox, HelpMailer + views, factories, tenant+platform controllers, HelpMenu + dialogs + thread components, help_menu + help_attachments Stimulus, locales, specs.

Modify: routes, ability, maintenance_contributor, topbar (pass user), notifications button/inbox/row, chrome + maint_platform locales, help_menu JS tests.

## Tasks

1. Migration + thin models + factories + model specs
2. Contracts + activities + mailer + specs
3. Notifications::Inbox + specs; extend bell components
4. Routes + controllers + routing/request specs
5. Help menu + dialogs + attachments Stimulus + Vitest 100%
6. Requester thread + owner queue UI + component specs
7. Locales en/zh-CN
8. Run targeted RSpec + Vitest; fix
