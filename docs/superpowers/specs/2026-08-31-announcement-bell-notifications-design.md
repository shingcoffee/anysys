# Platform announcement bell notifications — design

Date: 2026-08-31

## Problem

The platform owner already publishes time-bounded notices from `/81721200/admin/maintenance/platform/announcements`. Targeted tenant admins only see those notices as a dismissible top banner. The admin top-right bell (`NotificationsButtonComponent`) is still an empty stub. If an admin misses or dismisses the banner, there is no second place to find the same notice.

Publishing must also land the notice in that bell for the **target customer**, without changing banner, CRUD fields, or member chrome.

This is chrome for the existing announcements feature, not a new four-area module, and not a general-purpose notification product.

## Locked decisions

| Topic | Decision |
|---|---|
| Approach | Query-time inbox over `platform_announcements` (same targeting as the banner). Persist only **read receipts**. No fan-out table, no generic `notifications` product. |
| Banner vs bell | **Independent channels.** Dismissing the banner does not mark the bell read. Marking the bell read does not hide the banner. |
| History | After an announcement leaves the live window (ended, unpublished, or deleted), keep it in the bell for **7 days**, then drop it. |
| Acknowledge | Clicking one bell row marks **that** `(user, customer, announcement)` read. Opening the panel does not mark all read. No separate “Mark as read” control. |
| Who sees it | Same as the banner: tenant `admin`, and the platform `owner` when acting as that tenant. Members never. Resolution is always `Current.customer_id` (URL tenant). |
| Live window | Same as the banner: `status = published` and `starts_at` null/`<= now` and `ends_at` null/`> now`. Draft and future `starts_at` do not appear. When `starts_at` arrives, both banner and bell show it without a re-save. |
| Targeting | Same as the banner: `audience: all` (includes tenants created later) or `audience: selected` + `target_rules`. Empty/unusable selected rules match nobody. |
| Edit / republish | Same announcement id is one inbox item. Editing a live row updates title/body/link/severity in place. Republishing the same row does **not** reset read receipts (owner who wants a fresh unread creates a new announcement). |
| Banner cap | Banner stays capped at 3 strips. The bell lists every inbox candidate for this customer (resolver candidate cap 50, newest-first). |
| Transport | Next admin page load (or Turbo Stream after mark-read). No Action Cable. |
| Empty state | Existing `chrome.notifications.caught_up_html` / `empty` copy when the 7-day inbox set is **empty**. Read history still lists in the panel until it ages out. |

## Architecture

```
PlatformAnnouncements::Activities::Save
  └─ on live → not-live: stamp left_live_at
  └─ on not-live → live: clear left_live_at

AnnouncementsController#destroy
  └─ if the row was ever inbox-relevant: discarded (deleted_at + left_live_at)
  └─ else: hard destroy (never-published draft)

PlatformAnnouncements::InboxResolver
  └─ live targeted ∪ left-live within 7 days and targeted
  └─ same CustomerQuery targeting as PlatformAnnouncements::Resolver
  └─ does NOT consult platform_announcement_dismissals

PlatformAnnouncementRead.record!(announcement:, user_id:, customer_id:)
  └─ independent of PlatformAnnouncementDismissal

NotificationsButtonComponent (admin TopbarComponent)
  └─ badge = unread count for Current.user + Current.customer
  └─ list = InboxResolver items; click → POST reads
```

The banner keeps using `PlatformAnnouncements::Resolver` (live, minus dismissals, cap 3). The bell uses a sibling `InboxResolver` so the two channels cannot leak state.

## Data model

### `platform_announcements` (additions)

| Column | Type | Notes |
|---|---|---|
| `left_live_at` | datetime, nullable | Set when a **live** row first leaves the live window via save (unpublish, or window moved to the past/future). Cleared when the row becomes live again. `NULL` for drafts and scheduled-never-live rows. Ended-by-`ends_at` with no subsequent save may leave this null; the inbox query also treats `ends_at` as the left-live instant. |
| `deleted_at` | datetime, nullable | Soft-delete. CRUD and the banner ignore discarded rows. The inbox includes them for 7 days after `left_live_at`. |

No `customer_id` on announcements (unchanged: platform catalog).

Do **not** add a `default_scope` for `deleted_at`. Banner `live` / CRUD index use an explicit `.kept` scope (`WHERE deleted_at IS NULL`). Inbox queries include discarded rows on purpose.

### `platform_announcement_reads`

Mirrors dismissals, but is a separate table so the two channels stay independent.

| Column | Type | Notes |
|---|---|---|
| `platform_announcement_id` | FK, not null, on delete cascade | |
| `user_id` | bigint, not null, FK → `users`, on delete cascade | `Authentication::User` |
| `customer_id` | integer, not null, FK → `customers`, on delete cascade | URL tenant the read happened in |
| `created_at` | datetime, not null | No `updated_at`: a read is an event |

Unique `(user_id, customer_id, platform_announcement_id)` so `record!` is idempotent under double-click / two tabs.

Owner acting as several tenants acknowledges each tenant separately (same reason as dismissals).

### Destroy vs discard

`AnnouncementsController#destroy`:

- If the row is live, ended, or already has `left_live_at` (it is or was inbox-visible): set `deleted_at = now` and `left_live_at ||= (ends_at if ended else now)`. Do not hard-delete. Owner index/show/edit no longer find it (`.kept`). Deleting an already-ended notice does not restart the 7-day clock.
- Otherwise (draft or scheduled that never went live): `destroy!` as today.

No purge job in this slice. Discarded rows are few (platform catalog) and drop out of the inbox after 7 days by query.

### Save stamps

`PlatformAnnouncements::Activities::Save` after a successful persist:

- If the record **is live now**: `left_live_at = nil` (republish / window moved back).
- If the record **was live before assign** and **is not live now**, and `left_live_at` is nil: `left_live_at = Time.current`.

Scheduled → draft does **not** stamp `left_live_at`. Ended-by-clock without a save is handled at query time via `ends_at`.

## Inbox resolution

`PlatformAnnouncements::InboxResolver`

Constants:

- `CANDIDATE_LIMIT = 50` (same bound as the banner resolver)
- `HISTORY_RETENTION = 7.days`

An announcement is an inbox candidate at `now` when **either**:

1. **Live:** `deleted_at` nil, `status = published`, in window; or
2. **History:** not live, and `COALESCE(left_live_at, ends_at) > now - 7.days` (ended, unpublished-from-live, or discarded). Rows that were never live have both timestamps nil and are excluded.

Then the same targeting filter as `Resolver`: `audience: all` always matches; `selected` uses `CustomerQuery.matching_keys` in **one** extra query.

API:

```
PlatformAnnouncements::InboxResolver.for_customer(customer_id, now:)
PlatformAnnouncements::InboxResolver.for_viewer(user:, customer_id:, now:)
  # returns { announcements:, read_ids: }
```

`for_viewer` loads `PlatformAnnouncementRead.announcement_ids_for(user_id:, customer_id:)` in one query. It does **not** load or filter dismissals.

Query budget on an all-customers-only page: 2 (candidates + reads). Segmented candidates add one `matching_keys` query. Specs must assert the count does not grow with the number of segmented announcements.

Unread count = inbox announcements whose ids are not in `read_ids`.

## URLs & auth

### Mark read (tenant admin URL — not platform namespace)

`POST /:customer_id/admin/platform_announcement_reads` → `Admin::PlatformAnnouncementReadsController#create`

Same placement as dismissals: tenant admins cannot reach `/admin/maintenance/platform/`, so this lives under the plain admin prefix where `RouteAuthorization` already requires `admin_or_owner?`.

A posted id is only honoured when `InboxResolver` currently returns it for `Current.customer_id`. A forged id for another tenant’s notice, a draft, or an aged-out row writes nothing.

Responses:

- `turbo_stream` — replace two inner targets only (`notifications-badge` and `notifications-panel-body`) so the open dropdown is not torn down. Do not replace the Stimulus root.
- `html` — `redirect_back` to the admin dashboard, same fallback as dismissals.

Members, anonymous users, and cross-tenant forged ids cannot list or write reads. There is no member or public bell.

Owner on `/81721200/admin/...` without acting-as: inbox resolves against customer `81721200` only. A notice targeted at tenant C does not appear until the owner acts as C (same as the banner).

## Bell UI

Mount: existing `NotificationsButtonComponent` in `TopbarComponent` (admin chrome only). Member shell is unchanged.

`PlatformAnnouncement.live` and `#live?` must treat `deleted_at` as not live (banner and CRUD never see discarded rows). Inbox history queries discarded rows explicitly.

Gate rendering of items the same way as the banner: `viewer.admin? || viewer.platform_owner?`. Other viewers keep today’s empty stub (they never hit this layout in practice).

### Trigger

- Existing bell icon button, `aria-label` from `chrome.notifications.title`.
- When unread count > 0, show a numeric badge on the icon (`data-badge-count`). Do not show a badge for 0. `aria-label` becomes the titled unread form (`chrome.notifications.unread_titled`).
- Badge styling: small filled danger/primary pill, top-right of the icon, consistent with existing `icon-button` chrome. Tailwind only.

### Panel

- Header: existing `chrome.notifications.title`.
- **Empty** (zero inbox items): keep today’s caught-up illustration + `caught_up_html` / `empty`.
- **List:** every inbox item for this customer, sorted **unread first**, then newest-first (`created_at` desc, `id` desc). No severity reorder (unlike the banner). No cap of 3.
- Each row:
  - Unread: a leading status dot and default title weight. Read: muted text, no dot.
  - Title (announcement `title`).
  - Body via `announcement.body_for(I18n.locale)` (same `zh*` rule as the banner), truncated to ~3 lines in the dropdown.
  - Optional “Learn more” when `link_url` is present — reuse `comp_platform.announcement_banner.learn_more`, `target=_blank rel="noopener noreferrer"`. Clicking Learn more also marks the row read (the row click handler fires, or the link POSTs then navigates).
  - The row itself is the hit target: click → POST mark-read for that id. Nested Learn more must not double-submit (one POST).
- Dropdown chrome stays the existing Stimulus `notifications-menu` (toggle, outside click, Escape, peer topbar menu). Width may grow from `w-80` to `w-96` so body text is readable on desktop; on small viewports the panel is `max-w-[calc(100vw-2rem)]` and still right-aligned.

### Independence from the banner

Banner dismissals continue to write only `platform_announcement_dismissals`. Bell reads write only `platform_announcement_reads`. Neither query reads the other table.

## I18n

| Key | English (byte-identical to the UI string) | zh-CN |
|---|---|---|
| `chrome.notifications.title` | Notifications (existing) | 通知 (existing) |
| `chrome.notifications.caught_up_html` | You're all caught up (existing) | 您已查看全部内容 (existing) |
| `chrome.notifications.empty` | No new notifications right now. (existing) | 暂无新通知 (existing) |
| `chrome.notifications.unread_titled` | Notifications, %{count} unread | 通知，%{count} 条未读 |
| `chrome.notifications.mark_read` | Mark as read | 标为已读 |

Announcement title and bodies are data, not I18n keys. Learn more reuses `comp_platform.announcement_banner.learn_more`. No new keys in one locale without the other.

Stimulus: no literal UI strings. Any new copy on `notifications-menu` is an English `default:` Value plus `data-notifications-menu-*-value` from `t()`. Prefer server-rendered Turbo for mark-read so the controller stays a menu shell.

## Testing

- Model: `kept` vs discarded; `live?` false when `deleted_at` present; `left_live_at` stamp on unpublish-from-live and clear on republish; scheduled unpublish does not stamp; destroy of never-live hard-deletes; destroy of live/ended/history discards.
- InboxResolver: live targeted items; future `starts_at` excluded until the clock passes; ended within 7 days included, older excluded; unpublished-from-live included for 7 days; discarded included for 7 days; `audience: all` includes a tenant created after publish; `selected` non-match excluded; does not honour banner dismissals; query budget does not grow with segment count.
- Read model: `record!` idempotent; `announcement_ids_for` scoped by `(user, customer)`; two admins of the same customer independent; owner acting-as is per URL customer.
- Component: empty state when inbox empty; badge absent at 0 and present with count; unread-first ordering; Learn more when `link_url` present; truncated body uses locale; member/non-admin `render?` of items.
- Request: `POST` reads as tenant admin succeeds; member/anonymous denied; forged id for another customer writes nothing; Turbo Stream replaces the bell; banner dismiss does not create a read; mark-read does not create a dismissal; owner without acting-as does not see tenant C’s item; owner acting as C does.
- Stimulus: `notifications_menu_controller` stays at 100% lines/branches (menu behaviour). Mark-read is server-side; do not add untested JS branches.

## Out of scope

- Email, SMS, Slack, or any channel other than the admin bell
- Action Cable / websocket live push
- Member or public chrome, or a bell on `Member::ShellComponent`
- Four-area module surfaces
- Changing owner CRUD fields, audience builder, or banner stacking/severity
- Markdown, HTML, images, or rich templates
- A general-purpose inbox for payments, flowchart `in_app`, email events, etc.
- Mark-all-read, preferences, mute, digest
- A job that purges discarded announcements after 7 days
- Granting `owner` to anyone other than the canonical platform owner

## Success criteria

1. Owner publishes a live `audience: all` (or matching `selected`) announcement → targeted tenant admins see the existing banner **and** an unread bell item on the next admin page load.
2. Draft / scheduled / non-matching tenant → no bell item.
3. Clicking the bell row marks it read for that admin+customer only; the banner is unchanged.
4. Dismissing the banner leaves the bell item unread.
5. After end / unpublish / delete, the item remains in the bell for 7 days, then disappears.
6. Members never see it. Cross-tenant forged reads write nothing.
