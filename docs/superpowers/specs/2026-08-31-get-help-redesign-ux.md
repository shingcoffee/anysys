# Get Help redesign — UX

## Surface inventory

- Help menu dropdown (admin chrome) — Notify / Email / Docs
- Notify dialog (modal) — subject, message, image dropzone with previews
- Email dialog (modal) — subject, message, attachment dropzone with previews
- Requester thread page `/:cid/admin/help_requests/:id`
- Owner queue index + thread `/81721200/admin/maintenance/platform/help_requests`
- Unified bell rows for help tickets (alongside announcements)

## Help menu

```
[ ? ]
  ┌─────────────────────────────┐
  │ Notify platform owner       │  (hidden for platform owner)
  │   Screenshots in the app    │
  │ Email support               │
  │   help@anysys.com           │
  │ Documentation          ↗    │
  │   Guides & how-tos          │
  └─────────────────────────────┘
```

Width `w-72`. Same dropdown-panel / icon-button language as today. Docs opens a new tab.

## Notify / Email dialogs

Centered modal (`max-w-lg`), overlay `bg-slate-900/40`, sticky header with title + close, form body, sticky footer Cancel / Send.

Notify: subject input, message textarea (min 6 rows), image dropzone (`image/jpeg,image/png,image/gif,image/webp`, max 5, 5MB) with thumbnail strip + remove.

Email: same plus PDF in accept. Helper line: “Sent to help@anysys.com”.

Empty submit: inline field errors. Success: close dialog, flash notice.

## Requester thread

AdminPage: breadcrumb Dashboard / Help request. Title = subject. Badge open/resolved.

Card thread: each message is author name, role chip (You / Platform), timestamp, body, image gallery.

If open: reply composer (textarea + image dropzone + Send). If resolved: muted “This request is resolved.”

## Owner queue

AdminPage + AdminTable. Columns: subject, customer, requester, status, last message. Search by subject. Filter status. Row → show.

Show: same thread as requester plus customer name/id, requester email, Resolve (open only). Reply composer uses `author_role: owner`.

Empty index: “No help requests yet.”

## Bell help row

Same layout as announcement rows. Title = subject. Body = latest message clipped 3 lines. Unread: accent dot + mark-read then navigate. Kind chip optional (“Help”). Owner rows include customer name in the subtitle.

## Stimulus

- `help-menu`: panel toggle, open notify/email dialogs, Escape/outside/peer close. Values for i18n error strings.
- `help-attachments`: file input change → preview thumbnails, enforce max files/types, remove chip, disable submit when over limit. English `default:` values; server passes translated strings.

## I18n

All labels/errors in `chrome.en.yml` / `chrome.zh-CN.yml` (menu + dialogs + bell) and `maint_platform.*.yml` (queue). No hard-coded user-facing strings.
