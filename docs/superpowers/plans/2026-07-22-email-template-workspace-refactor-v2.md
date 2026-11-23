# Email Template Workspace Refactor v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the email template creation and edit workspace for maximum usability, offering a spacious creation canvas and a powerful, tabbed edit view with embedded settings and version history.

**Architecture:** 
- Distinguish between creation (`!template.persisted?`) and editing (`template.persisted?`) in the shared `_form.html.erb` layout.
- Creation page presents a clean, full-width editor containing only Name, Subject, Composer, and an "Activate immediately" toggle (defaulting to unchecked/draft).
- Editing page wraps the workspace in a 3-tab layout (`section-tabs` controller): (1) Composer & Preview (split-view workspace), (2) Settings, and (3) Version History.

**Tech Stack:** Rails v8.1.2, TailwindCSS, StimulusJS (`section-tabs`), Rspec.

## Global Constraints
- Do not introduce any hardcoded user-facing strings; all copy must be fully translated under both `en` and `zh-CN`.
- Do not commit changes; leave modifications uncommitted for human review.
- Avoid modifying unrelated components; ensure multi-tenant security is strictly maintained.

---

### Task 1: Register Internationalization Keys

**Files:**
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`

**Interfaces:**
- Consumes: Existing locale structures under `admin_modules.emails.templates.form`
- Produces: Translated tabs and form status labels

- [ ] **Step 1: Add translation keys for English locale**
  Edit `config/locales/admin_modules.en.yml` and add keys for the tab names and the new status label under `admin_modules.emails.templates.form`:
  ```yaml
          activate_immediately: "Activate template immediately"
          activate_immediately_hint: "If checked, this template will be active and ready to send. Otherwise, it will be saved as a draft."
          tabs:
            composer: "✍️ Composer & Preview"
            settings: "⚙️ Settings & Delivery"
            versions: "📋 Version History"
  ```

- [ ] **Step 2: Add translation keys for Simplified Chinese locale**
  Edit `config/locales/admin_modules.zh-CN.yml` and add the same keys in Simplified Chinese:
  ```yaml
          activate_immediately: "立即启用此模板"
          activate_immediately_hint: "如果选中，此模板将处于启用状态并可供发送。否则将保存为草稿。"
          tabs:
            composer: "✍️ 编辑与预览"
            settings: "⚙️ 模板设置"
            versions: "📋 版本历史"
  ```

- [ ] **Step 3: Verify locales parse cleanly using Ruby YAML parser**
  Run:
  ```bash
  ruby -e "require 'yaml'; YAML.load_file('config/locales/admin_modules.en.yml'); YAML.load_file('config/locales/admin_modules.zh-CN.yml'); puts 'YAML Parsed successfully!'"
  ```
  Expected: Prints `YAML Parsed successfully!` with no syntax errors.

---

### Task 2: Refactor Template Creation View

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

**Interfaces:**
- Consumes: `template` object (`::Emails::Template`) in `_form.html.erb`
- Produces: A spacious, single-column creation form when `template.new_record?` is true

- [ ] **Step 1: Restructure creation form conditionally**
  Refactor `app/views/admin/modules/emails/templates/_form.html.erb`. If `!template.persisted?` (creating a new template), render only the Name, Subject, and the interactive editor (Rich Text / HTML Source, click-to-copy variables, and Plain Text fallback) stretching across the full screen. Add the "Activate immediately" checkbox.
  
  ```erb
  <%# Inside _form.html.erb %>
  <% unless template.persisted? %>
    <%# Section 1: Basic Info %>
    <div class="card p-8 space-y-6">
      <h2 class="section-header text-xl"><%= t("admin_modules.emails.templates.form.details_title") %></h2>
      <div class="space-y-4">
        <div>
          <%= f.label :name, t("common.labels.name"), class: "form-label text-base font-semibold" %>
          <%= f.text_field :name, placeholder: t("admin_modules.emails.templates.form.name_placeholder"), 
                class: "input-field mt-1.5 w-full py-3 px-4 text-base rounded-lg" %>
        </div>
        <div>
          <%= f.label :subject, t("common.labels.subject"), class: "form-label text-base font-semibold" %>
          <%= f.text_field :subject, placeholder: t("admin_modules.emails.templates.form.subject_placeholder"), 
                class: "input-field mt-1.5 w-full py-3 px-4 text-base rounded-lg" %>
        </div>
      </div>
    </div>

    <%# Section 2: Composer Editor Only %>
    <div class="card p-8 space-y-6"
         data-controller="template-editor-mode"
         data-template-editor-mode-initial-value="<%= template.editor_type %>">
      <%# Render composer controls and inputs (Rich text / Code Editor, variables board, and plain text fallback) %>
      <%# Reuse the existing editor layout in full-width mode %>
    </div>

    <%# Section 3: Simple Activate Immediately checkbox (defaults to draft) %>
    <div class="card p-8 space-y-4">
      <div class="flex items-start gap-3">
        <div class="flex items-center h-5">
          <%= f.check_box :status, { class: "h-4 w-4 rounded border-gray-300 text-primary focus:ring-primary cursor-pointer" }, "active", "draft" %>
        </div>
        <div class="text-sm">
          <%= f.label :status, t("admin_modules.emails.templates.form.activate_immediately"), class: "font-semibold text-gray-700 cursor-pointer" %>
          <p class="text-gray-500 text-xs mt-1"><%= t("admin_modules.emails.templates.form.activate_immediately_hint") %></p>
        </div>
      </div>
    </div>
  <% end %>
  ```

- [ ] **Step 2: Form submit actions**
  Ensure the cancel and create buttons are rendered beautifully at the bottom of the creation form.
  
- [ ] **Step 3: Verify creation form renders correctly in browser (manually or via specs)**
  Navigate to the creation page and confirm only basic info, the composer editor, and the "Activate immediately" checkbox are present.

---

### Task 3: Refactor Template Edit View with Tabs

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`
- Modify: `app/views/admin/modules/emails/templates/edit.html.erb`

**Interfaces:**
- Consumes: Stimulus `section-tabs` controller and `template.persisted?` check
- Produces: A multi-tab layout on the edit page (Composer & Preview, Settings, Version History)

- [ ] **Step 1: Clean up edit.html.erb actions**
  In `app/views/admin/modules/emails/templates/edit.html.erb`, remove the redundant `Versions` link button in the top right, as version history is now integrated natively inside the workspace tabs. Keep only the Delete button.

- [ ] **Step 2: Embed section-tabs container in _form.html.erb**
  When `template.persisted?` is true, wrap the form contents in a tab switcher container:
  ```erb
  <% if template.persisted? %>
    <div data-controller="section-tabs"
         data-section-tabs-active-class="border-accent text-accent font-semibold"
         data-section-tabs-inactive-class="border-transparent text-text-muted hover:text-text hover:border-gray-300"
         class="space-y-6">
      
      <%# Tabs Navigation Header %>
      <div class="border-b border-border-subtle">
        <nav class="-mb-px flex gap-6" aria-label="Template tabs">
          <a href="#" data-section-tabs-target="tab" data-section-tabs-id="composer" data-action="section-tabs#select" class="whitespace-nowrap border-b-2 px-1 py-3 text-sm">
            <%= t("admin_modules.emails.templates.form.tabs.composer") %>
          </a>
          <a href="#" data-section-tabs-target="tab" data-section-tabs-id="settings" data-action="section-tabs#select" class="whitespace-nowrap border-b-2 px-1 py-3 text-sm">
            <%= t("admin_modules.emails.templates.form.tabs.settings") %>
          </a>
          <a href="#" data-section-tabs-target="tab" data-section-tabs-id="versions" data-action="section-tabs#select" class="whitespace-nowrap border-b-2 px-1 py-3 text-sm">
            <%= t("admin_modules.emails.templates.form.tabs.versions") %>
          </a>
        </nav>
      </div>

      <%# Panel 1: Composer & Preview %>
      <div data-section-tabs-target="panel" data-section-tabs-id="composer" class="space-y-6">
        <%# Put the side-by-side workspace here (Name, Subject, Editor Columns) %>
      </div>

      <%# Panel 2: Settings %>
      <div data-section-tabs-target="panel" data-section-tabs-id="settings" class="hidden">
        <%# Put advanced Settings form fields here (Status, Key (readonly), Type, Category, Stream, Variables) %>
      </div>

      <%# Panel 3: Versions %>
      <div data-section-tabs-target="panel" data-section-tabs-id="versions" class="hidden">
        <%# Embedded Version History Panel %>
      </div>
    </div>
  <% end %>
  ```

---

### Task 4: Embed Version History inside Workspace Tab

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

**Interfaces:**
- Consumes: `@template.template_versions` association
- Produces: An embedded version history table inside Tab 3

- [ ] **Step 1: Render inline versions table**
  Within the `"versions"` panel in `_form.html.erb`, load and list the template versions directly:
  ```erb
  <div class="card p-8 space-y-6">
    <h2 class="section-header text-xl"><%= t("admin_modules.emails.templates.versions.title") %></h2>
    <p class="text-body-sm text-text-muted mt-1"><%= t("admin_modules.emails.templates.versions.description", name: template.name) %></p>

    <% versions = template.template_versions.includes(:created_by).order(created_at: :desc) %>
    <% if versions.any? %>
      <div class="bg-white rounded-lg border border-border overflow-hidden">
        <table class="min-w-full divide-y divide-gray-300">
          <thead class="bg-gray-50">
            <tr>
              <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6"><%= t("admin_modules.emails.templates.versions.columns.date") %></th>
              <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900"><%= t("admin_modules.emails.templates.versions.columns.user") %></th>
              <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900"><%= t("admin_modules.emails.templates.versions.columns.status") %></th>
              <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-6">
                <span class="sr-only">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white">
            <% versions.each do |v| %>
              <tr>
                <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm text-gray-900 sm:pl-6">
                  <%= v.created_at.to_fs(:short) %>
                </td>
                <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                  <%= v.created_by ? "#{v.created_by.first_name} #{v.created_by.last_name}" : t("admin_modules.emails.templates.versions.system") %>
                </td>
                <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                  <span class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium <%= v.snapshot['status'] == 'active' ? 'bg-green-50 text-green-700 ring-1 ring-inset ring-green-600/20' : 'bg-gray-50 text-gray-600 ring-1 ring-inset ring-gray-500/10' %>">
                    <%= t("admin_modules.emails.templates.statuses.#{v.snapshot['status']}") %>
                  </span>
                </td>
                <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 space-x-4">
                  <%= link_to t("common.actions.view"), admin_modules_emails_template_version_path(current_customer_id, template, v), class: "text-indigo-600 hover:text-indigo-900", target: "_blank" %>
                  <%= button_to t("common.actions.restore"), restore_admin_modules_emails_template_version_path(current_customer_id, template, v), method: :post, class: "inline-block text-red-600 hover:text-red-900 cursor-pointer", form: { class: "inline-block", data: { turbo_confirm: t("admin_modules.emails.templates.versions.restore_confirm") } } %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% else %>
      <div class="text-center py-8 text-gray-500 text-sm">
        <%= t("admin_modules.emails.templates.versions.no_versions", default: "No saved versions yet. Modifying template attributes will create new version snapshots.") %>
      </div>
    <% end %>
  </div>
  ```

---

### Task 5: Verify & Run Specs

**Files:**
- Test: `spec/requests/admin/modules/emails/templates_spec.rb`

**Interfaces:**
- Consumes: RSpec request test suite
- Produces: Confirmed passing specs covering creation defaulting to draft, and correct status behavior on submit

- [ ] **Step 1: Write test cases in templates_spec.rb**
  Add request test cases inside `spec/requests/admin/modules/emails/templates_spec.rb` to cover our new behavior:
  - Verify that when submitting template creation params with `status: "draft"`, it creates a draft template.
  - Verify that when submitting template creation params with `status: "active"`, it creates an active template.
  - Verify that Key, Category, Stream, and Variables are omitted on creation but are successfully default/empty initialized.

- [ ] **Step 2: Run targeted request specs**
  Run the test suite for templates:
  ```bash
  bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb
  ```
  Expected: All specs pass successfully.

- [ ] **Step 3: Run full email module suite to prevent regressions**
  Run:
  ```bash
  bundle exec rspec spec/requests/admin/modules/emails/
  ```
  Expected: All specs pass successfully.
