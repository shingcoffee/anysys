# Email Template ActionText + Persisted body_html Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ActionText the rich_text authoring source of truth, always persist email-ready HTML in `body_html`, and force preview/test/send through that same HTML via one sync helper.

**Architecture:** Keep `Emails::CompileTemplate` as the single ActionText-fragment → `body_html` sync (no layout chrome; CID image rewrite once). Expose `Emails::Template#sync_body_html!` used by `before_validation`, preview, and test_send. Preview stays `tracking: false`. Transport unchanged (`DeliveryMailer`).

**Tech Stack:** Rails 8.1 ActionText, ActionMailer, RSpec, existing Lexxy editor

## Global Constraints

- Authored rich_text persists via `has_rich_text :body`; authored code persists in `body_html`
- `body_html` remains `null: false` and is the canonical email HTML for every template
- One sync helper for save + unsaved preview/test — no divergent compilers
- Do not revive hand-rolled SMTP; do not replace Lexxy with ERB mailer views
- Do not commit unless the human explicitly asks

---

## File Structure

**Modify:**
- `app/models/emails/template.rb` — public `sync_body_html!`; `before_validation` calls it
- `app/services/emails/compile_template.rb` — docs/comments as save-time sync; keep fragment + CID behavior
- `app/controllers/admin/modules/emails/templates_controller.rb` — preview/test_send call `@template.sync_body_html!`
- `spec/models/emails/template_spec.rb` — persistence + sync specs
- `spec/services/emails/compile_template_spec.rb` — already covers fragment; keep/adjust
- `spec/requests/admin/modules/emails/template_previews_spec.rb` — already covers no chrome / no tracking; keep

**Unchanged:** `Emails::DeliveryMailer`, `Emails::TemplateRenderer`, Gateway/campaign enqueue, Lexxy UI

---

### Task 1: `Emails::Template#sync_body_html!`

**Files:**
- Modify: `app/models/emails/template.rb`
- Test: `spec/models/emails/template_spec.rb`

**Interfaces:**
- Produces: `Emails::Template#sync_body_html! -> self` — for `rich_text`, sets `body_html` from `Emails::CompileTemplate.call(self)` (or `""` if body blank); for `code`, no-op (leaves authored `body_html`)

- [ ] **Step 1: Write the failing specs**

Add to `spec/models/emails/template_spec.rb`:

```ruby
describe "#sync_body_html!" do
  it "writes ActionText fragment HTML into body_html for rich_text" do
    template = build(:email_template, customer: customer, editor_type: "rich_text", body_html: "stale")
    template.body = "<p>Hello <strong>world</strong> {{first_name}}</p>"
    template.sync_body_html!
    expect(template.body_html).to include("Hello")
    expect(template.body_html).to include("{{first_name}}")
    expect(template.body_html).not_to include("trix-content")
    expect(template.body_html).not_to include("BEGIN")
  end

  it "does not overwrite authored body_html for code templates" do
    template = build(:email_template, customer: customer, editor_type: "code",
                     body_html: "<p>Authored {{email}}</p>")
    template.sync_body_html!
    expect(template.body_html).to eq("<p>Authored {{email}}</p>")
  end

  it "persists synced body_html on save for rich_text" do
    template = build(:email_template, customer: customer, editor_type: "rich_text", body_html: "x")
    template.body = "<p>Persisted body</p>"
    template.save!
    expect(template.reload.body_html).to include("Persisted body")
    expect(template.body.to_plain_text).to include("Persisted body")
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/models/emails/template_spec.rb -e sync_body_html --format documentation`

Expected: FAIL — `sync_body_html!` undefined

- [ ] **Step 3: Implement `sync_body_html!` and wire `before_validation`**

In `app/models/emails/template.rb`:

```ruby
# Sync email-ready HTML from ActionText for rich_text templates.
# Code templates author body_html directly — leave it alone.
def sync_body_html!
  return self unless editor_type == "rich_text"

  self.body_html = body.present? ? Emails::CompileTemplate.call(self) : ""
  self
end

private

def compile_body_html
  sync_body_html!
end
```

Remove the old private `compile_body_html` body that duplicated this logic (keep the `before_validation :compile_body_html` callback name or rename callback to `sync_body_html!` — prefer renaming callback to `before_validation :sync_body_html!` and delete `compile_body_html`).

Preferred final shape:

```ruby
before_validation :sync_body_html!

def sync_body_html!
  return self unless editor_type == "rich_text"

  self.body_html = body.present? ? Emails::CompileTemplate.call(self) : ""
  self
end
```

Delete private `compile_body_html`.

- [ ] **Step 4: Run specs to verify they pass**

Run: `bundle exec rspec spec/models/emails/template_spec.rb -e sync_body_html --format documentation`

Expected: PASS

---

### Task 2: Preview + test_send use the same sync helper

**Files:**
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb`
- Test: `spec/requests/admin/modules/emails/template_previews_spec.rb`
- Test: `spec/requests/admin/modules/emails/template_test_sends_spec.rb` (smoke existing)

**Interfaces:**
- Consumes: `Emails::Template#sync_body_html!`

- [ ] **Step 1: Replace duplicated compile assignments**

In `preview` and `test_send`, replace:

```ruby
if @template.editor_type == "rich_text"
  @template.body_html = @template.body.present? ? ::Emails::CompileTemplate.call(@template) : ""
end
```

with:

```ruby
@template.sync_body_html!
```

Leave `tracking: false` on preview. Leave `CompileTemplate.blob_ids_for` on test_send attachments.

- [ ] **Step 2: Adjust preview spec expectation if it stubs `CompileTemplate.call`**

In `template_previews_spec.rb` rich_text context, change:

```ruby
expect(Emails::CompileTemplate).to receive(:call).with(template).and_call_original
```

to either keep (still called via `sync_body_html!`) or:

```ruby
expect_any_instance_of(Emails::Template).to receive(:sync_body_html!).and_call_original
```

Prefer stubbing/expecting `CompileTemplate.call` still — behavior unchanged.

- [ ] **Step 3: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/template_previews_spec.rb spec/requests/admin/modules/emails/template_test_sends_spec.rb --format documentation`

Expected: PASS

---

### Task 3: Document CompileTemplate as save-time sync

**Files:**
- Modify: `app/services/emails/compile_template.rb` (comments only)
- Test: `spec/services/emails/compile_template_spec.rb` (already asserts no layout chrome)

- [ ] **Step 1: Update class comment**

Replace the top-of-file description so it states:

- This is the ActionText fragment → email `body_html` sync used on save / unsaved preview
- Uses content fragment (`body.body.to_html`), never `RichText#to_s` layout
- CID rewrite for images is owned here once; DeliveryMailer inlines matching blobs
- `{{tokens}}` left for TemplateRenderer

- [ ] **Step 2: Run compile + model + preview specs**

Run: `bundle exec rspec spec/services/emails/compile_template_spec.rb spec/models/emails/template_spec.rb spec/requests/admin/modules/emails/template_previews_spec.rb --format documentation`

Expected: PASS

---

### Task 4: Verification smoke

- [ ] **Step 1: Rails runner check**

```bash
bin/rails runner '
c = Customer.first
t = Emails::Template.new(customer: c, editor_type: "rich_text", name: "Sync Check", key: "sync_check_#{SecureRandom.hex(4)}", subject: "Hi", body_html: "stale")
t.body = "<p>Hello <strong>world</strong> {{first_name}}</p>"
t.sync_body_html!
raise "chrome" if t.body_html.include?("trix-content") || t.body_html.include?("BEGIN")
raise "missing" unless t.body_html.include?("Hello") && t.body_html.include?("{{first_name}}")
puts "OK #{t.body_html.inspect}"
'
```

Expected: prints `OK` with fragment HTML

- [ ] **Step 2: Done**

No commit unless the human asks.

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| Persist ActionText + body_html for rich_text | Task 1 |
| Persist authored body_html for code | Task 1 |
| Single sync helper save/preview/test | Tasks 1–2 |
| No layout chrome in body_html | Tasks 1, 3 |
| Preview tracking false | Task 2 (preserve) |
| ActionMailer transport untouched | (no task) |
| CID once at sync | Task 3 (document; behavior kept) |
