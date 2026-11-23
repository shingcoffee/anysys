# AI Assistant workspace — visual refactor

Date: 2026-09-14
Audience: `admin` or `owner` at `GET /:cid/admin/assistant`
Nav area: **admin** (top-level chrome, not a module Settings / Maintenance surface)
Status: ready for frontend

This is a visual/structural pass on the existing studio. It does **not** add capabilities, routes, models, or Stimulus controller APIs. It keeps the 2026-09-08 studio decisions that still hold (flush split, living preview, unboxed successful assistant replies, preview always on at `lg+`) and fixes what the current screenshots and markup actually get wrong.

Source markup (do not invent new wrappers around these):

- `Admin::Assistants::WorkspaceComponent`
- `AiAssistant::ConversationListComponent`
- `AiAssistant::AssistantPanelComponent`
- `AiAssistant::MessageComponent` / `DraftMessageComponent` / `ProgressComponent`
- `AiAssistant::ArtifactPaneComponent` / `ArtifactPreviewDialogComponent`
- `SpeechToText::DictateFieldComponent` (composer layout)
- `ButtonComponent`, `BadgeComponent`

---

## 1. Critique (current)

Prioritized from what the 1440 / 390 / empty / thread / mentions / attachment / phone-chats-open shots actually show. The pre-fix clipping on `desktop-1440.png` is ignored.

### P0 — Phone chrome eats the transcript

On 390 the stack is: Conversation/Preview pills → Chats + New chat → Show chats disclosure → AI Assistant header → composer. With chats closed the thread still has maybe two bubbles of air. With chats open (`phone-chats-open.png`) the list becomes the page; the last user turn is crushed under the composer and the greeting/transcript disappear.

The disclosure is the right pattern, but (a) “Chats” + “New chat” + “Show chats” are three chrome rows for one job, (b) the expanded list has no max-height, (c) the chevron never rotates even though `aria-expanded` already flips.

### P0 — Three empty states do not read as one studio

| State | What the shots show | Problem |
|---|---|---|
| Empty thread | Centered sparkle + “Hello, {name}” at `text-2xl/3xl`, then “Try asking” cards, then recent chips | Sparkle duplicates the panel header icon. Greeting is hero-sized on an admin canvas. Prompt cards are white-on-white (`bg-surface` + `ring-border-subtle`) so they look like empty placeholders. “Try asking” is left-aligned inside a centered column — the axis flips twice. |
| Empty preview | Large `bg-canvas` void, small icon, “Nothing to preview yet”, three pill chips | Occupies ~40% of 1440 with almost no hierarchy. Kind pills use the same rounded-full + ring language as the **actionable** recent chips, so they look clickable and aren’t. |
| Empty chats | Caption “No chats yet.” | Fine. Not the problem. |

On an empty new thread the right pane is a dead column. That is acceptable (preview stays mounted at `lg+`), but it must feel like a waiting partner, not an unfinished page.

### P1 — Chat rail is louder than the conversation

`New chat` is `ButtonComponent` `variant: :primary` — the most saturated object on the 1440 shot, louder than Send. Kebab triggers are always visible, so every row has a persistent “…” that competes with the title. `xl:w-60` truncates real titles (“Create a Student entity…”) to a stub. Active row treatment (`bg-accent-subtle` + `ring-accent-muted/60`) is the one part that already works.

### P1 — Thread rhythm and bubble family

Locked 2026-09-08 decision still holds: **successful assistant replies stay unboxed markdown**. What the thread shot actually shows is a different family:

- User: compact `bg-accent-subtle` pills, right-aligned — correct.
- Failed assistant: full `bg-danger-subtle` rounded-2xl pills — the loudest objects in the column. In the current fixture they *are* the conversation.
- Successful assistant: unboxed (correct when present) but the author row + `mt-6` avatar create a tall, loose cadence (`gap-6` between turns).
- User “hi” is a tiny orphan pill; failures read as the primary content.

Failed must stay danger-colored. They should not impersonate a third bubble type that outranks the user.

### P1 — Composer is the best piece; its neighbors fight it

The elevated `rounded-2xl shadow-elevated` well is right. Issues around it:

- Footer dock is `bg-surface` — same as the well — so the composer does not lift; it looks like a boxed hole in a white page.
- Mention menu (`mentions.png`) covers the prompt grid with a flat white list. Selected/hover classes in JS are `bg-surface-muted` / `hover:bg-surface-muted` — **that token does not exist** (`surface-hover` / `surface-active` do). Kind is raw caption, not a badge.
- Attachment chip (`attachment.png`) is correct and quiet. Keep the shape; only tighten token use.
- Mic in `DictateFieldComponent` is `size-8`; attach/send are `size-9 !rounded-full`. The action row is visually uneven.

### P2 — The two panes do not share a header rhythm

Conversation header: sparkle + title + `what` subtitle (`hidden` below `sm`) + regenerate. Preview header: monitor icon + “Preview” and nothing else when empty. Heights roughly match, but the conversation subtitle makes the left header heavier, and `what` repeats the empty-state job. On phone the header is a full row for a title the page chrome already announced.

### P2 — Desktop split is preview-heavy when idle

`lg:grid-cols-[minmax(0,1.25fr)_minmax(26rem,1fr)]` gives an idle preview almost half the studio. The empty canvas then dominates 1440.

---

## 2. Surface inventory

| Surface | URL / mount | nav_area | Change? |
|---|---|---|---|
| Studio shell (tabs + 2/3-col grid + offline) | `/:cid/admin/assistant` | admin | Yes — grid ratio, phone tab compacting |
| Chat list rail / disclosure | inside conversation column | admin | Yes — chrome collapse, density, New chat quiet |
| Conversation panel (header, empty, thread, composer) | same | admin | Yes — header, empty, composer dock, mention classes |
| Message / draft / progress | thread | admin | Yes — failed tone, turn gap; success stays unboxed |
| Preview pane + enlarge dialog | right pane / `<dialog>` | admin | Yes — empty-state language; filled/dialog mostly stay |
| Dictate field (composer layout) | composer | admin | Yes — icon size only |
| Offline empty (module off) | same URL | admin | **No** |

No Settings, Maintenance/Modules, or Maintenance/Platform surfaces.

---

## 3. Layout spec per surface

Breakpoints stay exactly:

| Width | Layout |
|---|---|
| `< lg` (390, 768) | One column. Conversation \| Preview tablist. Chat list is a disclosure above the transcript. |
| `lg`–`xl` (1024–1279) | Two columns: conversation \| preview. Chat list still a disclosure strip on the conversation column. |
| `≥ xl` (1280, 1440+) | Three columns: chat rail \| transcript \| preview. |

### 3.1 Studio shell — `Admin::Assistants::WorkspaceComponent`

#### ASCII — `≥ xl`

```
+--[topbar + admin menu, unchanged]----------------------------------+
| CHATS          | AI Assistant                    | Preview         |
| [New chat]     | (slim header, no subtitle)      | (slim header)   |
| · current      |                                 |                 |
| · …            |  thread  OR  empty greeting     |  waiting empty  |
| Archived ▸     |                                 |  OR thumbnail   |
|                | --------------------------------|                 |
|                | [ composer well on canvas dock ]|                 |
+----------------+---------------------------------+-----------------+
```

#### ASCII — `< lg`

```
+--[topbar]------------------------+
| ( Conversation )  Preview        |   pill tablist, compact
+----------------------------------+
| [ Show chats ▾ ]     [ New chat ]|   ONE chrome row (h2 sr-only)
| (list, max-h-52, scrolls)        |   only when expanded
+----------------------------------+
| AI Assistant            [regen]  |   slimmer header
| transcript / empty               |
| [ composer well ]                |
+----------------------------------+
```

#### Classes to apply

Root (unchanged): `flex h-full min-h-0 flex-col bg-surface`

Mobile tablist strip:

```
shrink-0 border-b border-border-subtle bg-canvas px-3 py-2 lg:hidden
```

(was `py-2.5` — save 4px.) Inner track stays `mx-auto grid max-w-sm grid-cols-2 rounded-full bg-surface-active p-1`. Tab selected / idle classes stay as they are (including the artifact `size-1.5 rounded-full bg-accent` dot).

Studio grid — **chat-heavier**, preview still has a floor:

```
grid min-h-0 flex-1 grid-cols-1
lg:grid-cols-[minmax(0,1.45fr)_minmax(24rem,0.9fr)]
xl:grid-cols-[minmax(0,1.5fr)_minmax(26rem,0.85fr)]
```

Conversation section (unchanged structure): `relative flex min-h-[70dvh] min-w-0 flex-col overflow-hidden bg-surface lg:flex lg:min-h-0`

Chat-list wrapper — slightly wider rail, same canvas ground:

```
shrink-0 border-b border-border-subtle bg-canvas px-3 py-2 xl:w-64 xl:overflow-y-auto xl:border-b-0 xl:border-r
```

(`py-2.5` → `py-2`, `xl:w-60` → `xl:w-64`.)

Preview aside (unchanged): `hidden min-h-[70dvh] min-w-0 flex-col overflow-hidden bg-canvas lg:flex lg:min-h-0 lg:border-l lg:border-border-subtle`

Keep every id / `role` / `data-assistant-workspace-*` / `data-dashboard-region` exactly.

#### Empty / loading / error

- Offline branch: **do not touch**.
- Loading: still server HTML + Turbo. No skeleton.
- Permission denied: existing admin auth. No new flash.

#### Actions

None at the shell. Primary/secondary live in the list, panel, and preview.

---

### 3.2 Chat list — `AiAssistant::ConversationListComponent`

#### Regions

| Region | Data | Display |
|---|---|---|
| Heading | — | `t("...conversations.title")` (“Chats”) — visible `≥ xl`, `sr-only` below |
| New chat | POST create | `ButtonComponent` **`variant: :secondary`** `size: :sm` (Send stays the only primary in the studio) |
| Toggle | — | Visible `< xl` only. Label flips with CSS (see i18n). Chevron rotates via `aria-expanded`. |
| Active rows | `display_title`, `last_active_at` | Title `text-sm font-medium truncate`; time `text-caption` |
| Archived | same, capped at 20 | Existing disclosure |
| Kebab | rename / archive / delete | `dropdown-panel`; pointer-fine hover/focus reveal |

#### Chrome — one row at every breakpoint

Replace the current stacked “heading row + toggle button” with a single flex row:

```erb
<div class="flex items-center gap-2">
  <h2 class="sr-only xl:not-sr-only xl:min-w-0 xl:flex-1 xl:truncate text-label">Chats</h2>
  <button id="toggle" class="... xl:hidden flex-1 ... group">Show / Hide</button>
  <%= ButtonComponent secondary sm, create %>
</div>
```

Toggle button classes (keep id, `aria-controls`, `aria-expanded`, `data-action`):

```
flex min-h-10 flex-1 items-center justify-between gap-2 rounded-lg bg-surface px-2.5 text-sm font-medium text-text-secondary ring-1 ring-border-subtle transition-base hover:bg-surface-hover hover:text-text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent pointer-coarse:min-h-11 xl:hidden
```

Chevron svg — add `transition-base group-aria-expanded:rotate-180` (button gets `group`). No Stimulus change; `#toggle` already sets `aria-expanded`.

Toggle label — two spans, CSS-swapped (new key `toggle_hide`):

```
<span class="group-aria-expanded:hidden"><%= t("...toggle") %></span>
<span class="hidden group-aria-expanded:inline"><%= t("...toggle_hide") %></span>
```

#### Expanded list below `xl`

Panel (`#ai_assistant_conversations_panel`) gains a cap so the composer never leaves the viewport:

```
hidden flex-col gap-3 xl:flex
max-h-52 overflow-y-auto xl:max-h-none
```

`max-h-52` (13rem) is enough for ~4 rows + archived header. The rail at `xl` is already `xl:overflow-y-auto` on the wrapper — do not double-cap there (`xl:max-h-none`).

#### Row

Keep `row_classes` logic. Only change the kebab visibility and the row `group` so hover-reveal works.

Row `<li>`: add `group/chat`.

Kebab `<summary>`:

```
flex size-8 cursor-pointer list-none items-center justify-center rounded-md text-text-muted transition-base
hover:bg-surface-active hover:text-text-primary
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent
pointer-coarse:size-11
pointer-fine:opacity-0 pointer-fine:group-hover/chat:opacity-100 pointer-fine:group-focus-within/chat:opacity-100
```

Same pattern as the message copy button. Touch (`pointer-coarse`) stays always-visible.

Menu panel classes stay `dropdown-panel absolute right-0 top-full z-20 mt-1 flex w-44 flex-col p-1`. Item classes stay.

Active row (unchanged, restated so it is not “improved” away):

```
bg-accent-subtle text-accent-text ring-1 ring-accent-muted/60
```

Idle:

```
text-text-secondary hover:bg-surface-hover hover:text-text-primary
```

#### Empty / error

- Empty active list: keep `px-2.5 py-3 text-caption` + `conversations.empty`.
- Rename / archive / delete failure: existing `conversations.failed` via the current Stimulus value. No new toast chrome.
- Delete confirm: existing `conversations.delete_confirm`.

#### Actions

| Kind | Action | Where |
|---|---|---|
| Secondary | New chat | Heading row, right |
| Secondary | Open chat | Row link |
| Secondary | Rename / Archive | Kebab |
| Destructive | Delete | Kebab, `text-danger hover:bg-danger-subtle` |

---

### 3.3 Conversation panel — `AiAssistant::AssistantPanelComponent`

#### Header

```
flex shrink-0 items-center gap-2.5 border-b border-border-subtle px-4 py-2.5 sm:px-5
```

(was `gap-3` / `py-3`.)

- Icon wrap stays `flex size-8 shrink-0 items-center justify-center rounded-xl bg-accent-subtle text-accent`. Hide the icon on the narrow column to reclaim width: add `hidden sm:flex`.
- **Drop the `what` subtitle from the header** (it duplicates the empty state and makes the left header taller than Preview). Keep `h2#ai-assistant-title`.
- Status slot and regenerate stay. Regenerated button classes stay `shrink-0 gap-1.5 text-text-muted`; label already `hidden sm:inline`.

`what` is unused in the header after this. Do **not** delete the locale key (other copy / future use). Do not relocate it into the empty state — `how` already covers orientation.

#### Empty thread

Keep the empty node and its id (`Stream::EMPTY_ID`), `usePrompt` cards, recent chips.

Root:

```
mx-auto flex min-h-full w-full max-w-2xl flex-col items-center justify-center px-1 py-4 text-center
```

(was `py-6`.)

**Remove the duplicate sparkle** above the greeting. The panel header already carries the mark. Greeting becomes the first visual.

Greeting `h3`:

```
text-xl font-semibold tracking-tight text-text-primary sm:text-2xl
```

(was `mt-5 text-2xl sm:text-3xl`.)

Lead `how`:

```
mt-2 max-w-md text-body-sm text-text-muted
```

Section labels (“Try asking”, “Recent…”) — keep `text-label`, but **center them** so they stop fighting the centered column:

```
mt-6 text-label
```

(drop `self-start`; was `mt-8`.)

Prompt cards — sit on canvas so they separate from the white panel:

```
group flex items-start gap-3 rounded-2xl bg-canvas p-3.5 text-left shadow-xs ring-1 ring-border-subtle transition-base hover:bg-surface hover:shadow-md hover:ring-accent-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent
```

Icon tile (unchanged hover):

```
flex size-8 shrink-0 items-center justify-center rounded-lg bg-surface text-text-tertiary transition-base group-hover:bg-accent-subtle group-hover:text-accent
```

Label / prompt typography unchanged (`text-xs font-semibold uppercase tracking-[0.06em] text-text-tertiary`, `text-sm leading-snug text-text-secondary`). Grid stays `mt-2.5 grid w-full grid-cols-1 gap-2.5 sm:grid-cols-2`.

Recent chips — unchanged classes. They stay the only rounded-full **buttons** in the empty state (preview kind “chips” will stop looking like this).

#### Thread

Scroll container (unchanged): `h-full overflow-y-auto px-4 py-6 sm:px-6` + `data-ai-assistant-target="thread"`.

Turn stack — tighten only:

```
mx-auto flex w-full max-w-3xl flex-col gap-4 py-1
```

and the live log `flex flex-col gap-4` (both were `gap-6`). Keep `role="log"` and all aria attributes.

Jump-to-latest: unchanged (`hidden` until Stimulus, `!rounded-full shadow-float`).

#### Composer dock

Wrap:

```
shrink-0 border-t border-border-subtle bg-canvas px-4 pb-4 pt-3 sm:px-6
```

(`bg-surface` → `bg-canvas` so the well lifts.)

Inner column stays `mx-auto w-full max-w-3xl`.

Attachment list / error: keep targets and `text-caption text-danger`. Attachment chips are JS-built — see §6.

Composer well (unchanged shape):

```
relative rounded-2xl bg-surface shadow-elevated ring-1 ring-border-subtle transition-base focus-within:ring-2 focus-within:ring-accent-muted
```

Mention menu — full well width, real tokens:

```
absolute bottom-full left-0 z-20 mb-2 hidden w-full overflow-hidden rounded-xl bg-surface shadow-float ring-1 ring-border-subtle
```

(was `max-w-sm shadow-elevated`. Drop the width cap so the menu aligns with the composer, as `mentions.png` currently undershoots.)

Keep `role="listbox"`, `mentionMenu` / `mentionList` targets, `aria-label` on the existing `mention_hint` key.

Textarea classes unchanged.

Hints row unchanged (`composer_hint` + `mention_hint` at `sm+`, turns hint).

#### Empty / loading / error

- Empty: greeting + how + cards + optional chips, as above.
- Streaming: existing draft + progress. No new pending chrome.
- Composer error: existing `#ai_assistant_composer_error` alert.
- Turns exhausted: existing placeholder / disabled send.
- Send / stop / connection-lost: existing keys, same slots.

#### Actions

| Kind | Action | Where |
|---|---|---|
| Primary | Send | Composer trailing, `size-9 !rounded-full` |
| Secondary | Stop (while running) | Same slot, already `hidden` until target swap |
| Secondary | Attach, mic | Same trailing row |
| Secondary | Prompt card / recent chip | Empty state, `usePrompt` |
| Secondary | Regenerate | Header, only when `regeneratable?` |
| Secondary | Jump to latest | Overlay on thread |

---

### 3.4 Messages — `MessageComponent` + `DraftMessageComponent` + `ProgressComponent`

Keep the DOM: `dom_id(message)`, `data-role`, `data-body`, copy button + `data-copy-idle` / `data-copy-done`, changes `<details>`.

#### Author row

Unchanged structure. Avatar on assistant stays `mt-6 flex size-7 … rounded-lg bg-accent-subtle text-accent ring-1 ring-accent-muted/40` so it still clears the author line.

#### User bubble (unchanged)

```
w-fit max-w-[min(88%,34rem)] rounded-2xl rounded-br-md bg-accent-subtle px-4 py-2.5 text-sm leading-6 text-accent-text ring-1 ring-accent-muted/70 whitespace-pre-line break-words
```

#### Successful assistant (unchanged — locked)

```
w-full max-w-[min(92%,42rem)] text-[15px] leading-7 break-words text-text-primary
```

plus existing `BUBBLE_MARKDOWN`. Draft `body_classes` must keep resolving to the same string so the swap does not reflow.

#### Failed assistant — quieter danger well

Today: `rounded-2xl bg-danger-subtle px-4 py-2.5 text-danger ring-1 ring-danger/15` (a sibling of the user pill).

Replace `ASSISTANT_TONES["failed"]` with:

```
w-full max-w-[min(92%,42rem)] rounded-xl bg-danger-subtle/80 px-3.5 py-2 text-sm leading-6 text-danger ring-1 ring-danger/10
```

Same copy, less radius, less padding, thinner ring. It reads as an inline alert under the author row, not as a chat bubble competing with “You”.

Cancelled stays:

```
rounded-2xl bg-canvas px-4 py-2.5 text-text-muted ring-1 ring-border-subtle
```

#### Progress

Unchanged caption list. Draft caret unchanged (`h-4 w-0.5 animate-pulse rounded-full bg-accent`).

#### Changes disclosure

Unchanged.

---

### 3.5 Preview pane — `ArtifactPaneComponent`

Header classes stay `shrink-0 border-b border-border-subtle bg-surface px-4 py-3 sm:px-5` so it matches the conversation header after that header loses its subtitle (both ~52px). Icon + title stay. Kind `BadgeComponent variant: :primary size: :sm` only when `resolved`. Actions (Open preview / Open details) stay in the header when resolved.

#### Empty (no artifact)

Do **not** add a dashed card (2026-09-08 locked “no dashed inner box”). Do change the kind “chips” so they stop impersonating the recent-chip buttons.

```
flex min-h-full flex-col items-center justify-center px-6 py-12 text-center
```

Icon wrap — quieter, still on canvas:

```
flex size-12 items-center justify-center rounded-2xl bg-surface text-text-muted shadow-xs ring-1 ring-border-subtle
```

Title: `mt-4 text-sm font-semibold text-text-primary` (existing `empty_title`).

Body: `mt-1.5 max-w-xs text-caption text-text-muted` (existing `empty`).

**Replace the `<ul>` of pills** with a single caption line of the existing kind labels, middot-separated, not interactive:

```
<p class="mt-5 text-caption text-text-tertiary">
  Entity<span aria-hidden="true"> · </span>Page<span aria-hidden="true"> · </span>Flowchart
</p>
```

Build it from `kind_labels` in the template (join with ` · `). No new i18n key. No `role="list"`. Not a `<button>`.

#### Non-visual artifact (entity / flowchart)

Keep the centered card:

```
flex w-full max-w-sm flex-col items-center gap-4 rounded-2xl bg-surface px-6 py-8 text-center shadow-xs ring-1 ring-border-subtle
```

Primary “Open details” stays.

#### Page thumbnail

Keep the faux browser (`rounded-2xl bg-surface shadow-elevated ring-1 ring-border-subtle`, traffic lights `bg-border-strong`, `view_larger` button). Do not restyle the iframe/scale math. Scroll hint stays `mt-2 text-center text-caption text-text-muted`.

#### Enlarge dialog

**No visual change.** Keep `<dialog>`, loading spinner, failure + Retry, footer actions.

#### Actions

| Kind | Action | Where |
|---|---|---|
| Secondary | View larger | Browser chrome + click-to-zoom viewport |
| Secondary | Open preview | Header + dialog footer |
| Primary (dialog footer / non-visual card) | Open details | Header + dialog + empty-visual card |
| Secondary | Close / Retry | Dialog |

---

### 3.6 Dictate field — composer layout only

Trailing action row:

```
flex items-center gap-2 px-2 pb-2
```

Mic `ButtonComponent`: change `size-8` → `size-9 shrink-0 !rounded-full !p-0 text-text-muted pointer-coarse:size-11` so it matches attach/send. Keep every `speech-to-text` target, `aria-pressed`, and icon swap svgs.

Inline (non-composer) layout: **do not touch**.

---

## 4. Interaction flow

No new user stories. Existing stories, with visual outcomes called out.

### US-1 — Open an empty workspace

1. `GET /:cid/admin/assistant` (module on, no messages in the current chat).
2. Desktop: three columns. Rail shows chats; center shows greeting (no second sparkle) + canvas prompt cards + composer on a canvas dock; preview shows waiting empty with caption kinds.
3. Phone: Conversation tab selected. One chats chrome row. Transcript/empty + composer visible without scrolling past a second header stack.

Failure (module off): unchanged offline card.

### US-2 — Browse chats on the phone

1. Start on Conversation tab.
2. Tap **Show chats** → `aria-expanded="true"`, label becomes **Hide chats**, chevron rotates 180°, list appears in a `max-h-52` scroller. Composer and at least the last turn stay on screen.
3. Tap a row → `GET /:cid/admin/assistant?conversation=:id` (existing `open_url`).
4. Tap **Hide chats** or the toggle again → list collapses.

Failure (rename/archive/delete): existing confirm / `conversations.failed`. No new dialog chrome.

### US-3 — Start a chat / send

1. **New chat** (secondary) → existing POST. Empty greeting.
2. Click a prompt card → composer fills (`usePrompt`), user sends via Enter / Send.
3. User bubble appears (accent). Draft + progress + caret stream in. Successful reply is unboxed markdown. Preview updates if an artifact is applied; Preview tab dot appears below `lg`.

Failure (vendor / extract): failed well (quieter danger). User can regenerate or retry. Composer error slot for send/stop/connection-lost.

### US-4 — Mention and attach

1. Type `@` → listbox opens **full composer width**, selected row `bg-accent-subtle`, hover `bg-surface-hover`. Arrow / Enter / click unchanged (`aria-activedescendant` stays).
2. Attach → chips above the well (`bg-canvas`, thumbnail + name + remove). Validation errors in the existing alert.

Failure: existing type/size/count copy.

### US-5 — Preview an artifact

1. After apply, desktop preview fills with thumbnail or non-visual card. Phone: Preview tab shows the accent dot; tap to switch `aria-selected`.
2. View larger → existing `<dialog>`. Open preview / Open details → `_blank`.

Failure: dialog failure panel + Retry.

### US-6 — Denied

Anonymous / `member` / cross-tenant admin: existing `RouteAuthorization`. No UI change.

---

## 5. Component reuse map

| Piece | Reuse | New? |
|---|---|---|
| Send / Stop / Attach / New chat / Regenerate / Jump / Offline CTA / Open details / Open preview / dialog close | `ButtonComponent` (variants as specified) | No |
| Artifact kind (when resolved) | `BadgeComponent` `variant: :primary` `size: :sm` | No |
| Kebab menu | existing `<details>` + `dropdown-panel` | No |
| Dictate | `SpeechToText::DictateFieldComponent` `layout: :composer` | No |
| Tabs / panels | existing `assistant-workspace` wiring | No |
| Studio / list / panel / message / artifact / dialog | existing ViewComponents | **No new component** |

Frontend implements class/structure changes **inside** the current components. Do not introduce `AiAssistant::EmptyStateComponent` or a new shell.

---

## 6. Tailwind & Stimulus notes

### Token vocabulary (use only these)

Ground: `bg-canvas`, `bg-canvas-elevated`, `bg-surface`, `bg-surface-hover`, `bg-surface-active`, `bg-accent-subtle`, `bg-danger-subtle`, `bg-accent`

Text: `text-text-primary`, `text-text-secondary`, `text-text-tertiary`, `text-text-muted`, `text-accent`, `text-accent-text`, `text-danger`

Line: `border-border-subtle`, `ring-border-subtle`, `ring-accent`, `ring-accent-muted`, `ring-danger/10`

Type: `text-label`, `text-caption`, `text-body-sm`, `text-sm`, `text-xl` / `text-2xl` (greeting only)

Elevation: `shadow-xs`, `shadow-md`, `shadow-elevated`, `shadow-float`

Motion: `transition-base`; `motion-reduce:animate-none` stays on pulses.

Do **not** use `bg-surface-muted`, `bg-gray-*`, `bg-indigo-*`, or any hex. Do not add `<style>` or new CSS framework classes.

### Stimulus — no API changes

Keep every current target / value / action on `assistant-workspace`, `ai-assistant-conversations`, `ai-assistant`, `speech-to-text`, `artifact-preview`.

CSS-only behavior that piggybacks existing aria:

- Chat toggle chevron: `group` + `group-aria-expanded:rotate-180`
- Chat toggle label swap: two i18n spans + `group-aria-expanded:hidden` / `group-aria-expanded:inline`
- Kebab reveal: `pointer-fine:opacity-0` + `group-hover/chat` / `group-focus-within/chat`

### Stimulus — class-string updates (not API)

These live in `app/javascript/controllers/ai_assistant_controller.js`. They do **not** rename targets. Vitest does not currently pin the broken `bg-surface-muted` string; still re-run coverage on this file.

**`#mentionRow` option.className** — replace the non-token:

```
flex w-full items-center justify-between gap-3 rounded-md px-3 py-2 text-left text-sm transition-base hover:bg-surface-hover
```

Selected (`index === this.mentionIndex`):

```
bg-accent-subtle text-accent-text
```

Kind cell stays `shrink-0 text-caption text-text-muted`. Label cell stays `truncate text-text-primary` (selected inherits accent-text from the row — acceptable). Empty row stays `px-3 py-2 text-caption text-text-muted`.

**`#renderPreviews` item.className**:

```
flex items-center gap-2 rounded-xl bg-canvas px-2 py-1 text-xs text-text-secondary ring-1 ring-border-subtle
```

(was `bg-surface` — chips sit on the new canvas dock.) Thumbnail `size-8 rounded object-cover` and remove-button classes stay.

No new targets. No new values. No new actions.

---

## 7. New i18n keys

Existing namespace: `ai_assistant.assistant.*` in `config/locales/ai_assistant.{en,zh-CN}.yml`.

Add **one** key. English is the string that would otherwise be hard-coded.

```yaml
# en
ai_assistant.assistant.conversations.toggle_hide: "Hide chats"

# zh-CN
ai_assistant.assistant.conversations.toggle_hide: "隐藏会话列表"
```

Parallel to existing `toggle: "Show chats"` / `"显示会话列表"`.

Do **not** change existing English values (`how`, `what`, `empty`, `placeholder`, `new`, prompt copy, etc.). Specs and the 2026-09-08 byte-identical lock stay intact. Unused-in-header `what` remains in the locale files.

---

## 8. Explicitly not changing (and why)

| Leave alone | Why |
|---|---|
| Stimulus controller APIs (targets, values, actions, param names) | 100% Vitest; every rename is test churn. CSS + two class strings are enough. |
| DOM ids (`assistant-*-tab/panel`, `ai-assistant-title`, `COMPOSER_ID`, `HINT_ID`, `MENTION_MENU_ID`, `ERROR_ID`, all `AiAssistant::Stream::*` ids, `PANEL_ID`, `TOGGLE_ID`, `dom_id(message)`, dialog `title_id`) | Turbo streams and a11y references. |
| `data-ai-assistant-target`, `data-action`, `data-prompt`, `data-conversation-id`, `data-dashboard-region`, `data-role`, `data-body`, `data-copy-*`, `data-artifact-preview-*`, `data-speech-to-text-*` | Same. |
| ARIA: tablist/tab/tabpanel, `role="log"`, composer `role="combobox"` + `aria-controls` / `aria-activedescendant` / `aria-autocomplete`, listbox/option, `role="status"` / `role="alert"`, sr-only labels, `aria-current="page"` on the current chat | Already correct. Do not “simplify”. |
| Successful assistant unboxed markdown + `BUBBLE_MARKDOWN` + draft `body_classes` parity | 2026-09-08 locked Claude-calm replies; boxing them would reflow mid-stream. |
| Preview always mounted at `lg+` (do not auto-collapse the empty pane) | Same lock; hiding it needs workspace JS. |
| Page thumbnail scale math, iframe sandbox, click-to-zoom, enlarge `<dialog>` | Works; high risk, low visual return. |
| Offline empty card | Already on-token and isolated. |
| Backend, routes, controllers, models, stream payloads, mention JSON | Out of scope. |
| New ViewComponents, custom CSS, new color tokens, non-Stimulus JS | Forbidden. |
| Header `what` key deletion, prompt/greeting copy edits | Byte-identical English lock; no product copy brief. |
| Dictate destination / transcribe wiring; non-composer dictate layout | Shared widget. |
| Archived section behavior, kebab action set, delete confirm | Product-complete. |
| `ButtonComponent` / `BadgeComponent` APIs | Reuse only. |

---

## 9. Frontend implementation order

1. Conversation list chrome (one row, max-height, kebab reveal, New chat secondary, chevron/label). Highest phone impact.
2. Shell grid ratio + rail width + compact tab/header padding.
3. Panel header (drop `what`, compact) + composer `bg-canvas` dock + empty-state (no extra sparkle, smaller greeting, canvas cards, centered labels).
4. Mention + attachment class strings in `ai_assistant_controller.js`.
5. Failed-tone + thread `gap-4`.
6. Preview empty kinds as caption; dictate mic size.
7. Component specs that pin old classes (`py-2.5`, `xl:w-60`, `bg-surface` dock, `self-start`, `text-3xl`, `bg-danger-subtle` without `/80`, `max-w-sm` on the mention menu). Locale spec for `toggle_hide`. `npx vitest run --coverage` on the JS file after step 4.

Do not ship a new Stimulus controller. Do not extract new components.
