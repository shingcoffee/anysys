# Replace Rhino Editor with Basecamp Lexxy (Action Text)

**Date:** 2026-06-26
**Goal:** Replace the Rhino Editor (TipTap-based) rich-text editor wired into Action Text with Basecamp's **Lexxy** (Lexical-based), completely. Rhino is removed; Lexxy becomes the Action Text editor.

## Background / Current State

- **Backend:** `Emails::Template` (`has_rich_text :body`) is the only rich-text surface. `before_validation :compile_body_html` compiles the Action Text `body` into `body_html` via `Emails::CompileTemplate`. Action Text partials: `app/views/layouts/action_text/contents/_content.html.erb`, `app/views/active_storage/blobs/_blob.html.erb`.
- **Frontend (Rhino — to remove):**
  - `vendor/javascript/rhino-editor.js` — vendored esm bundle (rhino-editor@0.18.3).
  - `config/importmap.rb` — `pin "rhino-editor"`.
  - `app/javascript/application.js` — `import { TipTapEditor } from "rhino-editor"` + `TipTapEditor.define()`.
  - `app/assets/stylesheets/actiontext.css` — default Trix toolbar/editor chrome styles.
  - `app/views/admin/modules/emails/templates/_form.html.erb` (rich_text branch, lines ~90-99) — `f.hidden_field :body` seeded with `to_trix_html` + `<rhino-editor input=… data-blob-url-template=… data-direct-upload-url=…>`.
  - `app/javascript/controllers/template_variable_picker_controller.js` — inserts `{{var}}` via Rhino's TipTap instance (`this.editorTarget.editor.chain().focus().insertContent(...)`).
- **Stack:** importmap-rails + propshaft + tailwindcss-rails. Admin uses `dashboard_layout`.

## Verified Lexxy facts (from basecamp.github.io/lexxy)

- Gem: `gem "lexxy", "~> 0.1.26.beta"` (pre-release; version pin required), then `bundle install`.
- importmap (propshaft): `pin "lexxy", to: "lexxy.js"` and `pin "@rails/activestorage", to: "activestorage.esm.js"` (Active Storage Direct Upload powers attachments).
- JS entrypoint: `import "lexxy"` in `application.js`.
- CSS: `<%= stylesheet_link_tag "lexxy" %>` in the layout head.
- Lexxy **overrides `form.rich_text_area` by default** to render `<lexxy-editor>`, auto-loads existing Action Text content, and configures direct uploads. (Toggle: `config.lexxy.override_action_text_defaults = false` → then `form.lexxy_rich_text_area`. We keep the default override.)
- Generates the **same canonical Action Text HTML** Action Text expects → backend unaffected.
- Events: `lexxy:initialize|change|focus|blur|file-accept|upload-*|insert-link|insert-markdown`. **No documented programmatic insert-at-cursor API.**

## Decisions

1. **Use the idiomatic `f.rich_text_area :body`** (Lexxy owns the Action Text integration: content load + direct uploads). Drop the `hidden_field`/`to_trix_html` seed and the blob-url/direct-upload data attrs.
2. **Keep Lexxy's default Action Text override** (`form.rich_text_area` → Lexxy) — no `lexxy_rich_text_area`.
3. **Variable picker** rewired to locate `<lexxy-editor>` in its own Stimulus scope and insert `{{token}}` via `document.execCommand("insertText", …)` (simulated typing Lexical processes natively). Browser-verified; fallback synthetic `InputEvent('beforeinput', {inputType:'insertText', data})` if needed.
4. **No backend changes** unless verification shows `Emails::CompileTemplate` depends on Trix-specific markup (it reads canonical AT HTML, so expected to be unaffected).
5. The editor-type toggle (rich_text vs **code**) and the plain-text fallback field are untouched.

## Changes

**Remove**
- Delete `vendor/javascript/rhino-editor.js`.
- Remove `pin "rhino-editor"` (and its comment) from `config/importmap.rb`.
- Remove the rhino import + `TipTapEditor.define()` block from `application.js`.
- Prune dead Trix editor/toolbar rules from `actiontext.css` (keep content-display rules used when rendering stored bodies; verify rendered preview).

**Add**
- `Gemfile`: `gem "lexxy", "~> 0.1.26.beta"`; `bundle install`.
- `config/importmap.rb`: `pin "lexxy", to: "lexxy.js"`, `pin "@rails/activestorage", to: "activestorage.esm.js"`.
- `application.js`: `import "lexxy"`.
- `app/views/layouts/dashboard.html.erb` head: `<%= stylesheet_link_tag "lexxy" %>`.

**Modify**
- `_form.html.erb` rich_text branch: replace the hidden_field + `<rhino-editor>` with `<%= f.rich_text_area :body, class: "block w-full min-h-[320px] rounded-md" %>` (keep the surrounding `template-variable-picker` wrapper + the picker `<select>`).
- `template_variable_picker_controller.js`: drop the `editor` target dependency on a TipTap instance; query `lexxy-editor` from `this.element`, focus its contenteditable, insert via `execCommand`.

## Authorization & Tenancy

No change. The email-templates form lives under `/:cid/admin/modules/emails/...` behind the existing admin guard; no new routes/records. Multi-tenant scoping unchanged.

## Testing

- Update `spec/requests/admin/modules/emails/templates_spec.rb`: form renders `<lexxy-editor>` (not `<rhino-editor>`); create/update round-trips a rich_text `body`; `body_html` compiles.
- Keep `attachments_spec.rb` green.
- Browser smoke (Chromium): editor mounts, variable picker inserts `{{token}}` at the cursor, content persists on submit.

## Risks

1. **Beta gem + network:** `bundle install` of `lexxy ~> 0.1.26.beta` needs network (rubygems reachable in this env — verified HTTP 200). If a later step loses network, stop and report.
2. **Undocumented insert API:** the variable picker is the only doc-unbacked piece → browser-verified, with an `InputEvent` fallback.
3. **CSS pruning:** removing Trix styles must not break rendering of already-stored bodies → verify rendered preview.

## Out of Scope

- No change to the `code` editor mode, the preview/test-send flows, or attachment storage schema.
- No re-theming of Lexxy beyond linking its stylesheet (CSS-variable overrides optional, deferred).
