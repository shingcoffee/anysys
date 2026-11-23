# Send Activity Chip Links + Templates Index UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make send-activity detail template/list links chip-style and professionalize the email templates index (stacked name+subject, Editor column, clearer actions).

**Architecture:** Extend `AdminTableComponent` with optional `subtitle:` and `display: false` column keys (safe, no `html_safe` from controllers). Update send-activity show markup to chip links. Rework templates index columns/actions; Preview deep-links to edit with `tab=preview` via existing `workspace-tabs` `active` value (server-side, no JS change).

**Tech Stack:** Rails 8.1.2, ViewComponent, Tailwind, Stimulus (existing tabs), RSpec, I18n `en` + `zh-CN`.

## Global Constraints

- I18n hard rule: no new hard-coded user-facing strings; `en` + `zh-CN` parity.
- No schema/migrations.
- Do **not** invent Figma work if MCP auth fails — match AdminPage / wizard chip / AdminTable patterns.
- Do **not** auto-commit (repo rule); skip plan “Commit” steps unless the human explicitly asks.
- Preview index action must deep-link to edit workspace; never GET the existing `POST preview` endpoint.
- Keep multi-tenant / admin auth unchanged.

## File map

| File | Responsibility |
|------|----------------|
| `app/components/admin_table_component.rb` | Filter `display: false`; expose `subtitle_for` |
| `app/components/admin_table_component.html.erb` | Render subtitle under primary cell (mobile + desktop) |
| `spec/components/admin_table_component_spec.rb` | Cover subtitle + hidden searchable columns |
| `app/views/admin/modules/emails/send_activities/show.html.erb` | Chip links for template + lists |
| `spec/requests/admin/modules/emails/send_activities_spec.rb` | Assert chip classes / links |
| `app/controllers/admin/modules/emails/templates_controller.rb` | Columns + row actions |
| `app/views/admin/modules/emails/templates/edit.html.erb` (and/or `_workspace.html.erb`) | Pass `active` tab from `params[:tab]` |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Template column headers / Preview action if needed |
| `spec/requests/admin/modules/emails/templates_spec.rb` | Index expectations |

---

### Task 1: AdminTable `subtitle:` + `display: false`

**Files:**
- Modify: `app/components/admin_table_component.rb`
- Modify: `app/components/admin_table_component.html.erb`
- Test: `spec/components/admin_table_component_spec.rb`

**Interfaces:**
- Consumes: existing column hashes
- Produces: columns with optional `subtitle: ->(row) { String }`, `display: false` (hidden from UI, still present for callers/resolvers)

- [ ] **Step 1: Write failing component specs**

Add to `spec/components/admin_table_component_spec.rb`:

```ruby
describe "subtitle" do
  it "renders a muted subtitle under the primary cell on desktop and mobile" do
    cols = [
      { key: :name, label: "Name", subtitle: ->(r) { "Subject for #{r.name}" } },
      { key: :status, label: "Status" }
    ]
    rows_with = [OpenStruct.new(id: 1, name: "Alpha", status: "active")]
    render_inline(described_class.new(
      rows: rows_with, columns: cols, pagination: pagination, params: {},
      row_path: ->(r) { "/rows/#{r.id}" }
    ))
    expect(page).to have_css("a.link", text: "Alpha")
    expect(page).to have_css(".text-text-muted", text: "Subject for Alpha")
  end
end

describe "display: false" do
  it "omits non-display columns from headers and cells but keeps them in the columns list for callers" do
    cols = [
      { key: :name, label: "Name" },
      { key: :subject, label: "Subject", display: false, searchable: true },
      { key: :status, label: "Status" }
    ]
    render_table(columns: cols)
    expect(page).to have_text("Name")
    expect(page).to have_text("Status")
    expect(page).not_to have_css("th", text: "Subject")
  end
end
```

- [ ] **Step 2: Run specs to verify they fail**

Run: `bundle exec rspec spec/components/admin_table_component_spec.rb -e "subtitle|display: false" --format documentation`  
Expected: FAIL (subtitle / Subject header still visible or missing muted subtitle)

- [ ] **Step 3: Implement**

In `admin_table_component.rb`, add:

```ruby
def visible_columns
  columns.reject { |col| col[:display] == false }
end

def subtitle_for(row, column)
  return nil unless column[:subtitle].respond_to?(:call)
  column[:subtitle].call(row).presence
end
```

In `admin_table_component.html.erb`, replace iteration over `columns` in **headers, desktop tbody, and mobile cards** with `visible_columns`. After rendering the primary cell value (inside or immediately after the name link), if `(sub = subtitle_for(row, col))`:

```erb
<p class="text-xs text-text-muted mt-0.5 truncate"><%= sub %></p>
```

Keep the name itself in the existing `link` / `link text-sm font-medium` anchor. Subtitle stays outside the anchor on desktop if nesting `<p>` in `<a>` is awkward — preferred structure:

```erb
<div class="min-w-0">
  <%= link_to row_path.call(row), class: "link", data: { turbo_frame: "_top" } do %>
    <%= cell_text(row, col) %>
  <% end %>
  <% if (sub = subtitle_for(row, col)) %>
    <p class="text-xs text-text-muted mt-0.5 truncate"><%= sub %></p>
  <% end %>
</div>
```

Apply the same pattern on mobile for `idx == 0`.

- [ ] **Step 4: Run specs to verify pass**

Run: `bundle exec rspec spec/components/admin_table_component_spec.rb --format progress`  
Expected: PASS (full file)

- [ ] **Step 5: Skip commit** (unless human asks)

---

### Task 2: Send activity detail chip links

**Files:**
- Modify: `app/views/admin/modules/emails/send_activities/show.html.erb`
- Test: `spec/requests/admin/modules/emails/send_activities_spec.rb`

**Interfaces:**
- Consumes: existing `@send_activity.email_template` / `email_lists`
- Produces: chip-styled `link_to` markup

- [ ] **Step 1: Strengthen/adjust the show request example**

In the existing example that asserts `target="_blank"` and paths (~line 354), also assert chip classes, e.g.:

```ruby
expect(response.body).to include("bg-blue-50")
expect(response.body).to include("border-blue-200")
```

- [ ] **Step 2: Run to confirm current failure or already-weak assertion**

Run: `bundle exec rspec spec/requests/admin/modules/emails/send_activities_spec.rb -e "target" --format documentation`

- [ ] **Step 3: Update show markup**

Replace template link and list links with chip classes matching the wizard chips:

```erb
<%= link_to @send_activity.email_template.name,
      admin_modules_emails_template_path(current_customer_id, @send_activity.email_template),
      target: "_blank", rel: "noopener noreferrer",
      class: "inline-flex items-center gap-1 px-2 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded border border-blue-200 hover:bg-blue-100 transition-colors" %>
```

For lists:

```erb
<div class="flex flex-wrap gap-1.5">
  <% lists.each do |list| %>
    <%= link_to list.name,
          admin_modules_emails_list_path(current_customer_id, list),
          target: "_blank", rel: "noopener noreferrer",
          class: "inline-flex items-center gap-1 px-2 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded border border-blue-200 hover:bg-blue-100 transition-colors" %>
  <% end %>
</div>
```

Remove the plain `<ul>/<li>` wrappers.

- [ ] **Step 4: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/send_activities_spec.rb -e "GET /:cid/admin/modules/emails/send_activities/:id" --format progress`  
Expected: PASS

- [ ] **Step 5: Skip commit**

---

### Task 3: Templates index columns + actions + Preview tab deep-link

**Files:**
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` (index `@columns` / `@row_actions`)
- Modify: `app/views/admin/modules/emails/templates/_workspace.html.erb` (or `edit.html.erb`) to set tabs `active` from params
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`
- Test: `spec/requests/admin/modules/emails/templates_spec.rb`

**Interfaces:**
- Consumes: Task 1 `subtitle:` / `display: false`
- Produces: index columns Template (name+subject), Editor, Status, Updated; actions Edit, Preview (`?tab=preview`), Versions, status transitions

- [ ] **Step 1: Add failing request expectations**

```ruby
it "stacks subject under the name and shows editor type" do
  template = create(:email_template, customer: customer, name: "Welcome", subject: "Hello there", editor_type: "rich_text")
  get base_path
  expect(response.body).to include("Welcome")
  expect(response.body).to include("Hello there")
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.form.editor_types.rich_text"))
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.index.columns.template"))
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.index.columns.editor"))
end

it "exposes Edit and Preview row actions" do
  template = create(:email_template, customer: customer, status: "pending")
  get base_path
  expect(response.body).to include(I18n.t("common.actions.edit"))
  expect(response.body).to include(edit_admin_modules_emails_template_path(customer, template, tab: "preview"))
end
```

Keep existing Versions / status action examples passing.

- [ ] **Step 2: Run to verify fail**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb -e "stacks subject|Edit and Preview" --format documentation`  
Expected: FAIL

- [ ] **Step 3: Locales**

In `admin_modules.en.yml` under `emails.templates.index` (create keys if missing):

```yaml
columns:
  template: "Template"
  editor: "Editor"
```

Matching `zh-CN`:

```yaml
columns:
  template: "模板"
  editor: "编辑器"
```

Reuse `common.actions.edit`. For Preview action label, reuse an existing preview key if byte-identical English exists (e.g. workspace tab “Preview”); otherwise add `admin_modules.emails.templates.actions.preview: "Preview"` / zh-CN `"预览"`.

- [ ] **Step 4: Controller columns + actions**

Replace index `@columns` / `@row_actions` roughly with:

```ruby
@columns = [
  {
    key: :name,
    label: I18n.t("admin_modules.emails.templates.index.columns.template"),
    sortable: true,
    searchable: true,
    subtitle: ->(t) { t.subject }
  },
  {
    key: :subject,
    label: I18n.t("common.labels.subject"),
    searchable: true,
    display: false
  },
  {
    key: :editor_type,
    label: I18n.t("admin_modules.emails.templates.index.columns.editor"),
    sortable: true,
    cell: ->(t) { I18n.t("admin_modules.emails.templates.form.editor_types.#{t.editor_type}") }
  },
  {
    key: :status,
    label: I18n.t("common.labels.status"),
    type: :badge,
    sortable: true,
    badge: ->(t) { { variant: t.status == "active" ? :success : :default, label: I18n.t("common.status.#{t.status}") } },
    cell: ->(t) { I18n.t("common.status.#{t.status}") }
  },
  {
    key: :updated_at,
    label: I18n.t("common.labels.updated_at"),
    type: :datetime,
    sortable: true
  }
]

@row_actions = lambda do |template|
  [
    {
      label: I18n.t("common.actions.edit"),
      path: edit_admin_modules_emails_template_path(current_customer_id, template)
    },
    {
      label: I18n.t("admin_modules.emails.templates.actions.preview"),
      path: edit_admin_modules_emails_template_path(current_customer_id, template, tab: "preview")
    },
    {
      label: I18n.t("maint_core.nav.versions"),
      path: "#",
      data: {
        turbo: "false",
        action: "versions#open",
        "versions-id-param": template.id,
        "versions-name-param": template.name
      }
    }
  ] + status_actions_for(template)
end
```

Keep `row_path` → edit (without tab).

- [ ] **Step 5: Preview tab deep-link on edit workspace**

Find the element with `data-controller` including `workspace-tabs` in `_workspace.html.erb`. Ensure it can receive an active tab. Example:

```erb
data-workspace-tabs-active-value="<%= params[:tab].presence_in(%w[edit preview]) || "" %>"
```

(Use the actual tab ids from the markup — today preview panel uses `data-tabs-id="preview"`; the compose/edit tab id may be `edit` or similar — read the file and only allow known ids.)

`TabsController#connect` already calls `show(this.activeValue)` when set — no JS change.

- [ ] **Step 6: Run templates request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb --format progress`  
Expected: PASS

- [ ] **Step 7: Skip commit**

---

### Task 4: Verification sweep

**Files:** none (run only)

- [ ] **Step 1: Run targeted suites**

```bash
bundle exec rspec \
  spec/components/admin_table_component_spec.rb \
  spec/requests/admin/modules/emails/send_activities_spec.rb \
  spec/requests/admin/modules/emails/templates_spec.rb \
  --format progress
```

Expected: 0 failures

- [ ] **Step 2: Optional smoke**

If the human wants assets: rebuild Tailwind if classes are new (chip classes already used elsewhere — usually no precompile needed). Restart only if asked.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Chip links on send activity show | Task 2 |
| Stacked name + subject | Tasks 1 + 3 |
| Editor column | Task 3 |
| Edit / Preview / Versions / status actions | Task 3 |
| Preview via edit `tab` not POST preview | Task 3 |
| Subject remains searchable | Task 3 (`display: false` subject column) |
| I18n en + zh-CN | Task 3 |
| AdminTable safe subtitle API | Task 1 |
| No schema | All |

## Placeholder scan

No TBD/TODO steps; commands and code are concrete.
