# Notifications + Help — UX spec

Date: 2026-08-31
Audience: frontend developer. ViewComponent + Tailwind + Stimulus only. Do not edit routes, activities, or stream payloads in this slice beyond mounting `turbo_stream_from` and keeping the listed DOM ids stable.

shadcn analog: Alert + Badge + Card + Avatar + Dialog + DropdownMenu, delivered through existing Anysys tokens (`surface`, `canvas`, `border-subtle`, `text-primary` / `secondary` / `muted`, `accent-subtle`, `info-subtle`, `warning-subtle`, `danger-subtle`, `btn-primary` / `btn-secondary`, `dropdown-panel`, `card`, `badge`). Swiss Modernism 2.0 — quiet, 8px grid, no inverted white-on-saturated strips.

Locked product: admin + owner only. Members never see these surfaces. Evolve existing components; no required new ViewComponent.

---

## 1. Surface inventory

| # | Surface | Component | Nav area | URL | Audience |
|---|---|---|---|---|---|
| A | Platform announcement stack | `Platform::AnnouncementBannerComponent` | admin (Shell chrome) | every admin page that renders `ShellComponent` | `admin` or `owner` when the component already `render?`s |
| B | Admin bell dropdown | `NotificationsButtonComponent` + inbox + rows + badge | admin (Topbar chrome) | every admin topbar | `admin` or `owner` |
| C | Help compose dialogs | `HelpComposeDialogComponent` (`:notify`, `:email`) | admin (Topbar chrome) | opened from `HelpMenuComponent` | tenant `admin` (notify); `admin` / `owner` (email) |
| D | Tenant help thread | `HelpThreadComponent` `owner_view: false` | admin | `GET /:cid/admin/support_tickets/:id` | tenant `admin` (own tickets) |
| E | Platform help thread | `HelpThreadComponent` `owner_view: true` | admin / Maintenance / Platform | `GET /81721200/admin/maintenance/platform/support_tickets/:id` | `owner` on `81721200` |
| F | Platform help index | existing `AdminTableComponent` | admin / Maintenance / Platform | `GET /81721200/admin/maintenance/platform/support_tickets` | `owner` on `81721200` |

Not in this redesign: Help `?` menu items, announcement CRUD, member/public chrome, backend Turbo Stream payloads. Shell order stays **A → ContextBanner → Topbar (B + C)**.

---

## 2. Layout spec per surface

Shared rhythm: `gap-3`, `px-4`, `py-3`, `p-4`. Stacks are `flex flex-col gap-*` (never `space-y-*`). Equal boxes use `size-*`.

### A. Announcement banner — `Platform::AnnouncementBannerComponent`

Placement: first child of the Shell column, above `ContextBanner`. Normal document flow (not sticky). Wrapper `#platform-announcements` stays in the DOM whenever the component `render?`s — including when the stack is empty — so a Turbo replace still has a target.

Current problem: full-bleed `bg-info text-white` / `bg-danger text-white` strips. Replace with a shadcn Alert analog: `*-subtle` fill, 3px left severity bar, tinted icon, dark-on-tint type. Never invert.

```
┌─ 3px severity bar ───────────────────────────────────────────────────────┐
│ [icon-well]  Title (semibold, 1 line, truncate)                          │
│  36×36       Body (text-sm text-secondary, line-clamp-2)                 │
│                                        [Learn more]  [× dismiss]         │
└──────────────────────────────────────────────────────────────────────────┘
```

Mobile (`<sm`): icon + copy full width; actions under the body, `justify-end gap-3`. `sm+`: one row — copy `flex-1 min-w-0`, actions `shrink-0 self-center`.

**Data**

| Region | Source |
|---|---|
| Wrapper id | `STACK_DOM_ID` = `platform-announcements`; keep `aria-live="polite"` |
| Strip id | `platform-announcements-#{id}` (`dom_id_for`) |
| Icon path | `AlertComponent::TYPES` — `info` → `:info`, `warning` → `:warning`, `critical` → `:error` |
| Title | `announcement.title` — `text-sm font-semibold text-text-primary truncate` |
| Body | `body_for(announcement)` — `text-sm text-text-secondary line-clamp-2` |
| Learn more | `announcement.link_url` if present — `t("comp_platform.announcement_banner.learn_more")` |
| Dismiss | existing `button_to dismiss_path`, `params: { platform_announcement_id: }` |

**Severity chrome** (`SEVERITY_CHROME[:strip_class]` plus shared `px-4 py-3`)

| Severity | Fill | Border | Left bar | Icon | `role` |
|---|---|---|---|---|---|
| `info` | `bg-info-subtle` | `border border-info/20` | `border-l-[3px] border-l-info` | `text-info` | `status` |
| `warning` | `bg-warning-subtle` | `border border-warning/20` | `border-l-[3px] border-l-warning` | `text-warning` | `status` |
| `critical` | `bg-danger-subtle` | `border border-danger/20` | `border-l-[3px] border-l-danger` | `text-danger` | `alert` |

Drop `bg-info text-white`, `bg-warning text-amber-950`, `bg-danger text-white`.

**Icon well:** `size-9 shrink-0 rounded-lg` on the strip tint (no second saturated circle). SVG `size-5 fill="currentColor"` using the Alert path. `items-start`; icon may use `mt-0.5`.

**Actions**

| Action | Placement | Chrome |
|---|---|---|
| Learn more | right of body / under body on mobile | `text-sm font-medium text-accent-text hover:underline underline-offset-2`; `target="_blank"` `rel="noopener noreferrer"` |
| Dismiss | far right | existing `button_to`; hover `hover:bg-black/5` (not `hover:bg-white/20`); `aria-label` stays `comp_platform.announcement_banner.dismiss_titled` |

No primary button. Dismiss only hides for this viewer.

**States**

| State | Look |
|---|---|
| Empty | `#platform-announcements` with `flex w-full flex-col` and no children. Zero height. Stays in the DOM. |
| 1–3 strips | Stacked `flex flex-col` with no gap (each strip has its own border). Existing severity-then-newest sort. Max 3. |
| Loading | None. SSR + Turbo replace. |
| Error | Existing form/redirect on failed dismiss. |

---

### B. Bell dropdown — `NotificationsButtonComponent`

Placement: Topbar actions, after `HelpMenuComponent`, before `UserMenuComponent`. Stimulus root `data-controller="notifications-menu"` wraps trigger + badge + panel and is **never** Turbo-replaced.

**Live subscription:** first child inside the Stimulus root (before the trigger):

```erb
<%= helpers.turbo_stream_from Notifications::Stream.name(viewer.id) %>
```

Do not remount `data-controller="notifications-menu"` from any stream.

```
                 ┌ trigger #notifications-trigger ┐
                 │  🔔  [#notifications-badge]    │
                 └────────────────────────────────┘
┌ panel  w-[26rem] max-w-[calc(100vw-2rem)]  dropdown-panel ──────────────┐
│  Notifications                         [ 3 ]  ← BadgeComponent sm danger│
│  ────────────────────────────────────────────────────────────────────── │
│  #notifications-panel-body  (scroll)                                    │
│    #notifications-inbox-list                                            │
│    ┌ #notifications-support-ticket-row-9 ───────────────────────────────────────┐ │
│    │ • [well 36]  Help  ·  2 hours ago                                │ │
│    │              Cannot save a page                                  │ │
│    │              The button does nothing…                            │ │
│    │              Acme Co.          Learn more (announcements only)   │ │
│    └──────────────────────────────────────────────────────────────────┘ │
│    #notifications-inbox-empty     (when list empty)                     │
│    #notifications-support-ticket-unread     (hidden live count)                   │
└─────────────────────────────────────────────────────────────────────────┘
```

**Panel:** `hidden absolute right-0 mt-2 w-[26rem] max-w-[calc(100vw-2rem)] dropdown-panel py-0 z-40 overflow-hidden`. `role="dialog"` + `aria-label` = `t("chrome.notifications.title")`.

**Header:** `flex items-center justify-between gap-3 px-4 py-3 border-b border-border-subtle`. Title `text-sm font-semibold text-text-primary`. Unread count: `BadgeComponent.new(variant: :danger, size: :sm)` **only when visible count > 0**. Same overflow as the trigger badge (`99+` via `chrome.notifications.unread_overflow`). Hide at 0.

**Stable ids (keep)**

| Id | Component |
|---|---|
| `#notifications-trigger` | `NotificationsBellTriggerComponent` — `icon-button`; SVG `size-5` |
| `#notifications-badge` | `NotificationsBellBadgeComponent` — `absolute -top-0.5 -right-0.5 h-4 min-w-4 rounded-full bg-danger text-white text-[10px] font-semibold tabular-nums` |
| `#notifications-panel-body` | `NotificationsInboxComponent` root — `max-h-[min(24rem,calc(100vh-8rem))] overflow-y-auto` |

**Add**

| Id | Role |
|---|---|
| `#notifications-inbox-list` | Row container when there is ≥1 item. Streams upsert here. |
| `#notifications-inbox-empty` | Empty-state wrapper when the list is empty. |
| `#notifications-support-ticket-unread` | Always present in the Stimulus root (header sibling is fine). Visually `hidden` or `sr-only`. `data-count="<%= support_ticket_unread_count %>"`. |
| `#notifications-support-ticket-row-<%= id %>` | Each help row root. Announcement rows do not need a live id. |

**Badge summing (extend `notifications-menu`, do not remount)**

Visible unread = announcement unread **frozen at this page’s tenant render** + help unread **live-replaced**.

- `#notifications-badge` (or the Stimulus root) carries `data-announcement-unread="<%= announcement_unread_count %>"`. Help streams must not change this.
- `#notifications-support-ticket-unread` carries `data-count` for help unread.
- Stimulus sums the two integers, then: show/hide the trigger badge; set label (`n` or `unread_overflow` at ≥ 100); set trigger `aria-label` (`unread_titled` vs `title`); show/hide + label the header `BadgeComponent`.
- When Turbo replaces `#notifications-support-ticket-unread`, `supportTicketUnread` `targetConnected` re-runs the sum.

Announcement mark-read streams still replace `#notifications-trigger`, `#notifications-badge`, and `#notifications-panel-body`. After replace, the new badge’s `data-announcement-unread` is the new frozen count; Stimulus reconnects and re-sums.

**Empty state:** keep the crossed-bell illustration. Tighten to `px-4 py-8` (was `px-6 py-10`). Well `size-11 rounded-full bg-surface-hover`; icon `size-5 text-text-muted`. Copy: `chrome.notifications.caught_up_html` (`text-sm font-medium text-text-primary`) + `chrome.notifications.empty` (`text-xs text-text-muted`).

**Row — `NotificationsInboxRowComponent`**

```
[unread-dot] [kind well 36]  Kind Badge  ·  relative time
                             Title
                             Preview (line-clamp-2)
                             subtitle + Learn more
```

| Piece | Spec |
|---|---|
| Root | `flex items-start gap-3 px-4 py-3 hover:bg-surface-hover transition-base` |
| Unread dot | unread: `mt-1.5 size-1.5 shrink-0 rounded-full bg-accent`; read: same box, no fill (column align) |
| Kind well | `size-9 shrink-0 rounded-lg inline-flex items-center justify-center`. Announcement: megaphone on `bg-accent-subtle text-accent-text`. Help: life-ring or chat-bubble on `bg-info-subtle text-info`. Stroke SVG `size-4`. |
| Kind chip | `BadgeComponent` `size: :sm` — announcement `variant: :primary` + `chrome.notifications.kind`; help `variant: :info` + `chrome.help_menu.inbox.kind`. Drop the raw `text-[10px] uppercase` span. |
| Relative time | `t("chrome.admin_table.time_ago", time: time_ago_in_words(item.occurred_at))` in `<time datetime="<%= item.occurred_at.iso8601 %>">`. `text-xs text-text-muted tabular-nums`. Middot separator `text-text-muted`. |
| Title | `text-sm`; unread `font-semibold text-text-primary`; read `font-normal text-text-secondary` |
| Preview | `item.body`; `text-xs`; unread `text-text-secondary` / read `text-text-muted`; `line-clamp-2` (was 3) |
| Subtitle | owner only: `item.subtitle` (customer name). `text-xs text-text-muted truncate`. Tenant admins: omit. |
| Learn more | announcement + `item.link_url`. Existing link, `data-turbo="false"`, `target="_blank"`. |

**Row actions (behavior unchanged)**

| Kind | Control |
|---|---|
| Help (any) | `button_to support_ticket_read_path`, `data: { turbo: false }`, wraps the text column. Server marks read then full-page navigates to `item.href`. |
| Announcement unread | `button_to mark_read_path`, `data-turbo-stream="true"`, `aria-label` = `chrome.notifications.mark_read`. |
| Announcement read | static text; no form. Learn more still available. |

Do not turn help rows into `<a href>`.

**States:** empty illustration; items use `divide-y divide-border-subtle`; no loading skeleton; mark-read failure is existing controller behavior; overflow `99+`.

**Responsive:** `max-w-[calc(100vw-2rem)]` so 26rem never clips a 320px viewport. Right-aligned to the bell.

---

### C. Help compose dialogs — `HelpComposeDialogComponent`

Keep structure and fields. Polish only (shadcn Dialog analog).

| Region | Spec |
|---|---|
| Overlay | `fixed inset-0 z-[60]`; backdrop `absolute inset-0 bg-slate-900/50`. Click still `help-menu#closeDialogs`. Drop `backdrop-blur-[2px]`. |
| Dialog | `relative mt-[6vh] w-full max-w-lg max-h-[82vh] flex flex-col overflow-hidden bg-surface rounded-xl ring-1 ring-border shadow-float`. Keep `role="dialog"` `aria-modal` `aria-labelledby`. |
| Header | `flex items-start gap-3 px-4 py-3 border-b border-border-subtle`. **Add** 36px icon well before the title stack: notify = life-ring/bell on `bg-info-subtle text-info`; email = envelope on `bg-accent-subtle text-accent-text`. Title `text-sm font-semibold text-text-primary`. Email helper `text-xs text-text-muted`. Close stays `icon-button` + `common.actions.close`. |
| Body | `flex flex-col gap-4 overflow-y-auto px-4 py-4` |
| Inputs | unchanged names / maxlength / required. `w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-text-primary` (or `input-field` if already used — do not invent a third class). Labels `text-sm font-medium text-text-primary`. |
| Footer | `flex shrink-0 items-center justify-end gap-2 border-t border-border-subtle px-4 py-3`. Cancel `btn btn-secondary` → `help-menu#closeDialogs`. Submit `btn btn-primary` + existing `data-help-attachments-target="submit"`. |

**States:** closed = `hidden`; open = overlay + dialog, first text input focused (existing); validation = HTML5 + `HelpAttachmentsFieldComponent` `text-xs text-danger`; owner never sees Notify (`show_notify?`); email vendor-down = existing flash after redirect.

`help-menu` behavior unchanged.

---

### D. Tenant thread show — `HelpThreadComponent` (`owner_view: false`)

Page: `AdminPageComponent` — breadcrumbs Help → subject; `title` = `@support_ticket.subject`. No page actions.

Single conversation column. **No resolve button. No metadata sidebar.**

```
AdminPage
  [status Badge]                    ← Open :info / Resolved :default
  ┌─ #support-ticket-messages ───────────────────────────────────────────────┐
  │  [AV] Name          14:02                                             │
  │  ┌ theirs ─────────────────────────────┐                              │
  │  │ body + [img] [img]                  │  left, bg-surface            │
  │  └─────────────────────────────────────┘                              │
  │                   You [AV]          14:05                             │
  │                   ┌ mine ──────────────┐                              │
  │                   │ body               │  right, accent-subtle        │
  │                   └────────────────────┘                              │
  └───────────────────────────────────────────────────────────────────────┘
  ┌─ sticky composer card (open only) ────────────────────────────────────┐
  │  Reply                                                                │
  │  [ textarea ]                                                         │
  │  [ HelpAttachmentsField compact ]                    [ Send reply ]   │
  └───────────────────────────────────────────────────────────────────────┘
```

**Scroller:** id **`support-ticket-messages`** (required). Counterpart Turbo appends land here; missing target = no-op. `flex flex-col gap-3`. If the thread is long, `max-h-[min(32rem,calc(100vh-20rem))] overflow-y-auto` and composer `sticky bottom-0 z-10 bg-canvas pt-2`.

**Bubble (shadcn Avatar + Card)**

| | Mine (`message.user_id == viewer.id`) | Theirs |
|---|---|---|
| Alignment | `justify-end` | `justify-start` |
| Avatar | `.avatar size-7` after the bubble. Initials: first + last of `display_name`, else first two of email. | `.avatar size-7` before the bubble. Same initials. |
| Name | `chrome.help_menu.thread.you` | requester `message.user.display_name`; owner-author `chrome.help_menu.thread.platform` |
| Time | `<time datetime=iso>` `l(..., format: :short)` `text-xs text-text-muted tabular-nums` | same |
| Bubble | `bg-accent-subtle border border-accent-muted rounded-2xl rounded-br-md px-4 py-3` | `bg-surface border border-border rounded-2xl rounded-bl-md px-4 py-3` |
| Body | `text-sm text-text-secondary whitespace-pre-wrap` | same |
| Images | `flex flex-wrap gap-2`; each `rounded-lg max-h-48 border border-border object-contain` | same |
| Max width | `max-w-[min(100%,36rem)]` | same |

Avatar sits **outside** the bubble, top-aligned, using the existing `.avatar` token (same as `UserMenuComponent`). Do not invent a second avatar system.

If thread ERB becomes unreadable, extract optional `HelpMessageBubbleComponent` (`message:`, `mine:`, `author_label:`, `initials:`). Only then.

**Composer (open only):** `card p-4 flex flex-col gap-3`. Label `chrome.help_menu.thread.reply`. Existing textarea + compact attachments. Submit `btn btn-primary` → `chrome.help_menu.thread.send_reply`. Existing `form_with` POST `reply_path`.

**Resolved:** no composer. Muted note `maint_platform.support_tickets.show.resolved_note` in `bg-surface-hover rounded-lg px-4 py-3 text-sm text-text-muted`.

**States:** empty thread should not happen (create writes a first message); if it does, empty scroller + composer when open. Reply errors stay on the form. Tenant admin sees only own ticket (controller).

---

### E. Platform thread show — `HelpThreadComponent` (`owner_view: true`)

Same conversation + composer as D, plus metadata + resolve.

Page: `AdminPageComponent` — Maintenance → Support tickets → subject.

```
AdminPage header:  [Open]                         [ Mark resolved ]
┌ metadata card (lg:col-span-3) ┐  ┌ conversation (lg:col-span-9) ────────┐
│ Customer     Acme Co.         │  │  #support-ticket-messages               │
│ Customer ID  42               │  │  …bubbles…                           │
│ Requester    Jane Q           │  │  sticky composer / resolved note     │
│ Email        jane@acme.test   │  └──────────────────────────────────────┘
│ Created      2026-08-30 09:12 │
│ Last message 2 hours ago      │
└───────────────────────────────┘
```

`<lg`: metadata **above** the thread (`flex flex-col gap-4`). `lg:` `grid grid-cols-12 gap-4` — metadata `lg:col-span-3`, thread `lg:col-span-9`.

**Header (inside the component, above the grid):** status badge as in D. **Mark resolved** (`btn btn-secondary`) only while `support_ticket.open?` **and** `resolve_path` present. Existing `button_to` + `data-turbo-confirm` = `maint_platform.support_tickets.show.resolve_confirm`. Tenant view (`owner_view: false`) must not render this button even if a path is passed.

**Metadata card:** `card p-4 flex flex-col gap-3`. Title `t("maint_platform.support_tickets.show.details")` — `text-sm font-semibold text-text-primary`. Definition list: label `text-xs text-text-muted`, value `text-sm text-text-primary truncate`.

| Label key | Value |
|---|---|
| `maint_platform.support_tickets.show.meta.customer` | `support_ticket.customer.name` |
| `maint_platform.support_tickets.show.meta.customer_id` | `support_ticket.customer_id` |
| `maint_platform.support_tickets.show.meta.requester` | `support_ticket.user.display_name` |
| `maint_platform.support_tickets.show.meta.email` | `support_ticket.user.email` |
| `maint_platform.support_tickets.show.meta.created` | `l(created_at, format: :short)` in `<time>` |
| `maint_platform.support_tickets.show.meta.last_message` | `chrome.admin_table.time_ago` + `<time datetime=iso>` |

Drop the current one-line `name (id) · email` header string.

After resolve: badge → Resolved, button gone, composer replaced by the muted note.

---

### F. Platform index — existing `AdminTable`

Keep columns, search, status filter, empty copy, row path. Visual-only: subject leading icon + optional unread badge.

**Subject column:** `cell_text` stays `row.subject` (`font-medium` already).

```ruby
leading: ->(row) { { icon: :mail, tone: unread_for_viewer?(row) ? :accent : :default } }
```

`:mail` is **already** in `AdminTableComponent::LEADING_ICONS`. Do not add a second mail path. Tone `:accent` → `bg-accent-subtle text-accent-text`; `:default` → `bg-surface-active text-text-muted`. Existing `w-9 h-9` tile (`size-9` only if you already touch that markup).

**Status `badge:`:** first badge stays Open (`:info`) / Resolved (`:default`). When unread for the viewing owner, append `{ label: t("help.unread"), variant: :info }`. `badges_for` already `Array.wrap`s.

**Unread** (viewing owner): requester messages newer than that owner’s `SupportTicketRead.last_read_at`, or no read row. Frontend does not compute this — the controller / a helper passes a boolean into `leading:` and `badge:`.

Empty / loading / mobile: existing AdminTable. Opening a row runs `SupportTicketRead.record!` in `show`, so returning to F clears that row’s unread chrome.

---

## 3. Interaction flow

### A1. Dismiss a banner strip

Starting URL: any `/:cid/admin/…` with 1–3 strips. User clicks × on `platform-announcements-#{id}` → existing `POST /:cid/admin/platform_announcement_dismissals` → Turbo replaces `#platform-announcements`. Empty wrapper stays. Failure: existing redirect/status; strip remains.

### A2. Learn more from the banner

Clicks Learn more → new tab to `link_url`. Does not dismiss. Does not mark the inbox row read.

### B1. Open / close the bell

Clicks `#notifications-trigger` → `notifications-menu#toggle`. Outside click / Escape / peer topbar menu → close. Unchanged.

### B2. Mark an announcement read

Clicks unread announcement row → `POST` mark-read `turbo_stream: true` → stream replaces trigger / badge / panel-body. Stimulus root stays mounted. Sum re-runs from new `data-announcement-unread` + current help count. Row restyles to read. Learn more still works.

### B3. Open a help row

Clicks help row (read or unread) → `POST` `support_ticket_read_path` `turbo: false` → server records read → **full navigation** to tenant `/:cid/admin/support_tickets/:id` or owner `/81721200/admin/maintenance/platform/support_tickets/:id` (D or E).

### B4. Live help unread (counterpart replies)

Viewer has any admin page open. Stream (backend, out of scope) replaces `#notifications-support-ticket-unread` and may upsert `#notifications-support-ticket-row-#{id}` / list / empty. `#support-ticket-messages` append is a no-op if that id is absent. `supportTicketUnread` connects → restyle trigger badge, header badge, `aria-label`. Do not remount `notifications-menu`.

### C1. Compose notify / email

Help `?` → Notify / Email → `help-menu#openNotify` / `#openEmail` → overlay + dialog, scroll lock, focus first field. Cancel / overlay / Escape resets. Submit → existing POST-redirect-GET + flash. Validation stays in-dialog. Owner never sees Notify.

### D1 / E1. Reply

Open ticket, composer visible → POST `reply_path`. **Author:** existing POST-redirect-GET; page re-renders with the new bubble. **Counterpart** with the thread open: Turbo **appends** to `#support-ticket-messages` (missing target = no-op) and updates help-unread + help-row. Attachment / resolved errors stay on the form.

### E2. Resolve (owner only)

Open ticket on E → Mark resolved → `turbo_confirm`. Cancel = no POST. Confirm → existing POST → show re-renders resolved (badge, no composer, no button).

### F1. Index → show

Owner on F. Unread rows: accent mail well + Unread badge. Click subject → E.

### Failure matrix

| Failure | Surface | UI |
|---|---|---|
| Validation (compose / reply) | C, D, E | Inline field / attachment error. No toast. |
| Permission denied | all | Existing 403 / redirect. Members never see A–F. |
| Vendor-down (email) | C email | Existing flash after redirect. |
| Missing Turbo target | B, D, E | no-op. |
| Confirm cancel | E resolve | no change. |

---

## 4. Component reuse map

| Piece | Reuse / evolve | New? |
|---|---|---|
| Banner stack | **Evolve** `Platform::AnnouncementBannerComponent` | No |
| Banner icons | `AlertComponent::TYPES[:info/:warning/:error][:icon_path]` | No |
| Shell placement | `ShellComponent` (already first child) | No |
| Bell / trigger / badge / inbox / row | **Evolve** `NotificationsButtonComponent`, `NotificationsBellTriggerComponent`, `NotificationsBellBadgeComponent`, `NotificationsInboxComponent`, `NotificationsInboxRowComponent` | No |
| Kind / status / unread chips | `BadgeComponent` | No |
| Bell panel | `dropdown-panel` | No |
| Help `?` menu | `HelpMenuComponent` — behavior unchanged | No |
| Compose dialogs | **Evolve** `HelpComposeDialogComponent` | No |
| Attachments | `HelpAttachmentsFieldComponent` | No |
| Tenant / owner pages | `AdminPageComponent` | No |
| Thread | **Evolve** `HelpThreadComponent` | No |
| Message bubble | stay in thread ERB, **or** optional `HelpMessageBubbleComponent` | Optional |
| Inbox empty | stay in inbox ERB, **or** optional `NotificationsInboxEmptyComponent` | Optional — not required |
| Owner index | `AdminTableComponent` — existing `:mail` leading icon + `badges_for` array | No |
| Buttons | `btn-primary` / `btn-secondary` / `icon-button` | No |
| Avatars | existing `.avatar` token | No |
| Cards | `card` | No |

Do not build a new banner component, dropdown primitive, toast system, member inbox, or a resolve control on the tenant show.

---

## 5. Tailwind & Stimulus notes

### Tailwind

- Spacing: `gap-3`, `px-4`, `py-3`, `p-4`. No `space-y-*`.
- Boxes: `size-9` wells, `size-7` avatars, `size-5` / `size-4` icons, `size-1.5` unread dot.
- Type: title `text-sm font-semibold text-text-primary`; body `text-sm text-text-secondary`; meta `text-xs text-text-muted`.
- Banner: `*-subtle` + `border-*/20` + `border-l-[3px]`. Never `bg-info text-white`.
- Panel: `w-[26rem] max-w-[calc(100vw-2rem)] dropdown-panel overflow-hidden`.
- Dialog: overlay `bg-slate-900/50`; dialog `rounded-xl ring-1 ring-border shadow-float`.
- Bubbles: mine `bg-accent-subtle border-accent-muted`; theirs `bg-surface border-border`.
- Images: `rounded-lg max-h-48`.
- Owner grid: `flex flex-col gap-4 lg:grid lg:grid-cols-12` / `lg:col-span-3` + `lg:col-span-9`.

### Stimulus

| Controller | Change |
|---|---|
| `notifications-menu` | Keep `panel` + `trigger`, toggle / close / peer-menu. **Add** optional `supportTicketUnread` target. On `supportTicketUnreadTargetConnected` and `connect`, sum `data-announcement-unread` + `#notifications-support-ticket-unread[data-count]`; update badge visibility, label, overflow, trigger `aria-label`, header count badge. Prefer this over a new controller. |
| `help-menu` | Unchanged. |
| `help-attachments` | Unchanged. |
| `admin-table` | Unchanged. |

No new JS framework. New Stimulus only if badge summing cannot live on `notifications-menu`.

### Turbo contract (frontend)

| Target | Stream action | Frontend duty |
|---|---|---|
| `#platform-announcements` | replace (dismiss) | keep wrapper in DOM |
| `#notifications-trigger` / `#notifications-badge` / `#notifications-panel-body` | replace (announcement mark-read) | do not wrap these in a Stimulus-root replacement |
| `#notifications-support-ticket-unread` | replace | restyle badge via `targetConnected` |
| `#notifications-inbox-list` | append / prepend / replace children | stable id |
| `#notifications-support-ticket-row-#{id}` | replace / remove | stable id on help rows |
| `#support-ticket-messages` | append | id present on D and E |

### I18n

No hard-coded user-facing strings. `en` + `zh-CN` in parity. English values **byte-identical** to former hard-coded / existing keys when replacing current copy.

**Reuse as-is**

| Key | en |
|---|---|
| `chrome.notifications.title` | Notifications |
| `chrome.notifications.kind` | Notice |
| `chrome.notifications.caught_up_html` | You're all caught up |
| `chrome.notifications.empty` | No new notifications right now. |
| `chrome.notifications.unread_titled` | Notifications, %{count} unread |
| `chrome.notifications.mark_read` | Mark as read |
| `chrome.notifications.unread_overflow` | 99+ |
| `chrome.help_menu.inbox.kind` | Help |
| `chrome.help_menu.thread.you` | You |
| `chrome.help_menu.thread.platform` | Platform |
| `chrome.help_menu.thread.reply` | Reply |
| `chrome.help_menu.thread.send_reply` | Send reply |
| `chrome.help_menu.notify.*` / `email.*` | existing compose copy |
| `chrome.admin_table.time_ago` | %{time} ago |
| `comp_platform.announcement_banner.learn_more` | Learn more |
| `comp_platform.announcement_banner.dismiss_titled` | Dismiss announcement: %{title} |
| `maint_platform.support_tickets.show.resolve` | Mark resolved |
| `maint_platform.support_tickets.show.resolve_confirm` | Mark this support ticket as resolved? |
| `maint_platform.support_tickets.show.resolved_note` | This request is resolved. |
| `maint_platform.support_tickets.show.images` | Screenshots |
| `help.status.open` / `help.status.resolved` | Open / Resolved |

**Add (`en` + `zh-CN`)**

| Key | en | zh-CN |
|---|---|---|
| `help.unread` | Unread | 未读 |
| `maint_platform.support_tickets.show.details` | Details | 详情 |
| `maint_platform.support_tickets.show.meta.customer` | Customer | 客户 |
| `maint_platform.support_tickets.show.meta.customer_id` | Customer ID | 客户 ID |
| `maint_platform.support_tickets.show.meta.requester` | Requester | 提交人 |
| `maint_platform.support_tickets.show.meta.email` | Email | 邮箱 |
| `maint_platform.support_tickets.show.meta.created` | Created | 创建时间 |
| `maint_platform.support_tickets.show.meta.last_message` | Last message | 最后消息 |

Bell relative time **replaces** `I18n.l(..., format: :short)` — presentation only; do not hard-code `"ago"`. Stimulus copy (none expected) uses English `default:` plus server-passed `data-*-value`.

---

## Out of scope

- Backend `Notifications::Stream` name helper / broadcast payloads (frontend only mounts `turbo_stream_from`).
- Member inbox, email/SMS fan-out, markdown bodies.
- Changing dismiss / mark-read / reply / resolve routes.
- New roles or surfaces outside admin / Maintenance / Platform.
