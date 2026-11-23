# AI Assistant — Website generation (design + plan)

Date: 2026-09-30 · Surface: `/:cid/admin/assistant` · Module: `website` (+ `ai_assistant`)

## Goal

An admin describes their business and scenario in the AI Assistant, optionally attaches photos, and
the assistant builds pages of the tenant's Website module (the same `WebsitePage` rows that
`/:cid/admin/modules/website/pages/new` creates). When the model lacks facts it cannot invent, it
asks (the existing `clarify` intent). Attached photos are looked at by the (vision) model and placed
in the section whose meaning fits the picture; the server copies them into tenant website media.

## Product rules (decided)

1. **Drafts only.** New pages are created with `published: false`. The assistant never publishes,
   never changes `published`, never touches site settings/theme, and never demotes the home page.
2. **Published pages are read-only to the assistant.** It may revise a page only when that page is
   an unpublished draft (`page_id` of a draft). A published target is a validation error; the repair
   instructions tell the model to create a new draft page instead.
3. **Home.** A new page becomes home only when the website has no home page yet (the first new page
   in the document). Revising the existing (draft) home page keeps it home with `slug: ""`.
4. **Clarify before inventing facts.** Business identity, offerings, contact details, prices, hours,
   named people and testimonials are never fabricated. When they are missing and matter, the model
   returns `clarify` with at most five numbered questions, each with a suggested default. If the admin
   says to go ahead anyway, bracketed placeholders (`[Your phone number]`) are used.
5. **Images.** Every image the admin attached in the conversation is addressed by a token
   `upload:<ActiveStorage::Attachment id>`. Image fields accept only: an `upload:N` token attached in
   this conversation, a value already used for an image on this tenant's website, or blank (blank is
   auto-filled with curated stock photography by `Websites::Skeletons.decorate_sections`).
   Hallucinated URLs are rejected.
6. **Placement pressure.** "Pending" uploads (attached in this conversation and never imported into
   website media) that a document does not place trigger **one** repair nudge. After that the
   document is applied anyway and the reply lists the images left unplaced.
7. **Internal links** (slug hrefs) must point at an existing page slug of the site or a page in the
   same document (its `slug`, or its title parameterized when `slug` is omitted).
8. **Module gate.** If the Website module is disabled for the tenant, website prompt sections are
   omitted and an `apply_website` document is answered with a localized "turn the module on" message.
   The website row is provisioned on demand (`Websites::Activities::Provision`).
9. **Size bounds.** At most `MAX_PAGES = 5` pages per document, `MAX_SECTIONS = 12` sections per
   page (Bedrock output token caps make larger single documents unreliable).
10. **Attachments.** `AiAssistant::Assistant::Attachments::MAX_FILES` goes 4 → 8 per message.
    `PromptBuilder` replays at most `MAX_REPLAYED_IMAGES = 16` newest images across history (Claude
    on Bedrock caps a request at 20 images); older images remain addressable by token in text.

Out of scope (v1): theme/site settings, publishing, deleting pages, reordering, navigation menus,
proposals/confirmation for published pages, `@` mentions of website pages.

## Wire contract (what the model emits)

```json
{
  "intent": "apply_website",
  "reply": "One or two sentences: what was built and where the photos went.",
  "pages": [
    {
      "page_id": 12,
      "title": "About us",
      "slug": "about",
      "nav_visible": true,
      "sections": [
        { "type": "hero_split", "props": { "headline": "…", "visual_url": "upload:45" } }
      ]
    }
  ]
}
```

- `page_id` optional — revise that draft page (full replacement of its sections).
- `title` required. `slug` optional (lowercase-hyphen); ignored for the home page.
- `nav_visible` optional (default true). Any other page keys (`home`, `published`, `layout_key`,
  `id`, `position`, …) are dropped.
- `sections[].type` ∈ `Websites::SectionKit::TYPES`; `props` keys come from
  `Websites::SectionFields.schema_for(type)` — unknown keys are dropped, scalars are stringified,
  arrays respect the schema `min`/`max`, selects must be one of the options, hrefs must pass
  `Websites::Href.valid?`. Image keys are `image_url` and `visual_url` (top level or inside items).
- `clarify` and `chat` intents keep the existing entity contract (`reply` only, `entities: []`).

## Interfaces (shared by all lanes — do not change signatures)

### `Websites::Assistant::Extraction` — `app/services/websites/assistant/extraction.rb`

```ruby
INTENT = "apply_website"; MAX_PAGES = 5; MAX_SECTIONS = 12
self.website_document?(text) #=> true when text decodes to a Hash whose "intent" == "apply_website"
self.parse(text)             #=> Extraction (decode! like EntityDefinitions::Assistant::Extraction)
#intent #reply #pages (Array of Hash, deep-stringified) #error
#valid?        # intent == INTENT, reply non-blank String, pages is an Array of Hashes
#persistable?  # valid? && pages.any?
#as_json       #=> { "intent" =>, "reply" =>, "pages" => }
```
JSON body extraction (fenced ```json block → whole string starting with `{` → first `{…}` span)
matches `EntityDefinitions::Assistant::Extraction#json_body`.

### `Websites::Assistant::Uploads` — `app/services/websites/assistant/uploads.rb`

```ruby
TOKEN = /\Aupload:(\d+)\z/
Upload = Struct.new(:token, :attachment, :blob, :filename, :width, :height, :orientation,
                    :message_id, :pending, keyword_init: true)
self.token_for(attachment)      #=> "upload:#{attachment.id}"
self.token?(value)              #=> Boolean
self.ordered(message)           #=> message.images.attachments sorted by id (Array)
self.manifest_line(attachments) #=> nil when empty, else e.g.
  # 'Attached images, in order: upload:45 "storefront.jpg" (landscape 1600x1067); upload:46 "chef.png"'
new(conversation:)
#all      #=> [Upload] every image on the conversation's user messages, message id then attachment id,
          #   scoped to conversation.customer_id (never another tenant/conversation)
#find(token) #=> Upload or nil (only within #all)
#pending  #=> uploads whose blob has never been imported into website media
```
`orientation` is `"landscape" | "portrait" | "square"` from blob metadata width/height when analyzed,
else nil.

### `Websites::Activities::ImportMedia` — `app/services/websites/activities/import_media.rb`

```ruby
Result = Struct.new(:success?, :url, :error, keyword_init: true)
self.call(customer:, blob:)   #=> copies blob bytes into a new tenant blob (customer_id set,
                              #   metadata website_media: true, assistant_source_blob_id: blob.id)
                              #   and returns url "/#{customer.id}/site/media/#{signed_id}".
                              #   Idempotent: an existing import for (customer, source blob) is reused.
self.imported?(customer:, blob:) #=> Boolean
```
Same type/size rules as `Websites::Activities::UploadMedia` (reuse its `TYPES`/`MAX_BYTES`). Refuses a
source blob whose `customer_id` is present and differs from `customer.id`.

### `Websites::Assistant::SchemaValidator` — `app/services/websites/assistant/schema_validator.rb`

```ruby
Result = Struct.new(:errors, :pages, :unplaced, keyword_init: true)
self.call(extraction:, website:, uploads:) #=> Result
# pages: normalized Array of Hash
#   { "page_id" => Integer|nil, "title" =>, "slug" => String|nil, "nav_visible" => Boolean,
#     "home" => Boolean (true only for the new-home rule or a revised home page),
#     "sections" => [{ "type" =>, "props" => {...} }] }   # tokens still "upload:N" here
# errors: Array<String> localized under ai_assistant.assistant.website.errors.*
# unplaced: [Upload] — uploads#pending not referenced anywhere in pages
```

### `Websites::Assistant::Processor` — `app/services/websites/assistant/processor.rb`

```ruby
MAX_REPAIR = 2
Message = Struct.new(:body, :status, :intent, :applied, :created, :updated, :pages, keyword_init: true)
self.call(text:, customer:, conversation:, chat: nil, write_guard: nil) #=> Message
```
Flow: module gate → parse → provision website → validate → (errors or first unplaced nudge →
`AiAssistant::Assistant::DocumentRepair` with `mode: :entity`, `instructions: "website_repair"`,
`parser: Extraction`) → persist under `GenerationWriteGuard.wrap(write_guard)`:
import each referenced upload (ImportMedia), rewrite tokens to URLs, then one
`WebsitePage.transaction` calling `Websites::Activities::SavePage.call(page:, params:,
structure_editable: true)` per page (new pages: `customer_id`, `website`, `published: false`,
`position` appended). Any SavePage failure rolls the whole document back and becomes repair errors.
`created`/`updated` are page titles; `pages` the persisted `WebsitePage` records (document order).
Success body = reply + `website.apply_created` / `website.apply_updated` (+ `website.unplaced_images`).

### Assistant integration (glue)

- `AiAssistant::Assistant::Artifact`: kind `"website_page"` ↔ `WebsitePage`; label = `title`;
  `resolve` returns nil for it when the Website module is disabled. `pick(website_page:, page:, flowchart:, entity:)`.
- `AiAssistant::Assistant::Progress::KEYS` gains `:website`.
- `TurnProcessor`: when `Websites::Assistant::Extraction.website_document?(loop_text)` → progress
  `:website`, run `Websites::Assistant::Processor`, result carries `website_result`; no flowchart pass.
- `Finalizer`: artifact prefers the last website page; `changes` rows
  `{ "kind" => "website_page", "action" => "created"|"updated", "name" => title }`.
- `Verify`: kind `"website_page"` → issue when sections are empty or contain an unknown type.

### Prompt layer

- `Prompt::Context`: `website_enabled?`, `website`, `website_pages`, `focused_website_page`
  (pinned artifact of kind `website_page`), `uploads` (`Websites::Assistant::Uploads`).
- New sections (each returns blank → dropped when `!context.website_enabled?`):
  `WebsiteSectionKit` (generated from SectionKit + SectionFields), `WebsiteContract`
  (`website_contract.md` + example), `WebsiteAuthoring` (`website_authoring.md`), `WebsiteCatalog`
  (pages list + focused page JSON), `WebsiteImages` (upload manifest, pending flags).
- `Composer` entity outline: `…EntityExamples, WebsiteSectionKit, WebsiteContract, WebsiteAuthoring,
  EntityCatalog, EntityFocus, WebsiteCatalog, WebsiteImages, Mentions`.
- `role.md` mentions website pages when the website sections are present.
- `PromptBuilder`: user messages list images in attachment-id order and (website enabled) append
  `Uploads.manifest_line`; newest 16 images replayed at most.
- New prompt documents: `website_authoring.md`, `website_contract.md`, `website_repair.md`.

### UI

- `ArtifactPaneComponent`: `website_page` → preview `preview_admin_modules_website_page_path`
  (`embed: 1` for the frame), open → `edit_admin_modules_website_page_path` labelled
  `artifact.open_editor`; subtitle `artifact.website_draft` / `artifact.website_published`;
  empty-state copy and kind list include website pages when the module is enabled.
- `MessageComponent#change_label`: kinds from `Artifact::KINDS`.
- `AssistantPanelComponent`: starter card `create_website` when the Website module is enabled.

## I18n keys (added up front, en + zh-CN)

`ai_assistant.assistant.prompts.create_website`, `prompt_labels.create_website`, `progress.website`,
`artifact.kinds.website_page`, `artifact.open_editor`, `artifact.website_draft`,
`artifact.website_published`, `artifact.empty_with_website`,
`artifact.empty_with_flowchart_and_website`, `website.*` (apply + errors), `verify.website_page_empty`,
`verify.website_page_unknown_section`.

## Tests

Service specs per class above; component specs for the three components; prompt section specs;
turn processor / finalizer / verify / artifact spec updates; cross-tenant: another tenant's
attachment token, another tenant's `page_id`, and another tenant's blob import are all refused.
