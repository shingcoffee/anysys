---
title: "AI assistant"
summary: "Admin chat threads, streamed replies, tools, automatic entity/form/process activation, background sub-system builds, and platform provider settings in front of the ruby_llm wrapper."
---

## Summary

The AI assistant is the feature module `ai_assistant`. `FeatureModules::AiAssistant::Registration` registers it, points the entry at `/:customer_id/admin/assistant`, and exposes an editable tenant language (`auto`, `en`, `zh-CN`) and a read-only dictation limit in Settings. Provision and deprovision are no-ops. Enabling the module is what [speech-to-text](speech-to-text) checks; that dictation path is not a second module.

A thread is `AiAssistant::Conversation`, scoped to one customer and one user. Turns are `AiAssistant::Message` rows. Each reply is an `AiAssistant::Generation` that a job finishes. The request thread persists the user message and enqueues work. Vendor HTTP runs only inside `AiAssistant::ReplyJob`.

Chat completions go through `Llm`, the app wrapper around the `ruby_llm` gem. Callers do not construct `RubyLLM::Chat`. Whisper transcription stays on `ruby-openai` inside `AiAssistant::Providers::OpenaiWhisper`. Cursor Cloud Agents stay on `OutboundHttp` inside `AiAssistant::Providers::Cursor`. Platform credentials and the two job switches live on `AiAssistant::ProviderSettings`, edited at `/:customer_id/admin/maintenance/platform/module_settings/ai_assistant/settings`.

## Configure AI and transcription providers

At `/81721200/admin/maintenance/platform/module_settings/ai_assistant/settings`, edit each intended provider, save the credential under its **provider-specific label** (API Key, AWS Secret Access Key or Aliyun Access Key Secret), and run **Test connection**. The button queues a background probe; wait for its reported result instead of treating the immediate response as a pass. Then use **Change providers** to assign a *configured* provider separately to **Entity/Flowchart generation** and **Audio Transcribe**; saving a key or passing the test does not assign a job. Enable `ai_assistant` for each customer at `/:cid/admin/maintenance/modules`; the platform owner also sets that customer's positive `max_duration_seconds` recording limit there. The tenant can edit the language but only view the recording limit at `/:cid/admin/settings/modules/ai_assistant`; forging a Settings PATCH cannot change it. Dictation is part of this module, not another switch. Test a real chat reply and spoken clip: the connection probe uses silent audio for transcription providers, text for most generation-only providers, and only lists models for Cursor; it cannot validate every modality or model.

| Provider / job | Vendor-side setup and fields in Anysys | Verification / integration constraint |
| --- | --- | --- |
| **OpenAI / Whisper** (`openai_whisper`): both | [Create a billed OpenAI API project/key](https://developers.openai.com/api/docs/quickstart); enter **API Key**, optional **Organization**, audio **Model** (`whisper-1`) and **Chat model** (`gpt-4o-mini`). See [OpenAI speech-to-text](https://developers.openai.com/api/docs/guides/speech-to-text). | The connection probe transcribes silent audio; it does **not** test chat-model access. Check a spoken clip and a chat reply separately. |
| **DeepSeek** (`deepseek`): generation | [Create a DeepSeek API key](https://platform.deepseek.com/api_keys); enter **API Key** and **Chat model**. The app defaults to `deepseek-chat`, which is **not on the current published [model list](https://api-docs.deepseek.com/quick_start/pricing)** (`deepseek-flash` / `deepseek-v4-pro`); select a currently listed model and test it instead of relying on the default. | No audio transcription. |
| **Qwen / Model Studio** (`qwen`): generation | Activate [Alibaba Cloud Model Studio and create an API key](https://www.alibabacloud.com/help/en/model-studio/first-api-call-to-qwen); enter **API Key** and **Chat model** (`qwen-plus` by default). Select a key and model from the **China (Beijing)** region. | Anysys fixes the endpoint to `https://dashscope.aliyuncs.com/compatible-mode/v1`; a key from another [region](https://www.alibabacloud.com/help/en/model-studio/regions) cannot be selected through this form. The vendor recommends workspace-dedicated endpoints; the legacy DashScope domain stops receiving new features after September 30, 2026. No audio transcription. |
| **AWS Bedrock** (`aws_bedrock`): generation, optional audio | Set up an IAM key with `bedrock:InvokeModel` and, for streaming, `bedrock:InvokeModelWithResponseStream`; check [model access in the selected region](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html). Enter **Access Key ID**, **Secret Access Key** (stored in the shared `api_key` column), **Region**, **Chat model** and audio **Model**. | The default `amazon.nova-lite-v1:0` [does not accept audio input](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-lite.html). The selected audio **Model** must support `audio` blocks through **Converse**; even a speech model such as [Nova 2 Sonic](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-sonic.html) is unsuitable if it uses a different API. Test connection sends text to **Chat model**, not audio to **Model**. |
| **AWS Transcribe** (`aws_transcribe`): audio | Grant IAM `transcribe:StartStreamTranscription` in the chosen region, as in the [AWS streaming setup](https://docs.aws.amazon.com/transcribe/latest/dg/streaming-setting-up.html). Enter **Access Key ID**, **Secret Access Key** (stored in `api_key`), **Region** (`us-east-1` default); install `ffmpeg` on workers to transcode uploads. | Uses HTTP/2 streaming; automatic language detection is limited to `en-US` / `zh-CN`. No generation. |
| **Alibaba Cloud speech** (`aliyun`): audio | Activate [Intelligent Speech Interaction](https://www.alibabacloud.com/help/en/isi/getting-started/start-here), create an authorized RAM AccessKey and a [speech project](https://www.alibabacloud.com/help/en/isi/getting-started/manage-projects). Enter **Access Key ID**, **Access Key Secret** (stored in `api_key`), project **App Key**, and **Region** (`cn-shanghai` default). | The adapter fetches its [access token](https://www.alibabacloud.com/help/en/isi/getting-started/use-http-or-https-to-obtain-an-access-token) itself, but the token host/region remain fixed to Shanghai even if Region is changed; set project language in Aliyun. No generation. |
| **Cursor Cloud Agents** (`cursor`): generation | Create a [Cursor API key](https://cursor.com/docs/api); enter **API Key** and optionally a **Chat model** from `GET /v1/models`. | Create now reads `agent.id` plus `run.id`, then polls that exact run, not mutable latestRunId. FINISHED reads result; ERROR/CANCELLED/EXPIRED fail, with bounded polling. A model-list probe is still not a real reply test. Only the last five attached images are forwarded; no transcription. |

See [speech to text](speech-to-text) for upload formats, duration limits, background processing, and what a successful transcription job means.

Flowchart names appear in mentions, catalog tools, and the flowchart pass only when `FlowchartVisibility.allowed?` is true. That predicate is `platform_owner?`. The flowchart output contract (`FlowchartDefinitions::StructureSchema`) and its palette are generated from `CodeGenerators::ActionCatalog.export` so step actions and field names cannot drift from the ported generators. Regenerate the committed snapshot with `bin/rails ai_assistant:flowchart_schema`. See [flowchart-builder](flowchart-builder).

The assistant creates and changes entity schemas by calling the [Operations API](operations-api) as tools: `get_entity` reads, `create_entity` creates and applies at once, and `update_entity` changes and always waits for the admin, who approves the plan with **Apply changes** or withdraws it with **Discard**. An invalid call comes back as typed violations that the model fixes, asks about or explains. Nothing is written from the model's final reply text. When the model is blocked on something only the admin can decide, it asks through a question card — structured `questions` with its suggested answers pre-selected — and it lists the material decisions it took on the admin's behalf as `assumptions` under its reply.

New resources generated through `/:customer_id/admin/assistant` (including `/81721200/admin/assistant`) are ready for use: entities and association bridges are active immediately, newly created flowcharts launch after validation, and generated form `Page` records launch with the column defaults (admin on, member and public off). Existing records keep their lifecycle state when updated or reused. See [Entity builder](entity-builder), [Flowchart builder](flowchart-builder), and [Page builder](page-builder).

When the tenant's `website` module is on, the assistant also builds pages of the [website builder](website-builder). The admin describes the business, the model asks for missing facts with a `clarify` question card, and an `apply_website` document writes draft `WebsitePage` rows. Photos attached to the conversation are placed into image fields by content and copied into tenant website media.

## Flow

```text
POST /:cid/admin/modules/ai_assistant/messages
  or POST /:cid/admin/assistant/messages (desktop Bearer)
        |
        v
AiAssistant::Activities::SendMessage
        |  user message + AiAssistant::Generation (queued)
        v
AiAssistant::Assistant::GenerationHandoff
        |
        v
AiAssistant::ReplyJob
        |
        v
AiAssistant::Activities::Reply
        |  ExecutionPolicy, then ProviderClient#chat
        |  Llm.complete -> RubyLLM.context (generation vendors that use it)
        |  native tool calls -> Tools::Session
        |    operations -> Operations::Activities::Execute
        v
AiAssistant::Assistant::TurnProcessor
        |  Loop (JSON "tool" documents, max 8 steps) -> the same Tools::Session
        |  Websites::Assistant::Processor
        |    intent apply_website; replaces the two passes below
        |  ReplyEnvelope (intent chat or clarify)
        |    entity result built from the turn's operation outcomes
        |  FlowchartDefinitions::Assistant::Processor
        |    only when FlowchartVisibility.allowed?(user)
        v
AiAssistant::Stream
        |  Turbo stream name [:ai_assistant, customer_id, user_id, conversation_id]
        v
Admin assistant panel
```

A bare decision skips the vendor completion. `AiAssistant::Assistant::PendingConfirmation.consume` recognises a bare yes ("yes", "确认") and a bare no ("no", "算了") from every locale's token lists, and acts only on the proposal the reply directly answers: the latest complete assistant message before it, unless that message also carries a question card. The **Apply changes** button posts the same yes with `proposal_message_id`, which pins it to its own message, so it still applies after the admin has asked questions in between. Approving an operation proposal runs `Operations::Activities::Confirm` on its parked invocation; a flowchart proposal replays its stored document with `confirmed: true`. A bare no retires the proposal. **Discard** posts to `POST /:cid/admin/modules/ai_assistant/messages/:id/discard_proposal` and retires it without spending a turn.

## Implementation

`SendMessage` validates contract/module/provider and consumes burst (5/15 seconds) and sustained (30/hour) windows through atomic hits scoped to customer/user. Under one conversation lock it inserts the turn, records activity and installs the generation, preserving order and the 40-turn ceiling. Enqueue follows that boundary; failure creates a terminal failed assistant message with `enqueue_failed` and clears the generation pointer. Polling pending derives only from an active current generation, not a trailing user message.

For desktop polling, an unanswered user row alone returns `pending_reply: false`. Installing a queued/running current generation makes it true; a terminal generation makes it false even if its user message remains. Polling does not infer worker activity from message order.

`Reply` claims the generation, runs `ExecutionPolicy` (same customer on the generation, conversation, and user message; the user is an active admin of that customer or a platform owner; the module is on; `ProviderSettings.active_for(:generation)` is present), then calls the vendor. `ProviderClient` counts every completion in the turn, including tool-loop and repair calls, and stops at `AiAssistant::Limits::MAX_VENDOR_CALLS` (12). `on_chunk` is forwarded only when `supports_streaming?` is true. `DeltaPump` coalesces tokens (24 new characters or 120 ms) and stops publishing after cancel. `Stream` replaces a single draft node so a retried job does not stack a second bubble.

`TurnProcessor` runs `Loop` on the vendor text. A JSON object with a `tool` key is executed by `AiAssistant::Assistant::Tools::Session` and the model is called again, up to `Loop::MAX_STEPS` (8). Documents without `tool` pass through. The final text must parse as `ReplyEnvelope`, `{"intent": "chat", "reply": "…"}` or the same with `clarify`; plain text counts as chat. Any other document fails the turn with the extraction message. The envelope may also carry `questions` and `assumptions`. `AiAssistant::Assistant::Questions` sanitizes both and never fails the turn: at most `MAX_QUESTIONS` (5) questions of type `single`, `multiple` or `text`, 2–`MAX_OPTIONS` (8) options each, defaults matched to the offered options, long text truncated, ids `q1…qN`; at most `MAX_ASSUMPTIONS` (5) assumptions. A surviving question turns the intent into `clarify`, and a blank `reply` then falls back to `questions.intro`. `Finalizer` stores both lists in the assistant message's `metadata["questions"]` and `metadata["assumptions"]` for complete turns. The entity result comes from the turn's operation outcomes, not from the text: when an entity write succeeded, the names in `created`, `updated` and `bridges` are appended to the reply, and a parked proposal adds the review notice. The flowchart processor runs only when the viewer is allowed to see flowcharts and the entity result is `complete`, has no parked proposal, and either applied a change or was a chat intent. Its reply is appended to the entity reply, except when the flowchart pass also ends as a `chat` intent (nothing saved, nothing proposed): the entity reply already answered the turn, so the flowchart reply is dropped rather than repeating it. A flowchart proposal whose viewer is not allowed fails the turn.

An `apply_website` final document skips entity/flowchart passes. `TurnProcessor` starts `:website`, calls `Websites::Assistant::Processor` and returns `website_result`. Module-off returns `website.module_disabled`; otherwise the processor provisions and validates at most five pages of twelve sections each. Types/props use SectionKit/SectionFields, links name existing/same-document slugs and page slugs are unique. DocumentRepair uses `website_repair` for up to two rounds.

GenerationWriteGuard encloses provisioning and the document write. `PageShortcuts::Collisions.with_customer_lock` owns the document savepoint and locks existing tenant/site pages in ID order. Generation state and draft eligibility are rechecked there; `Undo.snapshot` deep-copies the fresh pre-write state before `SavePage(..., structure_editable: true)`. Any failed page rolls back the document. New pages are unpublished; home selection is checked at write time and revisions preserve home identity. Finalizer records created/updated changes and pins the first written page with local site media, otherwise the last. ArtifactPaneComponent uses the existing embedded preview/edit routes, shows persisted publication state and hides the website artifact while the module is off.

Finalizer stores created/revised Undo entries and SHA-256 fingerprints in `metadata["website_undo"]["pages"]`. Committed effects survive cancellation, failure or supersession in a provenance-bearing reply. The Website-enabled message button posts to `POST /:cid/admin/modules/ai_assistant/messages/:id/undo`; UndoWebsiteReply scopes through Conversation.owned_by and requires the module.

Undo takes the conversation lock, then the shared customer boundary, reloads/locks the message and loads pages in ID order. It validates current provenance, publication and fingerprints before any revert. One transaction deletes created pages, restores revised title/slug/nav/sections through SavePage and marks undone_at; it refuses missing/published/changed pages, restore/slug conflicts or deletion of a home still needed by surviving pages. RecordNotUnique/StatementTimeout returns retry feedback. The controller redraws via Turbo Stream, with inline 422 refusal. Post-commit message/artifact broadcast failure is logged without undoing committed work; PromptBuilder adds UNDONE_NOTE to history.

The entity outline in `Prompt::Composer` carries five website sections, and each renders nothing while the module is off. `WebsiteSectionKit` is the section table generated from `SectionKit` and `SectionFields`. `WebsiteContract` is the `apply_website` document shape. `WebsiteAuthoring` covers when to clarify, copy, and photo placement. `WebsiteCatalog` lists pages with their status, the pinned page's sections, and the sections of other draft pages up to `WebsiteCatalog::DRAFT_BUDGET` (12,000 characters). `WebsiteImages` is the upload manifest.

Each image attached to a user message is addressed as `upload:<ActiveStorage::Attachment id>` (`Websites::Assistant::Uploads`). `PromptBuilder` appends a manifest line to the user turn (token, filename, orientation, size) and replays the pictures of the newest image turns, whole turns only, up to `PromptBuilder::MAX_REPLAYED_IMAGES` (16) images and `MAX_REPLAYED_BYTES` (20 MB). A message carries at most `Attachments::MAX_FILES` (8) images of `MAX_BYTES` (5 MB) each and `MAX_TOTAL_BYTES` (20 MB) together, so the newest image turn always fits one vendor request; the composer checks the same limits before upload. An image field accepts a token from this conversation, a URL the tenant's site already uses, or blank, which `Websites::Skeletons.decorate_sections` fills with stock photography. On write, `Websites::Activities::ImportMedia` copies each referenced blob into tenant website media once and the token becomes `/:customer_id/site/media/:signed_id`. The chat attachment is never modified. `Websites::ImageFit.rendition` prepares the copy once, at import. A photo whose long edge already reaches 1920 pixels, and any GIF, is copied byte for byte. A smaller JPEG, PNG, or WebP is enlarged uniformly toward 1920 pixels, at most 4×, through the `image_processing` gem with a light sharpen. It is never downscaled, cropped, or stretched. A file the library cannot read is copied as uploaded. The backend is whichever one `config.active_storage.variant_processor` names: libvips, or ImageMagick on hosts without libvips (`config/initializers/active_storage_image_processor.rb`). The same setting lets Active Storage record image width and height. The site serves the copy's bytes unchanged. Sections render these imports (`ImageFit.fitted?`) with `Websites::FittedPhotoComponent`, which shows the whole photo (`object-contain`) over a blurred copy of itself that fills the frame, so the subject is never cropped away. Other media keep `object-cover`. Copies made for a document that fails to save, or whose save raises, are purged. An upload counts as placed only while its imported copy's URL is on one of the tenant's pages (`ImportMedia.placed_source_ids`), so a photo the admin later removes is offered for placement again. When a document leaves attached images unplaced, the processor sends one repair nudge, then applies the document and lists the unplaced filenames in the reply.

`Tools::Session` implements `list_catalog`, `generate_page`, `verify_artifact` and every registered operation. `list_catalog` returns the tenant's non-bridge entities in the operation vocabulary (`EntityDefinitions::Api::Mapper#from_entity`, including `version`) and the tenant's own form processing under `processing` (`FlowchartDefinitions::Catalog`) for every admin. `generate_page` writes through `GenerationWriteGuard` when one is installed. Vendors with `supports_native_tools?` also receive `ListCatalog`, `GeneratePageTool`, `VerifyArtifactTool` and one `Tools::OperationTool` per operation whose `available?` is true. Each is a `RubyLLM::Tool` whose `execute` calls the same session; an `OperationTool` takes its name from the operation key, its description from `summary` and its parameters from the projected schema. Vendors without native tools get the same operations from the `Prompt::Sections::OperationTools` prompt section, which lists each projected schema and the `{"tool": "<name>", "arguments": {…}}` convention that `Loop` executes. `Llm` caps native tool calls at `Llm::MAX_TOOL_CALLS` (8) and raises `Llm::ToolLimitExceeded`.

Both tool paths reach `Session#dispatch_operation`. It runs `Operations::Activities::Execute` with channel `assistant`, the conversation's user as actor, the conversation and generation, the idempotency key `gen-<generation id>-<operation key>-<input digest>`, and an `around_write` that wraps `GenerationWriteGuard`. The model receives `Outcome#to_tool_payload` with `next_step`, plus `attempts_remaining` when the call was rejected. `Prompt::Sections::OperationTools` (`documents/operation_tools.md`) tells the model to call `get_entity` before an update and pass its `version` as `expected_version`, to use `create_entity` only for new names, and to combine every change into one `update_entity` call per turn. On `fix_payload` it resends the full corrected call without mentioning the errors; on `ask_user` it returns `clarify` with one question per item, offering a violation's candidates as options; on `refresh` it calls `get_entity` again and rebuilds; on `blocked` it explains and stops. A reply that parks an update asks nothing else, so a yes or no to it is unambiguous.

`Tools::Session::MAX_ATTEMPTS` (3) bounds self-correction: each operation may be rejected three times per turn. Successful calls do not count, so `get_entity` reads and a parked `update_entity` are free. After the third rejection the next call returns `attempts.exhausted` (`blocked`) without running. The first `confirmation_required` outcome becomes the turn's `pending_proposal`, `{"kind": "operation", "operation", "invocation_id", "customer_id", "plan"}`. After that, any call in the same turn to an operation with `confirmation: :always` returns `proposal.already_pending` (`blocked`) without running, and nothing is superseded.

`ReplyWriter` stores the proposal in the assistant message's `metadata["pending_confirmation"]`. In the same transaction `PendingConfirmation.retire_open!` moves every older pending proposal in the thread to `superseded_proposal` and marks its parked invocation `superseded` with `Operations::Activities::Confirm.supersede!`. The panel shows the plan with **Apply changes**, **Discard** and **Tell me what to change**. `PendingConfirmation.consume` first classifies the reply as a bare approve or decline; a question mark never counts, and a reply with an added requirement goes to the model. Under the conversation lock it then resolves the target. A pinned `metadata["confirms_message_id"]` (approve only, written by `SendMessage` from `proposal_message_id`) must name a complete assistant message in this conversation that is still pending. A typed reply targets the latest complete assistant message and acts only when that message is pending and carries no `questions`. A pinned target that is no longer pending, or a typed yes/no right after a settled proposal (`applied_proposal`, `declined_proposal` or `superseded_proposal` — a regenerated confirmation turn, or a yes after **Discard**), replies `proposal_not_pending` without a vendor call or a write. Approval locks the customer, checks that the invocation is still `awaiting_confirmation` for this customer and conversation, and calls `TurnProcessor#apply_operation_proposal`, which runs `Confirm` with the conversation's user as approver. `succeeded` lists the updated entities and bridges and moves the proposal to `applied_proposal`. `conflict` replies that the entity changed since the proposal and asks the admin to request it again. Any other status fails the turn. When the approval does not apply and `Confirm` has settled the invocation (`conflict`, `invalid` or `failed`), `consume` moves the proposal to `superseded_proposal` instead. A decline moves the proposal to `declined_proposal`, marks an awaiting invocation of this customer and conversation `declined` with `Confirm.decline!(invocation, actor:)`, and replies `plan.declined`. Every path re-broadcasts the proposal message after the lock, so the panel stops offering its buttons. The parked `operation_invocations` row keeps the plan and snapshot, then records `confirmed_by_id`, `confirmed_at` — whoever settled it, approving or declining — and the final status.

`AiAssistant::Activities::DiscardProposal` backs **Discard**. It reaches the message only through `AiAssistant::Conversation.owned_by(customer:, user:)` (404 otherwise), runs `PendingConfirmation.decline!` under the conversation lock, and returns 422 `proposal_not_pending` when nothing was pending. It spends no turn, makes no vendor call and appends no message; the controller re-renders the message as declined. It may run while a turn is in flight: the lock serialises it against `consume`, and it never cancels the generation.

Two prompt sections carry this to the model. `Prompt::Sections::Clarifying` (`documents/clarifying.md`, after `OperationTools`) says when to ask — blocked on identity or purpose, an organisation-specific list, two materially different designs, or facts visitors rely on — how to ask (one round, every question with a suggested `default`), and when to state `assumptions`. `Prompt::Sections::PendingProposal` (`documents/pending_proposal.md`, after `EntityFocus`) shows the live parked change set, so a refinement resends one complete change set and an approval given in words after other messages re-offers the same input. `Prompt::Context#pending_operation_proposal` returns `{ "operation", "input" }` only for an `operation` proposal whose invocation matches id, customer and conversation and is `awaiting_confirmation`; an input longer than `PendingProposal::MAX_INPUT_CHARS` (8,000) is replaced by a note. `PromptBuilder` appends notes to replayed assistant turns: the questions asked, the assumptions stated, and the proposal's state (`PENDING_NOTE`, `APPLIED_NOTE`, `DECLINED_NOTE` or `SUPERSEDED_NOTE`).

`AiAssistant::ClarifyingQuestionsComponent` renders the question card. `ai_assistant_questions_controller.js` composes the answers into an ordinary message — each prompt followed by its answer, "No preference" when none — and `ai_assistant_controller.js#answerQuestions` posts it through the normal send path. A card is open only on the newest message (`AssistantPanelComponent#questions_active?`; a standalone render checks that no later message exists) and closes in place on any successful send. `MessageComponent` lists `assumptions` under the bubble. `AiAssistant::ReplyJob` and `Cron::ReconcileGenerations` run under `AiAssistant::Locale.for(user:, customer:)` — the user's UI locale, then the tenant's, not the module's `language` setting — so broadcast bubbles and server-written sentences use the admin's language; `Tools::Session#call` pins tool results to `I18n.default_locale`, so what the model reads does not change with it.

`AiAssistant::Providers` loads `app/services/ai_assistant/providers`. `OpenaiWhisper` calls `register!` and `default!`. Generation vendors that stream and accept native tools: `openai_whisper` (via `Llm` provider `:openai`), `deepseek` (`:deepseek`), `qwen` (`Llm` provider `:openai` with the DashScope base URL), `aws_bedrock` (`:bedrock`). `cursor` generates through Cloud Agents, ignores `on_chunk`, and does not transcribe. `aws_transcribe` and `aliyun` transcribe only; `#chat` stays the base fail-closed result. `ProviderSettings` keeps one row per provider. `transcribe_active` and `generation_active` are partial-unique: `activate_for!` clears the other row's flag. `active_for` returns that row only when `configured?` is true.

`Mentions` resolves `@` against the tenant's own entity names, and flowchart names only for a viewer `FlowchartVisibility` allows. `ListMentions` serves the composer menu from the same list. `Prompt::Sections::EntityPlatform` strips the flowchart capability bullet unless the viewer is allowed. `Prompt::Sections::FlowchartCatalog` renders nothing unless the viewer is allowed. The flowchart prompt outline is used only from the flowchart processor, which `TurnProcessor` does not start for other viewers, and from a sub-system build's `AuthorProcessing` (below).

`AiAssistant::ReconcileGenerationsJob` runs every 15 minutes and times out stalled generations (`running` older than 30 minutes, `queued` older than 10 minutes).

The cookie composer is `Admin::Modules::AiAssistant::MessagesController`. The desktop client uses `Admin::Assistant::MessagesController`, which includes `Oauth::BearerAuthenticatable` and rejects cookie sessions. See [authentication](authentication).

### Automatic resource launch

`EntityDefinitions::Persist` retains the entity enum's `active` default; association bridges are explicitly active. Entities have no separate launch flag. Entity updates still require the Operations approval flow.

`FlowchartDefinitions::Persist::Writer#create!` assigns the graph to an unsaved tenant-owned candidate, runs `FlowchartInputOutputValidator`, then runs `FlowchartServerValidator` on a separate in-memory record with a deep-copied configuration. The server validator mutates its input, so its copy is never saved. Missing input pins and server problems of severity `error` return their translated messages in `Persist::Result#errors`; warnings do not block. Only a valid candidate is set to `status: :launched` and saved, with its compiled activity and first version. A launch-validation failure leaves no flowchart or version and enters the processor's existing bounded repair flow (at most two repairs). A false save returns errors, with `apply_errors.flowchart_save_failed` as the fallback when callbacks supplied none. `Writer#update!` preserves the existing status and confirmation requirements.

Explicit `generate_page` calls and `Finalizer`'s automatic forms after successful entity creates/approved updates both use `AiAssistant::Assistant::GeneratePage`. The wrapper runs `Pages::Activities::CreateFromEntityVersion(shared: false)` and calls `Page#launch!` inside `Page.transaction(requires_new: true)`. The new row keeps the column defaults (admin-only). Creation/rebuilding, the page version, audiences and launch share that savepoint. Failed results roll back; `ActiveRecord::RecordInvalid` or `RecordNotSaved` returns `ok: false`, `skipped: :launch_failed`, and the translated validation reason (or `apply_errors.page_launch_failed`) through `apply_page_skipped`, with no page or created name reported. An unsuccessful form does not undo an entity write already completed by its operation.

For `:page_exists`, the wrapper reuses only the page matching the exact customer and entity version and changes neither launch state nor audiences. The underlying activity's manual-builder behavior is unchanged. Tool/finalizer generation remains inside the existing generation write guard, and the chat flowchart pass remains owner-gated; sub-system builds write processing for tenant admins (below). All writes stay customer-owned; shared global launch/audiences still require the platform resource path. Prompt documents and `GeneratePageTool` describe the automatic policy for forms; website marketing pages retain their separate draft/publication contract.

The reply links the forms it produced. `Finalizer` collects the pages from its own `GeneratePage` results and from the turn's `generate_page` tool effects (same customer only, de-duplicated by id). It then drops the form of any entity that another of those pages' entities targets through its `associations`, because the primary entity's form already collects the association rows. For example, when a turn builds Student and Course and Student associates Course, only the Student form is linked. `documents/entity_authoring.md` makes a domain's single person entity the primary one: it extends the person base model (`Authentication::User`) when `Prompt::Sections::EntityCapabilities` lists it, comes first in `create_entity`, owns the call's associations and never redeclares the inherited columns the section lists. `SemanticValidator` enforces the hard parts (see [Operations API](operations-api)). When the associated entity's form is the only one, it is still linked. Pages that are launched and visible to `:admin` are stored as `metadata["page_links"]` (`[{ "id", "name" }]`). `AiAssistant::MessageComponent#page_links` re-reads them by `customer_id` at render time, so a form that has been deleted, taken offline or moved to another tenant is not shown, and a renamed form shows its current name. Each form renders as a card linking to `admin_page_form_path` (`/:customer_id/admin/pages/:page_id/form`) with `target="_blank"` and `rel="noopener noreferrer"`. The wording comes from `ai_assistant.assistant.page_links.*`.

Reply bodies are composed with `AiAssistant::Assistant::Markdown.compose(prose, notes)` and `.paragraphs(*parts)`. Prose comes first, followed by the platform's notes (`apply_created`, `apply_bridges`, `apply_flowchart_created`, `apply_page_created`, `apply_page_skipped`, `verify.failed`, …) as a bulleted list. A single note with no prose stays a plain sentence. The entity reply and the flowchart reply are separate paragraphs. `Markdown.render` handles each blank-line chunk line by line, so a sentence followed by `- ` or `1. ` items renders as a paragraph and then a list, and a `#`–`######` heading line renders as a bold paragraph.

### Sub-system builds

A build finishes a domain in the background after the model has created its entities in a turn. The model calls `start_subsystem_build` (see [Operations API](operations-api)) with journey keys from `list_journey_options` and the form processing the admin described. The operation stores an `AiAssistant::SubsystemBuild` (`ai_assistant_subsystem_builds`: `customer_id`, `conversation_id`, `user_id`, `status`, `stage`, and JSON `blueprint`, `questions`, `answers`, `results`) and enqueues `AiAssistant::SubsystemBuildJob`. A partial unique index allows one `running` or `waiting_for_answers` build per conversation. `Prompt::Sections::SubsystemBuilds` (`documents/subsystem_builds.md`) and `Prompt::Sections::PageProcessing` teach this to every admin.

`SubsystemBuildJob` re-enqueues itself after `GENERATION_WAIT` (5 seconds) while the conversation's current generation is active. It then sets `Current.customer` and the admin's locale (`AiAssistant::Locale.for`) and calls `AiAssistant::Subsystems::Build`. `Build` checks the user again (active, and the platform owner or an admin of the customer), the module and the generation provider, then runs the stages from the stored `stage`:

| Stage | What happens |
| --- | --- |
| `journeys` | `Journeys::Activities::Generate` under the customer lock for each key without a journey yet; an existing journey is reused. |
| `processing` | `Subsystems::AuthorProcessing` writes one flowchart per need through `FlowchartDefinitions::Assistant::Processor`, with its own `ProviderClient` (budget `NEED_BUDGET`, 4 calls) and `documents/subsystem_processing.md` as the instruction. |
| `binding` | `Pages::Activities::BindFlowchart` sets each written flowchart on its page: the journey's `page_steps[page_index]` for the need's audience, checked against the need's entity. |
| `launch` | `Journeys::Activities::Launch`, except journeys whose pages still wait on processing and `public` journeys while sign-up is off. |
| `report` | `Subsystems::Report` posts one assistant message: journeys launched, already live, left as drafts or failed; processing set up, needing setup, not set, left out or failed; the pre-check notes. |

Every write is conditional on the build still running (`update_all` where `status` is `running`), and results are saved after each item. A cancelled build therefore stops at the next item, and a re-run skips finished work. An unexpected error fails the build with `build.unexpected` and keeps what it built.

**Screen.** `Subsystems::Screen` is passed to `Processor` as `screen:`, and its errors join the validators' errors in the repair loop. A step may not fill a secret (`api_call.authToken` or `authPassword`, `send_chat_message.signingSecret`, `send_webhook.secretExpression`, or a credential-like header). Every literal web or email address in a step's config must appear word for word in one of the admin's own messages (`role: "user"`); palette defaults are exempt. `AuthorProcessing` checks addresses before the first write and asks instead of repairing. A secret that was repaired away is listed as needing setup, named by its palette labels.

**Questions and answers.** When a need lacks a value, the model answers `clarify` with `questions`, or the build asks `build.value_question`. `Build` collects the questions of every need, sets `waiting_for_answers` and posts `build.questions_intro` with `metadata["questions"]`, so the usual question card shows. While a build waits, `Subsystems::Answer.consume` in `Activities::Reply` takes the next message as the answers, before `PendingConfirmation` and before any vendor call. It stores `{message_id, questions}`, sets the build running, enqueues the job again and replies `answers.received`. A message sent while the build runs gets `answers.running`. A running build idle for 30 minutes (`SubsystemBuild::MAX_RUNNING_AGE`) is failed as stalled, and the message is handled normally. Each need's instruction includes the last three answer rounds. A need still asking after one round of answers is left out and reported with what it still needs.

**Cancel and display.** Build messages carry `metadata["subsystem_build"] = {"id"}`, and so does the reply that started the build (`Tools::Session#record_subsystem_build`, `Finalizer`). `MessageComponent` re-reads the build and shows its status badge and, while it is active, **Cancel build**, which posts to `POST /:cid/admin/modules/ai_assistant/messages/:id/cancel_build`. `Activities::CancelSubsystemBuild` reaches the build only through a message in the caller's own conversation (404 otherwise) and returns 422 `cancel.not_active` once the build has ended. Earlier build messages are re-broadcast whenever the build posts or is cancelled.

**Tenant wording.** Builds and `set_page_processing` are open to tenant admins, so their text says "form processing", never "flowchart". Failed authoring shows `build.processing_unwritten` instead of the flowchart pass's message, a refused binding shows `BindFlowchart` `reasons`, and the instruction tells the model to keep questions, `needs_setup` and replies free of the word. The platform owner sees the detailed messages.

## Where to pay attention

### Local browser fixture contracts and readiness

The app-backed assistant fixtures in `spec/e2e/` use the actual SDK HTTP/SSE
transport to a loopback-only provider. `helpers/provider_backend.js` exports the
resolved `create_entity`, `update_entity` and `get_entity` documents, with
vocabulary slots resolved for the platform customer, plus the flowchart contract,
through the exact-database guarded Rails runner. `support/provider_server.rb`
answers entity requests with native `tool_calls` in RubyLLM's OpenAI shape,
streamed or not, and replies with a `chat` envelope once the tool result arrives.
It validates every tool-call argument set against the exported operation document
with `JSONSchemer` before serialization, so the fixture cannot send what the live
tools would reject. Malformed fixture output returns 422 rather than weakening
application validation. Instruction detection accepts `system` and RubyLLM's
default OpenAI `developer` role; flowchart follow-ups receive the corresponding
valid chat document.

Browser interactions wait for the actual Stimulus controller on the current mount,
including after Turbo remounts. Mention typing additionally waits for the real
server-candidate request to finish. The tests never inject candidates or call
application action methods; mutations use per-test owned threads and entities.
Mutation/audio checks also await the `connected` attribute on both panel Turbo
stream sources, set only after Action Cable confirms the subscriptions.
See `spec/e2e/README.md` for the existing-server, four-worker follow-up command.

On 2026-10-12 this five-case assistant/entity/mention/microphone follow-up passed
5/5 with four workers and zero retries, skips or flaky cases; Node/Ruby provider
checks passed 4/4. It reused `storage/browser_audit_final.sqlite3` with the app on
3001 and provider on 3012. Evidence is under `/tmp/opencode/assistant-audio-followup/`
(`results-final.json`, `browser-final.log`, `helpers-final-2.log`, `summary.md`).

### Route audit: generation budget, confirmation and committed effects

Conversation creation/current lookup serialize on the user and recheck capacity/empty-thread guards. `SendMessage(..., idempotency_key:)` reuses a conversation-scoped turn before spending throttles; transcription uses a stable clip key. `ProviderClient` supplies `before_request`/`before_tool_call` callbacks for native tools. `Llm::CompletionBoundary` counts actual RubyLLM provider completions, including recursion, on this chat instance only; cancellation/supersession is rechecked before requests/tools. Vendor-call, native-tool, JSON-loop and per-operation rejection caps remain distinct.

Entity approval applies the parked `OperationInvocation`, not a new model-authored document, and only from the conversation that parked it. **Discard** (`discard_proposal`) sits under the same admin guard, resolves the message through `Conversation.owned_by` and never spends a turn. **Apply changes** is a turn, so once a thread has spent its 40 turns only **Discard** still works there. `Operations::Activities::Confirm` revalidates the stored input, then checks the snapshot of each entity's `current_line_head_version_id` and writes inside the same customer lock, so a concurrent edit returns `conflict` instead of being overwritten. `create_entity` never parks, so an approval can only apply the reviewed update. A superseded reply with already-committed website effects stores a cancelled provenance/Undo message without touching the replacement generation pointer/artifact.

Operation inputs may omit attribute slugs: `EntityDefinitions::Api::Mapper` derives them from the name, while an explicit invalid slug fails the schema pattern or `attribute.reserved_slug`. Entity and generated-page quota tests accept limits into a subscription snapshot before changing the catalog; increases/decreases do not change the accepted allowance. With no configured default, Billing supplies finite Starter fallback capacity of 50 pages, 25 entities and 5 members. See [Entity builder](entity-builder), [Operations API](operations-api) and [Billing](billing).

Website imports and public serving enforce actual-byte raster/tenant/media policy. AI draft revalidation and before-state capture share the locked document write; Undo uses fresh locked provenance and page fingerprints. Assistant dictation HTTP/component/Stimulus now pass and pin the selected owned conversation before recording; switching threads cannot redirect a buffered clip. See [Website builder](website-builder), [Speech to text](speech-to-text), [Entity builder](entity-builder).

:::note
On 2026-10-11 the targeted AI/entity-definition/STT/LLM slice, desktop/widget STT requests and website apply/Undo specs passed 1,666 examples with zero failures on `storage/ai_verify.sqlite3`, schema version `20261011190000`. This includes all eight files behind the 37 AI/STT failures in the earlier full-suite report, plus adjacent regression coverage. Entitlement and confirmation snapshots use persisted fixtures rather than stubbed snapshot results. Provider transports are mocked where appropriate. The later 2026-10-12 parallel RSpec suite passed **25,266 examples, 0 failures**. Neither run certifies live vendor or browser journeys. Exact commands and evidence for the targeted slice are in `docs/audits/2026-10-11-ai-stt-targeted-verification.md`.
:::

:::attention
`AiAssistant::Activities::Reply` and `AiAssistant::Assistant::ProviderClient#chat` run on `AiAssistant::ReplyJob`. `SendMessage` and the controllers must not construct `RubyLLM::Chat`, `OpenAI::Client`, or a provider HTTP client. `Llm.complete` is the chat seam for the vendors that use ruby_llm.
:::

:::attention
`FlowchartVisibility.allowed?` is the gate for flowchart mentions, the chat flowchart pass and flowchart proposals. `AiAssistant::Assistant::Mentions.kinds_for`, `Prompt::Context#flowchart_visible?`, `Prompt::Sections::EntityPlatform`, `Prompt::Sections::FlowchartCatalog`, and `TurnProcessor#flowchart_visible?` all call it. It is true only for `Authentication::User#platform_owner?`. A tenant admin does not receive flowchart catalog text, flowchart mention candidates, or the chat `FlowchartDefinitions::Assistant::Processor` pass. They do get form processing through `set_page_processing`, `list_catalog`'s `processing` and sub-system builds, all worded without "flowchart"; the build runs the processor in the background for them.
:::

:::attention
`AiAssistant::ProviderSettings.active_for` fail-closes. A row with `generation_active` or `transcribe_active` that fails `configured?` is treated as no provider. `UpdateProviderSettings.validate_assignees` rejects a generation assignee whose class does not implement `supports_generation?`, and a transcribe assignee whose class sets `supports_transcribe?` to false. At most one row holds each flag.
:::

:::attention
`AiAssistant::Assistant::ProviderClient` counts every vendor completion in the turn against `AiAssistant::Limits::MAX_VENDOR_CALLS`. `Llm` separately stops native tool calls at `MAX_TOOL_CALLS`. `Loop::MAX_STEPS` is the JSON-tool round-trip cap. `Tools::Session::MAX_ATTEMPTS` caps rejections per operation per turn and answers the next call with `attempts.exhausted`. Exhausting the vendor-call budget returns `outcome: :budget_exceeded` and the reply body is the budget message, not the generic outage string.
:::

:::attention
The model can never approve or discard a proposal. Only **Apply changes** (pinned to its message), **Discard**, or a bare yes/no that directly answers the proposal can; a yes that follows any later assistant reply goes to the model, so it cannot apply a plan offered several turns earlier. A reply with any added requirement also goes to the model. The thread holds at most one pending proposal: parking a new one supersedes the older invocation, and an approval that `Confirm` settles without applying retires its proposal.
:::

:::attention
`AiAssistant::Stream` names include `customer_id` and `user_id`. Conversation lookup is `AiAssistant::Conversation.resolve` / `owned_by`, which refuses another user's id. `ExecutionPolicy` rejects a generation whose message, conversation, and customer do not match, and rejects a member.
:::

:::attention
The assistant never publishes website marketing pages. `Websites::Assistant::Processor` writes `published: false` on new pages, refuses a `page_id` that is published, belongs to another site, or does not exist, and does not touch `Website` settings, theme, or the current home page. `Websites::Assistant::Uploads` resolves tokens only among the conversation's own user messages under the conversation's customer, and `ImportMedia` refuses a blob stamped with another `customer_id`. Image URLs the model invents are validation errors.
:::

## Key code

```ruby
# app/services/ai_assistant/assistant/loop.rb
def call
  current = parse(@text)
  return success(@text) unless tool?(current)

  messages = nil
  MAX_STEPS.times do
    messages ||= PromptBuilder.call(conversation: @conversation, mode: :entity)
    result = @tool_session.call(current["tool"], current["arguments"])
    messages += [
      { role: "assistant", content: current.to_json },
      { role: "user", content: { "tool_result" => result }.to_json }
    ]
    reply = @chat.call(messages)
    return Result.new(outcome: :provider_failure) unless reply.is_a?(Hash) &&
                                                          reply[:outcome] == :success

    text = reply[:text].to_s
    current = parse(text) || { "intent" => "chat", "reply" => text }
    return success(current.to_json) unless tool?(current)
  end
  Result.new(outcome: :max_steps)
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def run_website(text)
  @progress.start(:website)
  website_result = Websites::Assistant::Processor.call(
    text: text, customer: @customer, conversation: @conversation, chat: @chat, write_guard: @write_guard
  )
  result(website_result.body, website_result.status, entity_result: nil, website_result: website_result)
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def flowchart_follow_on?(entity_result)
  return false unless flowchart_visible?

  entity_result.status == "complete" &&
    entity_result.proposal.blank? &&
    (entity_result.applied || entity_result.intent == ReplyEnvelope::Intent::CHAT)
end
```

```ruby
# app/services/ai_assistant/assistant/tools/session.rb
if @failures[key] >= MAX_ATTEMPTS
  return tool_payload(
    Operations::Outcome.invalid(
      operation: key,
      violations: [
        Operations::Violation.new(code: "attempts.exhausted", resolution: "blocked")
      ]
    ),
    attempts_remaining: 0
  )
end

outcome = execute_operation(key, args)
record_operation(outcome)
return tool_payload(outcome) if outcome.ok?

@failures[key] += 1
tool_payload(outcome, attempts_remaining: MAX_ATTEMPTS - @failures[key])
```

```ruby
# app/services/ai_assistant/assistant/pending_confirmation.rb
def typed_target(conversation, user_message)
  message = locked_complete_assistant_messages(conversation, user_message).order(id: :desc).first
  return if message.nil?
  return if pending_proposal?(message) && questions?(message)
  return message if pending_proposal?(message)
  return :not_pending if settled_proposal?(message)

  nil
end
```

```ruby
# app/services/ai_assistant/assistant/turn_processor.rb
def flowchart_visible?
  FlowchartVisibility.allowed?(@conversation.user)
end
```

```ruby
# app/services/llm.rb
def run_chat
  ctx = RubyLLM.context { |config| apply_provider_config(config) }
  chat = ctx.chat(model: @model, provider: ruby_llm_provider, assume_model_exists: true)
  seed(chat)
  apply_options(chat)
  chat.instance_variable_set(:@anysys_before_request, method(:reserve_request!))
  chat.singleton_class.prepend(CompletionBoundary)
  cap_tool_calls(chat)
  return chat.complete unless @on_chunk

  chat.complete { |chunk| emit(chunk) }
end
```

```ruby
# app/models/ai_assistant/provider_settings.rb
def self.active_for(job)
  column = job_column(job)
  row = where(column => true).first
  row if row&.configured?
end
```
