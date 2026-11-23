# Website, shortcuts, AI, announcements, support and help source audit

Date: 2026-10-11. Implementation base HEAD: `91b89d3ee376a2b3a1a2af2ea0851c62799eadf4`.

## Method and exclusions

The initial audit was read-only. It traced every explicitly requested route through controllers, shared authorization/tenant/MFA concerns, services, activities, contracts, jobs, models, Active Storage, and database constraints, and inspected relevant existing specs. No tests, application requests, migrations, subagents, or generated-code execution were performed. Installed Active Storage/Marcel/RubyLLM source and a read-only fetch of Cursor's current API reference supplied additional dependency evidence.

Confirmed findings below are source/control-flow findings, not claims of reproduction in a running app. Source line references identify the original audited implementation; subsequent backend/coordinator changes can shift them. The initial audit's working tree was clean. Follow-up implementation started with existing coordinator work in other domains and respected that work.

Explicit exclusions:

- Flowchart authoring/builders, including their maintenance editors.
- Maintenance Page authoring/builders, including their editors. Public/member/admin **runtime** Page rendering/submission remains in scope.
- Every file under `app/services/page_layout_templates/templates/`; neither contents nor generated behavior were inspected/executed there.
- Execution of stored activities or generated ERB/Ruby.
- Unrelated payment/email/SMS/billing/authentication features except shared authentication/storage/backend dependencies needed to establish these routes' behavior.

The Website marketing module (`Website`, `WebsitePage`, layout/skeleton catalogs and previews) is distinct from the excluded maintenance Page builder and was fully in scope.

## Exact route-action inventory

The explicit request covers **30 controllers / 72 distinct controller-action pairs**. GET routes also accept HEAD. Multiple aliases dispatching the same action count once; resource update actions accept PATCH/PUT. `CID` is the eight-digit customer prefix.

| Controller path | Actions | Route family / original `config/routes.rb` lines |
| --- | --- | --- |
| `page_shortcuts/unavailable` | `show` | Terminal unavailable explicit `/`, 51–52 |
| `public_pages` | `show`, `submit` | `/CID/page/:uuid`, 204–207; root/glob aliases, 41–49 and 855–865 |
| `websites/pages` | `home`, `show` | `/CID/site`, `/CID/site/:page_slug`, 209–214; root/glob aliases, 41–49 and 855–858 |
| `websites/assets` | `show` | `/CID/site/media/:signed_id`, 211–212 |
| `admin/maintenance/page_shortcuts` | `index`, `create`, `update`, `destroy` | Tenant shortcut management, 372 |
| `admin/modules/website/pages` | `index`, `new`, `create`, `edit`, `update`, `destroy`, `preview`, `reorder` | Module root/pages; GET/POST preview; PATCH reorder, 786–795 |
| `admin/modules/website/media` | `create` | Marketing upload, 796 |
| `admin/settings/modules/website/sites` | `show`, `update` | Settings root/site, 337–339 |
| `admin/settings/modules/website/skeletons` | `create` | Customer starter replacement, 340 |
| `admin/maintenance/platform/website/skeletons` | `show`, `edit`, `update` | Platform skeleton catalog, 631–634 |
| `admin/maintenance/platform/website/layouts` | `index`, `new`, `create`, `edit`, `update` | Platform layout catalog, 635 |
| `admin/assistants` | `show` | Admin root and `/assistant`, 233 and 235 |
| `admin/dashboards` | `show` | Admin dashboard, 234 |
| `admin/modules/ai_assistant/conversations` | `index`, `create`, `update`, `destroy`, `archive` | Cookie conversation API, 805–807 |
| `admin/modules/ai_assistant/messages` | `create`, `mentions`, `undo`, `stop`, `regenerate` | Cookie composer API, 808–815 |
| `admin/modules/ai_assistant/transcriptions` | `create` | Cookie STT enqueue, 802 |
| `admin/assistant/messages` | `index`, `create` | Desktop OAuth-token API, 263–264 |
| `admin/assistant/transcriptions` | `create`, `show` | Desktop STT enqueue/poll, 265 |
| `admin/maintenance/platform/ai_assistant/settings` | `show`, `edit`, `update`, `test_connection` | Platform providers, 616–619 |
| `admin/maintenance/platform/announcements` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`, `audience_preview` | Platform CRUD/audience sizing, 560–564 |
| `admin/platform_announcement_reads` | `create` | Tenant-admin bell read receipt, 243 |
| `admin/platform_announcement_dismissals` | `create` | Tenant-admin banner dismissal, 239 |
| `admin/support_ticket_reads` | `create` | Support read receipt/thread redirect, 246 |
| `admin/support_tickets` | `show`, `create` | Requester thread, 248 |
| `admin/support_ticket_messages` | `create` | Requester reply, 249 |
| `admin/help_emails` | `create` | Help email, 251 |
| `admin/maintenance/platform/support_tickets` | `index`, `show` | Cross-tenant owner inbox/thread, 555 |
| `admin/maintenance/platform/support_ticket_messages` | `create` | Owner reply, 556 |
| `admin/maintenance/platform/support_ticket_resolutions` | `create` | Owner resolution, 557 |
| `admin/help/docs` | `index`, `show` | Customer documentation, 253–255 |

Thirteen related fallback/runtime/shared actions were also traced, for **85 inspected action pairs across 37 controllers**:

| Controller | Actions | Boundary |
| --- | --- | --- |
| `home` | `index` | Genuine unmapped-root fallback |
| `member/pages` | `show` | Member runtime render / submission return |
| `admin/maintenance/page_renders` | `show` | Tenant and platform runtime render |
| `admin/maintenance/platform/developer_docs` | `index`, `show` | Shared documentation reader |
| `admin/module_configs` | `show`, `update` | Website/AI branches of customer configuration |
| `admin/maintenance/platform/module_settings` | `index`, `show`, `configuration`, `developer`, `update` | Website/AI platform configuration branches |
| `admin/module_howtos` | `show` | Website/AI help branches |

### Shortcut variants checked

Explicit Website home, Website inner-page and public Page destinations; automatic Website home/inner slugs; customer-prefix precedence over host lookup; dedicated-domain/inactive-customer behavior; terminal unavailable root and bootstrap fallback; reserved namespaces; normalization/traversal/encoded spellings; route precedence; `SCRIPT_NAME`; query/body identity forgery; Page POST aliases; Website POST rejection; dispatch-time identity/publication rechecks; preferred host-aware links; request-local snapshot cleanup; canonical captcha-rule reuse; inherited CSRF.

There is no separate unavailable-glob controller route: unresolved globs fall through to routing failure. Unavailable explicit root mappings must not fall through to Home.

## Backend and authorization chains

### Shared request boundary

`ApplicationController` includes `TenantContext`, `FeatureModules::HostIntegration`, `RouteAuthorization`, `SetLocale`, then `Authentication::EnforcesMfa`. Tenant extraction and authorization classify `request.path_info`, including mounted paths. Namespace-root format suffixes are protected. Admin URLs require admin/owner; platform URLs require `platform_owner?`; member runtime admits the documented read-only same-tenant admin preview.

Cookie writes inherit Rails CSRF protection. `Oauth::BearerAuthenticatable` prepends token authentication, forces JSON, rejects cookie-only requests and skips cookie CSRF/MFA. `Oauth::TokenIdentity` requires a live acceptable token, first-party desktop application, required scope and active user. TenantContext subsequently sees the token principal and enforces URL tenancy.

Conversation, message Undo, transcription polling and requester-ticket actions add their own user/record ownership scopes. Platform ticket readers intentionally use cross-tenant scopes behind the owner gate. The platform role gate does not generally constrain the URL customer to `81721200`.

### Shortcuts

Journey constraints → `Resolver.cached_resolve` → `PathPolicy` / `Hosts` / `Customer.domain_owner_id` → `PageShortcut` / `Collisions` / `TargetEligibility` → immutable fixed-destination `Target` → prepended `RouteContext` → trusted tenant/UUID/slug replacement → destination controller checks.

Management writes use `Contracts::Shortcut` and `Activities::Save`, customer locking, persisted-row reload, eligibility/collision validation and unique-index error handling. Polymorphic types are restricted rather than arbitrary constantization. `PublicPath` / `Lookup` handle preferred aliases and batch presentation snapshots without supplying routing authority.

### Public Page runtime

`Page.accessible.launched` → resolved version/content → visibility gate → `PageRendering` → `PageContentGenerator` (FormFields, LayoutElements, DynamicOptionsResolver, CompositePageRenderer/CompositeRenderer) → runtime inline ERB rendering.

Submission → page visibility authorization → `Pages::PublicSubmission` → accessible/referenceable flowchart + entity binding/mismatch checks → `FormParams` schema/audience filtering → RulesEngine/FormulaEvaluator → request-derived `FlowchartRuntime::Authentication` → PasswordEffects transaction → ActivityTracer → ActivityClassBuilder/DynamicClassLoader/contracts → stored activity boundary → entry extraction → redirect or InputMapper/Invocation handoff.

The audit read the loaders/renderers as source without executing their generated payloads. Successful activity execution commits before handoff; this is important for F03–F04.

### Website marketing module

CurrentSite/module gate → customer Website/Page scopes → SavePage/SaveSite → Page/Site/Section Reform contracts → persistence. DestroyPage protects the current home. ReorderPages filters IDs through the site's association. Provision/ReplaceSkeleton call Catalog/Skeletons. Platform catalog writes call SaveLayout/SaveSkeleton. Public rendering additionally requires published site and page, then supplies published navigation, theme, safe hrefs, section components and read-only HomeSite localization.

UploadMedia → Active Storage → tenant stamp → signed public media path. ImportMedia copies assistant attachments with an independent lifecycle through ImageFit. AssetsController verifies signature and URL customer before downloading/serving inline; the original controller did not verify classification or safe MIME/disposition.

### AI / STT

MessageSending → SendMessage → Message/Attachments contract → module/provider/rate preflight → owned conversation → user turn → GenerationLifecycle → GenerationHandoff → ReplyJob → ExecutionPolicy → ProviderClient/Llm/provider → tools/document processors → Finalizer/ReplyWriter → terminal generation + signed Turbo streams.

Website apply/import/undo, entity apply/confirmation, artifact scoping, provider setting activation, health probes and generation reconciliation were traced. Flowchart authoring internals were excluded; visibility and runtime entry boundaries were inspected.

TranscriptionEnqueueing → Transcription contract / AudioUpload / DurationPolicy / AudioFormats → Preflight → Clip/audio → TranscribeJob → active provider → field broadcast or SendMessage → outcome update → audio purge → desktop ShowTranscription → PruneClipsJob. Generation jobs recheck actor authorization through ExecutionPolicy; transcription processing chiefly rechecks module/provider availability.

### Announcements / support / help

Announcements Save/contract/TargetRules → field catalog/CustomerQuery → PlatformAnnouncement → banner Resolver / InboxResolver → Notifications Stream / scheduled BroadcastAnnouncementJob → per-user/customer reads/dismissals. Delete chooses soft discard for history-bearing records and hard destroy for never-live records.

Support scoped controller → CreateRequest/AddMessage/Resolve → contracts/AttachmentRules → ticket/messages/read cursor → Notifications Inbox/Stream. Requester threads are scoped to both customer and opener; platform owner threads are cross-tenant.

Help email → SendEmail → attachment byte snapshots → HelpMailer/ApplicationMailer → synchronous `deliver_now`.

Customer/platform docs → catalog slug allowlist → locale files → safe YAML front matter → tenant/locale/route/mtime-keyed cache → Kramdown → link rewriting/sanitization. Customer docs send `private, no-store`; screenshot paths are narrowly allowlisted static resources.

## Ranked original findings

IDs are stable handoff references. Remediation state is documented below; findings outside this implementation's ownership require coordinator verification against concurrent work.

### P1 security/destructive behavior

#### F01 — Runtime identifiers become executable Ruby/ERB

Evidence: `app/services/page_content_generator.rb:185`; `app/services/page_content_generator/composite_renderer.rb:25,51`; `app/views/public_pages/show.html.erb:2`; `app/services/pages/configuration_validator.rb:42–49`.

Trigger: a saved multi-step Page ID contains Ruby interpolation, or composite ID/listen-event data contains template delimiters. Identifiers are inserted into generated Ruby/HTML and later compiled by inline rendering; validation does not sufficiently constrain them.

Fix: serialize every Ruby argument safely, escape HTML attributes and prevent data from introducing ERB delimiters; prefer direct component rendering for composite HTML. Relevant specs: `spec/services/page_content_generator_safety_spec.rb`, `page_content_generator_composite_spec.rb`. Existing tests cover labels/button text, not identifier sinks. Nonowned.

#### F02 — Website media permits same-origin stored XSS

Evidence: `app/services/websites/activities/upload_media.rb:27–38,43–52`; `app/controllers/websites/assets_controller.rb:14–22`. Installed Active Storage identifies bytes automatically; Marcel recognizes HTML. Active Storage's normal safe serving MIME/forced disposition is bypassed by the custom controller.

Trigger: HTML declares an allowed image MIME, is subsequently identified as HTML and is served inline on the app origin. The endpoint also accepts generic same-tenant signed blobs without `website_media` classification.

Fix: classify actual bytes, reject non-raster uploads/imports, enforce classification at public serving and use safe MIME/disposition. Specs: `spec/services/websites/activities/upload_media_spec.rb`, `import_media_spec.rb`, `spec/requests/websites/media_spec.rb`. Backend addressed; controller follow-up remains.

#### F03 — Handoff mappings dispatch arbitrary model methods

Evidence: `app/services/feature_modules/input_mapper.rb:36–42`; `app/contracts/feature_module_handoff_contract.rb:93–115`; `app/controllers/public_pages_controller.rb:104–123`.

Trigger: an entity mapping path such as `destroy!` or `delete` passes nonblank-path validation and is invoked with `public_send` when a visitor submits the Page.

Fix: read a schema/attribute-allowlisted immutable representation, never arbitrary public methods. Specs: `spec/services/feature_modules/input_mapper_spec.rb`, `spec/requests/public_pages_submission_spec.rb`. Also verify nested `data` mappings against real JSON-string-backed entries rather than Hash-only doubles. Nonowned.

#### F04 — Failed handoff deletes pre-existing entries

Evidence: `app/services/pages/public_submission.rb:83–101,129–134`; `app/controllers/public_pages_controller.rb:126–133`.

Trigger: an update activity returns an existing entry; a disabled/invalid handoff then destroys that persisted record after the activity already committed. Creation provenance is not established.

Fix: validate/prepare handoff before business commit or compensate only explicitly proven new records. Spec: `spec/requests/public_pages_submission_spec.rb` currently tests creation cleanup only. Nonowned.

#### F05 — Runtime subflows bypass launched/tenant eligibility

Evidence: `app/services/concerns/activity_class_builder.rb:95–112`; `app/services/pages/public_submission.rb:53–62`; `app/models/flowchart.rb:83–91`.

Trigger: a launched parent references a child taken offline or belonging to another tenant. Child lookup is unrestricted `Flowchart.find_by`; default visibility includes drafts.

Fix: apply tenant/shared + launched policy to every referenced runtime child and fail closed if unavailable. Specs: `spec/services/concerns/activity_class_builder_spec.rb`, `activity_tracer_spec.rb`, `spec/services/pages/public_submission_spec.rb`. Nonowned runtime; builder editing remains excluded.

#### F06 — Public readers expose audience-hidden fields

Evidence: `app/services/composite_page_renderer.rb:90–96`; `app/services/page_content_generator/composite_renderer.rb:63–65`; `app/services/page_content_generator/form_fields.rb:121–127`; `dynamic_options_resolver.rb:51–59` in the same directory.

Trigger: a public list/dropdown references an attribute whose schema explicitly disables public visibility. Readers check tenant/schema membership but not attribute audience.

Fix: propagate effective runtime audience and filter columns/labels/values. Specs: `spec/services/composite_page_renderer_spec.rb`, `page_content_generator_safety_spec.rb`, public Page request specs. Nonowned.

### P2 runtime form/submission correctness

#### F07 — Password/hidden/multi-select semantics are lost

Evidence: `app/services/page_content_generator.rb:18–24`; `app/services/page_content_generator/form_fields.rb:43–71`; `app/components/form_fields/text_field_component.rb:11–12`; `select_field_component.rb:19–33` in the same directory.

Trigger: password and hidden controls become forced `type="text"`; multi-select becomes an ordinary single select. Fix: preserve control type/cardinality through generation/components. Specs: `spec/services/page_content_generator_spec.rb` and FormFields component specs; assert DOM attributes and submitted shape. Nonowned.

#### F08 — File-bearing runtime forms lack multipart encoding

Evidence: `app/components/form_fields/form_component.html.erb:2–9`; `wizard_component.html.erb:48`; `file_upload_field_component.html.erb:8–14` in the same directory.

Trigger: native browser submission transmits filename rather than file bytes. Fix: multipart form rendering for file/image fields. Add component encoding and actual browser-submission regressions; direct multipart request specs do not establish rendered-form correctness. Nonowned.

#### F09 — Scalar filtering drops arrays/base/association inputs

Evidence: `app/services/pages/form_params.rb:22,35–50`; `app/services/page_content_generator/form_fields.rb:144–163`; `app/services/pages/public_submission.rb:112`.

Trigger: array attributes or generated `base[...]`/`assoc[...]` inputs cannot reach the activity. Fix: schema-aware allowed parameter shapes across supported namespaces, with audience/tenant checks. Specs: `spec/services/pages/form_params_spec.rb`, `public_submission_spec.rb`, `spec/requests/public_pages_submission_spec.rb`; current integration uses scalar primary-entity fields. Nonowned.

#### F10 — Dependent calculations use submitted intermediates

Evidence: `app/services/pages/rules_engine.rb:85–103`; `app/services/pages/form_params.rb:24–26`.

Trigger: subtotal is recomputed but tax references the original submitted subtotal snapshot; missing intermediate drops the result, forged intermediate governs it. Fix: topological dependency evaluation using authoritative computed values, excluding submitted calculation targets. Specs: `spec/services/pages/rules_engine_spec.rb`, `form_params_spec.rb`. Nonowned.

#### F11 — Shared overrides do not govern executed activity

Evidence: `app/models/flowchart.rb:169–174`; `app/services/activity_tracer.rb:43–48`; `app/models/concerns/versionable.rb:139–143`.

Trigger: resolved shared-flowchart configuration follows the tenant override while runtime executes the global compiled `activity` column. Fix: per-effective-version compiled artifacts or effective-definition runtime compilation without global mutation. Add shared runtime execution/version assertions to submission/tracer specs. Existing shared-resource docs acknowledge the behavior. Nonowned.

### P2 AI/transcription

#### F12 — Cursor rejects its valid create response

Evidence: `app/services/ai_assistant/providers/cursor.rb:92–99`; current [Cursor Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints).

Trigger: documented `{agent: {id: ...}, run: ...}` response is parsed as top-level `id` and reported unreachable. Fix: parse envelope and track run terminal state. `spec/services/ai_assistant/providers/cursor_spec.rb:56–89` supplies an incorrect happy-path fixture. Nonowned.

#### F13 — Dictation targets a different thread from the displayed one

Evidence: `app/services/speech_to_text/activities/transcribe.rb:76–86`; `app/controllers/admin/assistants_controller.rb:16–36`; `app/models/ai_assistant/conversation.rb:54–68`.

Trigger: opening an older conversation does not make it most recently active; clip stores no thread and SendMessage receives no ID. Fix: capture/resolve an owned thread at enqueue and retain it. Specs: transcription service/request specs; add older-selected-thread and delayed thread-switch cases. Nonowned.

#### F14 — Byte ceiling does not establish transcription duration

Evidence: `app/services/speech_to_text/activities/enqueue_transcription.rb:76–99`; `app/services/speech_to_text/audio_formats.rb:16–25`.

Trigger: ten minutes at 16 kbps is roughly 1.2 MB, below the 60-second worst-case ceiling (~3.75 MiB), while client reports one second. Fix: actual media duration probing/decoding before paid invocation. `spec/services/speech_to_text/activities/enqueue_transcription_spec.rb:186–214` stubs sizes rather than measures real duration. Nonowned.

#### F15 — STT queue refusal still returns success

Evidence: `app/services/speech_to_text/activities/enqueue_transcription.rb:37–39`.

Trigger: false/refused `perform_later` leaves pending clip/audio with 202; exceptions lack generation-style handoff handling. Fix: verify acceptance and terminalize/recover failed handoff. Add refused/raising queue cases to enqueue activity specs. Nonowned.

#### F16 — STT processing lacks terminal safety/idempotency

Evidence: `app/services/speech_to_text/activities/transcribe.rb:37–42,80–91`; `app/jobs/speech_to_text/transcribe_job.rb:9–14`.

Trigger: SendMessage/routing exception leaves pending clip with audio purged; re-running success overwrites it with missing-audio failure; concurrent executions can send duplicate turns. Fix: atomic claim/terminal state and idempotent transcript-to-message handoff, with whole-pipeline exception terminalization. Specs: Transcribe activity/job; existing terminal cases omit routing/duplicate execution. Nonowned.

#### F17 — Paid-operation throttles race

Evidence: `app/services/ai_assistant/activities/preflight.rb:90–98`; `app/services/authentication/throttle.rb:56–75`.

Trigger: concurrent requests read one under-limit count and all pass before incrementing. Fix: atomic hit/compare; the shared limiter already exposes `hit!`. Add real concurrent-boundary cases to SendMessage and STT enqueue specs. Nonowned.

#### F18 — Native tool continuations escape vendor-call accounting

Evidence: `app/services/ai_assistant/assistant/provider_client.rb:36–40`; `app/services/llm.rb:84–92,165–172`; installed RubyLLM `Chat#handle_tool_calls` recursively invokes `complete`.

Trigger: wrapper call counts once while tools issue further billed completions. Fix: budget actual provider completions and cancellation checks across native continuations. Specs: `spec/services/ai_assistant/assistant/provider_client_spec.rb`, `spec/services/llm_spec.rb`. Nonowned.

#### F19 — Failed AI enqueue remains pending in desktop polling

Evidence: `app/services/ai_assistant/assistant/generation_handoff.rb:46–58`; `app/services/ai_assistant/activities/list_messages.rb:63–67`; `app/models/ai_assistant/generation.rb:35–41`.

Trigger: terminal failed generation/pointer release leaves last user message; pending fallback remains true and reaper excludes terminal row. Fix: pending from live generation status plus terminal failure response. Extend refused-enqueue specs through message polling. Nonowned.

#### F20 — Send insertion and generation installation reorder

Evidence: `app/services/ai_assistant/activities/send_message.rb:40–52,103–112`.

Trigger: older A inserts/releases; newer B installs generation; A later supersedes B. Fix: atomically claim turn/install generation under one conversation boundary, enqueue after commit. Existing locked-cap spec does not establish ordering. Nonowned.

#### F21 — Supersession after Website commit loses Undo provenance

Evidence: `app/services/ai_assistant/activities/reply.rb:125–138`; `app/services/ai_assistant/assistant/finalizer.rb:155–156`.

Trigger: Website apply commits, replacement generation arrives, reply returns before storing undo metadata. Fix: durable generation effects/provenance with artifact writes and a terminal record of committed effects. `spec/services/ai_assistant/activities/reply_spec.rb:1019–1032` covers cancellation, not supersession after writes. Nonowned AI lifecycle.

#### F22 — Conversation creation ceiling/empty guards race

Evidence: `app/services/ai_assistant/activities/start_conversation.rb:24–32`; `app/models/ai_assistant/conversation.rb:54–59,75–89`.

Trigger: two requests see 49 threads/used current thread and both create; lazy GET creation is similarly unlocked. Fix: serialize per-user/tenant creation and recheck conditions within it. StartConversation/Conversation quota specs are sequential. Nonowned.

#### F23 — Confirmation policy and persistence review different states

Evidence: `app/services/entity_definitions/assistant/processor.rb:69–76`; `app/services/entity_definitions/persist.rb:94–109,124–137`.

Trigger: policy permits new entity/unchanged echo; another writer creates/changes it before guarded fresh lookup; persistence updates without confirmation for that state. Fix: review/version checks inside write boundary and missing-name reservations. Add interleavings to processor/change-plan/update-policy specs. Nonowned.

### P2 Website catalog/writes

#### F24 — Whole catalog structure is not validated

Evidence: `app/services/websites/activities/save_skeleton.rb:8–16,28–75`; `save_layout.rb:8–21` in the same directory; `app/models/website_skeleton.rb:6–8`; `website_layout.rb:6–8` in the same directory.

Trigger: nonempty catalog contains no/multiple homes, invalid/duplicate slugs, missing layout references, bad sections/props or malformed section JSON normalized to empty. Fix: strict whole-catalog contracts before decoration and before replacement. Original platform request specs covered galleries only; direct SaveSkeleton/SaveLayout specs were absent. Addressed in this backend slice; tests authored, unrun.

#### F25 — Skeleton writes bypass shortcut reservations

Evidence: `app/services/websites/activities/replace_skeleton.rb:14–16`; `app/services/websites/skeletons.rb:88–102`; `app/services/page_shortcuts/resolver.rb:35–39`.

Trigger: starter writes `about` despite valid `/about` Page shortcut; explicit mapping becomes unavailable. Fix: customer collision boundary and validation before destructive replacement, including provisioning/direct application. Specs: ReplaceSkeleton/Provision plus shortcut lifecycle. Addressed.

#### F26 — Stale instance silently ignores explicit unpublish

Evidence: `app/services/websites/activities/save_page.rb:10–12,62–69`.

Trigger: stale false publication state, another writer publishes, explicit false assignment equals stale original and is omitted by dirty tracking. Fix: scoped persisted-row reload inside customer lock before applying params. Add real stale instances to SavePage specs. Addressed; also retain current structural template when merging section updates.

### P2 announcements/support

#### F27 — Invalid audience values broaden delivery

Evidence: `app/services/platform_announcements/customer_query.rb:140–170,174–185`; `app/services/platform_announcements/contracts/announcement.rb:65–67`.

Trigger: `id > "garbage"` becomes `id > 0`; unknown enum `not_equals` becomes comparison with `-1`. Dropping bad AND conditions also widens a tree. Fix: strict field/operator/value/tree validation, rejecting the whole invalid selected audience. Specs: CustomerQuery/TargetRules/contract/save and preview. Addressed, including model validation and malformed historical-tree fail-closed reads.

#### F28 — Global candidates hide relevant/critical notices

Evidence: `app/services/platform_announcements/resolver.rb:35–50`; `inbox_resolver.rb:37–53` in the same directory.

Trigger: more than 50 newer other-tenant notices crowd out this tenant's notice; severity sorting happens after cap. Fix: evaluate relevance before result limit and prioritize banner severity before cap. Addressed using bounded keyset batches; query count now scales by scanned batches instead of a false globally constant budget.

#### F29 — Expired banners persist on open pages

Evidence: `app/jobs/notifications/broadcast_announcement_job.rb:10–21`; `app/services/notifications/stream.rb:44–53`; `app/components/platform/announcement_banner_component.html.erb:1–47`.

Trigger: page remains open across end time; only start-time pushes are scheduled. Fix: guarded latest-state expiry refresh on same signed stream, preserving bell history. Specs: notification job/stream/banner. Addressed with ExpireAnnouncementJob; no new route/view/JS.

#### F30 — Reply can commit after resolution

Evidence: `app/services/help/activities/add_message.rb:14–19,45–51`; `resolve.rb:7–14` in the same directory.

Trigger: stale open instance is checked outside locking transaction after another resolution commits. Fix: reload/serialize both operations under ticket lock and guard inside boundary. Specs: AddMessage/Resolve and platform support requests. Addressed with real stale-instance regressions and post-commit reply broadcasting.

### Runtime presentation / supplemental documentation

#### F31 — Wizard submit tag is malformed (P2)

Evidence: `app/components/form_fields/wizard_component.html.erb:96–100`.

Trigger: `<button>` closes before intended attributes; type/class/submit-target render as text and step visibility cannot govern it. Fix tag and assert real DOM attributes. Specs: `spec/components/form_fields/wizard_component_spec.rb`, `spec/javascript/controllers/wizard_controller.test.js`; JS fixture independently constructs valid HTML. Nonowned.

#### F32 — Platform docs drop explicit locale (P3)

Evidence: `app/controllers/admin/maintenance/platform/developer_docs_controller.rb:23–27`; `app/services/developer_docs/repository.rb:211–212`.

Trigger: English-preference owner opens `?locale=zh-CN` and follows generated navigation/search; locale disappears. Fix effective locale route options/search fields like customer docs. `spec/requests/admin/maintenance/platform/developer_docs_spec.rb:41–54` currently pins query-free links. Nonowned.

## Database/storage evidence and gaps

| Area | Existing DB enforcement | Application-only / absent enforcement |
| --- | --- | --- |
| Shortcuts | Unique customer/path; required identities; target-type/leading-slash CHECKs; customer FK/cascade | Target existence/eligibility, full path grammar and cross-writer reservations |
| Website | Unique site/customer, page/site slug, partial one-home index, catalog keys | No WebsitePage website/customer equality FK/check; no at-least-one-home or JSON structure CHECK |
| AI threads/messages/generations | Required ownership columns, unique generation token, ownership/history indexes | No relationship FKs/status/role CHECKs; conversation ceiling/state leases |
| AI settings | Unique provider; partial unique job selectors; encrypted API key | Credential readiness does not prove model/modalities |
| STT | Required ownership/destination/status and indexes | No relationship FKs/state lease/verified duration/thread binding |
| Announcements | Required identity/content/audience/status; live/history indexes | Enum/window/AST semantics |
| Announcement receipts | Unique user/customer/announcement; FKs/cascades | Visibility eligibility |
| Support | Ticket/message/read FKs/cascades; unique read cursor | Author role/body/tenant equality/closed-ticket write exclusion |
| Active Storage | Unique key/attachment identity; blob FKs | Nullable tenant stamp, no customer FK, generic signed ID and metadata classification |
| Runtime Page data | Version/head uniqueness/content-addressed storage; EntityEntry rejects unknown/non-writable schema keys | Effective compiled shared behavior and uniformly propagated audience/parameter policies |

Production uses SQLite with separate primary/cache/queue/cable databases. Primary persistence and queue handoff are therefore not one DB transaction. No migrations/schema changes are included in this backend slice.

## Existing coverage strengths and remaining gaps

Strengths inspected: shortcut precedence/forged IDs/mounts/inactive customers/root fallback/publication rechecks; real alias CSRF rejection (`spec/requests/page_shortcuts_spec.rb:417–429`); global namespace auth; conversation/Undo/poll tenant-user isolation; Page visibility/draft top-level flowchart/scalar filtering/rollback/password effects; announcement CRUD/URL/JSON/receipt/history authorization; requester/owner support separation; customer docs tenant/slug/traversal/locale/cache/screenshot/navigation handling.

Gaps:

1. Platform skeleton/layout write routes originally had gallery-only request specs. New backend contracts/specs still need coordinator request-level create/edit/update coverage.
2. Runtime generation → actual DOM → browser submission → backend filtering is not integrated; F01 and F07–F10/F31 are not established by isolated string/fixture tests.
3. Sequential/mock single-boundary tests do not establish rate, conversation, send ordering, confirmation, publication or reply/resolve concurrency under production SQLite.
4. Immediate queue-failure result tests omit subsequent polling/terminal UI state.
5. STT fake audio/stubbed size tests do not measure duration, thread binding or duplicate/routing recovery.
6. Cursor fixtures conceal real contract drift. Bedrock's default audio model is documented as not accepting audio; credential readiness/text health checks do not establish transcription modality.
7. Shared definition hydration needs execution/version assertions, not merely head-pointer checks.
8. Announcements need multi-batch tenant crowding, severity, expiry and rescheduling coverage. New backend specs cover these cases but have not been run.
9. Malformed/orphan relationships need explicit defense-in-depth coverage, especially AI/STT owners, WebsitePage site/customer agreement and non-Website signed blobs.

Observed policy decisions requiring coordinator/product reconciliation, not accidental implementation claims:

- Signed-in nonowners are rejected on another tenant's public Page/Website even though public-category wording says anonymous and authenticated readers may open them. Website/shortcut specs intentionally pin this.
- Platform role gate generally admits the owner under another customer's platform URL rather than a universal `81721200` URL lock.
- Tenant support is opener-private even against same-tenant peer admins; specs intentionally pin this despite broader reserved-admin wording.

## Owned backend remediation and coordinator handoff

Implementation ownership: `app/services/websites/**`, Website catalog models/media services; platform-announcement services/models/jobs; notification services/jobs for expiry refresh; Help AddMessage/Resolve; regression specs; this audit artifact. No controllers, views, JavaScript, routes, migrations, schema or reference docs were edited here. AI services and maintenance/public Page runtime fixes belong to the coordinator/other owner.

| Finding | Backend result | Remaining glue |
| --- | --- | --- |
| F02 | Marcel classifies actual bytes, raster-only allowlist, authoritative tenant stamp; import checks source/output bytes; MediaPolicy classifies eligible public blobs | AssetsController must enforce MediaPolicy and safe serving MIME/disposition; legacy unclassified blobs must not be admitted |
| F24 | Whole Layout/Skeleton/Sections contracts and JSONSchemer-backed prop shape; strict JSON, one home, slugs, layout refs, section types/IDs, props/lists/options; model validation | Request-level platform writes and informative validation display; no controller/view changes included |
| F25 | Provision/application/replacement use customer lock; structure/collisions checked before deletion; replacement errors return activity Result | Module enablement caller must surface failed provisioning Result rather than assuming success |
| F26 | Scoped persisted reload inside customer lock; HomeSite explicit ordering retained | AI Website writer must recheck draft-only policy inside its write boundary; reload alone does not supply that policy |
| F27 | Entire invalid AST rejects on parse/contract/model; reads fail closed; known field/operator/value, signed-64-bit IDs, finite numeric values, valid enum values, ISO dates, joins/depth/node limits; LIKE wildcards are literal text | Existing audience_preview controller already responds 422 via malformed flag; coordinator should verify request regression |
| F28 | Keyset batches of 100, result cap after tenant matching; banner severity before cap; inbox retains newest-first | Verify query-budget wording and UI/bell behavior at scale |
| F29 | ExpireAnnouncementJob scheduled with exact end snapshot; latest record lock/state/end guard; existing per-user stream refreshes banner/counters/history | Run queue/stream integration specs; no route/JS glue required |
| F30 | Ticket with_lock reload/state guard for both writes; message/read/image transaction; broadcast after all transactions commit | Run requester/owner request regressions; read-cursor consistency beyond these writes remains separate |

### Public media controller follow-up

After signature resolution, `Websites::AssetsController#show` should reject unless:

```ruby
Websites::MediaPolicy.public_image?(blob, customer_id: current_customer_id)
```

Keep module/customer/signature gates, return empty 404 for failure, and use safe serving MIME/disposition (`content_type_for_serving` / `forced_disposition_for_serving`) rather than unrestricted inline content. Add requests for generic same-tenant attachments, HTML/SVG/non-image blobs, malformed classification, foreign tenants, valid classified raster media and missing storage bytes. New uploads determine type from bytes, not filename/client declaration; a valid PNG with misleading `.html` filename is still stored/served as PNG.

### Other caller glue

- `FeatureModules::Website::Provisioner.call` currently returns `.model` from Provision instead of checking `.success?`. Collisions now fail atomically; ensure module enablement does not mark a failed provision as successful. This caller was outside the requested owned services path.
- The AI Website processor's publication precheck precedes SavePage/customer locking. It must recheck that the current row is still draft inside the write boundary, independently of this stale-row reload.
- Whole-catalog failures preserve persisted data and return errors; coordinator request tests should verify 422/refusal and form error presentation.

### Specs authored/updated, not executed

New: `spec/services/websites/activities/save_layout_spec.rb`, `save_skeleton_spec.rb`; `spec/services/websites/media_policy_spec.rb`; `spec/services/platform_announcements/backend_audience_spec.rb`; `spec/jobs/notifications/expire_announcement_job_spec.rb`.

Updated: Website UploadMedia/ImportMedia/SavePage/ReplaceSkeleton/Provision activity specs; TargetRules spec; notification Stream spec; Help AddMessage/Resolve specs.

Tests use actual MIME bytes and Active Storage persistence/downloads, corrupt/imported definitions, real stale AR instances, complete persistence rollback checks, more than one keyset batch with tied timestamps, enum/date/numeric rejection and guarded expiry/current stream behavior. No vendor API write, generated activity execution, or test run occurred during implementation.

Verification: `ruby -c` succeeded for the 30 changed/new backend Ruby source files and 14 changed/new spec files. Final source/spec adjustments were checked again, and the scoped tracked diff passed `git diff --check`. This establishes syntax/whitespace only, not passing tests, coverage or integration readiness.

### Reference-doc updates reserved for coordinator

Update both `doc/reference/en/` and `doc/reference/zh-CN/` pages together: `websites`, `website-builder`, `page-shortcuts` (all slug writers/collision boundary), `announcements` (strict AST, batched eligibility, severity and expiry stream), `support-tickets` (locked resolution/replies, post-commit notifications), and relevant `background-jobs`/`ai-assistant` media-import descriptions. Mention actual-byte raster MIME classification, classified public serving, rejection-before-replacement, persisted reload semantics, new expiry job/guard, changed query-budget semantics and unrun verification status. No reference docs were edited in this slice.

Recommended coordinator order: close F01–F06 and public-media serving first, then runtime form/AI/STT lifecycle defects, then run the owned regression slice and request/queue integration checks. Nonowned findings in this artifact must be rechecked against concurrent coordinator changes rather than assumed still present.

## Website verification follow-up: groups 29–30

Date: 2026-10-11. This section supplements the historical read-only audit and syntax-only implementation evidence above. The user subsequently authorized targeted Website tests, test-harness isolation and paired reference documentation. No full suite or subagents were run for this follow-up. The final passing scope covers Website services, requests, models and module hooks, including media, catalogs and `Websites::Assistant::SchemaValidator`; it does not verify unrelated domains or a browser release.

### Reported failures and disposition

| Reported failures | Diagnosis / change | Final evidence |
| --- | --- | --- |
| Two ImportMedia failures in the parallel run | Both passed in the initial isolated reproduction. Source fixtures now explicitly establish the owning Current customer and assert the source exists. Added a correctly stamped invalid-MIME source under a foreign Current context to distinguish MIME refusal from tenancy refusal without losing source bytes. Shared-directory deletion was not reproduced and is not claimed as the established cause. | ImportMedia is included in the final passing cohort with real Disk uploads/downloads and MIME bytes. |
| Locked SavePage props overlay rejects ignored type/order changes | Eager decoration of an incoming ignored type could add image props before the saved type was resolved. Sanitize into raw string-keyed hashes, resolve locked IDs/types first, then decorate only effective changed/new sections. | Original overlay plus ignored-type, content-preservation, empty-template, legacy-unpublish and republish-refusal regressions pass. |
| Two assistant array-bound/minimum failures include a second invalid-JSON error | Normalization already emits a precise field/count error. Run the contract drift check only when normalization added no error; use JSONSchemer violations for localized Section bounds/schema errors. | Original exact-error expectations and English/Chinese Section cardinality regressions pass. |
| Public foreign-tenant reader still expects redirect/403 | Coordinator public-read authorization now intentionally admits anonymous and authenticated visitors. Updated the obsolete expectation to 200 while asserting URL-tenant content, no actor-tenant content, forged-query resistance and no persistent mutation. | Public Website requests pass with real authorization enabled (`SKIP_AUTH` unset). |

`SavePage` also preserves sections for metadata/publication-only changes without layout/media refill. Unchanged legacy-invalid content can be unpublished; new records, section changes and explicit publication retain full section validation. `Contracts::Page` defaults to validation, and SavePage selects the internal `validate_sections:` option rather than accepting a submitted bypass flag.

### Storage harness

`config/storage.yml` now partitions the test Disk root into sibling worker directories. The base prefix is nonblank `ACTIVE_STORAGE_ROOT` or `<Rails.root>/tmp/storage`, expanded to an absolute path before `TEST_ENV_NUMBER` is appended even to an explicit prefix. Normalizing trailing slashes avoids nesting worker 2 inside worker 1's root. Blank worker 1 uses the base; worker 2 uses `<base>2`. The development/production `local` service is unchanged.

No global upload-directory cleanup hook was found in `spec/support`. `spec/config/active_storage_isolation_spec.rb` verifies default/explicit/blank-override roots and real uploads with the same key in two exclusively allocated sibling Disk services. It removes only its own newly created second-worker directory and confirms first-worker bytes survive. The first regression draft used `delete_prefixed("")`, which the installed Active Storage rejects with `InvalidKeyError: key is blank`; that harness error was corrected with cleanup limited to the example's own `Dir.mktmpdir` allocation.

The initial selected reproduction was **87 examples, 5 failures**: the newly added harness cleanup error, locked overlay, two duplicate-schema-error expectations and obsolete public guard expectation. Both original import cases passed there. Subsequent focused verification passed **106 examples, 0 failures**; the initial complete Website cohort passed **572 examples, 0 failures**. These overlapping subsets are separate results, not numbers to sum into a full-suite claim.

### Final actual runs

All commands used a disposable `TEST_DATABASE=storage/website_verify.sqlite3` and test-only `ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify`. Schema preparation used that same environment with `bin/rails db:schema:load`; development/production schemas and uploads were not prepared or cleared.

```bash
env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bundle exec rspec spec/config/active_storage_isolation_spec.rb spec/services/websites spec/services/feature_modules/website spec/requests/websites spec/models/website_spec.rb spec/models/website_page_spec.rb --format progress --format documentation --out /tmp/opencode/website_verify_complete.log

env -u SKIP_AUTH -u TEST_ENV_NUMBER -u COVERAGE RAILS_ENV=test TEST_DATABASE=storage/website_verify.sqlite3 ACTIVE_STORAGE_ROOT=/home/ec2-user/anysys/tmp/storage-website-verify bundle exec rspec spec/services/developer_docs --format progress --format documentation --out /tmp/opencode/website_verify_docs_complete.log
```

| Final scope | Actual result | Runtime / load | Log |
| --- | --- | --- | --- |
| Website services/requests/models/module hooks plus storage-isolation harness, after explicit-root and trailing-slash worker hardening | **572 examples, 0 failures; exit 0** | 49.56s / 2.67s | `/tmp/opencode/website_verify_complete.log` |
| Developer documentation repository/renderer/highlighter, including every registered page in both locales | **76 examples, 0 failures; exit 0** | 7.6s / 2.29s | `/tmp/opencode/website_verify_docs_complete.log` |

Earlier raw logs are `/tmp/opencode/website_verify_baseline.log`, `/tmp/opencode/website_verify_focused.log` and `/tmp/opencode/website_verify_targeted.log`. The passing pre-normalization checks are also retained as `/tmp/opencode/website_verify_final.log` and `/tmp/opencode/website_verify_docs.log`. The final Website run emitted Rack deprecation warnings for `:unprocessable_entity`, not test failures. Historical full parallel failures remain recorded in `docs/audits/2026-10-11-rspec-verification.md`; this follow-up did not rerun or replace that aggregate.

Final static checks: `ruby -c` passed for the five follow-up Ruby source files (SavePage, Page/Section contracts, PropSchema and Website SchemaValidator) and five follow-up spec files (storage isolation, SavePage, ImportMedia, Section and public Website requests). The scoped tracked diff passed `git diff --check`.

### Documentation and coordinator integration

Updated `doc/reference/en/` and `doc/reference/zh-CN/` together for `websites`, `website-builder` and `background-jobs`: current public-read openness/content isolation, locked overlay/decorating order, publication-only preservation and validation, localized cardinality errors, reproducible database/upload isolation and worker-safe cleanup. Existing concurrent documentation changes were retained.

The current coordinator `Websites::AssetsController` enforces MediaPolicy, downloaded byte size and identified raster MIME with `nosniff`; its Website media request regressions pass in the final cohort, superseding the earlier F02 controller handoff. `FeatureModules::Website::Provisioner` now raises on a failed Result, and Website processor/Undo regressions also pass. Platform write-route error presentation, browser behavior, full-suite evidence and nonowned findings still require their own scoped verification; passing this cohort alone does not close those broader gaps.

## 2026-10-12 — preview lifecycle follow-up (W09)

Source reread confirms the additional preview-response root recorded as **W09** in the [fixed-bug ledger](2026-10-11-fixed-bug-ledger.md). Old asynchronous preview HTML or errors could outlive an edit/save/disconnect, and a revision reset on `connect()` could make an old connection's request current after reconnect. This is distinct from W01–W08's media, catalog, persistence and validation roots.

Current `app/javascript/controllers/website_builder_controller.js` initializes `previewRevision` once in `initialize()`. `connect()` does not reset it. Private `#scheduleLivePreview` increments immediately before debounce; `reloadPreview()` and `disconnect()` increment and clear the timer. `#pushLivePreview` captures the revision before fetch, compares after body reading, and gates non-OK/exception cleanup before `previewLoaded()`. The separate upload Map/object-identity guard still controls image responses.

Existing execution evidence was read, not rerun by this documentation lane:

* `spec/javascript/controllers/website_builder_controller.test.js`: **175/0**, including **8 additional** reconnect/upload regressions after the earlier 167-case preview suite. Actual Stimulus disconnect/reconnect covers old deferred responses/bodies, rejected/non-OK/body-error previews and rejected/non-OK/invalid-JSON uploads.
* Completed full Vitest: **6,956/0**, 290 files, **100% configured-scope** lines/statements **57,577**, branches **16,374**, functions **3,336**. Controller coverage is **1,181 lines, 619 branches, 103 functions**, all 100%.
* Raw logs and generated summaries: `/tmp/opencode/website-lifecycle-20261012-{targeted,full}.log` and the adjacent `-targeted-coverage/` / `-full-coverage/` directories. Full provenance is appended to [JavaScript verification](2026-10-11-javascript-verification.md#2026-10-12--preview-lifecycle-completed-evidence-6956-tests).

Paired `doc/reference/{en,zh-CN}/website-builder.md` preserves the current source-function/lifecycle contract and the exact preview POST/payload/iframe/saved-reload browser assertions. **Final combined RSpec (8 workers) / Playwright (4 workers): PENDING** in their execution reports. No tests or subagents ran in this integration lane, and the bounded JS evidence is not a final browser or every-route pass.
