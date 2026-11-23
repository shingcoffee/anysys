# Announcement bell notifications — UX

Date: 2026-08-31

Audience: frontend developer. Implement ViewComponent + Tailwind + existing Stimulus `notifications-menu` only. Do **not** add four-area module surfaces (Modules / Settings / Maintenance toggle / Platform Module Settings). This is **admin chrome** on `TopbarComponent`.

Locked product decisions (this brief):

| Topic | Decision |
|---|---|
| Independence from banner | Dismissing the banner does **not** mark the bell read. Marking a bell row read does **not** dismiss the banner. Separate persisted receipts. |
| History | After an announcement leaves live (`ended` / unpublished / deleted), it remains in the inbox for **7 days**. |
| Mark-read | Clicking **one** unread row marks **that** item read. Opening the panel does **not** mark all. No “Mark all as read”. |
| Audience | Same as the banner: tenant `admin`, and `owner` when acting as that tenant. Members never. **No member bell.** |
| Empty copy | Keep `chrome.notifications.caught_up_html` / `chrome.notifications.empty`. Show that empty state **only** when the inbox has **zero** items. Read history still lists. |
| New i18n | `chrome.notifications.unread_titled` = “Notifications, %{count} unread” / 通知，%{count} 条未读; `chrome.notifications.mark_read` = “Mark as read” / 标为已读. |
| Learn more | Reuse `comp_platform.announcement_banner.learn_more`. |
| Badge | When unread > 0, render a count pill with `data-badge-count`. **No badge at 0.** |
| Panel width | `w-96` desktop, `max-w-[calc(100vw-2rem)]` on small screens, right-aligned. |
| Sort | Unread first, then newest. **No** severity reorder. **No** cap of 3 (banner `MAX_VISIBLE = 3` stays on the banner only). |
| Body | Truncate ~3 lines (`line-clamp-3`). |
| Unread vs read | Unread: leading status dot + default title weight. Read: muted, no dot. |
| Transport | Row click → `button_to` POST mark-read + `turbo_stream`. Nested Learn more (`target=_blank`) must not double-submit. |
| Stimulus | Existing `notifications-menu` stays a menu **shell** (toggle / outside / Escape / peer). Do not invent a new JS framework. |
| Turbo | Replace inner targets `notifications-badge` and `notifications-panel-body` so an open dropdown is **not** torn down. |

Existing files to match: `NotificationsButtonComponent` (stub), `HelpMenuComponent` (sibling dropdown), `Platform::AnnouncementBannerComponent` (severity + Learn more — **do not reuse the strip chrome**), `.icon-button` / `.dropdown-panel` in `app/assets/tailwind/application.css`.

shadcn mapping (consulted; project has no Radix): Popover + Badge + Empty. Deliver through existing `icon-button` + `dropdown-panel` + compact empty markup already in the stub. Do **not** pull Radix, and do **not** use page-level `EmptyStateComponent` or `BadgeComponent` (those are the wrong density for a 2.125rem icon button).

---

## 1. Surface inventory

This is **admin chrome**, not a four-area feature module. `nav_area` is `admin`.

| # | Surface | Nav area | URL | Audience | Notes |
|---|---|---|---|---|---|
| A | Bell trigger + unread badge | admin | lives on every admin `TopbarComponent` (`ShellComponent`) | signed-in `admin` or `owner` on an admin URL | Existing stub. Badge only when unread > 0. |
| B | Notifications dropdown panel | admin | toggled from A; no route of its own | same | Header + scrollable body. Stimulus shell. |
| C | Inbox list (unread + 7-day history) | admin | rendered inside B (`#notifications-panel-body`) | same content rules as the banner | Unread first, then newest. No cap. |
| D | Zero-item empty state | admin | same body target as C | same | **Only** when inbox count is 0. Keep stub copy + slashed-bell icon. |
| E | Mark-read POST (not a page) | admin | `POST /:customer_id/admin/platform_announcement_reads` | tenant `admin`, or `owner` acting as that tenant | `button_to` + turbo_stream. Mirrors dismissals, **independent** table. |

**Not surfaces (do not build):**

- Member chrome bell (member layouts have no `TopbarComponent`; do not add one).
- Public chrome.
- Four-area module pages for the inbox.
- Banner changes (strip, dismiss, `MAX_VISIBLE = 3`, severity order) — leave `Platform::AnnouncementBannerComponent` as-is.
- “Mark all as read”, severity reordering, timestamp column, toast/sonner.

**Owner on `81721200` (not acting-as):** the bell **control** stays in the admin topbar (already shipped). Inbox **items** resolve against the URL customer with the same audience rules as the banner, so the platform-home context is typically an empty inbox (`caught_up`), not a dump of every tenant’s notices.

**Owner acting-as tenant C:** inbox is C’s notices. Banner (if any) and bell stay independent.

---

## 2. Layout spec per surface

### Shared chrome placement

Do not reorder the topbar. The bell is already the third trailing control:

```
┌─ TopbarComponent (sticky, bg-surface, border-b border-border) ──────────────┐
│ Logo / hamburger │ search │  [locale] [help] [🔔 A] [user]                 │
│                                         │                                   │
│                                         ▼ B (absolute right-0)              │
│                              ┌─ dropdown-panel ─────────────────────────┐   │
│                              │ Notifications                            │   │
│                              ├──────────────────────────────────────────┤   │
│                              │ C inbox  or  D empty                     │   │
│                              └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

`z-40` on the panel — match the current stub and `HelpMenuComponent`. Peer menus close each other via `anysys:topbar-menu-open`, so they never overlap.

---

### A. Bell trigger + unread badge

**Wrapper:** keep `data-controller="notifications-menu"` on the outer `relative` root. Do **not** turbo-replace this root.

```
┌─ relative ─────────────────────────────────┐
│  ┌─ relative ──┐                           │
│  │  [ 🔔 ]     │  ← button.icon-button     │
│  │     (3)     │  ← #notifications-badge   │
│  └─────────────┘                           │
└────────────────────────────────────────────┘
```

| Region | Content | Source |
|---|---|---|
| Trigger | Existing outline bell SVG (`w-5 h-5`, stroke 1.5). Class `icon-button`. | current stub |
| `aria-haspopup` | `true` (panel is now an inbox dialog/region, not a command `menu`) | see a11y below |
| `aria-expanded` | `false` closed / `true` open; Stimulus already toggles this | `notifications-menu` trigger target |
| `aria-label` (unread = 0) | `t("chrome.notifications.title")` → “Notifications” | existing |
| `aria-label` (unread > 0) | `t("chrome.notifications.unread_titled", count: n)` → “Notifications, %{count} unread” | **new** |
| Badge | Only when `unread_count > 0`. Count integer. Attribute `data-badge-count="<%= unread_count %>"`. | `#notifications-badge` |

**Badge visual (do not use `BadgeComponent`):**

- Position: sibling of the trigger, inside a `relative` cluster, `absolute -top-0.5 -right-0.5` (or `top-0 right-0`).
- Shape: `flex h-4 min-w-4 items-center justify-center rounded-full px-1`.
- Color: `bg-danger text-white` (unread attention; matches `.badge-danger` token, not a raw red).
- Type: `text-[10px] font-semibold leading-none tabular-nums`.
- Show the integer as-is. If the count would overflow the 34px button (practically ≥ 100), display `99+` but keep `data-badge-count` as the real integer for tests.

**Badge at 0:** `#notifications-badge` still exists (Turbo target must stay in the DOM) but is **empty** — no child, no `data-badge-count`.

**Loading:** none. Count is SSR on every admin page render (same budget class as the banner resolver).

**Error:** none on the trigger. A failed mark-read leaves the previous badge in place.

---

### B. Notifications dropdown panel

**Shell (Stimulus `panel` target — do not turbo-replace this node):**

```
hidden absolute right-0 mt-2 w-96 max-w-[calc(100vw-2rem)]
dropdown-panel py-0 z-40 overflow-hidden
```

Width change vs stub: `w-80` → `w-96` + viewport cap. Stay `right-0` (right-aligned under the bell). `overflow-hidden` stays on the **shell** so the header radius clips; scrolling lives on the **body**.

```
┌─ panel (w-96, max-w-[calc(100vw-2rem)], right-0) ─────────────┐
│ ┌─ header ─────────────────────────────────────────────────┐ │
│ │ Notifications                                            │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─ #notifications-panel-body (scroll) ─────────────────────┐ │
│ │  C list  or  D empty                                     │ │
│ └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

| Region | Content | Source |
|---|---|---|
| Header | `t("chrome.notifications.title")` | existing stub row: `flex items-center justify-between px-4 py-3 border-b border-border-subtle` + `text-sm font-semibold text-text-primary` |
| Header actions | **None.** No “Mark all”, no settings gear. | — |
| Body | C or D | `#notifications-panel-body` |

**A11y (panel is an inbox, not a command menu):**

- Remove `role="menu"` from the stub (command-menu semantics are wrong once rows are `button_to` + links).
- Use `role="dialog"` + `aria-label="<%= t("chrome.notifications.title") %>"` on the panel, **or** `role="region"` + `aria-labelledby` pointing at the header id (e.g. `notifications-panel-title`).
- Do **not** put `role="menuitem"` on rows.
- No focus trap. Match help-menu: open/close only. Escape / outside / peer still close.

**Loading:** none (SSR). Do not add a skeleton inside the panel.

**Error (panel):** if the inbox resolver raises, fail the page as today — no in-panel retry UI.

---

### C. Inbox list

**Shown when** `items.any?` — including the case “all read, history still present”.

**Sort (locked):** unread first, then newest (`created_at desc`, then `id desc`). **Do not** apply banner `SEVERITY_ORDER`. **Do not** slice to 3.

**Max height:** body `max-h-[min(24rem,calc(100vh-8rem))] overflow-y-auto`. Long inboxes scroll inside the panel; the header stays pinned.

**Row data** (presenter / inbox item → UI):

| UI | Model field |
|---|---|
| Title | `PlatformAnnouncement#title` |
| Body | `announcement.body_for(I18n.locale)` (`zh*` → `body_zh`, else `body_en`) — same as the banner |
| Learn more | `link_url` present → `link_to t("comp_platform.announcement_banner.learn_more")`, `target="_blank"`, `rel="noopener noreferrer"` |
| Unread | no read receipt for `(user_id, customer_id, announcement_id)` |
| Read | receipt exists |
| Identity for POST | `platform_announcement_id` |

Do **not** show severity chips, severity icons, or colored strips in the bell. Unread is the only status treatment. No timestamp. No “Ended” / “Unpublished” badge — 7-day inclusion is a resolver rule, not a row label.

**Unread row**

```
┌─ row (hover:bg-surface-hover, px-4 py-3) ─────────────────────┐
│  ●   Title (text-sm text-text-primary, default weight)        │
│      Body (text-xs text-text-secondary line-clamp-3)          │
│      Learn more   ← only if link_url; sibling, not in button  │
└───────────────────────────────────────────────────────────────┘
```

- Leading dot: `size-1.5 rounded-full bg-accent shrink-0 mt-1.5` (indigo token, **not** severity color).
- Title: `text-sm text-text-primary` — **default weight** (`font-normal`). Do not `font-semibold` (that is the panel header).
- Body: `mt-0.5 text-xs leading-snug text-text-secondary line-clamp-3`.
- The **title + body** are the `button_to` submit surface (`aria-label: t("chrome.notifications.mark_read")`).
- Hover: `hover:bg-surface-hover transition-base` on the row wrapper.

**Read row**

```
┌─ row (px-4 py-3) ─────────────────────────────────────────────┐
│  ○   Title (text-sm text-text-muted, default weight)          │
│      Body (text-xs text-text-muted line-clamp-3)              │
│      Learn more                                               │
└───────────────────────────────────────────────────────────────┘
```

- **No** status dot. Keep a `size-1.5 shrink-0` **spacer** (invisible) so title/body align with unread rows.
- Not a `button_to`. Static text. Clicking the read row is a no-op (does not re-POST).
- Learn more still works if `link_url` is present.

**Learn more (both states)**

- Sibling of the mark-read control — **never** a descendant of `<button>`. Invalid HTML and double-submit if nested.
- `text-xs font-medium text-accent-text hover:underline underline-offset-2` (admin `link` / accent text, not the banner’s white underlined-on-color treatment).
- `target="_blank"` `rel="noopener noreferrer"`.
- `data-turbo="false"` so Turbo does not intercept the new-tab navigation.
- Click must **not** submit mark-read. Sibling structure is the primary guard; do not rely on `stopPropagation` in a new controller.

**Row divider:** `border-b border-border-subtle` on every row except the last (or `divide-y divide-border-subtle` on the list). No extra `divider` component between items.

**Valid markup sketch (unread):**

```
<div class="flex items-start gap-2.5 px-4 py-3 hover:bg-surface-hover transition-base">
  <span class="mt-1.5 size-1.5 shrink-0 rounded-full bg-accent" aria-hidden="true"></span>
  <div class="min-w-0 flex-1 flex flex-col gap-1">
    <%= button_to mark_read_path, method: :post,
          params: { platform_announcement_id: item.id },
          form_class: "contents",
          class: "w-full text-left",
          aria: { label: t("chrome.notifications.mark_read") } do %>
      <span class="block text-sm text-text-primary"><%= item.title %></span>
      <span class="mt-0.5 block text-xs leading-snug text-text-secondary line-clamp-3"><%= body %></span>
    <% end %>
    <%= link_to t("comp_platform.announcement_banner.learn_more"), item.link_url,
          target: "_blank", rel: "noopener noreferrer", data: { turbo: false },
          class: "text-xs font-medium text-accent-text hover:underline underline-offset-2" %>
  </div>
</div>
```

`form_class: "contents"` matches the banner dismiss pattern so the form does not break flex layout.

---

### D. Zero-item empty state

**Shown when and only when** the inbox array is empty (no unread **and** no 7-day history).

**Keep the stub chrome** — do not swap in `EmptyStateComponent` (that is a page card):

```
┌─ body ────────────────────────────────────────────────────────┐
│            (slashed-bell in w-11 h-11 rounded-full            │
│             bg-surface-hover)                                 │
│            You're all caught up                               │
│            No new notifications right now.                    │
└───────────────────────────────────────────────────────────────┘
```

| Element | Classes / key |
|---|---|
| Wrapper | `flex flex-col items-center justify-center gap-2 px-6 py-10 text-center` |
| Icon well | `w-11 h-11 rounded-full bg-surface-hover flex items-center justify-center` |
| Icon | existing slashed-bell SVG, `w-5 h-5 text-text-muted` |
| Title | `text-sm font-medium text-text-primary` ← `t("chrome.notifications.caught_up_html")` |
| Subtitle | `text-xs text-text-muted` ← `t("chrome.notifications.empty")` |

No action button.

---

### E. Mark-read POST (not a page)

Not a visible surface. Behavior:

| | |
|---|---|
| Method / path | `POST /:customer_id/admin/platform_announcement_reads` (parallel to `platform_announcement_dismissals`) |
| Params | `platform_announcement_id` |
| Success (turbo) | Replace `#notifications-badge` and `#notifications-panel-body` only. Panel stays open. Stimulus controller stays connected. |
| Success (no-JS) | `redirect_back` to the current admin page (same fallback style as dismissals). |
| Idempotent | Re-POST of an already-read id is a no-op (no error flash). |
| Unknown / not-in-inbox id | Ignore; no leak; panel unchanged. |
| Does **not** write | `platform_announcement_dismissals` |
| Banner after mark-read | Unchanged (still visible if live and not dismissed). |

**A11y sync after replace:** if only the badge node is replaced, the trigger `aria-label` can go stale. In the **same** turbo response, also update the trigger accessible name (replace a small `#notifications-trigger` wrapper around the `<button>`, or `turbo_stream` attribute update). Do **not** replace the panel or the `data-controller` root.

---

### Empty / loading / error (summary)

| State | Treatment |
|---|---|
| Inbox empty (0 items) | Surface D — stub empty copy. No badge. `aria-label` = `title`. |
| Inbox has only read history | Surface C, all muted rows, no dots, no badge. **Not** the empty state. |
| Inbox has unread | Badge + unread rows on top. |
| Loading | None — SSR with the admin shell. |
| Mark-read network / 5xx | No stream; open panel and badge stay as last good HTML. No flash. |
| Permission denied | Existing admin `require_admin_or_owner!` / RouteAuthorization. Member never has this chrome. |
| Vendor-down | N/A — no external vendor. |

---

### Actions

| Kind | Action | Where |
|---|---|---|
| Primary | Mark this unread item as read | Click title/body of an unread row (`button_to`) |
| Secondary | Learn more | Optional link on the row; new tab |
| Secondary (chrome) | Open / close panel | Bell `icon-button`; Escape; outside click; peer topbar menu |
| Destructive | — | None in the bell |
| Banner dismiss | Independent | Stays on `AnnouncementBannerComponent` only |

---

## 3. Interaction flow

Base: tenant admin on `/:cid/admin/...` (any `ShellComponent` page). Owner acting-as uses that tenant’s `:cid`.

### US-1 Open the bell with unread items

1. Start: tenant admin, live announcement targeted at this customer, no read receipt. Banner may also be visible (independent).
2. Topbar bell shows badge `data-badge-count="N"`. `aria-label` is `unread_titled`.
3. Click bell → `notifications-menu#toggle` → panel unhides, `aria-expanded="true"`, peer menus close.
4. Outcome: unread rows first (dot + default-weight title), then any read history. Opening does **not** POST. Badge stays until a row is marked read.
5. Click bell again / Escape / outside / open Help or User menu → panel hides.

### US-2 Mark one item read

1. Panel open from US-1.
2. Click the unread row’s title or body (not Learn more).
3. `POST /:cid/admin/platform_announcement_reads` `{ platform_announcement_id }`.
4. Turbo replaces `#notifications-badge` and `#notifications-panel-body` (and trigger `aria-label` if needed).
5. Outcome: that row is now muted, no dot, sorted into the read group (unread-first still applies). Unread count decrements. If count is 0, badge node is empty (no `data-badge-count`).
6. Panel **stays open**. Banner for that announcement **stays** if it was showing.
7. Failure (forged / not-in-inbox id): ignore, no flash, HTML unchanged.
8. No-JS: full redirect_back; page reloads with updated badge/list.

### US-3 Learn more must not mark read

1. Unread row has `link_url`.
2. Click **Learn more** → new tab to `link_url`. No mark-read POST. Badge and unread styling unchanged.
3. Then click the title/body → US-2.

### US-4 Empty inbox vs read history

1. Inbox resolver returns `[]` → panel body is D (`caught_up_html` + `empty`). No badge.
2. Inbox returns only read items (e.g. user marked everything; or only 7-day history remains) → panel body is C, all muted. **Do not** show D. No badge.
3. A new live announcement appears on next full page load → badge returns; row sorts to top as unread.

### US-5 Independent of the banner

1. Banner **Dismiss** → POST dismissals → banner strip goes away (stack turbo-replaced). Bell badge and unread row **unchanged**.
2. Bell mark-read → banner strip **unchanged**.
3. User can dismiss the banner and still have an unread bell row, or mark the bell read and still see the banner.

### US-6 Seven-day history after leave-live

1. Announcement ends, is unpublished, or is deleted, and the inbox still includes it for 7 days.
2. If the user never marked it read → it stays an **unread** row (dot, counts toward badge) until they click it or 7 days elapse.
3. If they already marked it read → muted history row until 7 days elapse.
4. After 7 days the resolver drops it. If that was the last item → D empty state.
5. No extra “ended” chrome on the row.

### US-7 Owner / member / permission

1. Member on `/:cid/member/...` → no bell (no admin topbar). Do not add one.
2. Tenant admin → US-1–6 for that `:cid` only. Never another tenant’s inbox.
3. Owner acting-as C → inbox and mark-read scoped to C (same as banner targeting).
4. Owner on `81721200` not acting-as → bell chrome present; inbox usually D (no tenant-targeted dump).
5. Anonymous / member POSTing the reads URL → existing admin auth denial. No inbox leak.

### US-8 Peer topbar menus

1. Open notifications → open Help or User or Locale → notifications panel closes (`anysys:topbar-menu-open`). Existing `notifications-menu` behavior; do not change the controller contract.

---

## 4. Component reuse map

| Piece | Reuse or new | Notes |
|---|---|---|
| Topbar slot | `TopbarComponent` (existing) | Already renders `NotificationsButtonComponent`. No new slot. |
| Menu shell, trigger, panel show/hide | `NotificationsButtonComponent` (existing, extend) | Keep `data-controller="notifications-menu"`, trigger + panel targets. |
| Unread pill | **New inner markup** inside `#notifications-badge` | Do **not** use `BadgeComponent` (wrong size / padding). |
| Inbox list / empty body | **New** `NotificationsInboxComponent` (recommended) | Single render unit for `#notifications-panel-body` so the mark-read turbo_stream can `render` it without the shell. Props: `items:` (array of unread flag + announcement), `mark_read_path:`, `customer_id:`. |
| One row | **New** `NotificationsInboxRowComponent` (optional; may stay private to the inbox ERB if small) | Props: `announcement:`, `unread:`, `mark_read_path:`. |
| Banner strip | `Platform::AnnouncementBannerComponent` | **Do not reuse** for rows. Different chrome, independent receipts. |
| Sibling dropdown pattern | `HelpMenuComponent` | Match `icon-button`, `absolute right-0 mt-2`, `dropdown-panel`, header `px-4 py-3 border-b border-border-subtle`. |
| Page empty card | `EmptyStateComponent` | **Do not use.** Keep the stub’s compact empty. |
| Stimulus | `notifications_menu_controller.js` (existing) | Targets stay `panel` + `trigger`. No new actions required if Learn more is a sibling. Do **not** add a second notifications controller. |
| Shared peer helper | `controllers/shared/topbar_menu.js` | Unchanged. |

`NotificationsButtonComponent` initializes with the same viewer overrides the banner uses (`user:`, `customer_id:`) so specs can inject Current-less context. Default to `Current.user` / `Current.customer_id`.

---

## 5. Tailwind & Stimulus notes

### Tailwind (match admin chrome; no new CSS file)

| Token / utility | Use |
|---|---|
| `.icon-button` | Bell trigger (34×34, `text-text-muted` → hover `text-text-secondary` + `bg-surface-active`) |
| `.dropdown-panel` | Panel surface (`bg-surface`, `border-border`, `rounded-xl`, `shadow-float`) |
| `w-96 max-w-[calc(100vw-2rem)]` | Panel width (locked) |
| `absolute right-0 mt-2 z-40` | Panel position (locked right-align) |
| `border-border-subtle` | Header rule + row dividers |
| `text-text-primary` / `text-text-secondary` / `text-text-muted` | Title / unread body / read + empty subtitle |
| `text-accent-text` | Learn more |
| `bg-accent` | Unread status dot |
| `bg-danger text-white` | Unread count pill |
| `bg-surface-hover` | Row hover + empty icon well |
| `line-clamp-3` | Body truncation (~3 lines) |
| `size-1.5` | Dot / spacer (equal width/height) |
| `flex` + `gap-*` | Stacks. **No** `space-y-*` / `space-x-*` |
| `tabular-nums` | Badge count |
| `transition-base` | Row hover |

Do **not** add custom CSS. Do **not** use raw `bg-red-500` / `bg-blue-500`. Do **not** copy banner `bg-info` / `bg-warning` / `bg-danger` strips into the panel.

Responsive: the viewport `max-w` is the mobile treatment. No separate bottom-sheet. Topbar already collapses search; the bell stays an icon button at every breakpoint.

### Stimulus

Existing `notifications-menu` remains the **only** controller on this surface.

| Kind | Name | Role |
|---|---|---|
| target | `trigger` | Bell `<button>` — `aria-expanded` |
| target | `panel` | Dropdown shell (header + body wrapper). **Not** the turbo-replaced body. |
| action | `toggle` | `click->notifications-menu#toggle` on the bell |
| action | `close` | outside click, Escape, peer open (already wired) |

**Do not add** values for copy (no JS-owned strings). **Do not add** a mark-read action in JS — that is `button_to` + Turbo.

Learn more: sibling link + `data-turbo="false"`. If a future markup change nests the link inside the submit button, that is a bug — fix the markup, do not paper it over with a new controller.

`app/javascript/**` stays at 100% Vitest. Extending this controller is **not** required; if you touch it, cover the new branch.

### Turbo replace targets (locked)

| id | What it wraps | When replaced |
|---|---|---|
| `notifications-badge` | Count pill **or** empty | After every successful mark-read |
| `notifications-panel-body` | Inbox list **or** empty state | After every successful mark-read |

Never replace:

- `[data-controller="notifications-menu"]`
- `[data-notifications-menu-target="panel"]`

An open dropdown must survive the stream (no flash-close, no lost `aria-expanded`).

### I18n (exact English = would-have-been hard-coded)

**Existing (do not change copy):**

| Key | en | zh-CN (already present) |
|---|---|---|
| `chrome.notifications.title` | Notifications | 通知 |
| `chrome.notifications.caught_up_html` | You're all caught up | 您已查看全部内容 |
| `chrome.notifications.empty` | No new notifications right now. | 暂无新通知 |

**New (both locales required):**

| Key | en | zh-CN |
|---|---|---|
| `chrome.notifications.unread_titled` | Notifications, %{count} unread | 通知，%{count} 条未读 |
| `chrome.notifications.mark_read` | Mark as read | 标为已读 |

**Reuse, do not duplicate:**

| Key | en |
|---|---|
| `comp_platform.announcement_banner.learn_more` | Learn more |

Stimulus: no new Values. Server-passed `aria-label` / `button_to` aria on the ERB.

### Out of scope for this UX

- Changing banner cap, severity order, or dismiss persistence.
- Action Cable / live badge without reload.
- Email/SMS of the same notice.
- Member or public bells.
- Markdown/HTML/images in the row body (plain text + `line-clamp-3`, same as banner body).
