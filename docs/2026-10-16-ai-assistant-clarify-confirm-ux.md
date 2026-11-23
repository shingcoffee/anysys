# AI Assistant — clarify & confirm (UX spec)

Date: 2026-10-16
Audience: `admin` or `owner` on `GET /:customer_id/admin/assistant`. No Settings / Maintenance / member / public surfaces.
Behaviour source of truth: `docs/superpowers/specs/2026-10-16-ai-assistant-clarify-confirm-design.md` §§2.5, 2.6, 3.4.

All copy is I18n (`en` + `zh-CN`). JS words are Stimulus Values with English `default:` set from the server.

---

## 1. Surface inventory

All three live **inside an existing assistant bubble** in the admin thread. Same column as today’s plan panel: `w-full max-w-[min(92%,42rem)]`.

| Surface | Mount | nav_area |
|---|---|---|
| Question card (open / closed / held) | `AiAssistant::ClarifyingQuestionsComponent` after the plan panel | admin |
| Plan panel footer (+ declined) | existing `ProposedChangesComponent` | admin |
| Assumptions list | inline in `MessageComponent` (same as “What I changed”) | admin |

**Block order under an assistant bubble** (skip a block when it has no data):

1. Reply body → 2. images → **3. assumptions** → 4. “What I changed” → 5. website undo → 6. plan panel → **7. question card**.

---

## 2. Layout spec

### 2.1 Question card — `AiAssistant::ClarifyingQuestionsComponent`

Sibling chrome of the plan panel (`rounded-xl bg-canvas ring-1 ring-border-subtle`). `state` ∈ `:open, :closed`. Client may set `data-questions="held"` on an open card while the post is in flight.

Props: `questions:` (sanitized `[{id, prompt, type, options, default}]`, ≤ 5), `state:`.

Do not render when `questions` is empty. No skeleton — the card arrives with the finished message.

#### ASCII — open (desktop)

```
+--------------------------------------------------------------+
| A few questions                                              |
| Pick an answer or write your own. Suggested answers are      |
| already selected.                                            |
+--------------------------------------------------------------+
| (1) Which stages does your pipeline use?          fieldset   |
|  (● Qualification) (● Proposal) (○ Negotiation) …  chips     |
|  Or type your own answer                                     |
|  [ ____________________________________________ ]            |
|                                                              |
| (2) Should Opportunity link to your Account records?         |
|  (● Link to Account) (○ Store the company name as text)      |
|  Or type your own answer                                     |
|  [ ____________________________________________ ]            |
|                                                              |
| (3) Opening hours                                 text type  |
|  [ Mon–Sat 8:00–18:00                           ]            |
+--------------------------------------------------------------+
| [ Send answers ]  [ Skip — use your judgement ]              |
+--------------------------------------------------------------+
```

Mobile (`< sm`): chips wrap; footer stacks full-width, primary on top.

#### ASCII — closed

```
+--------------------------------------------------------------+
| A few questions                                              |
| Answered below.                                              |
+--------------------------------------------------------------+
| 1  Which stages does your pipeline use?                      |
|    [Qualification] [Proposal] [Negotiation] …   ← inert      |
| 2  Should Opportunity link to your Account records?          |
|    [Link to Account] [Store the company name as text]        |
| 3  Opening hours                                             |
+--------------------------------------------------------------+
```

Closed has **no inputs, no footer, no selected chip**. Options are a reminder of what was offered; the admin’s actual reply is the next user bubble. A `text` question shows only its prompt (no default chip).

#### Regions ↔ data

| Region | Source |
|---|---|
| Title / subtitle | I18n (`questions.title` / `.subtitle`) |
| Legend | `question["prompt"]` |
| Number badge | 1-based index from `id` (`q1` → 1). Hide the badge when there is only one question. |
| Chips | `question["options"]` (≤ 8). `single` = radio; `multiple` = checkbox. |
| Pre-selection | `question["default"]` (canonical option / option list / text value). |
| Other input | `single` / `multiple` only. Empty on open. |
| Text input | `type == "text"`, value = `default` or `""`. |

#### Fieldset / legend

One `<fieldset>` per question. `<legend>` is the prompt (`text-xs font-semibold text-text-primary break-words`) with the number badge (`aria-hidden`) to its left (`flex items-start gap-2`). Radios in one question share `name="<%= id %>"`. Checkboxes use `name="<%= id %>[]"`. The card `<section>` has `aria-label` = `questions.section`.

#### Chip styling (ToggleGroup / RadioGroup pattern)

Visually hide the control (`sr-only peer`). Style the following `<span>`:

| State | Utilities |
|---|---|
| Rest | `inline-flex max-w-full cursor-pointer items-center rounded-full bg-surface px-3.5 py-1.5 text-left text-sm leading-5 text-text-secondary ring-1 ring-border-subtle transition-base min-h-9 pointer-coarse:min-h-11` |
| Hover | `hover:bg-accent-subtle hover:text-accent hover:ring-accent-muted` |
| Checked | `peer-checked:bg-accent-subtle peer-checked:font-medium peer-checked:text-accent-text peer-checked:ring-accent-muted` |
| Focus | `peer-focus-visible:outline-none peer-focus-visible:ring-2 peer-focus-visible:ring-accent peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-canvas` |
| Disabled / held | `peer-disabled:cursor-not-allowed peer-disabled:opacity-50` — no hover |
| Closed (inert `<span>`, not a label) | `rounded-full bg-surface px-3 py-1 text-xs leading-5 text-text-muted ring-1 ring-border-subtle` — no hover, no checked paint |

Wrap: `flex flex-wrap gap-2`. Long options wrap inside the chip (`max-w-full whitespace-normal break-words`); do not truncate. Number badge: `flex size-5 shrink-0 items-center justify-center rounded-full bg-surface text-2xs font-semibold tabular-nums text-text-secondary ring-1 ring-border-subtle`.

#### Inputs

Project `input-field` class, `w-full min-h-11 text-sm`. `single` / `multiple` other: visible caption label `questions.other`. `text`: labelled by the legend (`aria-labelledby`); placeholder = `questions.text_placeholder`.

#### Footer (open only)

Left-to-right / top-to-bottom: **Send answers** (`ButtonComponent` `:primary` `:sm`) then **Skip — use your judgement** (`:secondary` `:sm`). `w-full sm:w-auto`. Same row recipe as the plan footer: `flex flex-col gap-2 border-t border-border-subtle px-3 py-2.5 sm:flex-row sm:items-center`.

#### Held (in-flight)

`data-questions="held"`. Disable every input and both footer buttons. Swap Send label → `questions.sending`. Dim the fieldsets (`opacity-60`). Keep the card ring; no spinner (mirrors Apply → “Applying…”).

#### Keyboard / touch

Tab order: chips → other/text → next question → Send → Skip. Arrow keys move within a radio group (native). Space/Enter toggles the focused chip (native). **Enter in an other/text field does not submit** — the admin must activate Send (a card can hold five questions). Skip is a button, not a form submit. Chips and footer buttons use `pointer-coarse:min-h-11`.

#### Empty / error

No empty card. No client validation — a blank question composes as `questions.no_preference`. Send refusal: release hold, keep values, existing composer error. Turns exhausted: both footer buttons disabled; card stays open; composer already explains why.

---

### 2.2 Plan panel footer — `ProposedChangesComponent`

Pending footer now has **three** actions. Body, header, and breaking badge are unchanged.

#### ASCII — pending

```
+--------------------------------------------------------------+
| Proposed changes                          [breaking badge]   |
| Nothing is saved yet.                                        |
+--------------------------------------------------------------+
| … existing plan rows …                                       |
+--------------------------------------------------------------+
| [ Apply changes ]  [ Discard ]  [ Tell me what to change ]   |
+--------------------------------------------------------------+
```

**Order (do not reorder):** Apply (`:primary` `:sm`) → Discard → Tell me (`:secondary` `:sm`).

Discard is a Rails `button_to` POST to `discard_proposal_admin_modules_ai_assistant_message_path` — same pattern as website Undo (`form: { class: "w-full sm:w-auto" }`, button `btn btn-ghost … px-3 py-1.5 text-[13px] w-full sm:w-auto`). **Not** `:danger`: nothing has been saved. No `turbo_confirm`. Mark the submit with `data-proposal-discard` so Apply’s hold can disable it. `data-turbo-submits-with` = `plan.discarding`.

Mobile: `flex-col gap-2`; all three `w-full`. `sm:` row + wrap (`sm:flex-row sm:flex-wrap sm:items-center`).

#### In-flight

| Trigger | Apply label | Discard label | All three |
|---|---|---|---|
| Apply pressed | Applying… | Discard | `disabled` |
| Discard submitting | Apply changes | Discarding… | `disabled` |
| Send refused | Apply changes | Discard | re-enabled |
| `#retireProposal` | buttons **removed** | — | superseded note shown |

`#holdProposal` must also disable `[data-proposal-discard]`. `#retireProposal` must also remove it.

#### Declined footer (`state: :declined`)

Same chrome as superseded (muted caption, not success green, not danger):

```
|  (minus / x icon)  Discarded. Nothing was saved.             |
```

`data-proposal="declined"`. `MessageComponent#proposal` order: applied → pending → declined → superseded.

`plan.errors.not_pending` is the 422 copy. Turbo replaces the message with its real footer — do not also paint the composer error slot.

---

### 2.3 Assumptions — always-open list

**Always open.** Not a `<details>`. “What I changed” is a historical trail that can run long; assumptions are ≤ 5 × 200 chars and exist to be *seen* (F5). Hiding them behind a click would recreate the bug.

No card ring — quieter than the plan / question cards, same type scale as the opened “What I changed” body.

```
Assumptions I made                         text-xs font-medium text-text-secondary
Tell me if any of these are wrong.         text-caption text-text-muted
  • Amount is in your reporting currency.  list-disc pl-4 text-xs text-text-muted
  • …
```

`w-full max-w-[min(92%,42rem)]`. Each `<li>` is `break-words`. No actions. Empty → do not render.

---

## 3. Interaction flow

Start: `GET /:customer_id/admin/assistant` (admin/owner). URL does not change.

### 3.1 Send answers

1. Newest assistant turn shows an **open** card; older cards are **closed**.
2. Admin adjusts chips / other / text (defaults already selected).
3. Typing in a `single` other input un-checks its radios; picking a radio clears the other input. `multiple` keeps both.
4. **Send answers** → `ai-assistant-questions` composes `{prompt}\n{answer}` per question, questions joined by a blank line (`single`: other if present, else checked option, else “No preference”; `multiple`: checked options + other, joined by `list_separator`, else “No preference”; `text`: trimmed value else “No preference”) and dispatches `ai-assistant-questions:answer` `{ body }`.
5. `ai-assistant#answerQuestions` runs `#canSpendTurn`, holds the card, POSTs through the ordinary message pipeline.
6. Success: user bubble with the composed body; **every** open card closes in place (`data-questions="closed"`: hide footer + inputs + other, neutralize chips, show “Answered below.”); composer focused. A later arriving open card also closes older ones.
7. Refusal / network: release hold, keep values, existing `send_failed` (or server errors) in the composer slot.

### 3.2 Skip

Same as 3.1, but the dispatched body is `questions.skip_reply` (“Use your best judgement for these and go ahead.”).

### 3.3 Type instead of the card

A successful typed/dictated send also closes every open card. A “yes” after a question card is **not** an Apply (server rule); it is just another message.

### 3.4 Apply / Discard / refine

1. **Apply changes** — existing: hold all three, send pinned “yes” + `proposal_message_id`. Success retires other pending panels. Refusal releases the hold.
2. **Discard** — `button_to` POST. Spends no turn. In-flight: all three disabled, label “Discarding…”. 200 Turbo-replaces the proposal message as `:declined` — **no** reply message is appended (only a typed/dictated “no” produces an assistant reply, with the same “Discarded. Nothing was saved.” text). 422 Turbo-replaces with the real state (declined / superseded / applied) — footer tells the story. 404 / network: buttons stay up; do not navigate away.
3. **Tell me what to change** — focus composer (unchanged). Does not hold the panel.

### 3.5 Failure matrix

| Failure | UI |
|---|---|
| Card send refused / vendor-down | Hold released; composer error |
| Turns exhausted / cooldown / busy | Send / Skip / Apply no-ops (`#canSpendTurn`) |
| Discard 422 not pending | Message re-rendered in real footer state |
| Discard 404 (not own conversation) | No change on the pending panel |
| Permission (member / other tenant) | Assistant route already blocked; no extra chrome |

---

## 4. Component reuse map

| Piece | Component | Notes |
|---|---|---|
| Card chrome, header, footer row | copy `ProposedChangesComponent` | same ring / padding / `max-w-[min(92%,42rem)]` |
| Send / Skip / Apply / Tell me | `ButtonComponent` | variants above; size `:sm` |
| Discard | `button_to` + `btn btn-ghost` | website Undo pattern, no confirm |
| Assumptions + “What I changed” | `MessageComponent` (inline) | assumptions **not** a `<details>` |
| Thread / composer | `AssistantPanelComponent` | pass `questions_active:` like `proposal_active:` |
| Question card | **new** `AiAssistant::ClarifyingQuestionsComponent` | props: `questions:`, `state:` (`:open` / `:closed`) |

No new dialog, toast, or `AlertComponent`.

---

## 5. Tailwind & Stimulus

**Tailwind.** Reuse assistant tokens only: `bg-canvas`, `bg-surface`, `bg-accent-subtle`, `text-text-primary|secondary|muted`, `text-accent` / `text-accent-text`, `ring-border-subtle`, `ring-accent` / `ring-accent-muted`, `text-xs` / `text-sm` / `text-caption`, `rounded-xl` (cards) / `rounded-full` (chips), `transition-base`, `break-words`, `pointer-coarse:min-h-11`. Header `px-3 py-2`; body `px-3 py-2.5`; fieldsets `flex flex-col gap-3`.

**New** `ai-assistant-questions` (identifier `ai-assistant-questions`). Composes text only; does not POST.

- Actions: `send`, `skip`, `pickOption` (clear other on `single`), `typeOther` (un-check radios on `single`).
- Values (English defaults = table below): `noPreference`, `listSeparator`, `skipReply`, `sendLabel`, `sendingLabel`.
- Dispatch: `ai-assistant-questions:answer` `{ body }`.

**Existing** `ai-assistant`:

- `answerQuestions` — `#canSpendTurn`, hold card, `#submit(body, [], false)`.
- Hold / release / close-all-open-cards / close-on-new-open-card (mirror `#retireStaleProposals`).
- `#holdProposal` / `#retireProposal` also target Discard.

---

## 6. Copy (final)

English is byte-identical to the string that would otherwise have been hard-coded.

**Source of truth: `config/locales/ai_assistant.{en,zh-CN}.yml` (already added).** Differences from
the table below: the list separator reuses the existing `ai_assistant.assistant.plan.list_separator`;
“Discarded. Nothing was saved.” is the single key `ai_assistant.assistant.plan.declined` (footer and
typed-“no” reply); “This proposal is no longer waiting for approval.” is the single key
`ai_assistant.assistant.proposal_not_pending` (Discard 422 and stale yes/no reply); zh-CN copy was
tightened in the YAML.

| Key | en | zh-CN |
|---|---|---|
| `assistant.questions.title` | A few questions | 有几个问题 |
| `assistant.questions.subtitle` | Pick an answer or write your own. Suggested answers are already selected. | 点选或自行填写。建议答案已预选。 |
| `assistant.questions.other` | Or type your own answer | 或自行填写 |
| `assistant.questions.text_placeholder` | Type your answer | 请输入答案 |
| `assistant.questions.send` | Send answers | 发送答案 |
| `assistant.questions.sending` | Sending… | 正在发送… |
| `assistant.questions.skip` | Skip — use your judgement | 跳过——请自行判断 |
| `assistant.questions.skip_reply` | Use your best judgement for these and go ahead. | 这些问题请自行判断，继续即可。 |
| `assistant.questions.no_preference` | No preference | 无偏好 |
| `assistant.questions.list_separator` | `, ` | `、` |
| `assistant.questions.answered` | Answered below. | 答案见下方。 |
| `assistant.questions.intro` | I have a few questions before I go ahead. | 继续之前，我有几个问题。 |
| `assistant.questions.section` | Questions for you | 需要你回答的问题 |
| `assistant.assumptions.title` | Assumptions I made | 我做的假设 |
| `assistant.assumptions.hint` | Tell me if any of these are wrong. | 如有不对，请告诉我。 |
| `assistant.plan.discard` | Discard | 放弃 |
| `assistant.plan.discarding` | Discarding… | 正在放弃… |
| `assistant.plan.declined` | Discarded. Nothing was saved. | 已放弃。未保存任何更改。 |
| `assistant.plan.errors.not_pending` | This proposal is no longer waiting for approval. | 该方案已不再等待批准。 |
| `assistant.proposal_declined` | Discarded. Nothing was saved. | 已放弃。未保存任何更改。 |
| `assistant.proposal_not_pending` | This proposal is no longer waiting for approval. | 该方案已不再等待批准。 |
