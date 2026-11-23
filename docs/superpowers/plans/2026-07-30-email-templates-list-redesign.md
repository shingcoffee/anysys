# Email templates list redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the email templates list so each row exposes only Edit + Preview, eliminate kebab overflow bugs, and move lifecycle / Duplicate / Delete to the template detail header.

**Architecture:** Keep `AdminTableComponent` columns/filters. Drop `@row_menu_actions` and the index `versions` Stimulus mount. Expand show-page `AdminPageComponent` actions with `status_actions_for`, mapping `method:` to `data: { turbo_method: }` because `AdminPageComponent` does not honor table-style `method:` keys.

**Tech Stack:** Rails 8.1.2, ViewComponent (`AdminTableComponent`, `AdminPageComponent`, `ButtonComponent`), Turbo (`data-turbo-method`), RSpec request specs, I18n (`en` + `zh-CN`).

**Spec:** `docs/superpowers/specs/2026-07-30-email-templates-list-redesign.md`

## Global Constraints

- Do not auto-commit; only commit when the human explicitly asks (AGENTS.md).
- No hard-coded user-facing strings; any new copy needs both `en` and `zh-CN`.
- No new Stimulus controllers; do not delete `menu_placement_controller.js` (other tables still use it).
- Out of scope: orphan `{{Token}}` / unnormalized `{{first_name}}` subject labels; global AdminTable kebab redesign.
- Run only targeted specs for this slice (not the full suite) unless auth/tenant behavior changes beyond existing coverage.

## File map

| File | Responsibility |
|------|----------------|
| `app/controllers/admin/modules/emails/templates_controller.rb` | Index: Edit+Preview `row_actions` only; remove `row_menu_actions`. Keep `status_actions_for` for show. |
| `app/views/admin/modules/emails/templates/index.html.erb` | Drop `row_menu_actions`, versions Stimulus wrapper, `VersionsModalComponent`. |
| `app/views/admin/modules/emails/templates/show.html.erb` | Append lifecycle header actions (PATCH via `turbo_method`). |
| `spec/requests/admin/modules/emails/templates_spec.rb` | Rewrite index action specs; extend show specs for status actions. |

---

### Task 1: Index — compact Edit + Preview only (TDD)

**Files:**
- Modify: `spec/requests/admin/modules/emails/templates_spec.rb` (GET index examples ~82–227)
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` (`#index` html branch)
- Modify: `app/views/admin/modules/emails/templates/index.html.erb`

**Interfaces:**
- Consumes: `AdminTableComponent` `row_actions:` lambda returning `[{ label:, path: }, ...]`
- Produces: Index HTML with Edit + Preview links; no `menu-placement` / More / Delete / Duplicate / status / Versions on the list

- [ ] **Step 1: Rewrite failing index action specs**

Replace these examples in `describe "GET /:cid/admin/modules/emails/templates"`:

1. `"keeps Preview reachable from the kebab menu"`
2. `"surfaces Edit inline and keeps secondary actions in the kebab menu"`
3. `"offers a confirmed delete from the kebab menu"`
4. `"renders actions for each status other than the current status"`
5. `"renders Versions and status actions inside the More menu"`

With:

```ruby
it "exposes Edit and Preview as compact row actions without a kebab" do
  template = create(:email_template, customer: customer, status: "draft")
  get base_path

  expect(response.body).to include(I18n.t("common.actions.edit"))
  expect(response.body).to include(edit_admin_modules_emails_template_path(customer, template))
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.actions.preview"))
  expect(response.body).to include(
    edit_admin_modules_emails_template_path(customer, template, anchor: Emails::TemplateEditorComponent::PREVIEW_ANCHOR)
  )

  expect(response.body).not_to include(%(aria-label="#{I18n.t("common.actions.more")}"))
  expect(response.body).not_to include('data-controller="menu-placement"')
  expect(response.body).not_to include("<details")
  expect(response.body).not_to include(duplicate_admin_modules_emails_template_path(customer, template))
  expect(response.body).not_to include(I18n.t("common.actions.delete"))
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.index.delete_confirm"))
  expect(response.body).not_to include('data-turbo-method="delete"')
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_active"))
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_retired"))
  expect(response.body).not_to include(I18n.t("maint_core.nav.versions"))
  expect(response.body).not_to include('data-controller="versions"')
end
```

Keep existing examples for search, status filter, messages count, token-labeled subject, result count, relative updated_at, JSON options, tenant isolation.

- [ ] **Step 2: Run the new example — expect FAIL**

Run:

```bash
bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb -e "exposes Edit and Preview as compact row actions without a kebab" --format documentation
```

Expected: FAIL because Preview is only in the kebab today and/or More/menu-placement/delete/status still appear.

- [ ] **Step 3: Update controller `#index` row actions**

In `app/controllers/admin/modules/emails/templates_controller.rb`, replace the `@row_actions` / `@row_menu_actions` block with:

```ruby
@row_actions = lambda do |template|
  [
    {
      label: I18n.t("common.actions.edit"),
      path: edit_admin_modules_emails_template_path(current_customer_id, template)
    },
    {
      label: I18n.t("admin_modules.emails.templates.actions.preview"),
      path: edit_admin_modules_emails_template_path(
        current_customer_id,
        template,
        anchor: ::Emails::TemplateEditorComponent::PREVIEW_ANCHOR
      )
    }
  ]
end
```

Delete the entire `@row_menu_actions = lambda do ... end` assignment. Keep `status_actions_for` private method (used by show in Task 2).

- [ ] **Step 4: Simplify index view**

Replace `app/views/admin/modules/emails/templates/index.html.erb` with:

```erb
<%# app/views/admin/modules/emails/templates/index.html.erb %>
<%= render AdminPageComponent.new(
      breadcrumbs: [{ label: t("admin_modules.nav.modules") }, { label: t("feature_modules.email.entries.content") }, { label: t("feature_modules.email.tabs.templates") }],
      title: t("feature_modules.email.tabs.templates"),
      description: t("admin_modules.emails.templates.index.description"),
      actions: [{ label: t("admin_modules.emails.templates.actions.new_template"), path: new_admin_modules_emails_template_path(current_customer_id), variant: :primary, icon: :plus }]
    ) do %>
  <%= render AdminTableComponent.new(
    rows:       @rows,
    columns:    @columns,
    pagination: @pagination,
    params:     params.permit(:q, :sort, :dir, :page, :per_page, :status).to_h.symbolize_keys,
    search:     { param: :q, placeholder: t("admin_modules.emails.templates.index.search_placeholder") },
    filters:    @table_filters,
    base_path:  admin_modules_emails_templates_path(current_customer_id),
    row_path:   ->(t) { admin_modules_emails_template_path(current_customer_id, t) },
    row_actions: @row_actions,
    empty_state: {
      title: t("admin_modules.emails.templates.index.empty_title"),
      description: t("admin_modules.emails.templates.index.empty_description"),
      action_path: new_admin_modules_emails_template_path(current_customer_id),
      action_text: t("admin_modules.emails.templates.actions.new_template")
    }
  ) %>
<% end %>
```

Notes:
- Remove `row_menu_actions:`
- Remove the wrapping `tag.div(data: { controller: "versions", ... })` and `VersionsModalComponent` (versions remain on show via versions index link)

- [ ] **Step 5: Run index specs**

Run:

```bash
bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb -e "GET /:cid/admin/modules/emails/templates" --format documentation
```

Expected: all index examples PASS (including the new compact-actions example; old kebab examples removed).

- [ ] **Step 6: Commit only if the human asks**

Do not commit unless explicitly requested.

---

### Task 2: Show — lifecycle actions in the header (TDD)

**Files:**
- Modify: `spec/requests/admin/modules/emails/templates_spec.rb` (GET show)
- Modify: `app/views/admin/modules/emails/templates/show.html.erb`

**Interfaces:**
- Consumes: `TemplatesController#status_actions_for(template)` → `[{ label:, path:, method: :patch }, ...]`
- Produces: Show header buttons that issue PATCH via `data-turbo-method="patch"`; Delete remains confirm-gated danger action

- [ ] **Step 1: Extend show header specs**

Update `"offers Edit, Preview, Duplicate and Delete from the detail page"` and add a lifecycle example:

```ruby
it "offers Edit, Preview, Duplicate, Delete, and lifecycle status actions from the detail page" do
  tmpl = create(:email_template, customer: customer, status: "draft")

  get "#{base_path}/#{tmpl.id}"

  expect(response.body).to include(edit_admin_modules_emails_template_path(customer, tmpl))
  expect(response.body).to include(
    edit_admin_modules_emails_template_path(customer, tmpl, anchor: Emails::TemplateEditorComponent::PREVIEW_ANCHOR)
  )
  expect(response.body).to include(duplicate_admin_modules_emails_template_path(customer, tmpl))
  expect(response.body).to include(I18n.t("common.actions.delete"))
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.edit.delete_confirm"))

  expect(response.body).to include(I18n.t("admin_modules.emails.templates.status.actions.set_active"))
  expect(response.body).to include(I18n.t("admin_modules.emails.templates.status.actions.set_retired"))
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_draft"))
  expect(response.body).to include(
    status_admin_modules_emails_template_path(customer, tmpl, status: "active")
  )
  expect(response.body).to include('data-turbo-method="patch"')
end
```

- [ ] **Step 2: Run show example — expect FAIL**

Run:

```bash
bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb -e "offers Edit, Preview, Duplicate, Delete, and lifecycle" --format documentation
```

Expected: FAIL — status action labels/paths missing from show HTML.

- [ ] **Step 3: Append lifecycle actions on show**

In `app/views/admin/modules/emails/templates/show.html.erb`, change the `actions = [...]` construction so lifecycle actions are included. `AdminPageComponent#button_kwargs_for` only passes `data:` through — it does **not** map `method:`. Convert explicitly:

```erb
<%
  token_catalog = Emails::TokenCatalog.for_customer(current_customer_id)
  display_subject = Emails::TemplateTokenCodec.tokens_to_labels(
    @template.subject, catalog: token_catalog
  )
  display_body_html = Emails::TemplateTokenCodec.tokens_to_labels(
    Emails::CompileTemplate.for_browser(@template), catalog: token_catalog
  )
  display_body_text = Emails::TemplateTokenCodec.tokens_to_labels(
    @template.body_text, catalog: token_catalog
  )
  status_actions = controller.send(:status_actions_for, @template).map do |action|
    {
      label: action[:label],
      path: action[:path],
      variant: :secondary,
      data: { turbo_method: action[:method] }
    }
  end
  actions = [
    { label: t("common.actions.edit"),
      path: edit_admin_modules_emails_template_path(current_customer_id, @template),
      variant: :primary, icon: :edit },
    { label: t("admin_modules.emails.templates.actions.preview"),
      path: edit_admin_modules_emails_template_path(current_customer_id, @template, anchor: Emails::TemplateEditorComponent::PREVIEW_ANCHOR),
      variant: :secondary },
    { label: t("common.actions.duplicate"),
      path: duplicate_admin_modules_emails_template_path(current_customer_id, @template),
      variant: :secondary,
      data: { turbo_method: :post } },
    *status_actions,
    { label: t("common.actions.delete"),
      path: admin_modules_emails_template_path(current_customer_id, @template),
      variant: :danger, icon: :trash,
      data: { turbo_method: :delete, turbo_confirm: t("admin_modules.emails.templates.edit.delete_confirm") } }
  ]
%>
```

Prefer not calling `controller.send(:status_actions_for)` long-term — if the private call feels wrong, promote a small helper on the controller:

```ruby
helper_method :template_status_actions

def template_status_actions(template = @template)
  status_actions_for(template).map do |action|
    {
      label: action[:label],
      path: action[:path],
      variant: :secondary,
      data: { turbo_method: action[:method] }
    }
  end
end
```

Then in the view: `*template_status_actions` (recommended). Keep Delete last so danger stays visually last in the header group.

- [ ] **Step 4: Run show + status specs**

Run:

```bash
bundle exec rspec \
  spec/requests/admin/modules/emails/templates_spec.rb \
  -e "GET /:cid/admin/modules/emails/templates/:id|PATCH /:cid/admin/modules/emails/templates/:id/status|exposes Edit and Preview" \
  --format documentation
```

Expected: PASS. Status PATCH examples remain green (endpoint unchanged).

- [ ] **Step 5: Commit only if the human asks**

Do not commit unless explicitly requested.

---

### Task 3: Verification pass

**Files:** none new — smoke + full templates request file

- [ ] **Step 1: Run the full templates request spec file**

```bash
bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb --format progress
```

Expected: 0 failures.

- [ ] **Step 2: Manual smoke (dev server)**

With `SKIP_AUTH=1` server on :3000:

1. Open `/81721200/admin/modules/emails/templates`
2. Confirm each row shows **Edit** and **Preview** only (no ⋮)
3. Open a draft template show page — confirm **Set active** and **Archive** appear; Delete still confirms
4. Click Archive — lands on index with flash; badge shows Archived

- [ ] **Step 3: Commit only if the human asks**

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| List Edit + Preview only; no kebab | Task 1 |
| Remove list Duplicate / Versions / status / Delete | Task 1 |
| Show keeps Edit / Preview / Duplicate / Delete | Task 2 |
| Show gains lifecycle actions via existing status endpoint | Task 2 |
| Fix kebab overflow by removing menu | Task 1 |
| Out-of-scope token label bugs | Not tasked |
| Targeted request specs | Tasks 1–3 |
| No new Stimulus | Satisfied |

No TBD/placeholder steps. `status_actions_for` → `turbo_method` mapping documented because `AdminPageComponent` differs from `AdminTableComponent`.
