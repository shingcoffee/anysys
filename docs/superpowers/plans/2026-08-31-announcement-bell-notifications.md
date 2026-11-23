# Announcement Bell Notifications Implementation Plan

> **For agentic workers:** Execute via the anysys SDLC subagents (backend / frontend / security in parallel after UX, then QA, then release-eng, then tech-lead + code-reviewer). Do not auto-commit.

**Goal:** When the platform owner publishes a live announcement, targeted tenant admins also receive it in the admin top-right bell, independent of the existing banner, with 7-day history after it leaves live and per-item click-to-read.

**Architecture:** Query-time inbox over `platform_announcements` (sibling of `PlatformAnnouncements::Resolver`). Persist only `platform_announcement_reads`. Soft-delete live/ended rows so history survives destroy. Banner and dismissals are unchanged.

**Tech Stack:** Rails 8.1.2, Trailblazer Activity, ViewComponent, Stimulus, Tailwind, RSpec.

## Global Constraints

- Roles: only `owner`, `admin`, `member`. Owner is `lingercoffee@gmail.com` under `81721200`.
- Bell and mark-read live under `/:cid/admin/` (RouteAuthorization already requires admin_or_owner). Do not add a duplicate `before_action`.
- I18n: en + zh-CN, no hard-coded UI strings. English value is byte-identical to the UI string.
- No `default_scope` on `deleted_at`. Use `.kept`.
- Banner cap stays 3. Bell lists all inbox candidates (limit 50).
- Do not auto-commit.

## Files

Create:
- `db/migrate/20260831120000_add_announcement_inbox.rb`
- `app/models/platform_announcement_read.rb`
- `app/services/platform_announcements/inbox_resolver.rb`
- `app/controllers/admin/platform_announcement_reads_controller.rb`
- `spec/models/platform_announcement_read_spec.rb`
- `spec/services/platform_announcements/inbox_resolver_spec.rb`
- `spec/requests/admin/platform_announcement_reads_spec.rb`
- `spec/routing/admin/platform_announcement_reads_routing_spec.rb`

Modify:
- `app/models/platform_announcement.rb` — `kept`, `deleted_at` in `live?`/`live`, `discard_or_destroy!`
- `app/services/platform_announcements/activities/save.rb` — stamp/clear `left_live_at`
- `app/controllers/admin/maintenance/platform/announcements_controller.rb` — `.kept` lookup, discard on destroy
- `config/routes.rb` — `resources :platform_announcement_reads, only: [:create]` next to dismissals
- `app/components/notifications_button_component.rb` + `.html.erb`
- `config/locales/chrome.en.yml` + `chrome.zh-CN.yml`
- Existing specs listed in the design spec (dismissal hard-destroy cascade, live?, Save)

## Task 1 — Backend (model + migration + Save + InboxResolver)

See design spec. Key APIs:

```
PlatformAnnouncement.kept
PlatformAnnouncement.live(now)           # kept + published + window
PlatformAnnouncement#discard_or_destroy!
PlatformAnnouncements::InboxResolver.for_customer(customer_id, now:)
PlatformAnnouncements::InboxResolver.for_viewer(user:, customer_id:, now:)
  # => InboxResolver::Result(announcements:, read_ids:)
PlatformAnnouncementRead.record!(announcement:, user_id:, customer_id:)
PlatformAnnouncementRead.announcement_ids_for(user_id:, customer_id:)
```

`HISTORY_RETENTION = 7.days`. Candidates = live OR `left_live_at > cutoff` OR published with `ends_at` in `(cutoff, now]`. Then same targeting as Resolver. Do not consult dismissals.

## Task 2 — Security (routes + controllers)

Mirror `Admin::PlatformAnnouncementDismissalsController`. Honour a posted id only if InboxResolver returns it for `Current.customer_id`. Turbo Stream replaces `notifications-badge` and `notifications-panel-body` inner targets (do not replace the Stimulus root). HTML `redirect_back`. Destroy of announcements calls `discard_or_destroy!`. Index/show/edit use `.kept`.

## Task 3 — Frontend (bell UI)

Fill `NotificationsButtonComponent`. Badge when unread > 0. List unread-first then newest. Click row = `button_to` POST mark-read (`form: { data: { turbo_stream: true } }`). Learn more reuses banner i18n, `target=_blank`, does not double-submit. Empty state unchanged when inbox empty. Tailwind only. Existing `notifications-menu` Stimulus stays a menu shell.

## Task 4 — QA

Request specs mirroring dismissals plus: banner dismiss does not create a read; mark-read does not create a dismissal; owner without acting-as does not see tenant C; owner acting as C does; 7-day history; independent unread per admin.

## Task 5 — Verify targeted specs, then smoke admin dashboard with a live announcement.
