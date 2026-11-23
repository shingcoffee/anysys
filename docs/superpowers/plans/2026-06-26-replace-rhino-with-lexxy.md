# Replace Rhino Editor with Lexxy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or executing-plans. Steps use checkbox (`- [ ]`) syntax.
>
> **Project note:** Drive via anysys-* SDLC agents. Gem/importmap/asset wiring + backend verify → `anysys-backend-developer` (Gemfile/importmap/JS/CSS are non-view, non-controller config; assign to backend-developer). View + Stimulus → `anysys-frontend-developer`. Specs → `anysys-qa-engineer`. Smoke + review → release-eng + tech-lead/code-reviewer.

**Goal:** Remove Rhino Editor and make Basecamp **Lexxy** the Action Text rich-text editor, end to end, with the email-template variable picker working against Lexxy.

**Architecture:** Lexxy (Lexical) generates canonical Action Text HTML, so the backend (`has_rich_text :body`, `Emails::CompileTemplate`) is unaffected. Lexxy overrides `form.rich_text_area` to render `<lexxy-editor>` with content load + Active Storage direct uploads. The variable picker inserts `{{token}}` via simulated typing.

**Tech Stack:** Rails 8.1, importmap-rails, propshaft, tailwindcss-rails, Action Text, Active Storage, Stimulus.

---

## File Structure

- **Modify** `Gemfile` — add `gem "lexxy", "~> 0.1.26.beta"`.
- **Modify** `config/importmap.rb` — drop rhino pin; add lexxy + activestorage pins.
- **Modify** `app/javascript/application.js` — drop rhino import/define; add `import "lexxy"`.
- **Delete** `vendor/javascript/rhino-editor.js`.
- **Modify** `app/views/layouts/dashboard.html.erb` — add `stylesheet_link_tag "lexxy"`.
- **Modify** `app/views/admin/modules/emails/templates/_form.html.erb` — Rhino block → `f.rich_text_area :body`.
- **Modify** `app/javascript/controllers/template_variable_picker_controller.js` — Lexxy insertion.
- **Modify** `app/assets/stylesheets/actiontext.css` — prune dead Trix chrome.
- **Modify** `spec/requests/admin/modules/emails/templates_spec.rb` — assert `<lexxy-editor>` + round-trip.

---

## Task 1: Install the Lexxy gem

**Files:** `Gemfile`

- [ ] **Step 1: Add the gem.** Add near the other asset/UI gems (after `gem "tailwindcss-rails"`):

```ruby
# Modern Action Text rich-text editor (Lexical-based), replaces Rhino/Trix.
gem "lexxy", "~> 0.1.26.beta"
```

- [ ] **Step 2: Install.**

Run: `bundle install`
Expected: resolves and installs `lexxy` (+ any deps). If it fails due to no network, STOP and report — do not proceed.

- [ ] **Step 3: Confirm the gem's assets are on the propshaft load path.**

Run: `bin/rails runner "puts Rails.application.assets.load_path.find('lexxy.js')&.then{'lexxy.js OK'} rescue puts('check manually')"` and `bin/rails runner "puts(Gem.loaded_specs['lexxy']&.version)"`
Expected: a lexxy version prints. (If the `assets.load_path` API differs, instead verify by booting the server in Task 7 and curling `/assets/lexxy.js`.)

- [ ] **Step 4: Commit.**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat(editor): add lexxy gem (replaces rhino)"
```

---

## Task 2: Wire JS/CSS, remove Rhino plumbing

**Files:** `config/importmap.rb`, `app/javascript/application.js`, `vendor/javascript/rhino-editor.js` (delete), `app/views/layouts/dashboard.html.erb`

- [ ] **Step 1: importmap.** In `config/importmap.rb`, remove the three rhino lines:

```ruby
# Rich text editing for Action Text is handled by Rhino Editor (TipTap-based),
# vendored as a single self-contained ESM bundle. Replaces Trix.
pin "rhino-editor" # @0.18.3 — vendor/javascript/rhino-editor.js
```

and add:

```ruby
# Rich text editing for Action Text is handled by Lexxy (Lexical-based).
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
```

- [ ] **Step 2: application.js.** Replace the rhino block:

```javascript
// Rhino Editor (TipTap-based) provides the Action Text rich-text editor,
// replacing Trix. It registers the <rhino-editor> custom element.
import { TipTapEditor } from "rhino-editor"
if (!customElements.get("rhino-editor")) {
  TipTapEditor.define()
}
```

with:

```javascript
// Lexxy (Lexical-based) provides the Action Text rich-text editor.
// Importing it registers the <lexxy-editor> custom element.
import "lexxy"
```

- [ ] **Step 3: Delete the vendored Rhino bundle.**

Run: `git rm vendor/javascript/rhino-editor.js`

- [ ] **Step 4: CSS link.** In `app/views/layouts/dashboard.html.erb`, immediately after the `stylesheet_link_tag :app …` line (≈ line 13), add:

```erb
    <%= stylesheet_link_tag "lexxy", "data-turbo-track": "reload" %>
```

- [ ] **Step 5: Sanity check importmap loads.**

Run: `bin/rails runner "Rails.application.config.importmap; puts 'importmap ok'"`
Expected: `importmap ok` (no reference to a missing rhino pin).

- [ ] **Step 6: Commit.**

```bash
git add config/importmap.rb app/javascript/application.js app/views/layouts/dashboard.html.erb
git rm --cached vendor/javascript/rhino-editor.js 2>/dev/null; git add -A vendor/javascript 2>/dev/null
git commit -m "feat(editor): pin+import lexxy, link lexxy css, remove rhino bundle"
```

---

## Task 3: Email-template form uses Lexxy via Action Text helper

**Files:** `app/views/admin/modules/emails/templates/_form.html.erb`

- [ ] **Step 1: Replace the Rhino block.** In the rich_text branch (inside `data-controller="template-variable-picker"`), replace these lines:

```erb
        <%# Rhino Editor (TipTap) — bound to the Action Text :body field via a
            hidden input it keeps in sync. Seeded with the existing rich text. %>
        <%= f.hidden_field :body, id: f.field_id(:body), value: f.object.body&.to_trix_html %>
        <rhino-editor
          input="<%= f.field_id(:body) %>"
          data-template-variable-picker-target="editor"
          data-blob-url-template="<%= rails_service_blob_url(":signed_id", ":filename") %>"
          data-direct-upload-url="<%= rails_direct_uploads_url %>"
          class="block w-full min-h-[320px] rounded-md"></rhino-editor>
```

with:

```erb
        <%# Lexxy editor — Lexxy overrides form.rich_text_area to render a
            <lexxy-editor>, auto-loading the existing Action Text body and
            wiring Active Storage direct uploads. %>
        <%= f.rich_text_area :body, class: "block w-full min-h-[320px] rounded-md" %>
```

(Leave the surrounding wrapper `<div data-controller="template-variable-picker">`, the "Insert variable" `<select>` with `data-template-variable-picker-target="picker"`, and the helper caption untouched. The `editor` Stimulus target is no longer set on the element — Task 4 locates `<lexxy-editor>` by query.)

- [ ] **Step 2: Commit.**

```bash
git add app/views/admin/modules/emails/templates/_form.html.erb
git commit -m "feat(emails): render email body with lexxy via rich_text_area"
```

---

## Task 4: Variable picker inserts into Lexxy

**Files:** `app/javascript/controllers/template_variable_picker_controller.js`

- [ ] **Step 1: Rewrite the controller.** Replace the file contents with:

```javascript
import { Controller } from "@hotwired/stimulus"

// Inserts a {{variable}} token at the editor's cursor when the user selects an
// option from the variable picker dropdown.
//
// Targets:
//   picker — the <select> containing the variable options
//
// The editor is a Lexxy <lexxy-editor> (Lexical-based). Lexical has no public
// "insert at cursor" method, so we focus the editor's contenteditable and use
// execCommand("insertText"), which fires a real beforeinput/input event that
// Lexical processes exactly like typing.
export default class extends Controller {
  static targets = ["picker"]

  insert() {
    const token = this.pickerTarget.value
    if (!token) return

    const editor = this.element.querySelector("lexxy-editor")
    const editable = editor?.querySelector('[contenteditable="true"]') || editor
    if (editable) {
      editable.focus()
      const text = `{{${token}}}`
      if (!document.execCommand("insertText", false, text)) {
        // Fallback: synthesize a beforeinput insertText event.
        editable.dispatchEvent(new InputEvent("beforeinput", {
          inputType: "insertText", data: text, bubbles: true, cancelable: true
        }))
      }
    }

    this.pickerTarget.value = ""
  }
}
```

- [ ] **Step 2: Browser-verify (deferred to Task 7).** The contenteditable selector and insertion must be confirmed in a real browser; adjust the selector there if Lexxy's DOM differs.

- [ ] **Step 3: Commit.**

```bash
git add app/javascript/controllers/template_variable_picker_controller.js
git commit -m "feat(emails): variable picker inserts into lexxy editor"
```

---

## Task 5: Prune dead Trix CSS

**Files:** `app/assets/stylesheets/actiontext.css`

- [ ] **Step 1: Inspect.** Read `app/assets/stylesheets/actiontext.css`. It is the default Action Text/Trix stylesheet. Remove rules that target editor chrome that no longer exists: any selector containing `trix-toolbar`, `trix-button`, `trix-dialog`, `trix-input`, and the `trix-editor` element rules. KEEP rules that style rendered/stored content (e.g. `.trix-content` typography, lists, `figure`, `.attachment*`) since stored Action Text bodies render with the `.trix-content` wrapper.

- [ ] **Step 2: If, after pruning, only content-display rules remain,** leave them. If the file becomes empty, replace its contents with a short comment:

```css
/* Action Text stored-content display styles live here. Editor chrome is
   provided by Lexxy (see stylesheet_link_tag "lexxy"). */
```

- [ ] **Step 3: Verify the build compiles (deferred to Task 7 asset rebuild).**

- [ ] **Step 4: Commit.**

```bash
git add app/assets/stylesheets/actiontext.css
git commit -m "chore(editor): drop dead Trix editor chrome from actiontext.css"
```

---

## Task 6: Specs

**Files:** `spec/requests/admin/modules/emails/templates_spec.rb`

- [ ] **Step 1: Read the spec** to learn its setup helpers (customer/admin sign-in, factory for `Emails::Template`, the new/edit paths). Mirror existing patterns exactly.

- [ ] **Step 2: Update/add assertions.** Where the spec renders the new/edit form, assert the Lexxy editor is present and Rhino is gone:

```ruby
it "renders the Lexxy rich-text editor on the form" do
  get new_admin_modules_emails_template_path(customer.id)  # use the spec's actual path helper
  expect(response.body).to include("lexxy-editor")
  expect(response.body).not_to include("rhino-editor")
end
```

If a rich_text create/update round-trip example exists, keep it; otherwise add one that posts a `body` and expects `body_html` to be compiled (non-blank) — reuse the spec's existing create/update example shape and its param keys.

- [ ] **Step 3: Run the email specs (single process, never concurrent).**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb spec/requests/admin/modules/emails/attachments_spec.rb`
Expected: PASS. If an example asserted `rhino-editor`/`to_trix_html`, update it (stale test for intentionally-changed production behavior).

- [ ] **Step 4: Commit.**

```bash
git add spec/requests/admin/modules/emails/templates_spec.rb
git commit -m "test(emails): assert lexxy editor renders + body round-trips"
```

---

## Task 7: Asset rebuild, browser smoke, spec run

**Files:** none (verification)

- [ ] **Step 1: Rebuild assets + boot.**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

- [ ] **Step 2: Confirm assets serve.** `curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3000/assets/lexxy.js` and the same for the lexxy stylesheet → expect 200 (the digested path may differ; grep the rendered form page head for the lexxy CSS link).

- [ ] **Step 3: Browser smoke (Chromium).** Open the email-template **new** form (`/<cid>/admin/modules/emails/templates/new`). Verify:
  - a `<lexxy-editor>` mounts (toolbar visible, typing works);
  - selecting a variable in the "Insert variable" dropdown inserts `{{token}}` at the cursor (this validates Task 4 — adjust the contenteditable selector if needed and re-commit);
  - submitting the form persists the body (edit form re-renders with the content).
  Use the project's existing browser-driving approach (playwright-core + cached Chromium).

- [ ] **Step 4: Run touched specs together.**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb spec/requests/admin/modules/emails/attachments_spec.rb spec/requests/admin/modules/emails/template_test_sends_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Confirm no stray Rhino references remain.**

Run: `grep -rniE "rhino|to_trix_html|TipTapEditor" app config vendor spec | grep -v actiontext.css`
Expected: no matches.

---

## Self-Review Notes

- **Coverage:** gem (T1), JS/CSS wiring + rhino removal (T2), form helper (T3), variable picker (T4), CSS prune (T5), specs (T6), smoke + grep-clean (T7). ✔
- **Backend:** intentionally untouched — Lexxy emits canonical Action Text HTML; `compile_body_html`/`Emails::CompileTemplate` read that. T6/T7 round-trip confirms. If a round-trip fails, escalate (do not silently edit the model).
- **Risk gates:** T1 stops on network failure; T4/T7 browser-verify the only doc-unbacked piece; T5/T7 verify CSS prune doesn't break rendering.
