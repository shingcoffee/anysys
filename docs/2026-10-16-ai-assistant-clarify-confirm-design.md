# AI Assistant — structured clarification and safe confirmation (design)

Status: approved for build · Date: 2026-10-16 · Owner decision: creates stay immediate; only
`update_entity` (and owner-only flowchart updates) wait for approval — unchanged policy.

## 1. Why

Review of the assistant against current industry practice for agentic assistants
(human-in-the-loop approval bound to a specific proposal, structured elicitation such as MCP
`elicitation/create` / "AskUserQuestion" cards, "act then disclose assumptions") found:

| # | Severity | Finding |
|---|----------|---------|
| F1 | P0 safety | A bare "yes" applies the newest pending proposal in the thread no matter how many turns ago it was offered or which question the "yes" answers. Reproduced: proposal → admin asks a question → model asks "Do you also want a Phone field?" → admin "yes" → the old Notes change is applied with **zero** vendor calls and the reply says "Updated: Student." |
| F2 | P0 safety | Approval is approve-only. There is no Discard; a prose "no" leaves the proposal pending (Apply stays live), and only a newer proposal retires it. |
| F3 | P1 | The model never sees its own pending change set — history replays reply text only — yet the prompt demands that a refinement resend "a complete new update_entity that includes both the earlier change and the refinement". |
| F4 | P1 | Clarifying questions are prose. No options, no suggested defaults, no one-click acceptance; the admin retypes. `ask_user` violations also end up as prose. |
| F5 | P1 | The ask-vs-assume policy is narrow (two blockers) and decisions taken without asking are not disclosed. |
| F6 | P1 i18n | `AiAssistant::ReplyJob` never sets a locale, so broadcast bubbles, progress steps, plan panels and server-appended sentences ("Updated: Student.") render in `en` for zh-CN admins until reload. |
| F7 | P2 | Website prompt documents still reference the retired `entities: []` field. |

Out of scope (recommended follow-ups): per-generation token/cost accounting, reply feedback
(thumbs), a golden-conversation eval harness, proposal TTL, entity-create approval, and letting
Apply work once a thread has spent its 40 turns (Apply is a turn today; Discard is not).

## 2. Structured clarification (F4, F5)

### 2.1 Envelope (model → server)

The final reply envelope gains two optional keys:

```json
{
  "intent": "clarify",
  "reply": "Two lists are specific to your team — confirm them and I'll build Opportunity.",
  "questions": [
    { "prompt": "Which stages does your pipeline use?", "type": "multiple",
      "options": ["Qualification", "Proposal", "Negotiation", "Closed won", "Closed lost"],
      "default": ["Qualification", "Proposal", "Negotiation", "Closed won", "Closed lost"] },
    { "prompt": "Should Opportunity link to your Account records?", "type": "single",
      "options": ["Link to Account", "Store the company name as text"], "default": "Link to Account" },
    { "prompt": "Opening hours", "type": "text", "default": "Mon–Sat 8:00–18:00" }
  ],
  "assumptions": ["Amount is in your reporting currency."]
}
```

### 2.2 Sanitizer — `AiAssistant::Assistant::Questions` (new)

Model output is untrusted; the sanitizer never fails a turn, it drops what it cannot use.

* `Questions.sanitize(raw) → Array<Hash>`; anything but an Array → `[]`.
* Per item (non-Hash items dropped):
  * `prompt`: String, `squish`ed, required (blank → drop item), truncated to `MAX_PROMPT_LENGTH`
    (300) with `…`.
  * `options`: Strings only, `squish`ed, blank dropped, longer than `MAX_OPTION_LENGTH` (80)
    dropped, de-duplicated case-insensitively keeping the first spelling, first `MAX_OPTIONS` (8).
  * `type`: `"single" | "multiple" | "text"`. Missing/unknown → `"single"` when ≥ 2 options,
    else `"text"`. A `single`/`multiple` left with < 2 options becomes `"text"` (its one option,
    if any, becomes the text default when no usable default was given).
  * `default`: `single` → the canonical option matching case-insensitively, else `nil`;
    `multiple` → array (a bare String is accepted as one element) filtered to canonical options,
    de-duplicated, `[]` when none; `text` → `squish`ed String truncated to
    `MAX_TEXT_DEFAULT_LENGTH` (300), `nil` when blank/not a String.
* First `MAX_QUESTIONS` (5) valid items kept; ids assigned after filtering: `"q1"…"qN"`.
* Output shape (string keys, stable): `{"id","prompt","type","options","default"}`;
  `options` is `[]` for `text`.
* `Questions.sanitize_assumptions(raw) → Array<String>`: Array of Strings (a bare String is
  wrapped), `squish`, blank dropped, truncated to `MAX_ASSUMPTION_LENGTH` (200) with `…`,
  de-duplicated case-insensitively, first `MAX_ASSUMPTIONS` (5).

### 2.3 `ReplyEnvelope`

* New readers `questions` (Array, default `[]`) and `assumptions` (Array, default `[]`).
* `questions.any?` ⇒ `intent` is forced to `clarify` (a question card always means "blocked on
  the admin"; this also keeps the owner-only flowchart follow-on from running).
* With questions present, a blank `reply` is not a rejection: it falls back to
  `I18n.t("ai_assistant.assistant.questions.intro")`.
* Plain-text replies carry no questions/assumptions. Everything else unchanged.

### 2.4 Pipeline and persistence

* `TurnProcessor::EntityTurn` and `TurnProcessor::Result` gain `questions` and `assumptions`
  (default `nil`). `synthesize_entity_turn` copies them from the envelope; `#result` copies
  them from the entity turn (so they survive the flowchart follow-on join).
* `Finalizer#changes_metadata` writes `metadata["questions"]` / `metadata["assumptions"]` only
  when the turn status is `complete` and the list is non-empty.
* `PromptBuilder#content_for` replays, for an assistant message, after its body:
  * questions: `(You asked these questions; the admin's next message answers them: <JSON of the
    sanitized questions without ids>)`
  * assumptions: `(Assumptions you stated: <JSON array>)`
  * proposal state (constants, model-facing English, not translated — like `UNDONE_NOTE`):
    pending → `(This proposal is waiting for the admin's approval. Nothing from it is saved yet.)`;
    applied → `(The admin approved this proposal and it was applied.)`;
    declined → `(The admin discarded this proposal. Nothing from it was saved.)`;
    superseded → `(This proposal was replaced or could no longer apply. Nothing from it was saved.)`

### 2.5 UI — question card

* `AiAssistant::ClarifyingQuestionsComponent.new(questions:, state:)`; `state` ∈ `:open, :closed`.
  Rendered by `MessageComponent` (assistant messages only) after the proposal panel.
* Open: one `fieldset`/`legend` per question. `single` → radio chips; `multiple` → checkbox
  chips; both get an "Or type your own answer" text input. `text` → text input prefilled with
  `default`. Defaults pre-selected. Footer: primary **Send answers**, secondary **Skip — use your
  judgement**.
* Closed: prompts and options as neutral, read-only chips (no selection state — we never store
  what was answered) and a muted "Answered below." note. No inputs, no footer.
* Open only for the newest message of the thread: `AssistantPanelComponent` passes
  `questions_active: message.id == messages.last.id`; a standalone render (broadcast, Turbo
  replace) computes it as "no later message exists in the conversation" — only when the message
  has questions, so other messages cost no query.
* Stimulus `ai_assistant_questions_controller.js` (identifier `ai-assistant-questions`) only
  composes text and dispatches `ai-assistant-questions:answer` with `{ body }`:
  * per question `"<prompt>\n<answer>"`, questions joined by a blank line;
  * `single`: other-text if non-blank, else the checked option, else **No preference**;
  * `multiple`: checked options + other-text (if non-blank), joined by the localized list
    separator, else **No preference**;
  * `text`: trimmed value, else **No preference**;
  * typing in a `single` question's other input un-checks its radios; picking a radio clears it;
  * Skip dispatches the localized skip phrase.
  All words come from Stimulus Values with English defaults, set by the component from I18n.
* `ai_assistant_controller.js` owns sending: `answerQuestions(event)` honours the existing
  `#canSpendTurn` guards, holds (disables) the card while the post is in flight, releases it if
  the send is refused, and on success closes **every** open card. Any successful typed send also
  closes open cards. A newly arrived open card closes older open cards (mirrors
  `#retireStaleProposals`).

### 2.6 UI — assumptions

`MessageComponent` renders `metadata["assumptions"]` under an assistant bubble as a compact
list titled "Assumptions I made" with the hint "Tell me if any of these are wrong." Order under
the bubble: assumptions → "What I changed" → website undo → proposal panel → question card.

## 3. Safe confirmation (F1, F2, F3)

### 3.1 Decisions recognised without a vendor call

`PendingConfirmation.consume` recognises two bare replies:

* **approve** — existing `explicit_confirmation?` (unchanged token logic);
* **decline** — new `explicit_rejection?`: same algorithm over new locale lists
  `ai_assistant.assistant.rejection_tokens` / `rejection_fillers` (all locales merged, questions
  never count).

### 3.2 Which proposal a decision targets

* **Pinned (Apply button).** The button posts its usual reply ("yes") plus
  `proposal_message_id`. `SendMessage` stores a positive integer as
  `metadata["confirms_message_id"]` on the user message (anything else is ignored). For an
  approve decision, the target is that assistant message, scoped to the conversation,
  `status: complete`, `id < user_message.id`, still pending. If it is no longer pending, the turn
  replies `I18n.t("ai_assistant.assistant.proposal_not_pending")` with no vendor call and no
  write. A pin is ignored for decline decisions.
* **Typed (or dictated).** The target is the latest `complete` assistant message before the user
  message, and only if it still carries `pending_confirmation` **and** has no
  `metadata["questions"]` (a yes/no after a question card is ambiguous). If that message instead
  carries a *settled* proposal (`applied_proposal`, `declined_proposal` or `superseded_proposal`),
  the turn replies `proposal_not_pending` with no vendor call and no write — this covers
  regenerating a confirmation turn and a typed yes after the Discard button. Otherwise `consume`
  returns `nil` and the turn goes to the model as before. This fixes F1: a "yes" that follows any
  later assistant reply is no longer a confirmation.
* A message that carries both a plan and a question card keeps both. Only the pinned Apply button
  (and the Discard button) can act on that plan; typed yes/no and card answers go to the model.

### 3.3 Decline

* Under the same conversation lock and `current_generation?` check as approve:
  `pending_confirmation` moves to `metadata["declined_proposal"]`; an operation proposal's
  invocation (same customer **and** conversation, still `awaiting_confirmation`) becomes
  `declined` via `Operations::Activities::Confirm.decline!(invocation, actor:)`, which also stamps
  `confirmed_by_id` / `confirmed_at` — those columns record who settled a proposal, either way.
  Flowchart proposals just move.
* Reply body: `I18n.t("ai_assistant.assistant.proposal_declined")`, status `complete`, no
  vendor call, broadcast replace of the proposal message after the lock (as approve does).
* `OperationInvocation::STATUSES` gains `declined`.
* `PendingConfirmation.decline!(message)` (public, caller holds the conversation lock) returns
  `true` when it retired a live proposal, `false` otherwise.

### 3.4 Discard button

* Route (admin, existing guard via `RouteAuthorization`):
  `POST /:customer_id/admin/modules/ai_assistant/messages/:id/discard_proposal` →
  `Admin::Modules::AiAssistant::MessagesController#discard_proposal`, mirroring `#undo`:
  Turbo Stream replace of the message, status from the activity.
* `AiAssistant::Activities::DiscardProposal` (mirrors `UndoWebsiteReply`): `ConversationScoped`
  preflight (module gate); message found only through
  `AiAssistant::Conversation.owned_by(customer:, user:)` (404 otherwise); under
  `message.conversation.with_lock` calls `PendingConfirmation.decline!(message.reload)`;
  `false` → 422 with `proposal_not_pending` (message re-rendered in its real state);
  `true` → broadcast replace, 200. Spends no turn, makes no vendor call and appends **no** reply
  message — the panel re-renders as declined. Allowed while a turn is running: it never cancels
  the generation, and the conversation lock serialises it against `consume`.
* `ProposedChangesComponent` pending footer: **Apply changes** (primary, carries
  `data-ai-assistant-message-id-param`), **Discard** (`button_to` the route), **Tell me what to
  change** (focus composer). New state `:declined` renders "Discarded. Nothing was saved."
  `MessageComponent#proposal` order: applied → pending → declined → superseded.
* Client: holding a panel during Apply also disables Discard; retiring a panel removes it.

### 3.5 Pending proposal in the prompt (F3)

New section `Prompt::Sections::PendingProposal` (entity outline, right after `EntityFocus`),
static wording in `documents/pending_proposal.md`, rendered only when the conversation's live
proposal is an `operation` whose `OperationInvocation` (looked up by id **and** this customer
**and** this conversation) is `awaiting_confirmation`. Body: the guidance document, the operation
key, and the parked `input` as JSON (omitted with a note when it exceeds `MAX_INPUT_CHARS`,
8,000). `Prompt::Context#pending_operation_proposal` supplies `{ operation:, input: }` or `nil`.

## 4. Locale of background turns (F6)

* `AiAssistant::Locale.for(user:, customer:)` → first available of `user.locale`,
  `customer.locale`, else `I18n.default_locale`. This is the UI locale (the chain `SetLocale`
  uses for a signed-in request), not the module's `language` setting, which only steers
  transcription.
* `AiAssistant::ReplyJob` runs `Reply` inside `I18n.with_locale(...)` for the conversation's
  user/customer; `Cron::ReconcileGenerations` wraps each reconcile the same way.
* Model-facing tool results stay as today: `Tools::Session#call` evaluates in
  `I18n.default_locale`, so violation messages / `next_step` the model reads do not change with
  the admin's locale.

## 5. Prompt contract changes (F4, F5, F7)

* `role.md`: envelope may carry `questions` (clarify) and `assumptions`; questions never as a
  list inside `reply`; the website numbered-list exception is removed.
* New section `Sections::Clarifying` + `documents/clarifying.md` (entity outline, after
  `OperationTools`): when to ask (blocked on identity/purpose, organisation-specific lists,
  materially different designs where a wrong create is costly), the `questions` schema and
  limits, a suggested `default` on every question, one round, never re-ask, skip ⇒ proceed with
  defaults and list them in `assumptions`; when to state `assumptions`.
* `operation_tools.md`: `ask_user` → `clarify` with one question per item (candidates become
  options); never ask a question in the same reply that parks an update.
* `entity_authoring.md`, `entity_examples.md`: choice-list clarification uses `questions`; the
  create example states `assumptions`.
* `website_authoring.md`, `website_contract.md`: clarification uses `questions` (text questions
  with suggested defaults); the stale `entities: []` references are removed.

## 6. Invariants that must keep holding

* The model can never approve or discard; only a bare reply directly answering the proposal, the
  Apply button (pinned), or the Discard endpoint can.
* At most one pending proposal per thread (`ReplyWriter` → `retire_open!`, unchanged).
* Every lookup is tenant- and conversation-scoped; Discard is reachable only through the
  caller's own conversation.
* No user-facing literal strings: new UI words are I18n keys in `ai_assistant.en.yml` and
  `ai_assistant.zh-CN.yml` with identical key sets; JS words are Stimulus Values.
* `app/javascript/**` stays at 100 % Vitest lines/branches/functions.
