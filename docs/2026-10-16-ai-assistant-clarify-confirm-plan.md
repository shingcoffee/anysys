# AI Assistant — structured clarification and safe confirmation (build plan)

Read first: `docs/2026-10-16-ai-assistant-clarify-confirm-design.md` (behaviour, the source of
truth) and, for UI, `docs/2026-10-16-ai-assistant-clarify-confirm-ux.md`. Root `AGENTS.md`
conventions apply. Lanes own disjoint files; never edit a file owned by another lane — report the
need in your RETURN notes instead. Do not commit.

## 0. Contract already in place (read-only for every lane)

* **Locale keys** (`config/locales/ai_assistant.{en,zh-CN}.yml`, under `ai_assistant.assistant`):
  `rejection_tokens`, `rejection_fillers`, `questions.{section,title,subtitle,other,text_placeholder,
  send,sending,skip,skip_reply,no_preference,answered,intro}`, `assumptions.{title,hint}`,
  `plan.{discard,discarding,declined}`, `proposal_not_pending`. Reuse `plan.list_separator` for the
  answer list separator and `plan.declined` for the typed-"no" reply. Add no other keys without
  adding them to both files.
* **Prompt documents** (`app/services/ai_assistant/assistant/prompt/documents/`): new
  `clarifying.md`, `pending_proposal.md`; updated `role.md`, `operation_tools.md`,
  `entity_authoring.md`, `entity_examples.md`, `website_authoring.md`, `website_contract.md`.
* **Route**: `discard_proposal_admin_modules_ai_assistant_message_path(customer_id, message)` →
  `POST /:customer_id/admin/modules/ai_assistant/messages/:id/discard_proposal` →
  `admin/modules/ai_assistant/messages#discard_proposal`. Guarded by `RouteAuthorization` (admin
  path ⇒ admin or owner).

## 1. Lane B — backend (`anysys-backend-developer`)

Owns exactly these files (create or edit) plus their specs:

| File | Change |
|------|--------|
| `app/services/ai_assistant/assistant/questions.rb` (new) | Sanitizer, design §2.2 |
| `app/services/ai_assistant/assistant/reply_envelope.rb` | `questions`, `assumptions`, forced clarify, fallback reply, design §2.3 |
| `app/services/ai_assistant/assistant/turn_processor.rb` | `questions` / `assumptions` on `EntityTurn` and `Result`, design §2.4 |
| `app/services/ai_assistant/assistant/finalizer.rb` | metadata keys, design §2.4 |
| `app/services/ai_assistant/assistant/prompt_builder.rb` | history notes, design §2.4 |
| `app/services/ai_assistant/assistant/prompt/context.rb` | `#pending_operation_proposal` |
| `app/services/ai_assistant/assistant/prompt/sections/clarifying.rb` (new) | `heads "Asking questions and stating assumptions"`, `document "clarifying"`, body = document |
| `app/services/ai_assistant/assistant/prompt/sections/pending_proposal.rb` (new) | design §3.5 |
| `app/services/ai_assistant/assistant/prompt/composer.rb` | entity outline: `Clarifying` right after `OperationTools`; `PendingProposal` right after `EntityFocus`; flowchart outline unchanged |
| `app/services/ai_assistant/assistant/pending_confirmation.rb` | design §3.1–3.3 |
| `app/services/ai_assistant/activities/discard_proposal.rb` (new) | design §3.4 |
| `app/services/ai_assistant/activities/send_message.rb` | `proposal_message_id:` kwarg → `metadata["confirms_message_id"]` |
| `app/services/ai_assistant/locale.rb` (new) | design §4 |
| `app/jobs/ai_assistant/reply_job.rb` | run `Reply` inside `I18n.with_locale(AiAssistant::Locale.for(...))` |
| `app/services/ai_assistant/cron/reconcile_generations.rb` | wrap each `reconcile(generation)` in the conversation's locale |
| `app/services/ai_assistant/assistant/tools/session.rb` | `#call` evaluates in `I18n.default_locale` |
| `app/services/operations/activities/confirm.rb` | `self.decline!(invocation, actor:)` |
| `app/models/operation_invocation.rb` | `declined` in `STATUSES` |

### Interfaces (other lanes rely on these names)

```ruby
AiAssistant::Assistant::Questions
  MAX_QUESTIONS = 5; MAX_OPTIONS = 8; MAX_PROMPT_LENGTH = 300; MAX_OPTION_LENGTH = 80
  MAX_TEXT_DEFAULT_LENGTH = 300; MAX_ASSUMPTIONS = 5; MAX_ASSUMPTION_LENGTH = 200
  TYPES = %w[single multiple text]
  .sanitize(raw)             # => [{"id"=>"q1","prompt"=>…,"type"=>…,"options"=>[…],"default"=>…}]
  .sanitize_assumptions(raw) # => ["…"]

AiAssistant::Assistant::ReplyEnvelope#questions / #assumptions   # arrays, default []
AiAssistant::Assistant::TurnProcessor::Result  # + :questions, :assumptions (keyword_init, default nil)
AiAssistant::Assistant::TurnProcessor::EntityTurn # + :questions, :assumptions
# Finalizer writes message.metadata["questions"] / ["assumptions"] (complete turns, non-empty only)

AiAssistant::Assistant::PendingConfirmation
  .consume(conversation:, user_message:, generation:) { |proposal| … }  # signature unchanged;
      # returns nil (send the turn to the model) or a TurnProcessor::Result
  .decline!(message, actor:)  # => true/false; caller holds the conversation lock

AiAssistant::Activities::DiscardProposal.call(customer:, user:, message_id:)
  # => Result(success?, message (alias of record), http_status, errors) — like UndoWebsiteReply

AiAssistant::Activities::SendMessage.call(customer:, user:, body:, images: [], conversation_id: nil,
                                          idempotency_key: nil, proposal_message_id: nil)
AiAssistant::Locale.for(user:, customer:)  # => Symbol
Operations::Activities::Confirm.decline!(invocation, actor:)
```

### Behaviour checklist (each item needs a spec)

1. Sanitizer: every rule in design §2.2 (drops, truncation with `…`, case-insensitive de-dup and
   canonical defaults, type inference/demotion, caps, ids after filtering, stable output shape,
   non-Array input ⇒ `[]`, bare-String assumptions wrapped).
2. Envelope: questions force `clarify`; blank reply + questions ⇒ `questions.intro`; blank reply
   without questions still invalid; plain text has none; malformed `questions` never invalidates.
3. Turn/Finalizer: a clarify turn's questions and assumptions reach `message.metadata`; failed
   turns never carry them; a turn with questions never runs the flowchart follow-on.
4. PromptBuilder: questions/assumptions/proposal-state notes on assistant turns exactly as design
   §2.4 (constants, model-facing English).
5. PendingProposal section: renders only for a live `operation` proposal whose invocation matches
   id **and** customer **and** conversation and is `awaiting_confirmation`; never for flowchart
   proposals, another conversation's or another tenant's invocation, or a settled one; JSON input
   omitted with a note above `MAX_INPUT_CHARS` (8,000); `plain`-safe for tenant text.
6. PendingConfirmation (design §3.1–3.3 + the settled-proposal rule): pinned approve; pinned target
   not pending ⇒ `proposal_not_pending` result, no yield, no write; typed approve only when the
   latest complete assistant message before the user message is the pending one; **regression:**
   proposal → later assistant reply → "yes" ⇒ returns nil (model), nothing applied; typed decline
   (en and zh-CN tokens, fillers, question mark never counts); decline retires to
   `declined_proposal`, invocation `declined` with `confirmed_by_id`/`confirmed_at`, broadcast
   replace after the lock, result body `plan.declined`; proposal message with `questions` ⇒ typed
   yes/no returns nil; settled proposal on the latest message ⇒ `proposal_not_pending`; flowchart
   proposal decline only moves metadata; cross-conversation / cross-tenant invocations untouched.
7. DiscardProposal: module gate (ConversationScoped preflight); another user's or tenant's message
   ⇒ 404; user messages ⇒ 404; not pending ⇒ 422 with `proposal_not_pending` and the message;
   success ⇒ 200, metadata moved, invocation declined, `Stream.broadcast_message_replace` called,
   no new message, no generation, no turn spent.
8. SendMessage: positive integer `proposal_message_id` (Integer or numeric String) stored as
   `confirms_message_id` alongside any `idempotency_key`; anything else ignored.
9. Locale: `Locale.for` chain and available-locale filtering; ReplyJob runs Reply in that locale;
   reconcile writes the timeout bubble in that locale; `Session#call` payloads stay in the default
   locale even inside `I18n.with_locale(:"zh-CN")`.
10. `Confirm.decline!` and the `declined` status/scope/predicate.

Keep existing specs in your files green; when a spec fails because behaviour intentionally changed
(e.g. typed "yes" after an intervening reply), rewrite it to the new behaviour. Run
`bundle exec rspec spec/services/ai_assistant spec/services/operations spec/jobs/ai_assistant spec/models/operation_invocation_spec.rb spec/integration/operations`
before returning and report the real result.

## 2. Lane F — frontend (`anysys-frontend-developer`)

Owns exactly these files plus their component specs and Vitest tests:

| File | Change |
|------|--------|
| `app/components/ai_assistant/clarifying_questions_component.rb` + `.html.erb` (new) | UX §2.1 |
| `app/components/ai_assistant/message_component.rb` + `.html.erb` | questions, assumptions, declined state, block order |
| `app/components/ai_assistant/proposed_changes_component.rb` + `.html.erb` | Discard, `:declined`, pinned Apply param |
| `app/components/ai_assistant/assistant_panel_component.rb` + `.html.erb` | `questions_active?`, new Stimulus values |
| `app/javascript/controllers/ai_assistant_questions_controller.js` (new) | compose + dispatch |
| `app/javascript/controllers/ai_assistant_controller.js` | answer/hold/close cards, pinned Apply, Discard hold/retire |

### Interfaces

* `AiAssistant::ClarifyingQuestionsComponent.new(questions:, state: :open)`; `STATES = %i[open closed]`;
  `render?` is false without questions. It receives questions already read by `MessageComponent`
  and re-checks shape defensively (Hash rows with a non-blank `prompt`, `type` in
  `single|multiple|text`, `options` an Array of Strings) — do **not** call backend classes.
* `AiAssistant::MessageComponent.new(message:, proposal_active: true, questions_active: nil, undo_errors: [])`
  * `questions` / `assumptions` read `message.metadata_json` defensively (assumptions: non-blank
    Strings, first 5).
  * `questions_active: nil` ⇒ open only when no later message exists in the conversation, and the
    query runs only when the message has questions.
  * `proposal` order applied → pending → declined (`metadata["declined_proposal"]`) → superseded;
    `proposal_state` adds `:declined`.
  * Renders `ProposedChangesComponent.new(proposal:, state:, message_id: message.id,
    discard_path: helpers.discard_proposal_admin_modules_ai_assistant_message_path(message.customer_id, message))`.
  * Block order: bubble → images → assumptions → What I changed → website undo → plan → questions.
* `AiAssistant::ProposedChangesComponent.new(proposal:, state: :pending, message_id: nil, discard_path: nil)`;
  `STATES = %i[pending applied declined superseded]`; Apply carries
  `data-ai-assistant-message-id-param` when `message_id` is present; Discard only when
  `discard_path` is present (`button_to`, ghost style, `data-turbo-submits-with` =
  `plan.discarding`, marked `data-proposal-discard`); declined footer `plan.declined`.
* `AiAssistant::AssistantPanelComponent#questions_active?(message)` ⇒ `message.id == messages.last&.id`;
  passes `questions_active:` to each `MessageComponent`; new Stimulus values
  `ai_assistant_questions_send_label_value` (`questions.send`) and
  `ai_assistant_questions_sending_label_value` (`questions.sending`).
* `ai-assistant-questions` controller: composes and dispatches `ai-assistant-questions:answer`
  with `{ body }` exactly as design §2.5; values `noPreference`, `listSeparator`, `skipReply`
  (English defaults, server sets from I18n); the card root also carries
  `data-action="ai-assistant-questions:answer->ai-assistant#answerQuestions"`.
* `ai-assistant` controller: `answerQuestions(event)` (guards, hold card with
  `data-questions="held"` + disabled controls + Send label swap, release on refusal, close all
  open cards on success); every successful post closes open cards; a newly arrived open card closes
  older open ones; `applyProposal` appends `proposal_message_id` from `event.params.messageId`
  when present; `#holdProposal` also disables Discard; `#retireProposal` also removes it.

Component specs cover open/closed/held markup, each question type, defaults pre-selected,
aria/fieldset/legend, Stimulus wiring attributes, the declined footer, Discard presence/absence,
the Apply param, assumptions, block order, and `questions_active` resolution (explicit and
auto). Vitest keeps `app/javascript/**` at 100 % lines/branches/functions — verify with
`npx vitest run --coverage` and report the real numbers. Also run
`bundle exec rspec spec/components/ai_assistant`.

## 3. Lane S — security (`anysys-security-engineer`)

Owns exactly:

| File | Change |
|------|--------|
| `app/controllers/admin/modules/ai_assistant/messages_controller.rb` | `discard_proposal` action mirroring `undo`: call `::AiAssistant::Activities::DiscardProposal.call(customer: current_customer, user: current_user, message_id: params[:id])`; `head(result.http_status)` when `result.message` is nil; otherwise Turbo Stream replace of `dom_id(result.message)` with `::AiAssistant::MessageComponent.new(message: result.message)` and `status: result.http_status` |
| `app/controllers/concerns/ai_assistant/message_sending.rb` | permit `:proposal_message_id`; pass `proposal_message_id: message_params[:proposal_message_id]` to `SendMessage` (the desktop controller's narrower `message_params` stays as is) |
| `spec/routing/admin/modules/ai_assistant/messages_routing_spec.rb` (new) | routes for `create`, `undo`, `discard_proposal`, `mentions`, `stop`, `regenerate` |
| `spec/requests/admin/modules/ai_assistant/messages_spec.rb` | discard: admin 200 + declined panel; not pending 422; another user's conversation 404; another tenant 404/redirect per existing conventions; member blocked; anonymous redirected; module disabled refused. create: `proposal_message_id` reaches `metadata["confirms_message_id"]` |

`DiscardProposal` and the `SendMessage` kwarg are built by lane B in parallel — code against the
interfaces above, never create or edit `app/services/**`. Request specs that need them may fail
until lane B lands; say so in RETURN.

## 4. After the build

* **QA** (`anysys-qa-engineer`): integration specs in `spec/integration/operations/` for the full
  turn flows (F1 regression through `Reply`, pinned Apply, typed decline, Discard then typed yes,
  regenerate of a confirmation, plan + questions), stale prompt-document specs
  (`website_contract_spec`, `website_authoring_spec`, composer outline), cross-tenant checks.
* **Release** (`anysys-release-engineer`): assistant/operations/components/requests specs, Vitest
  coverage, `bin/rails tailwindcss:build`, dev-server restart, smoke `/81721200/admin/assistant`.
* **Review** (`anysys-tech-lead` + `anysys-code-reviewer`, in parallel).
* **Docs** (orchestrator): `doc/reference/{en,zh-CN}/ai-assistant.md` and
  `doc/reference/{en,zh-CN}/operations-api.md` (`declined` status).
