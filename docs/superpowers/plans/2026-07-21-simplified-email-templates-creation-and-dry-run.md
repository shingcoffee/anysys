# Simplified Email Template Creation & Dry-Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the email template creation/editing layout into a professional split two-column responsive canvas, while enabling instant live previews and dry-run test-sending of unsaved drafts directly via AJAX.

**Architecture:** We will implement two new collection-level endpoints (`/preview` and `/test_send`) alongside the existing member endpoints, allow the controller to build unpersisted templates dynamically from parameters, and wire them to an enhanced, robust Stimulus controller that gathers live form data and drives interactive sidebar controls without page reloads.

**Tech Stack:** Rails v8.1.2, Ruby v3.2.8, TailwindCSS, StimulusJS, Action Text (Lexxy Editor), RSpec, Vitest (happy-dom)

## Global Constraints
- **Multi-Tenant Isolation:** Access to templates and sending gateways must be scoped strictly to the current customer (`current_customer`).
- **No Hardcoded User-Facing Text:** All display copy (labels, placeholders, buttons, status messages, alerts) must utilize Rails I18n translation helpers (`t("...")` or `I18n.t("...")`). English and Simplified Chinese locale files must remain completely in parity.
- **Responsive Layout:** The design must adapt seamlessly across desktop, tablet, and mobile screens using native Tailwind utility classes.
- **100% JS Test Coverage:** Any changes or additions to Javascript files under `app/javascript/` must maintain 100% line and branch coverage in Vitest tests.
- **Keep Existing Passing Specs Green:** Existing routing, request, and controller specs must continue to pass seamlessly.

---

### Task 1: Route Extensions for Unpersisted Operations

**Files:**
- Modify: `config/routes.rb`

**Interfaces:**
- Produces: `preview_admin_modules_emails_templates_path` and `test_send_admin_modules_emails_templates_path` (collection-level POST actions)

- [ ] **Step 1: Edit routes file to declare collection actions**
Edit `config/routes.rb` around the emails templates resource mapping:
```ruby
# Replace:
# resources :templates, only: %i[index new create edit update destroy] do
#   resources :versions, only: %i[index show], controller: "template_versions" do
#     member { post :restore }
#   end
#   member do
#     post :test_send
#     post :preview
#   end
# end

# With:
resources :templates, only: %i[index new create edit update destroy] do
  resources :versions, only: %i[index show], controller: "template_versions" do
    member { post :restore }
  end
  member do
    post :test_send
    post :preview
  end
  collection do
    post :test_send
    post :preview
  end
end
```

- [ ] **Step 2: Run routing specs to verify routes are registered**
Run: `bundle exec rspec spec/routing/admin/modules/emails/emails_routing_spec.rb`
Expected: Passes or fails with no other routing issues.

- [ ] **Step 3: Stage changes**
Run: `git add config/routes.rb`

---

### Task 2: Controller Enhancements for Unpersisted Templates

**Files:**
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb`

**Interfaces:**
- Consumes: `template_params` and `params[:id]`
- Produces: `preview` and `test_send` controller actions supporting unpersisted/unsaved template parameters and returning AJAX-friendly HTML or JSON formats.

- [ ] **Step 1: Update before_action filter**
Modify lines 9-10 in `app/controllers/admin/modules/emails/templates_controller.rb` so `@template` is only loaded from the DB if `params[:id]` is present (skips for collection preview/test-send actions):
```ruby
# Replace:
# before_action :load_template, only: %i[edit update destroy test_send preview]

# With:
before_action :load_template, only: %i[edit update destroy test_send preview], if: -> { params[:id].present? }
```

- [ ] **Step 2: Update `preview` action to support params-driven unsaved templates**
Revise `preview` to instantiate a new template if `@template` is nil (collection endpoint), and merge `template_params` into the template instance so users can preview unsaved drafts or edits:
```ruby
# Replace:
#       def preview
#         vars_param = params[:vars]
# 
#         vars = if vars_param.present?
#                  vars_param.is_a?(String) ? JSON.parse(vars_param) : vars_param.to_unsafe_h
#         else
#                  ::Emails::VariableContext.for(user: current_user)
#         end
# 
#         if @template.editor_type == "rich_text"
#           @template.body_html = ::Emails::CompileTemplate.call(@template)
#         end
# 
#         stream = @template.email_stream ||
#                  ::Emails::Streams::DefaultForKind.call(customer: current_customer, kind: "transactional")
#         rendered = ::Emails::TemplateRenderer.render(
#           template:   @template,
#           vars:       vars,
#           tracking:   stream&.tracking_enabled?,
#           message_id: SecureRandom.uuid
#         )
# 
#         render json: {
#           subject: rendered[:subject],
#           body_html: rendered[:body_html],
#           body_text: rendered[:body_text]
#         }
#       rescue JSON::ParserError
#         render json: { error: t("admin_modules.emails.templates.preview.invalid_json") }, status: :unprocessable_entity
#       end

# With:
      def preview
        if params[:email_template].present?
          @template ||= ::Emails::Template.new(customer: current_customer)
          @template.assign_attributes(template_params)
        end

        # Return empty responses safely if the template has no basic info
        @template ||= ::Emails::Template.new(customer: current_customer, editor_type: "code", body_html: "")

        vars_param = params[:vars]
        vars = if vars_param.present?
                 vars_param.is_a?(String) ? JSON.parse(vars_param) : vars_param.to_unsafe_h
        else
                 ::Emails::VariableContext.for(user: current_user)
        end

        if @template.editor_type == "rich_text"
          @template.body_html = @template.body.present? ? ::Emails::CompileTemplate.call(@template) : ""
        end

        stream = @template.email_stream ||
                 ::Emails::Streams::DefaultForKind.call(customer: current_customer, kind: "transactional")
        rendered = ::Emails::TemplateRenderer.render(
          template:   @template,
          vars:       vars,
          tracking:   stream&.tracking_enabled?,
          message_id: SecureRandom.uuid
        )

        render json: {
          subject: rendered[:subject],
          body_html: rendered[:body_html],
          body_text: rendered[:body_text]
        }
      rescue JSON::ParserError
        render json: { error: t("admin_modules.emails.templates.preview.invalid_json") }, status: :unprocessable_entity
      end
```

- [ ] **Step 3: Update `test_send` action to support params-driven unsaved templates**
Revise `test_send` to build from `template_params` if `@template` is nil (collection endpoint), support overriding details on edit-page test-sends, and introduce AJAX-ready `respond_to` JSON blocks:
```ruby
# Replace:
#       def test_send
#         recipients = (params[:to].presence || current_user.email).to_s
#                        .split(",").map(&:strip).reject(&:empty?)
# 
#         invalid = recipients.reject { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }
#         if invalid.any?
#           redirect_to("/#{current_customer.id}/admin/modules/emails/templates",
#                       alert: t("admin_modules.flash.templates.invalid_email", email: invalid.first)) and return
#         end
# 
#         vars = ::Emails::VariableContext.for(user: current_user)
# 
#         recipients.each do |to|
#           rendered = ::Emails::TemplateRenderer.render(template: @template, vars: vars)
# 
#           ::Emails::Gateway.send_raw(
#             customer:            current_customer,
#             to:                  to,
#             subject:             rendered[:subject],
#             body_html:           rendered[:body_html],
#             body_text:           rendered[:body_text],
#             attachment_blob_ids: ::Emails::CompileTemplate.blob_ids_for(@template)
#           )
#         end
# 
#         notice = if recipients.size == 1
#                    t("admin_modules.flash.templates.test_sent", email: recipients.first)
#         else
#                    t("admin_modules.flash.templates.test_sent_multi", count: recipients.size)
#         end
# 
#         redirect_to(
#           request.referer || "/#{current_customer.id}/admin/modules/emails/templates",
#           notice: notice
#         )
#       end

# With:
      def test_send
        if params[:email_template].present?
          @template ||= ::Emails::Template.new(customer: current_customer)
          @template.assign_attributes(template_params)
        end

        @template ||= ::Emails::Template.new(customer: current_customer, editor_type: "code", body_html: "")

        if @template.editor_type == "rich_text"
          @template.body_html = @template.body.present? ? ::Emails::CompileTemplate.call(@template) : ""
        end

        recipients = (params[:to].presence || current_user.email).to_s
                       .split(",").map(&:strip).reject(&:empty?)

        invalid = recipients.reject { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }
        if invalid.any?
          respond_to do |format|
            format.html do
              redirect_to("/#{current_customer.id}/admin/modules/emails/templates",
                          alert: t("admin_modules.flash.templates.invalid_email", email: invalid.first))
            end
            format.json do
              render json: { success: false, error: t("admin_modules.flash.templates.invalid_email", email: invalid.first) }, status: :unprocessable_entity
            end
          end
          return
        end

        vars = ::Emails::VariableContext.for(user: current_user)

        recipients.each do |to|
          rendered = ::Emails::TemplateRenderer.render(template: @template, vars: vars)

          ::Emails::Gateway.send_raw(
            customer:            current_customer,
            to:                  to,
            subject:             rendered[:subject],
            body_html:           rendered[:body_html],
            body_text:           rendered[:body_text],
            attachment_blob_ids: ::Emails::CompileTemplate.blob_ids_for(@template)
          )
        end

        notice = if recipients.size == 1
                   t("admin_modules.flash.templates.test_sent", email: recipients.first)
                 else
                   t("admin_modules.flash.templates.test_sent_multi", count: recipients.size)
                 end

        respond_to do |format|
          format.html do
            redirect_to(
              request.referer || "/#{current_customer.id}/admin/modules/emails/templates",
              notice: notice
            )
          end
          format.json do
            render json: { success: true, message: notice }
          end
        end
      end
```

- [ ] **Step 4: Run controller request specs to verify existing member endpoints**
Run: `bundle exec rspec spec/requests/admin/modules/emails/template_previews_spec.rb` and `spec/requests/admin/modules/emails/template_test_sends_spec.rb`
Expected: PASS

- [ ] **Step 5: Stage changes**
Run: `git add app/controllers/admin/modules/emails/templates_controller.rb`

---

### Task 3: Interactive Dry-Run & Preview Controller (JavaScript)

**Files:**
- Modify: `app/javascript/controllers/remote_template_preview_controller.js`
- Create: `spec/javascript/controllers/remote_template_preview_controller.test.js`

**Interfaces:**
- Consumes: Form DOM elements (`#email_template_subject`, `[name="email_template[body_html]"]`, Lexxy hidden input, setting selects)
- Produces: On-demand AJAX compilation/rendering and background test delivery with inline loader feedback and notifications.

- [ ] **Step 1: Rewrite `remote_template_preview_controller.js`**
Replace `app/javascript/controllers/remote_template_preview_controller.js` with an extremely robust, fully featured interactive agent that scrapes form values on demand to support dry-run previews & AJAX test-sends:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "button", "subjectPane", "htmlPane", "textPane", 
    "tabSubject", "tabHtml", "tabText", "iframe",
    "testEmailInput", "testSendButton", "testStatus"
  ]
  static values = { 
    url: String, 
    testSendUrl: String,
    loadingLabel: { type: String, default: "Loading..." },
    sendingLabel: { type: String, default: "Sending..." }
  }

  // Gather current form field values into an API-compatible nested structure
  getFormData() {
    const root = this.element.closest("form") || document
    
    const name = root.querySelector('[name="email_template[name]"]')?.value || ""
    const key = root.querySelector('[name="email_template[key]"]')?.value || ""
    const subject = root.querySelector('[name="email_template[subject]"]')?.value || ""
    const editorType = root.querySelector('[name="email_template[editor_type]"]')?.value || "code"
    
    // Lexxy editor stores Action Text HTML in a hidden field with name "email_template[body]"
    const body = root.querySelector('[name="email_template[body]"]')?.value || ""
    const bodyHtml = root.querySelector('[name="email_template[body_html]"]')?.value || ""
    const bodyText = root.querySelector('[name="email_template[body_text]"]')?.value || ""
    const templateType = root.querySelector('[name="email_template[template_type]"]')?.value || "transactional"
    const category = root.querySelector('[name="email_template[category]"]')?.value || ""
    const status = root.querySelector('[name="email_template[status]"]')?.value || "draft"
    const emailStreamId = root.querySelector('[name="email_template[email_stream_id]"]')?.value || ""
    const variables = root.querySelector('[name="email_template[variables]"]')?.value || ""

    return {
      email_template: {
        name, key, subject, editor_type: editorType,
        body, body_html: bodyHtml, body_text: bodyText,
        template_type: templateType, category, status,
        email_stream_id: emailStreamId, variables
      }
    }
  }

  async loadPreview(event) {
    if (event) event.preventDefault()

    this.buttonTarget.disabled = true
    const originalText = this.buttonTarget.textContent
    this.buttonTarget.textContent = this.loadingLabelValue

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ""
      const payload = this.getFormData()

      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })

      if (!response.ok) throw new Error("Failed to load preview")
      
      const data = await response.json()
      
      if (this.hasSubjectPaneTarget) {
        this.subjectPaneTarget.textContent = data.subject || "(Empty Subject)"
      }
      
      if (this.hasIframeTarget) {
        this.iframeTarget.srcdoc = this.wrapContent(data.body_html || "")
      }
      
      if (this.hasTextPaneTarget) {
        this.textPaneTarget.textContent = data.body_text || "(Empty Text)"
      }
      
    } catch (error) {
      console.error(error)
      alert("Error loading preview")
    } finally {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = originalText
    }
  }

  async sendTestEmail(event) {
    if (event) event.preventDefault()

    const to = this.testEmailInputTarget.value.trim()
    if (!to) {
      this.showStatus("Please enter an email address", "error")
      return
    }

    this.testSendButtonTarget.disabled = true
    const originalText = this.testSendButtonTarget.textContent
    this.testSendButtonTarget.textContent = this.sendingLabelValue
    this.clearStatus()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ""
      const payload = {
        ...this.getFormData(),
        to: to
      }

      const response = await fetch(this.testSendUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })

      const data = await response.json()

      if (response.ok && data.success) {
        this.showStatus(data.message, "success")
        this.testEmailInputTarget.value = ""
      } else {
        this.showStatus(data.error || "Failed to send test email", "error")
      }
    } catch (error) {
      console.error(error)
      this.showStatus("Network error sending test email", "error")
    } finally {
      this.testSendButtonTarget.disabled = false
      this.testSendButtonTarget.textContent = originalText
    }
  }

  showStatus(message, type) {
    if (!this.hasTestStatusTarget) return
    this.testStatusTarget.textContent = message
    this.testStatusTarget.className = "mt-2 text-xs font-medium " + 
      (type === "success" ? "text-green-600 dark:text-green-400" : "text-red-600 dark:text-red-400")
    this.testStatusTarget.classList.remove("hidden")
  }

  clearStatus() {
    if (!this.hasTestStatusTarget) return
    this.testStatusTarget.textContent = ""
    this.testStatusTarget.classList.add("hidden")
  }

  showTab(event) {
    if (event) event.preventDefault()
    const tabName = event.currentTarget.dataset.tab

    if (this.hasSubjectPaneTarget) this.subjectPaneTarget.classList.add("hidden")
    if (this.hasHtmlPaneTarget) this.htmlPaneTarget.classList.add("hidden")
    if (this.hasTextPaneTarget) this.textPaneTarget.classList.add("hidden")

    if (this.hasTabSubjectTarget) this.deactivateTab(this.tabSubjectTarget)
    if (this.hasTabHtmlTarget) this.deactivateTab(this.tabHtmlTarget)
    if (this.hasTabTextTarget) this.deactivateTab(this.tabTextTarget)

    if (tabName === "subject" && this.hasSubjectPaneTarget) {
      this.subjectPaneTarget.classList.remove("hidden")
      if (this.hasTabSubjectTarget) this.activateTab(this.tabSubjectTarget)
    } else if (tabName === "html" && this.hasHtmlPaneTarget) {
      this.htmlPaneTarget.classList.remove("hidden")
      if (this.hasTabHtmlTarget) this.activateTab(this.tabHtmlTarget)
    } else if (tabName === "text" && this.hasTextPaneTarget) {
      this.textPaneTarget.classList.remove("hidden")
      if (this.hasTabTextTarget) this.activateTab(this.tabTextTarget)
    }
  }

  activateTab(el) {
    el.classList.add("border-primary", "text-primary")
    el.classList.remove("border-transparent", "text-text-muted", "hover:text-text", "hover:border-border")
  }

  deactivateTab(el) {
    el.classList.remove("border-primary", "text-primary")
    el.classList.add("border-transparent", "text-text-muted", "hover:text-text", "hover:border-border")
  }

  wrapContent(html) {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 16px; line-height: 1.5; }
    img { max-width: 100%; height: auto; }
  </style>
</head>
<body>${html}</body>
</html>`
  }
}
```

- [ ] **Step 2: Create Vitest Unit Tests (`spec/javascript/controllers/remote_template_preview_controller.test.js`)**
Ensure robust 100% line & branch test-suite coverage.
```javascript
import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/remote_template_preview_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = () => `
<form data-controller="remote-template-preview" 
      data-remote-template-preview-url-value="/preview"
      data-remote-template-preview-test-send-url-value="/test_send">
  <input name="email_template[name]" value="Test Name" />
  <input name="email_template[key]" value="test_key" />
  <input id="email_template_subject" name="email_template[subject]" value="Hello {{first_name}}" />
  <select name="email_template[editor_type]"><option value="code" selected>Code</option></select>
  <textarea name="email_template[body_html]"><h1>Hi</h1></textarea>
  <textarea name="email_template[body_text]">Hi plain</textarea>
  <select name="email_template[template_type]"><option value="transactional" selected>Transactional</option></select>
  <select name="email_template[category]"><option value="account" selected>Account</option></select>
  <select name="email_template[status]"><option value="draft" selected>Draft</option></select>
  <input name="email_template[variables]" value="first_name" />

  <button type="button" data-remote-template-preview-target="button" data-action="click->remote-template-preview#loadPreview">Load</button>
  <div data-remote-template-preview-target="subjectPane"></div>
  <div data-remote-template-preview-target="htmlPane">
    <iframe data-remote-template-preview-target="iframe"></iframe>
  </div>
  <div data-remote-template-preview-target="textPane"></div>

  <button type="button" data-remote-template-preview-target="tabSubject" data-action="click->remote-template-preview#showTab" data-tab="subject">Subject</button>
  <button type="button" data-remote-template-preview-target="tabHtml" data-action="click->remote-template-preview#showTab" data-tab="html">HTML</button>
  <button type="button" data-remote-template-preview-target="tabText" data-action="click->remote-template-preview#showTab" data-tab="text">Text</button>

  <input data-remote-template-preview-target="testEmailInput" value="test@example.com" />
  <button type="button" data-remote-template-preview-target="testSendButton" data-action="click->remote-template-preview#sendTestEmail">Send Test</button>
  <div data-remote-template-preview-target="testStatus" class="hidden"></div>
</form>
`

describe("remote-template-preview controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("gathers all form inputs successfully into the getFormData hash", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const data = ctrl.getFormData()
    expect(data.email_template.name).toBe("Test Name")
    expect(data.email_template.key).toBe("test_key")
    expect(data.email_template.subject).toBe("Hello {{first_name}}")
    expect(data.email_template.editor_type).toBe("code")
    expect(data.email_template.body_html).toBe("<h1>Hi</h1>")
    expect(data.email_template.body_text).toBe("Hi plain")
    expect(data.email_template.variables).toBe("first_name")
  })

  it("loads the preview successfully and populates pane and iframe contents", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        subject: "Hello Alice",
        body_html: "<h1>Hi Alice</h1>",
        body_text: "Hi Alice plain"
      })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.loadPreview()

    expect(fakeFetch).toHaveBeenCalledWith("/preview", expect.any(Object))
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").textContent).toBe("Hello Alice")
    expect(element.querySelector("[data-remote-template-preview-target='iframe']").srcdoc).toContain("<h1>Hi Alice</h1>")
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").textContent).toBe("Hi Alice plain")
  })

  it("handles preview fetch error gracefully", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({ ok: false })
    vi.stubGlobal("fetch", fakeFetch)
    const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => {})

    await ctrl.loadPreview()

    expect(alertSpy).toHaveBeenCalledWith("Error loading preview")
  })

  it("switches tabs successfully on showTab", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    // Show HTML tab
    ctrl.showTab({ currentTarget: element.querySelector("[data-tab='html']"), preventDefault: () => {} })
    expect(element.querySelector("[data-remote-template-preview-target='htmlPane']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-remote-template-preview-target='subjectPane']").classList.contains("hidden")).toBe(true)

    // Show text tab
    ctrl.showTab({ currentTarget: element.querySelector("[data-tab='text']"), preventDefault: () => {} })
    expect(element.querySelector("[data-remote-template-preview-target='textPane']").classList.contains("hidden")).toBe(false)
  })

  it("sends a test email successfully and displays the message", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: true, message: "Email sent successfully!" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    expect(fakeFetch).toHaveBeenCalledWith("/test_send", expect.any(Object))
    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toBe("Email sent successfully!")
    expect(statusEl.classList.contains("hidden")).toBe(false)
  })

  it("displays an error message when dry-run test-send fails", async () => {
    const { application, element } = await mountController("remote-template-preview", Controller, html())
    const ctrl = controllerFor(application, element, "remote-template-preview")

    const fakeFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ success: false, error: "Invalid email domain" })
    })
    vi.stubGlobal("fetch", fakeFetch)

    await ctrl.sendTestEmail()

    const statusEl = element.querySelector("[data-remote-template-preview-target='testStatus']")
    expect(statusEl.textContent).toBe("Invalid email domain")
  })
})
```

- [ ] **Step 3: Run Vitest specs to verify 100% JS coverage**
Run: `npx vitest run spec/javascript/controllers/remote_template_preview_controller.test.js --coverage`
Expected: 100% Lines, Branches, Functions coverage for the new controller.

- [ ] **Step 4: Stage changes**
Run: `git add app/javascript/controllers/remote_template_preview_controller.js spec/javascript/controllers/remote_template_preview_controller.test.js`

---

### Task 4: Template Name-to-Key Auto-Slugifier (JavaScript)

**Files:**
- Create: `app/javascript/controllers/template_slugify_controller.js`
- Create: `spec/javascript/controllers/template_slugify_controller.test.js`

**Interfaces:**
- Consumes: Input event on Name input field
- Produces: Downcased, snake_cased alphanumeric slug written directly to Key field (only on template creation, or if Key field is pristine/empty).

- [ ] **Step 1: Write `template_slugify_controller.js`**
Create a tiny helper to keep creation page pristine and key generation dead simple:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "key"]

  connect() {
    this.isNewRecord = this.keyTarget.value === ""
  }

  suggest() {
    if (!this.isNewRecord) return

    const slug = this.nameTarget.value
      .toLowerCase()
      .replace(/[^a-z0-9\s_]/g, "")
      .replace(/\s+/g, "_")
      .substring(0, 50)

    this.keyTarget.value = slug
  }
}
```

- [ ] **Step 2: Create Vitest Unit Tests (`spec/javascript/controllers/template_slugify_controller.test.js`)**
Add full coverage test for the new helper:
```javascript
import { describe, it, expect } from "vitest"
import Controller from "controllers/template_slugify_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (keyVal = "") => `
<div data-controller="template-slugify">
  <input data-template-slugify-target="name" data-action="input->template-slugify#suggest" value="" />
  <input data-template-slugify-target="key" value="${keyVal}" />
</div>
`

describe("template-slugify controller", () => {
  it("slugifies standard text successfully", async () => {
    const { application, element } = await mountController("template-slugify", Controller, html())
    const ctrl = controllerFor(application, element, "template-slugify")

    element.querySelector("[data-template-slugify-target='name']").value = "Welcome Email Template!"
    ctrl.suggest()

    expect(element.querySelector("[data-template-slugify-target='key']").value).toBe("welcome_email_template")
  })

  it("does not overwrite an existing key values on load", async () => {
    const { application, element } = await mountController("template-slugify", Controller, html("fixed_key"))
    const ctrl = controllerFor(application, element, "template-slugify")

    element.querySelector("[data-template-slugify-target='name']").value = "New Title"
    ctrl.suggest()

    expect(element.querySelector("[data-template-slugify-target='key']").value).toBe("fixed_key")
  })
})
```

- [ ] **Step 3: Run Vitest specs to verify 100% JS coverage**
Run: `npx vitest run spec/javascript/controllers/template_slugify_controller.test.js --coverage`
Expected: 100% Lines, Branches, Functions coverage.

- [ ] **Step 4: Stage changes**
Run: `git add app/javascript/controllers/template_slugify_controller.js spec/javascript/controllers/template_slugify_controller.test.js`

---

### Task 5: Two-Column Form Layout Rewrite

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

- [ ] **Step 1: Replace form layout template**
Rewrite `app/views/admin/modules/emails/templates/_form.html.erb` completely to move settings into a responsive sidebar card, re-structure basic content/editor into primary left card, and embed our brand-new live interactive Dry-Run testing section:
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

  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6" data-controller="template-slugify">
    <%# ===== Primary Left Column: Content Canvas (2/3 width) ================= %>
    <div class="lg:col-span-2 space-y-6">
      <%# ----- Primary Details ----- %>
      <div class="card p-6 space-y-4">
        <h2 class="section-header"><%= t("admin_modules.emails.templates.form.details_title") %></h2>
        
        <div>
          <%= f.label :name, t("common.labels.name"), class: "form-label" %>
          <%= f.text_field :name, placeholder: t("admin_modules.emails.templates.form.name_placeholder"), 
                class: "input-field mt-1",
                data: { template_slugify_target: "name", action: "input->template-slugify#suggest" } %>
        </div>

        <div>
          <%= f.label :subject, t("common.labels.subject"), class: "form-label" %>
          <%= f.text_field :subject, placeholder: t("admin_modules.emails.templates.form.subject_placeholder"), class: "input-field mt-1" %>
          <p class="mt-1 text-caption">
            <%= t("admin_modules.emails.templates.form.use_variable_prefix") %>
            <code class="text-code">{{variable}}</code>
            <%= t("admin_modules.emails.templates.form.use_variable_suffix") %>
          </p>
        </div>
      </div>

      <%# ----- Email Body Editor ----- %>
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
             data-controller="template-preview"
             data-template-preview-empty-placeholder-value="<%= t("admin_modules.emails.templates.form.preview_empty_placeholder") %>"
             class="<%= template.editor_type == 'code' ? '' : 'hidden' %>">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <div>
              <label class="form-label mb-2 block"><%= t("admin_modules.emails.templates.form.html_code") %></label>
              <%= f.text_area :body_html,
                    rows: 16,
                    data: { template_preview_target: "source", action: "input->template-preview#sourceChanged" },
                    class: "input-field text-mono text-sm w-full" %>
              <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.use_variable_prefix") %><code class="text-code">{{variable}}</code><%= t("admin_modules.emails.templates.form.use_variable_suffix") %></p>
            </div>
            <div>
              <label class="form-label mb-2 block"><%= t("admin_modules.emails.templates.form.live_preview") %></label>
              <iframe data-template-preview-target="preview"
                      class="w-full h-[360px] border border-border rounded-md bg-white"></iframe>
            </div>
          </div>
        </div>

        <%# --- Plain Text Fallback --- %>
        <div class="pt-4 border-t border-border-subtle">
          <%= f.label :body_text, t("admin_modules.emails.templates.form.plain_text_fallback"), class: "form-label" %>
          <%= f.text_area :body_text, rows: 4, placeholder: t("admin_modules.emails.templates.form.plain_text_placeholder"), class: "input-field text-mono text-sm mt-1" %>
          <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.plain_text_hint_html") %></p>
        </div>
      </div>
    </div>

    <%# ===== Secondary Right Column: Settings & Dry-Run (1/3 width) =========== %>
    <div class="lg:col-span-1 space-y-6">
      <%# ----- Metadata / Configuration Settings ----- %>
      <div class="card p-6 space-y-4">
        <h3 class="section-header"><%= t("admin_modules.emails.templates.form.details_title") %></h3>

        <div>
          <%= f.label :key, t("common.labels.key"), class: "form-label" %>
          <%= f.text_field :key, placeholder: "lowercase_with_underscores", 
                class: "input-field text-mono mt-1",
                data: { template_slugify_target: "key" } %>
          <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.key_hint") %></p>
        </div>

        <div>
          <%= f.label :template_type, t("common.labels.type"), class: "form-label" %>
          <%= f.select :template_type, Emails::Template::TEMPLATE_TYPES.map { |type| [t("admin_modules.emails.templates.form.template_types.#{type}"), type] }, {}, class: "input-field mt-1" %>
        </div>

        <div>
          <%= f.label :category, t("admin_modules.emails.templates.form.category_label"), class: "form-label" %>
          <%= f.select :category, Emails::Template::CATEGORIES.map { |cat| [t("admin_modules.emails.templates.form.categories.#{cat}"), cat] }, {}, class: "input-field mt-1" %>
        </div>

        <div>
          <%= f.label :status, t("common.labels.status"), class: "form-label" %>
          <%= f.select :status, Emails::Template::STATUSES.map { |status| [t("admin_modules.emails.templates.form.statuses.#{status}"), status] }, {}, class: "input-field mt-1" %>
        </div>

        <div>
          <%= f.label :email_stream_id, t("admin_modules.emails.templates.form.stream_label"), class: "form-label" %>
          <%= f.select :email_stream_id,
                Emails::Stream.for_current_customer.active.map { |s| [s.name, s.id] },
                { include_blank: t("common.labels.none") },
                class: "input-field mt-1" %>
        </div>

        <div>
          <%= f.label :variables, t("admin_modules.emails.templates.form.variables_label"), class: "form-label" %>
          <%= f.text_field :variables, value: Array(template.variables).join(", "), placeholder: "first_name, order_id", class: "input-field mt-1" %>
          <p class="mt-1 text-caption"><%= t("admin_modules.emails.templates.form.variables_hint") %></p>
        </div>
      </div>

      <%# ----- Live Dry-Run / Preview Card ----- %>
      <%
        preview_url = template.persisted? ? 
          preview_admin_modules_emails_template_path(current_customer_id, template) : 
          preview_admin_modules_emails_templates_path(current_customer_id)

        test_send_url = template.persisted? ? 
          test_send_admin_modules_emails_template_path(current_customer_id, template) : 
          test_send_admin_modules_emails_templates_path(current_customer_id)
      %>
      <div class="card p-6 space-y-4"
           data-controller="remote-template-preview"
           data-remote-template-preview-url-value="<%= preview_url %>"
           data-remote-template-preview-test-send-url-value="<%= test_send_url %>">
        
        <div class="flex items-center justify-between">
          <h3 class="section-header mb-0"><%= t("email.preview.title") %></h3>
          <button type="button"
                  class="btn btn-secondary py-1 px-3 text-xs"
                  data-remote-template-preview-target="button"
                  data-action="click->remote-template-preview#loadPreview">
            <%= t("email.preview.load_button") %>
          </button>
        </div>

        <div class="border-b border-border">
          <nav class="-mb-px flex space-x-4" aria-label="Tabs">
            <button type="button" data-action="click->remote-template-preview#showTab" data-tab="subject" data-remote-template-preview-target="tabSubject" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-primary text-primary">
              <%= t("common.labels.subject") %>
            </button>
            <button type="button" data-action="click->remote-template-preview#showTab" data-tab="html" data-remote-template-preview-target="tabHtml" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-transparent text-text-muted hover:text-text hover:border-border">
              <%= t("email.preview.tab_html") %>
            </button>
            <button type="button" data-action="click->remote-template-preview#showTab" data-tab="text" data-remote-template-preview-target="tabText" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-transparent text-text-muted hover:text-text hover:border-border">
              <%= t("email.preview.tab_text") %>
            </button>
          </nav>
        </div>

        <div class="mt-2">
          <div data-remote-template-preview-target="subjectPane" class="p-3 bg-gray-50 rounded-md text-xs border border-border">
            <em class="text-text-muted"><%= t("email.preview.empty_placeholder") %></em>
          </div>
          
          <div data-remote-template-preview-target="htmlPane" class="hidden">
            <iframe data-remote-template-preview-target="iframe" class="w-full h-[240px] border border-border rounded-md bg-white"></iframe>
          </div>

          <div data-remote-template-preview-target="textPane" class="hidden p-3 bg-gray-50 rounded-md text-mono text-xs whitespace-pre-wrap border border-border max-h-[240px] overflow-y-auto"></div>
        </div>

        <%# --- Test-Send Section --- %>
        <div class="pt-4 border-t border-border-subtle space-y-2">
          <label for="dry_run_to" class="form-label text-xs block"><%= t("admin_modules.emails.templates.edit.send_test_label") %></label>
          <div class="flex gap-2">
            <%= email_field_tag :to, nil, 
                  id: "dry_run_to",
                  placeholder: t("admin_modules.emails.templates.edit.send_test_placeholder"),
                  data: { remote_template_preview_target: "testEmailInput" },
                  class: "input-field text-xs py-1 px-2 flex-grow" %>
            <button type="button"
                    class="btn btn-secondary text-xs py-1.5 px-3"
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

  <div class="flex justify-end gap-3 pt-4 border-t border-border-subtle">
    <%= link_to t("common.actions.cancel"), admin_modules_emails_templates_path(current_customer_id), class: "btn btn-secondary" %>
    <%= f.submit (template.persisted? ? t("admin_modules.emails.templates.form.update_submit") : t("admin_modules.emails.templates.form.create_submit")), class: "btn btn-primary" %>
  </div>
<% end %>
```

- [ ] **Step 2: Remove legacy redundant test-send forms**
Edit `app/views/admin/modules/emails/templates/edit.html.erb` to remove the old test send action form (since it's now beautifully handled as an interactive, unsaved-safe AJAX widget inside our updated unified layout form!):
```erb
# Replace:
# <div class="flex justify-between items-center mb-6">
#   <div>
#     <h1 class="text-heading"><%= t("admin_modules.emails.templates.edit.title") %></h1>
#     <p class="mt-1 text-body-sm"><%= t("admin_modules.emails.templates.edit.subtitle") %></p>
#   </div>
#   <div class="flex items-end gap-3">
#     <%= form_with url: test_send_admin_modules_emails_template_path(current_customer_id, @template),
#           method: :post, class: "flex items-end gap-2" do %>
#       <div>
#         <label for="test_send_to" class="form-label"><%= t("admin_modules.emails.templates.edit.send_test_label") %></label>
#         <%= email_field_tag :to, nil, id: "test_send_to",
#               placeholder: t("admin_modules.emails.templates.edit.send_test_placeholder"),
#               class: "mt-1 input-field" %>
#       </div>
#       <%= submit_tag t("admin_modules.emails.templates.edit.send_test_submit"), class: "btn btn-secondary" %>
#     <% end %>
#     <%= link_to t("admin_modules.emails.templates.edit.versions_button", default: "Versions"),
#           admin_modules_emails_template_versions_path(current_customer_id, @template),
#           class: "btn btn-secondary" %>
#     <%= button_to t("common.actions.delete"),
#           admin_modules_emails_template_path(current_customer_id, @template),
#           method: :delete,
#           data: { turbo_confirm: t("admin_modules.emails.templates.edit.delete_confirm") },
#           class: "btn btn-danger" %>
#   </div>
# </div>

# With:
<div class="flex justify-between items-center mb-6">
  <div>
    <h1 class="text-heading"><%= t("admin_modules.emails.templates.edit.title") %></h1>
    <p class="mt-1 text-body-sm"><%= t("admin_modules.emails.templates.edit.subtitle") %></p>
  </div>
  <div class="flex items-center gap-3">
    <%= link_to t("admin_modules.emails.templates.edit.versions_button", default: "Versions"),
          admin_modules_emails_template_versions_path(current_customer_id, @template),
          class: "btn btn-secondary" %>
    <%= button_to t("common.actions.delete"),
          admin_modules_emails_template_path(current_customer_id, @template),
          method: :delete,
          data: { turbo_confirm: t("admin_modules.emails.templates.edit.delete_confirm") },
          class: "btn btn-danger" %>
  </div>
</div>
```

- [ ] **Step 3: Stage changes**
Run: `git add app/views/admin/modules/emails/templates/_form.html.erb app/views/admin/modules/emails/templates/edit.html.erb`

---

### Task 6: Request Specs for Collection Dry-Run Actions

**Files:**
- Create: `spec/requests/admin/modules/emails/template_dry_runs_spec.rb`

- [ ] **Step 1: Write integration tests for collection-level dry-runs**
Create `spec/requests/admin/modules/emails/template_dry_runs_spec.rb` to cover unpersisted template actions fully:
```ruby
require 'rails_helper'

RSpec.describe "Admin::Modules::Emails::TemplateDryRuns", type: :request do
  include_context "as admin"

  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
  end

  before do
    ensure_customer_feature_module(customer, email_module, status: :active,
                                   configuration: { "campaigns_enabled" => true }.to_json)
    allow(Emails::DeliverMessageJob).to receive(:perform_later)
  end

  let!(:credential) { create(:email_credential, mode: "sandbox") }
  let!(:transactional_stream) { create(:email_stream, customer: customer, kind: "transactional", default_for_kind: true) }

  describe "POST /:customer_id/admin/modules/emails/templates/preview" do
    it "renders unpersisted template with mock variables" do
      allow(Emails::VariableContext).to receive(:for).with(user: admin).and_return({ "first_name" => "Dave" })

      post preview_admin_modules_emails_templates_path(customer.id), params: {
        email_template: {
          name: "Unsaved template",
          subject: "Draft Hello {{first_name}}",
          editor_type: "code",
          body_html: "<h1>Unsaved content</h1>"
        }
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["subject"]).to eq("Draft Hello Dave")
      expect(json["body_html"]).to include("Unsaved content")
    end
  end

  describe "POST /:customer_id/admin/modules/emails/templates/test_send" do
    it "sends transactional email for unpersisted template and returns success JSON" do
      expect {
        post test_send_admin_modules_emails_templates_path(customer.id), params: {
          email_template: {
            name: "Unsaved template",
            subject: "Hi",
            editor_type: "code",
            body_html: "<p>Unsaved code</p>"
          },
          to: "tester@example.com"
        }, as: :json
      }.to change { Emails::Message.where(message_type: "transactional").count }.by(1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["message"]).to include("tester@example.com")
    end
  end
end
```

- [ ] **Step 2: Run all email template request specs**
Run: `bundle exec rspec spec/requests/admin/modules/emails/template_dry_runs_spec.rb spec/requests/admin/modules/emails/template_previews_spec.rb spec/requests/admin/modules/emails/template_test_sends_spec.rb`
Expected: ALL PASS

- [ ] **Step 3: Stage changes**
Run: `git add spec/requests/admin/modules/emails/template_dry_runs_spec.rb`

---

### Task 7: Full Suite Verification & Asset Prep

**Files:**
- None

- [ ] **Step 1: Clean compiled assets to load newest JS controllers**
Run: `bin/rails assets:clobber && bin/rails tailwindcss:build`
Expected: Assets successfully wiped and rebuilt.

- [ ] **Step 2: Run entire Vitest unit-test suite**
Run: `npx vitest run --coverage`
Expected: Passes completely with 100% line & branch coverage on the new files `remote_template_preview_controller.js` and `template_slugify_controller.js`.

- [ ] **Step 3: Run target RSpec suites**
Run: `bundle exec rspec spec/requests/admin/modules/emails/template_dry_runs_spec.rb spec/requests/admin/modules/emails/template_previews_spec.rb spec/requests/admin/modules/emails/template_test_sends_spec.rb spec/models/emails/template_spec.rb`
Expected: ALL PASS
