# Person entry ↔ user account — UX spec (phase 1)

Date: 2026-10-27
Audience: `admin` or `owner` on the existing entry detail page.
Nav area: **admin** — Entries & Records (`/:cid/admin/entities/:entity_id/entries/:id`).
Not Settings / Maintenance / member / public. No new route chrome.

Behaviour: an entity with `extended_model == "Authentication::User"` is a person entity. Each `EntityEntry` may link to **one** same-tenant `Authentication::User`. This spec covers the Account card only.

shadcn patterns consulted: **Card**, **Badge**, **Command / Combobox**, **Alert Dialog**. Mapped onto existing ViewComponents and tokens below — do not introduce React/Radix.

---

## 1. Surface inventory

| Surface | Mount | Nav area | When shown |
|---|---|---|---|
| Account card | Inside `Admin::Entities::EntryDetailComponent` aside | admin (Entries) | Person entities only |
| User picker (combobox popover) | Inside the Account card | admin | Writable + not linked |
| Link confirm strip | Replaces the picker in the same card | admin | After a candidate is chosen |
| Unlink confirm | Native Turbo confirm (no new dialog) | admin | Writable + linked |
| Flash notice/alert | Existing admin flash (layout, not this card) | admin | After POST/DELETE redirect |

One page, one new card. No new screens, no member/public surface in phase 1.

---

## 2. Placement (relative to EntryDetailComponent)

The entry body is already:

```
grid
  main   → attribute-group cards, then association cards
  aside  → Record details, then (lg+) section index
```

**Insert the Account card as the first child of the aside**, above Record details.

When the Account card is present, give the aside `order-first lg:order-none` so mobile (single column) shows Account immediately under the page header. Do **not** change aside order for non-person entities.

```
Desktop lg+
┌─────────────────────────────┬──────────────────────┐
│ Attribute group cards       │ Account              │
│ Association cards           │ Record details       │
│                             │ Sections (lg only)   │
└─────────────────────────────┴──────────────────────┘

Mobile
┌────────────────────────────────────────────────────┐
│ Account                                            │
│ Attribute group cards …                            │
│ Record details                                     │
└────────────────────────────────────────────────────┘
```

Do not put the picker in `AdminPageComponent` actions. Edit / Delete stay in the page header.

---

## 3. Layout spec — Account card

### 3.1 Chrome (all states)

Match the sibling **Record details** card, not `CardComponent` (that sibling is a raw `section.card`).

```
<section class="card overflow-hidden" aria-labelledby="entry-account-heading">
  header: border-b border-border-subtle px-4 py-3.5 sm:px-5
          flex items-center justify-between gap-3
    h2#entry-account-heading  text-sm font-semibold text-text-primary
    BadgeComponent size: :sm
  body: px-4 py-4 sm:px-5 space-y-3
</section>
```

No icon tile (Record details has none). Badge sits in the header row.

### 3.2 State A — Not linked, writable

```
┌ Account                         [Not linked] ┐
│ Linking lets this person sign in and see     │
│ their own record in the member area.         │
│                                              │
│ [ Link user account ]                        │
│                                              │
│ ▾ picker (hidden until open)                 │
└──────────────────────────────────────────────┘
```

- Badge: `BadgeComponent` `variant: :default` `size: :sm` → “Not linked”
- Helper: `text-sm text-text-muted` (one short paragraph)
- Primary action: `ButtonComponent` `variant: :secondary` `size: :sm`
  classes: `min-h-11 w-full sm:w-auto` (same tap target as entry Edit)
- Picker closed by default

**Empty / loading / error** for the card itself: none. The page already rendered. Picker states live inside the popover (§4).

### 3.3 State B — Linked, writable

```
┌ Account                            [Linked] ┐
│ Ada Lovelace                    [Deactivated]│  ← Deactivated only if inactive
│ ada@example.com                              │
│ This account is deactivated and cannot       │  ← muted note, inactive only
│ sign in.                                     │
│                                              │
│ [ Unlink ]                                   │
└──────────────────────────────────────────────┘
```

Data → fields:

| UI | Source |
|---|---|
| Full name | `user.full_name` (`first_name` + `last_name`.strip). If blank, `user.display_name` (email) |
| Email | `user.email` — `text-sm text-text-muted break-words [overflow-wrap:anywhere]` |
| Deactivated badge | `user.inactive?` — `BadgeComponent` `variant: :warning` `size: :sm` |
| Deactivated note | same condition — `text-xs text-text-muted` |

- Linked badge: `BadgeComponent` `variant: :success` `size: :sm`
- Name: `text-sm font-medium text-text-primary break-words [overflow-wrap:anywhere]`
- Phase 1: name is **plain text**, not a link to the Users module (that module may be off)
- Destructive action: `ButtonComponent` `variant: :ghost` `size: :sm`
  classes: `min-h-11 w-full text-danger hover:text-danger hover:bg-danger-subtle sm:w-auto`
  wrapped in `button_to` DELETE + `data: { turbo_confirm: t("comp_admin.person_link.unlink_confirm", name: user.full_name) }`
  This is the project Alert Dialog equivalent (same pattern as association-row delete and entry-header delete on this page). Do **not** add `QuickAddDialog` / a custom `<dialog>`.

### 3.4 State C — Read-only (entity inactive, bridge, or `writable: false`)

Same status display as A or B. **No** Link button, picker, or Unlink. Omit the helper CTA in A; keep the deactivated note in B if the linked user is inactive.

```
┌ Account                         [Not linked] ┐
│ —                                            │  ← no helper, no action
└──────────────────────────────────────────────┘

┌ Account                            [Linked] ┐
│ Ada Lovelace                    [Deactivated]│
│ ada@example.com                              │
│ This account is deactivated and cannot       │
│ sign in.                                     │
└──────────────────────────────────────────────┘
```

No loading skeleton. No error card — server failures after write use flash on redirect.

---

## 4. User picker (combobox)

shadcn **Command / Combobox**: search field + list + empty. Implement with Stimulus, not `SearchableSelectComponent` (static grouped options) and not `InlineSearchComponent` (global admin search).

### 4.1 Open / close

- Click **Link user account** → open panel, focus search, `aria-expanded="true"`
- Click outside, Escape, or Cancel on the confirm strip → close, clear query, return focus to the trigger
- Panel is **not** a full-screen dialog. It is a `dropdown-panel` anchored under the trigger, `absolute z-50 mt-1 w-full` of the card body. `max-h-64 overflow-y-auto` on the list.

### 4.2 Panel anatomy

```
┌──────────────────────────────────┐
│ 🔍 Search by name or email       │  input-field pl-9
├──────────────────────────────────┤
│ status (loading / empty / error) │  role="status" aria-live="polite"
│ Ada Lovelace                     │  role="option"
│ ada@example.com                  │
│ Grace Hopper                     │
│ grace@example.com                │
└──────────────────────────────────┘
```

Search row: same icon + `input-field pl-9` as `SearchableSelectComponent`. `autocomplete="off"`, `type="search"`.

**Debounce:** 250ms (`customer-search` wait). **Fetch when** `q.trim.length >= 2`. Shorter query does not hit the network.

GET `/:cid/admin/entities/:entity_id/entries/:entry_id/person_link/candidates?q=…`
`Accept: application/json`, `credentials: "same-origin"`.
Expect `{ "users": [ { "id", "name", "email" } ] }`. Server already filters to same-tenant **active** users not already linked to this entity.

### 4.3 List / status states

| Condition | UI |
|---|---|
| Open, query < 2 chars | `text-sm text-text-muted text-center py-6` — “Type a name or email to find an account.” List hidden. |
| In-flight | Small spinner (`size-5 animate-spin rounded-full border-2 border-border-strong border-t-accent`) + “Searching…” (`text-sm text-text-muted`). Reuse the Quick Add spinner language. |
| 200 + empty `users` | “No matching users” — same centered muted treatment as searchable-select `noResults` |
| Network / non-OK | “Could not load users. Try again.” `role="alert"` `text-sm text-text-muted text-center py-6`. Retry = type again (no extra button). |
| 200 + rows | `ul role="listbox"`. Each row is a `button type="button" role="option"`: name `text-sm font-medium text-text-primary`, email `text-xs text-text-muted truncate`. Padding `px-3 py-2.5`, `w-full text-left`. Hover/active: `bg-surface-hover`. Keyboard highlight: `bg-accent-subtle`. |

No avatars (no `Avatar` component in this app). No “already used” suffix — server excludes those users.

### 4.4 Choose → confirm → POST

Selecting a row (click or Enter) **does not POST yet**. Close the list, hide the trigger, show an in-card confirm strip (avoids stacking a dialog on a popover):

```
┌ Account                         [Not linked] ┐
│ Link this entry to Ada Lovelace              │
│ (ada@example.com)?                           │
│                                              │
│ [ Cancel ]              [ Link ]             │
└──────────────────────────────────────────────┘
```

- Body: `text-sm text-text-primary`
- Cancel: `ButtonComponent` `variant: :ghost` `size: :sm` → back to empty picker (re-open search)
- Link: `ButtonComponent` `variant: :primary` `size: :sm` → submit the POST form (`user_id` hidden field)
- Mobile: `flex flex-col-reverse gap-2`; `sm:flex-row sm:justify-end sm:gap-2`. Both `min-h-11 w-full sm:w-auto`.

POST `/:cid/admin/entities/:entity_id/entries/:entry_id/person_link` with `user_id`. Rails `form_with` (CSRF). Server redirects back to the entry page with flash.

### 4.5 Unlink

DELETE same path. `turbo_confirm` copy states **both the entry and the account are kept**. On confirm, Turbo submits; redirect + flash.

---

## 5. Interaction flows

Start URL (all stories): `/:cid/admin/entities/:entity_id/entries/:id`

### 5.1 Link a user

1. Admin opens a person-entity entry (writable). Account card shows **Not linked**.
2. Clicks **Link user account**. Picker opens; focus in search.
3. Types ≥ 2 characters. After 250ms, GET candidates.
4. Sees name + email rows. Arrow keys move highlight; Enter or click chooses.
5. Confirm strip shows chosen name/email. **Cancel** returns to step 2. **Link** POSTs.
6. Redirect to the same entry URL. Card now **Linked**. Flash notice.

Failure:

| Failure | Outcome |
|---|---|
| Validation / user already taken / not found | Redirect, flash **alert**, card unchanged |
| 403 / wrong tenant | Existing admin denial (redirect or 403). No picker-specific UI |
| Candidates 4xx/5xx or network | Picker error state; card stays Not linked |
| Entity not writable | Card is read-only; no trigger |

### 5.2 Unlink

1. Linked + writable. Clicks **Unlink**.
2. Browser/Turbo confirm: “Unlink this entry from {name}? The entry and the account are both kept.”
3. Cancel → no request. Confirm → DELETE → redirect. Card **Not linked**. Flash notice.

### 5.3 Deactivated linked user

Linked user `status: inactive`. Card still **Linked**. Extra warning badge + muted note. Unlink still available when writable. Picker never lists inactive users.

### 5.4 Read-only

Inactive entity or bridge (`writable: false`). Status only. Keyboard users never tab into Link/Unlink.

---

## 6. Component reuse map

| Piece | Reuse | Notes |
|---|---|---|
| Page chrome | `AdminPageComponent` | Unchanged |
| Entry body | `Admin::Entities::EntryDetailComponent` | Render the new card first in the aside; pass `person_user:` (or nil) + existing `writable` |
| Account card | **New** `Admin::Entities::PersonLinkComponent` | Props: `entity:`, `entry:`, `user:` (nil if unlinked), `writable:` |
| Status badges | `BadgeComponent` | default / success / warning |
| Link / Unlink / Cancel / confirm Link | `ButtonComponent` | secondary / ghost / ghost / primary |
| Picker | **Do not** reuse `SearchableSelectComponent`, `InlineSearchComponent`, `QuickAddDialogComponent` | Wrong data / wrong chrome |
| Unlink confirm | `data-turbo-confirm` | Same as `comp_admin.entries_table.delete_entry_confirm` on this page |
| Flash | Existing layout flash | Keys listed in §8; controller sets them |

No new layout component. No `CardComponent` on this card (keep sibling Record card markup).

---

## 7. Tailwind & Stimulus

### 7.1 Tailwind (match existing admin cards)

- Card: `card overflow-hidden`
- Header: `flex items-center justify-between gap-3 border-b border-border-subtle px-4 py-3.5 sm:px-5`
- Title: `text-sm font-semibold text-text-primary`
- Body: `space-y-3 px-4 py-4 sm:px-5`
- Helper / email / notes: `text-sm` or `text-xs` + `text-text-muted`
- Name: `text-sm font-medium text-text-primary break-words [overflow-wrap:anywhere]`
- Actions: `min-h-11` always; `w-full sm:w-auto`
- Picker: `dropdown-panel absolute z-50 mt-1 w-full`
- Search: `input-field pl-9`
- Option hover: `hover:bg-surface-hover`; active option `bg-accent-subtle`
- Focus: rely on `input-field` / `btn` focus rings; options `focus-visible:bg-accent-subtle`
- No custom CSS. No indigo/gray leftovers from older selectors — use text-*/surface-* tokens.

### 7.2 Stimulus — `person-link-picker`

File: `app/javascript/controllers/person_link_picker_controller.js`
Identifier: `person-link-picker`
Mount only in State A (writable + not linked) on the card root.

**Targets**

| Target | Element |
|---|---|
| `trigger` | Link user account button |
| `panel` | Popover |
| `search` | Combobox input |
| `list` | `role="listbox"` |
| `status` | Live region (type-to-search / loading / empty / error) |
| `confirm` | Confirm strip (hidden until a user is chosen) |
| `confirmName` | Chosen name in the confirm copy |
| `form` | POST form |
| `userId` | Hidden `user_id` |

**Values**

| Value | Type | Default (English, byte-identical) |
|---|---|---|
| `candidatesUrl` | String | (required, from `person_link_candidates_path`) |
| `wait` | Number | `250` |
| `minQuery` | Number | `2` |
| `typeToSearchLabel` | String | `Type a name or email to find an account.` |
| `loadingLabel` | String | `Searching…` |
| `emptyLabel` | String | `No matching users` |
| `errorLabel` | String | `Could not load users. Try again.` |
| `confirmTemplate` | String | `Link this entry to {name} ({email})?` |

Server passes translated strings via `data-person-link-picker-*-value="<%= t(...) %>"`. Interpolate `{name}` / `{email}` with `.replace()` — no literals in JS.

**Actions**

| Action | Binding |
|---|---|
| `open` | `click->person-link-picker#open` on trigger |
| `query` | `input->person-link-picker#query` on search |
| `keydown` | `keydown->person-link-picker#keydown` on search |
| `select` | click on option (delegated) |
| `cancel` | Cancel on confirm strip |
| `close` | Escape / outside click |

`connect`/`disconnect`: debounce timer, document click-outside, abort in-flight `fetch` on disconnect.

---

## 8. Copy — `comp_admin.person_link.*`

English is the would-have-been hard-coded string. zh-CN is idiomatic (full-width punctuation, canonical terms). Reuse `common.actions.cancel` for Cancel. Do **not** reuse `common.status.inactive` (“Inactive”) for the deactivated badge — the requested word is “Deactivated”.

### en (`config/locales/comp_admin.en.yml`)

```yaml
person_link:
  heading: "Account"
  badge_not_linked: "Not linked"
  badge_linked: "Linked"
  badge_deactivated: "Deactivated"
  helper: "Linking lets this person sign in and see their own record in the member area."
  link_action: "Link user account"
  unlink_action: "Unlink"
  search_placeholder: "Search by name or email"
  search_aria: "Search users"
  listbox_aria: "Matching users"
  type_to_search: "Type a name or email to find an account."
  searching: "Searching…"
  empty: "No matching users"
  error: "Could not load users. Try again."
  confirm_body: "Link this entry to {name} ({email})?"
  confirm_submit: "Link"
  unlink_confirm: "Unlink this entry from %{name}? The entry and the account are both kept."
  deactivated_note: "This account is deactivated and cannot sign in."
  flash:
    linked: "Linked to %{name}."
    unlinked: "Account unlinked. The entry and the account were both kept."
    failed: "The account could not be updated."
```

`confirm_body` uses `{name}` / `{email}` because it is a Stimulus Value. `unlink_confirm` and flash use `%{name}` because they are server-rendered.

### zh-CN (`config/locales/comp_admin.zh-CN.yml`)

```yaml
person_link:
  heading: "账户"
  badge_not_linked: "未关联"
  badge_linked: "已关联"
  badge_deactivated: "已停用"
  helper: "关联用户账户后，此人即可登录，并在会员端查看自己的记录。"
  link_action: "关联用户账户"
  unlink_action: "取消关联"
  search_placeholder: "按姓名或邮箱搜索"
  search_aria: "搜索用户"
  listbox_aria: "匹配的用户"
  type_to_search: "输入姓名或邮箱以查找账户。"
  searching: "正在搜索…"
  empty: "没有匹配的用户"
  error: "无法加载用户，请重试。"
  confirm_body: "将此条目关联到 {name}（{email}）？"
  confirm_submit: "关联"
  unlink_confirm: "取消此条目与「%{name}」的关联？条目和账户都会保留。"
  deactivated_note: "此账户已停用，无法登录。"
  flash:
    linked: "已关联到%{name}。"
    unlinked: "已取消账户关联。条目和账户均已保留。"
    failed: "无法更新账户关联。"
```

Cancel button: `t("common.actions.cancel")` / 取消. Do not duplicate.

---

## 9. Accessibility

Follow the WAI-ARIA **combobox** pattern (shadcn Command / Combobox):

| Element | Roles / ARIA |
|---|---|
| Search input | `role="combobox"` `aria-expanded` `aria-controls="<list id>"` `aria-autocomplete="list"` `aria-activedescendant` (option id or empty) `aria-label` = `search_aria` |
| List | `role="listbox"` `id` `aria-label` = `listbox_aria` |
| Row | `role="option"` `id` `aria-selected="true|false"` |
| Status | `role="status"` `aria-live="polite"` `aria-atomic="true"` |
| Error | `role="alert"` |
| Card | `aria-labelledby="entry-account-heading"` |
| Trigger | `aria-expanded` `aria-haspopup="listbox"` `aria-controls` panel |

Keyboard:

| Key | Behavior |
|---|---|
| Arrow Down / Up | Open if closed; move highlight; update `aria-activedescendant`; `scrollIntoView({ block: "nearest" })` |
| Enter | If a row is highlighted, select it (go to confirm). Do not submit the page. |
| Escape | Close picker or dismiss confirm → focus trigger |
| Tab | Close picker; focus moves on. Do not trap focus (this is a combobox, not a modal). |
| Home / End | Optional: first / last visible option |

Focus management:

- Open → focus search
- Close / Cancel → focus trigger
- After choosing a row → focus the primary **Link** button on the confirm strip

Hit targets: `min-h-11` on every action (`pointer-coarse` friendly). Options `py-2.5` so rows are ≥ 44px.

Do not use `aria-modal` on the popover. Unlink uses the browser/Turbo confirm; no extra dialog to trap.

---

## 10. Out of scope (phase 1)

- Creating a user from the picker
- Linking to inactive users
- Relink / change-user without unlink
- Deep link to `/admin/modules/authentication/users/:id`
- Member-area “my record” UI
- Showing the Account card on non-person entities
