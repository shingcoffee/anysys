# Simplified Email Templates Tabbed Workspace Refactor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the email template creation/edit page to replace the compact, cramped two-column layout with a highly spacious, modern Tabbed Workspace layout.

**Architecture:** Utilize Rails' Action View templates coupled with the native Stimulus `tabs` controller to partition the workspace into full-width "Compose Content", "Settings", and "Live Preview & Test-Send" screens.

**Tech Stack:** Ruby v3.2.8, Rails v8.1.2, TailwindCSS, StimulusJS

## Global Constraints
- No hard-coded user-facing strings; all delivery must go through Rails I18n translations with matching English (`en`) and Simplified Chinese (`zh-CN`) keys.
- Preserve 100% lines/branches coverage for Stimulus JS unit tests in Vitest.
- Ensure all RSpec integration tests pass with zero regressions.

---

### Task 1: Declare Workspace Tab Translation Keys

**Files:**
- Modify: `config/locales/admin_modules.en.yml:393-410`
- Modify: `config/locales/admin_modules.zh-CN.yml:393-410`

- [ ] **Step 1: Write I18n translations in English locale**
  Add keys `tab_content`, `tab_settings`, and `tab_preview` inside the `form:` block under `admin_modules.emails.templates.form` in `config/locales/admin_modules.en.yml`.
  ```yaml
        form:
          tab_content:           "Compose Content"
          tab_settings:          "Settings & Delivery"
          tab_preview:           "Live Preview & Test-Send"
          details_title:         "Template details"
  ```

- [ ] **Step 2: Write I18n translations in Chinese locale**
  Add matching keys inside the `form:` block under `admin_modules.emails.templates.form` in `config/locales/admin_modules.zh-CN.yml`.
  ```yaml
        form:
          tab_content:           "撰写内容"
          tab_settings:          "设置与发送"
          tab_preview:           "实时预览与测试发送"
          details_title:         "模板详情"
  ```

- [ ] **Step 3: Run quick ruby parse check to ensure YAML is valid**
  Run: `ruby -e "require 'yaml'; YAML.load_file('config/locales/admin_modules.en.yml'); YAML.load_file('config/locales/admin_modules.zh-CN.yml')"`
  Expected: Exit with code 0 (no syntax errors).

- [ ] **Step 4: Commit**
  ```bash
  git add config/locales/admin_modules.en.yml config/locales/admin_modules.zh-CN.yml
  git commit -m "i18n: add email template workspace tab translations"
  ```

---

### Task 2: Build Spacious Tabbed HTML Form Workspace

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

- [ ] **Step 1: Refactor form to embed Stimulus tabs controller**
  Overwrite `app/views/admin/modules/emails/templates/_form.html.erb` using a spacious, single-column tabbed layout. The tabs switcher is wired to our native `tabs` controller. Clicking the "Live Preview" tab will trigger both the tab selection AND the `remote-template-preview#loadPreview` function to refresh the preview automatically.

  ```erb
  <%= form_with model: template, scope: :email_template, url: url, method: method, local: true, class: "space-y-6" do |f| %>
    <% if template.errors.any? %>
      <%= render "shared/form_errors", resource: template %>
    <% end %>

    <% if @lint_warnings.present? && @lint_warnings[:unknown].any? %>
      <div class="rounded-md bg-yellow-50 p-4 border border-yellow-200 mb-6">
        <div class="flex">
          <div class="ml-3">
            <h3 class="text-sm font-medium text-yellow-800"><%= t("admin_modules.emails.templates.form.lint.unknown_title") %></h3>
            <div class="mt-2 text-sm text-yellow-700">
              <p><%= t("admin_modules.emails.templates.form.lint.unknown_message", vars: @lint_warnings[:unknown].map { |v| "<code class='font-mono bg-yellow-100 px-1 py-0.5 rounded'>#{v}</code>" }.join(", ")).html_safe %></p>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <%
      preview_url = template.persisted? ? 
        preview_admin_modules_emails_template_path(current_customer_id, template) : 
        preview_admin_modules_emails_templates_path(current_customer_id)

      test_send_url = template.persisted? ? 
        test_send_admin_modules_emails_template_path(current_customer_id, template) : 
        test_send_admin_modules_emails_templates_path(current_customer_id)
    %>

    <div data-controller="tabs" 
         data-tabs-active-class="border-primary text-primary" 
         data-tabs-inactive-class="border-transparent text-text-muted hover:text-text hover:border-border"
         data-controller-template-slugify="template-slugify"
         class="space-y-6"
         data-controller="template-slugify remote-template-preview"
         data-remote-template-preview-url-value="<%= preview_url %>"
         data-remote-template-preview-test-send-url-value="<%= test_send_url %>">
      
      <%# ----- Modern Workspace Tab Bar ----- %>
      <div class="border-b border-border">
        <nav class="-mb-px flex space-x-8" aria-label="Workspace tabs">
          <button type="button" 
                  data-tabs-target="tab" 
                  data-tabs-id="content" 
                  data-action="click->tabs#select" 
                  class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2 border-primary text-primary">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path></svg>
            <%= f.label nil, t("admin_modules.emails.templates.form.tab_content"), class: "cursor-pointer m-0" %>
          </button>
          <button type="button" 
                  data-tabs-target="tab" 
                  data-tabs-id="settings" 
                  data-action="click->tabs#select" 
                  class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2 border-transparent text-text-muted hover:text-text hover:border-border">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path></svg>
            <%= f.label nil, t("admin_modules.emails.templates.form.tab_settings"), class: "cursor-pointer m-0" %>
          </button>
          <button type="button" 
                  data-tabs-target="tab" 
                  data-tabs-id="preview" 
                  data-action="click->tabs#select click->remote-template-preview#loadPreview" 
                  class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2 border-transparent text-text-muted hover:text-text hover:border-border">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path></svg>
            <%= f.label nil, t("admin_modules.emails.templates.form.tab_preview"), class: "cursor-pointer m-0" %>
          </button>
        </nav>
      </div>

      <%# ================= Tab 1: Compose Content ================= %>
      <div data-tabs-target="panel" data-tabs-id="content" class="space-y-6">
        <%# ----- Details Section ----- %>
        <div class="card p-6 space-y-4">
          <h2 class="section-header"><%= t("admin_modules.emails.templates.form.details_title") %></h2>
          
          <div>
            <%= f.label :name, t("common.labels.name"), class: "form-label" %>
            <%= f.text_field :name, placeholder: t("admin_modules.emails.templates.form.name_placeholder"), 
                  class: "input-field mt-1 w-full",
                  data: { template_slugify_target: "name", action: "input->template-slugify#suggest" } %>
          </div>

          <div>
            <%= f.label :subject, t("common.labels.subject"), class: "form-label" %>
            <%= f.text_field :subject, placeholder: t("admin_modules.emails.templates.form.subject_placeholder"), class: "input-field mt-1 w-full" %>
            <p class="mt-1 text-caption">
              <%= t("admin_modules.emails.templates.form.use_variable_prefix") %>
              <code class="text-code">{{variable}}</code>
              <%= t("admin_modules.emails.templates.form.use_variable_suffix") %>
            </p>
          </div>
        </div>

        <%# ----- Email Body Editor Section (Full Width) ----- %>
        <div class="card p-6 space-y-5"
             data-controller="template-editor-mode"
             data-template-editor-mode-initial-value="<%= template.editor_type %>">
          
          <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
            <div>
              <h2 class="section-header"><%= t("admin_modules.emails.templates.form.body_title") %></h2>
              <p class="text-body-sm text-text-muted mt-0.5"><%= t("admin_modules.emails.templates.form.body_subtitle") %></p>
            </div>
            <div class="w-full sm:w-56">
              <%= f.label :editor_type, t("admin_modules.emails.templates.form.editor_label"), class: "form-label" %>
              <%= f.select :editor_type, Emails::Template::EDITOR_TYPES.map { |type| [t("admin_modules.emails.templates.form.editor_types.#{type}"), type] }, {},
                    class: "input-field mt-1",
                    data: { action: "change->template-editor-mode#switch", template_editor_mode_target: "select" } %>
            </div>
          </div>

          <%# --- Rich Text (Lexxy Mode) --- %>
          <div data-template-editor-mode-target="richContainer"
               class="<%= template.editor_type == 'rich_text' ? '' : 'hidden' %>">
            <div data-controller="template-variable-picker">
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-2">
                <label class="form-label mb-0"><%= t("admin_modules.emails.templates.form.rich_text_body") %></label>
                <div class="flex flex-wrap items-center gap-2">
                  <label class="text-caption whitespace-nowrap"><%= t("admin_modules.emails.templates.form.insert_variable") %></label>
                  <select data-template-variable-picker-target="picker"
                          data-action="change->template-variable-picker#insert"
                          class="input-field py-1.5 text-sm w-44">
                    <option value=""><%= t("admin_modules.emails.templates.form.choose_option") %></option>
                    <% catalog_fields = Emails::Campaigns::FieldCatalog.new.fields %>
                    <% catalog_fields.each do |fld| %>
                      <option value="<%= fld[:field] %>"><%= fld[:label] %></option>
                    <% end %>
                    <% (Array(template.variables) - catalog_fields.map { |fld| fld[:field] }).each do |var| %>
                      <option value="<%= var %>"><%= var %></option>
                    <% end %>
                  </select>
                </div>
              </div>

              <%= f.rich_text_area :body, class: "block w-full min-h-[320px] rounded-md" %>
              <p class="mt-1.5 text-caption"><%= t("admin_modules.emails.templates.form.rich_hint") %></p>
            </div>
          </div>

          <%# --- HTML Code (Source Mode) --- %>
          <div data-template-editor-mode-target="codeContainer"
               class="<%= template.editor_type == 'code' ? '' : 'hidden' %>">
            <div>
              <label class="form-label mb-2 block"><%= t("admin_modules.emails.templates.form.html_code") %></label>
              <%= f.text_area :body_html,
                    rows: 20,
                    class: "input-field text-mono text-sm w-full" %>
              <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.use_variable_prefix") %><code class="text-code">{{variable}}</code><%= t("admin_modules.emails.templates.form.use_variable_suffix") %></p>
            </div>
          </div>

          <%# --- Plain Text Fallback --- %>
          <div class="pt-4 border-t border-border-subtle">
            <%= f.label :body_text, t("admin_modules.emails.templates.form.plain_text_fallback"), class: "form-label" %>
            <%= f.text_area :body_text, rows: 6, placeholder: t("admin_modules.emails.templates.form.plain_text_placeholder"), class: "input-field text-mono text-sm mt-1 w-full" %>
            <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.plain_text_hint_html") %></p>
          </div>
        </div>
      </div>

      <%# ================= Tab 2: Settings & Delivery ================= %>
      <div data-tabs-target="panel" data-tabs-id="settings" class="hidden">
        <div class="card p-6">
          <h2 class="section-header mb-6"><%= t("admin_modules.emails.templates.form.details_title") %></h2>
          
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <%= f.label :key, t("common.labels.key"), class: "form-label" %>
              <%= f.text_field :key, placeholder: "lowercase_with_underscores", 
                    class: "input-field text-mono mt-1 w-full",
                    data: { template_slugify_target: "key" } %>
              <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.key_hint") %></p>
            </div>

            <div>
              <%= f.label :template_type, t("common.labels.type"), class: "form-label" %>
              <%= f.select :template_type, Emails::Template::TEMPLATE_TYPES.map { |type| [t("admin_modules.emails.templates.form.template_types.#{type}"), type] }, {}, class: "input-field mt-1 w-full" %>
            </div>

            <div>
              <%= f.label :category, t("admin_modules.emails.templates.form.category_label"), class: "form-label" %>
              <%= f.select :category, Emails::Template::CATEGORIES.map { |cat| [t("admin_modules.emails.templates.form.categories.#{cat}"), cat] }, {}, class: "input-field mt-1 w-full" %>
            </div>

            <div>
              <%= f.label :status, t("common.labels.status"), class: "form-label" %>
              <%= f.select :status, Emails::Template::STATUSES.map { |status| [t("admin_modules.emails.templates.form.statuses.#{status}"), status] }, {}, class: "input-field mt-1 w-full" %>
            </div>

            <div>
              <%= f.label :email_stream_id, t("admin_modules.emails.templates.form.stream_label"), class: "form-label" %>
              <%= f.select :email_stream_id,
                    Emails::Stream.for_current_customer.active.map { |s| [s.name, s.id] },
                    { include_blank: t("common.labels.none") },
                    class: "input-field mt-1 w-full" %>
            </div>

            <div>
              <%= f.label :variables, t("admin_modules.emails.templates.form.variables_label"), class: "form-label" %>
              <%= f.text_field :variables, value: Array(template.variables).join(", "), placeholder: "first_name, order_id", class: "input-field mt-1 w-full" %>
              <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.variables_hint") %></p>
            </div>
          </div>
        </div>
      </div>

      <%# ================= Tab 3: Live Preview & Test-Send ================= %>
      <div data-tabs-target="panel" data-tabs-id="preview" class="hidden">
        <div class="card p-6 space-y-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <h2 class="section-header mb-0.5"><%= t("email.preview.title") %></h2>
              <p class="text-body-sm text-text-muted"><%= t("admin_modules.emails.templates.edit.subtitle") %></p>
            </div>
            <button type="button"
                    class="btn btn-secondary py-2 px-4 text-sm self-start sm:self-auto flex items-center gap-2"
                    data-remote-template-preview-target="button"
                    data-action="click->remote-template-preview#loadPreview">
              <svg class="w-4 h-4 animate-spin hidden" data-remote-template-preview-target="spinner" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              <%= t("email.preview.load_button") %>
            </button>
          </div>

          <%# Simulated Email Client Frame %>
          <div class="border border-border rounded-xl overflow-hidden bg-gray-50 flex flex-col min-h-[500px]">
            <%# Client Header Bar %>
            <div class="bg-white border-b border-border p-4 space-y-2">
              <div class="flex items-center text-xs text-text-muted gap-2">
                <span class="font-semibold text-text w-16"><%= t("common.labels.subject") %>:</span>
                <span data-remote-template-preview-target="subjectPane" class="text-text font-medium">
                  <em class="text-text-muted font-normal"><%= t("email.preview.empty_placeholder") %></em>
                </span>
              </div>
            </div>

            <%# Body Mode Tabs %>
            <div class="bg-gray-100 px-4 pt-3 border-b border-border flex items-center justify-between">
              <nav class="-mb-px flex space-x-6" aria-label="Body mode tabs">
                <button type="button" data-action="click->remote-template-preview#showTab" data-tab="html" data-remote-template-preview-target="tabHtml" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-primary text-primary">
                  <%= t("email.preview.tab_html") %>
                </button>
                <button type="button" data-action="click->remote-template-preview#showTab" data-tab="text" data-remote-template-preview-target="tabText" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-transparent text-text-muted hover:text-text hover:border-border">
                  <%= t("email.preview.tab_text") %>
                </button>
              </nav>
            </div>

            <%# Render Viewport %>
            <div class="flex-grow p-4 bg-gray-50 flex flex-col">
              <div data-remote-template-preview-target="htmlPane" class="flex-grow flex flex-col">
                <iframe data-remote-template-preview-target="iframe" class="w-full flex-grow min-h-[400px] border border-border rounded-lg bg-white shadow-sm"></iframe>
              </div>

              <div data-remote-template-preview-target="textPane" class="hidden flex-grow p-4 bg-white rounded-lg text-mono text-sm whitespace-pre-wrap border border-border min-h-[400px] overflow-y-auto shadow-sm"></div>
              
              <%# Hidden Legacy Target to avoid Stimulus target errors since the controller references it %>
              <div data-remote-template-preview-target="subjectPane" class="hidden"></div>
              <button type="button" data-remote-template-preview-target="tabSubject" class="hidden"></button>
            </div>
          </div>

          <%# --- Test-Send Section --- %>
          <div class="pt-6 border-t border-border-subtle space-y-3">
            <h3 class="text-sm font-semibold text-text"><%= t("admin_modules.emails.templates.edit.send_test_label") %></h3>
            <p class="text-caption"><%= t("admin_modules.emails.templates.form.plain_text_hint_html") %></p>
            
            <div class="flex flex-col sm:flex-row gap-3 max-w-xl">
              <%= email_field_tag :to, nil, 
                    id: "dry_run_to",
                    placeholder: t("admin_modules.emails.templates.edit.send_test_placeholder"),
                    data: { remote_template_preview_target: "testEmailInput" },
                    class: "input-field text-sm py-2 px-3 flex-grow" %>
              <button type="button"
                      class="btn btn-secondary text-sm py-2 px-5 font-medium whitespace-nowrap"
                      data-remote-template-preview-target="testSendButton"
                      data-action="click->remote-template-preview#sendTestEmail">
                <%= t("admin_modules.emails.templates.edit.send_test_submit") %>
              </button>
            </div>
            <div data-remote-template-preview-target="testStatus" class="hidden"></div>
          </div>
        </div>
      </div>
    </div>

    <%# Form Submit Actions Footer %>
    <div class="flex justify-end gap-3 pt-6 border-t border-border-subtle">
      <%= link_to t("common.actions.cancel"), admin_modules_emails_templates_path(current_customer_id), class: "btn btn-secondary" %>
      <%= f.submit (template.persisted? ? t("admin_modules.emails.templates.form.update_submit") : t("admin_modules.emails.templates.form.create_submit")), class: "btn btn-primary" %>
    </div>
  <% end %>
  ```

- [ ] **Step 2: Run targeted compilation and template controller specs**
  Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb spec/requests/admin/modules/emails/template_dry_runs_spec.rb`
  Expected: All specs PASS.

- [ ] **Step 3: Commit**
  ```bash
  git add app/views/admin/modules/emails/templates/_form.html.erb
  git commit -m "feat: implement spacious tabbed template creation/edit workspace"
  ```

---

### Task 3: Verify and Rebuild Assets

**Files:**
- Modify: None (rebuild assets)

- [ ] **Step 1: Clobber precompiled assets and rebuild tailwind styles**
  Run: `bin/rails assets:clobber && bin/rails tailwindcss:build`
  Expected: Exit with code 0 (compiled `app/assets/builds/tailwind.css` successfully).

- [ ] **Step 2: Run all request and javascript controller specs to ensure full stability**
  Run: `bundle exec rspec spec/requests/admin/modules/emails/template_dry_runs_spec.rb`
  Run: `npx vitest run spec/javascript/controllers/remote_template_preview_controller.test.js spec/javascript/controllers/template_slugify_controller.test.js --config config/javascript/vitest.config.js`
  Expected: Both suites PASS with 100% JS line/branch coverage maintained.

- [ ] **Step 3: Commit**
  ```bash
  git add app/assets/builds/tailwind.css
  git commit -m "build: rebuild assets for email templates tabbed workspace layout"
  ```
