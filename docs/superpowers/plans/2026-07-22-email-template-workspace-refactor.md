# Email Template Workspace UI/UX Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the email template creation page to introduce real-time auto-refresh previews, instant initial load, custom Focus Modes, a click-to-copy variable board, and polished test-sending alerts.

**Architecture:** We use decoupled StimulusJS controllers: `click_to_copy_controller` for variable badges, `template_workspace_layout_controller` for layout switching, and an enhanced `remote_template_preview_controller` for auto-updating previews and polished feedback. Backend compilation logic remains untouched.

**Tech Stack:** Rails v8.1.2, StimulusJS, TailwindCSS, Vitest, Rspec.

## Global Constraints
- **Styling:** Only TailwindCSS class names. Do not write custom CSS rules.
- **JavaScript:** Only StimulusJS. No custom inline JS or other frameworks.
- **Test Coverage:** All Javascript changes must keep 100% Vitest line/branch coverage.
- **I18n:** Every displayed label, button, placeholder, or status message must use `t("...")` or `I18n.t("...")`. All keys must be present in both English (`en`) and Simplified Chinese (`zh-CN`).
- **Commits:** Stage files with `git add`, but do not run `git commit` as per repository preferences.

---

### Task 1: Create the Click-to-Copy Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/click_to_copy_controller.js`
- Test: `spec/javascript/controllers/click_to_copy_controller.test.js`

**Interfaces:**
- Consumes: Standard HTML element with data attributes.
- Produces: Clipboard copy action and self-contained class/content visual changes.

- [ ] **Step 1: Create the Click-to-Copy Controller**
Create `app/javascript/controllers/click_to_copy_controller.js` with the following content:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String,
    copiedFeedback: { type: String, default: "Copied!" }
  }

  copy(event) {
    if (event) event.preventDefault()
    const text = this.textValue

    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      navigator.clipboard.writeText(text).then(() => {
        this.showFeedback()
      }).catch((err) => {
        console.error("Failed to copy using clipboard API:", err)
        this.fallbackCopy(text)
      })
    } else {
      this.fallbackCopy(text)
    }
  }

  showFeedback() {
    const originalText = this.element.textContent
    const originalClass = this.element.className

    this.element.textContent = this.copiedFeedbackValue
    this.element.classList.add("bg-green-100", "text-green-800", "border-green-300")
    this.element.classList.remove("bg-gray-50", "text-gray-700", "border-gray-200")

    setTimeout(() => {
      this.element.textContent = originalText
      this.element.className = originalClass
    }, 1500)
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    textarea.style.top = "0"
    textarea.setAttribute("readonly", "")
    document.body.appendChild(textarea)
    textarea.select()
    textarea.setSelectionRange(0, text.length)

    try {
      if (document.execCommand("copy")) {
        this.showFeedback()
      }
    } catch (err) {
      console.error("Fallback copy failed:", err)
    } finally {
      document.body.removeChild(textarea)
    }
  }
}
```

- [ ] **Step 2: Create the Click-to-Copy Controller Unit Test**
Create `spec/javascript/controllers/click_to_copy_controller.test.js` with the following content:
```javascript
import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/click_to_copy_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = () => `
  <button id="copy-btn"
          data-controller="click-to-copy"
          data-click-to-copy-text-value="{{first_name}}"
          data-action="click->click-to-copy#copy"
          class="bg-gray-50 text-gray-700 border-gray-200">
    first_name
  </button>
`

describe("click-to-copy controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
  })

  it("copies text using navigator.clipboard when available", async () => {
    const { application, element } = await mountController("click-to-copy", Controller, html())
    const btn = element.querySelector("#copy-btn")

    const writeTextMock = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal("navigator", {
      clipboard: {
        writeText: writeTextMock
      }
    })

    btn.click()

    expect(writeTextMock).toHaveBeenCalledWith("{{first_name}}")
    expect(btn.textContent.trim()).toBe("Copied!")
    expect(btn.classList.contains("bg-green-100")).toBe(true)
  })

  it("uses fallback when navigator.clipboard is unavailable", async () => {
    const { application, element } = await mountController("click-to-copy", Controller, html())
    const btn = element.querySelector("#copy-btn")

    vi.stubGlobal("navigator", {})
    const execMock = vi.spyOn(document, "execCommand").mockReturnValue(true)

    btn.click()

    expect(execMock).toHaveBeenCalledWith("copy")
    expect(btn.textContent.trim()).toBe("Copied!")
  })
})
```

- [ ] **Step 3: Run the Click-to-Copy Unit Test**
Run: `npx vitest run spec/javascript/controllers/click_to_copy_controller.test.js --coverage`
Expected: PASS with 100% line/branch coverage.

- [ ] **Step 4: Stage files**
Run: `git add app/javascript/controllers/click_to_copy_controller.js spec/javascript/controllers/click_to_copy_controller.test.js`

---

### Task 2: Create the Workspace Layout (Focus Mode) Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/template_workspace_layout_controller.js`
- Test: `spec/javascript/controllers/template_workspace_layout_controller.test.js`

**Interfaces:**
- Consumes: HTML element structure containing targets `container`, `composer`, `preview` and button targets.
- Produces: Class toggle mutations on containers and active/inactive styling for Focus buttons.

- [ ] **Step 1: Create the Layout Controller**
Create `app/javascript/controllers/template_workspace_layout_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "container", "composer", "preview",
    "btnSplit", "btnCompose", "btnPreview"
  ]
  static values = {
    current: { type: String, default: "split" }
  }

  connect() {
    this.updateLayout()
  }

  switchToSplit(event) {
    if (event) event.preventDefault()
    this.currentValue = "split"
  }

  switchToCompose(event) {
    if (event) event.preventDefault()
    this.currentValue = "compose"
  }

  switchToPreview(event) {
    if (event) event.preventDefault()
    this.currentValue = "preview"
  }

  currentValueChanged() {
    this.updateLayout()
  }

  updateLayout() {
    if (!this.hasContainerTarget || !this.hasComposerTarget || !this.hasPreviewTarget) return

    const layout = this.currentValue

    this.containerTarget.className = "grid gap-8 grid-cols-1"

    if (layout === "split") {
      this.containerTarget.classList.add("xl:grid-cols-2")
      this.composerTarget.classList.remove("hidden")
      this.previewTarget.classList.remove("hidden")

      this.activateButton(this.btnSplitTarget)
      this.deactivateButton(this.btnComposeTarget)
      this.deactivateButton(this.btnPreviewTarget)
    } else if (layout === "compose") {
      this.composerTarget.classList.remove("hidden")
      this.previewTarget.classList.add("hidden")

      this.deactivateButton(this.btnSplitTarget)
      this.activateButton(this.btnComposeTarget)
      this.deactivateButton(this.btnPreviewTarget)
    } else if (layout === "preview") {
      this.composerTarget.classList.add("hidden")
      this.previewTarget.classList.remove("hidden")

      this.deactivateButton(this.btnSplitTarget)
      this.deactivateButton(this.btnComposeTarget)
      this.activateButton(this.btnPreviewTarget)
    }
  }

  activateButton(btn) {
    if (!btn) return
    btn.classList.add("bg-primary-50", "text-primary-700", "border-primary-300", "ring-1", "ring-primary-500", "z-10")
    btn.classList.remove("bg-white", "text-gray-700", "border-gray-300", "hover:bg-gray-50")
  }

  deactivateButton(btn) {
    if (!btn) return
    btn.classList.remove("bg-primary-50", "text-primary-700", "border-primary-300", "ring-1", "ring-primary-500", "z-10")
    btn.classList.add("bg-white", "text-gray-700", "border-gray-300", "hover:bg-gray-50")
  }
}
```

- [ ] **Step 2: Create the Layout Controller Unit Test**
Create `spec/javascript/controllers/template_workspace_layout_controller.test.js`:
```javascript
import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/template_workspace_layout_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = () => `
  <div data-controller="template-workspace-layout" data-template-workspace-layout-current-value="split">
    <div class="flex">
      <button data-template-workspace-layout-target="btnSplit" data-action="click->template-workspace-layout#switchToSplit">Split</button>
      <button data-template-workspace-layout-target="btnCompose" data-action="click->template-workspace-layout#switchToCompose">Compose</button>
      <button data-template-workspace-layout-target="btnPreview" data-action="click->template-workspace-layout#switchToPreview">Preview</button>
    </div>
    <div data-template-workspace-layout-target="container">
      <div data-template-workspace-layout-target="composer">Composer</div>
      <div data-template-workspace-layout-target="preview">Preview</div>
    </div>
  </div>
`

describe("template-workspace-layout controller", () => {
  it("defaults to split view and updates elements", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const ctrl = controllerFor(application, element, "template-workspace-layout")

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(false)
    expect(preview.classList.contains("hidden")).toBe(false)
  })

  it("toggles compose focus on click", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const btnCompose = element.querySelector("[data-template-workspace-layout-target='btnCompose']")

    btnCompose.click()

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(false)
    expect(preview.classList.contains("hidden")).toBe(true)
  })

  it("toggles preview focus on click", async () => {
    const { application, element } = await mountController("template-workspace-layout", Controller, html())
    const btnPreview = element.querySelector("[data-template-workspace-layout-target='btnPreview']")

    btnPreview.click()

    const composer = element.querySelector("[data-template-workspace-layout-target='composer']")
    const preview = element.querySelector("[data-template-workspace-layout-target='preview']")

    expect(composer.classList.contains("hidden")).toBe(true)
    expect(preview.classList.contains("hidden")).toBe(false)
  })
})
```

- [ ] **Step 3: Run the Layout Unit Test**
Run: `npx vitest run spec/javascript/controllers/template_workspace_layout_controller.test.js --coverage`
Expected: PASS with 100% line/branch coverage.

- [ ] **Step 4: Stage files**
Run: `git add app/javascript/controllers/template_workspace_layout_controller.js spec/javascript/controllers/template_workspace_layout_controller.test.js`

---

### Task 3: Refactor the Remote Template Preview Stimulus Controller

**Files:**
- Modify: `app/javascript/controllers/remote_template_preview_controller.js`
- Modify: `spec/javascript/controllers/remote_template_preview_controller.test.js`

**Interfaces:**
- Consumes: Target element checkbox `autoRefresh`, loading state icons, status container.
- Produces: Debounced HTTP load requests, animated SVG button state updates, high-fidelity alert alerts.

- [ ] **Step 1: Refactor the JavaScript Controller**
Edit `app/javascript/controllers/remote_template_preview_controller.js` to implement:
- Connect: trigger automatic load on connect.
- Debounced load preview.
- Spinner integration.
- Polished test-send alert panel.

Let's write the complete updated Javascript controller:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "button", "subjectPane", "htmlPane", "textPane", 
    "tabSubject", "tabHtml", "tabText", "iframe",
    "testEmailInput", "testSendButton", "testStatus",
    "autoRefresh"
  ]
  static values = { 
    url: String, 
    testSendUrl: String,
    loadingLabel: { type: String, default: "Loading..." },
    sendingLabel: { type: String, default: "Sending..." }
  }

  connect() {
    // Automatically load preview upon mounting
    this.loadPreview()
  }

  // Gather current form field values into an API-compatible nested structure
  getFormData() {
    const root = this.element.closest("form") || document
    
    const name = root.querySelector('[name="email_template[name]"]')?.value || ""
    const key = root.querySelector('[name="email_template[key]"]')?.value || ""
    const subject = root.querySelector('[name="email_template[subject]"]')?.value || ""
    const editorType = root.querySelector('[name="email_template[editor_type]"]')?.value || "code"
    
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

  debouncedLoadPreview() {
    if (this.hasAutoRefreshTarget && !this.autoRefreshTarget.checked) return

    clearTimeout(this.previewTimeout)
    this.previewTimeout = setTimeout(() => {
      this.loadPreview()
    }, 1000)
  }

  async loadPreview(event) {
    if (event) event.preventDefault()

    const spinnerHtml = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-current" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    `

    const originalText = this.buttonTarget.textContent
    this.buttonTarget.disabled = true
    this.buttonTarget.innerHTML = `${spinnerHtml}<span>${this.loadingLabelValue}</span>`

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
      this.buttonTarget.innerHTML = originalText
    }
  }

  async sendTestEmail(event) {
    if (event) event.preventDefault()

    const to = this.testEmailInputTarget.value.trim()
    if (!to) {
      this.showStatus("Please enter an email address", "error")
      return
    }

    const spinnerHtml = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-current" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    `

    const originalText = this.testSendButtonTarget.innerHTML
    this.testSendButtonTarget.disabled = true
    this.testSendButtonTarget.innerHTML = `${spinnerHtml}<span>${this.sendingLabelValue}</span>`
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
      this.testSendButtonTarget.innerHTML = originalText
    }
  }

  showStatus(message, type) {
    if (!this.hasTestStatusTarget) return

    const successIcon = `
      <svg class="w-5 h-5 text-green-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    `
    const errorIcon = `
      <svg class="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
    `

    const icon = type === "success" ? successIcon : errorIcon
    const bgClass = type === "success" ? "bg-green-50 border-green-200 text-green-800" : "bg-red-50 border-red-200 text-red-800"

    this.testStatusTarget.className = `rounded-lg p-4 border text-sm mt-3 flex items-start gap-2.5 ${bgClass}`
    this.testStatusTarget.innerHTML = `
      ${icon}
      <div class="flex-grow">
        <p class="font-medium">${message}</p>
      </div>
    `
    this.testStatusTarget.classList.remove("hidden")
  }

  clearStatus() {
    if (!this.hasTestStatusTarget) return
    this.testStatusTarget.textContent = ""
    this.testStatusTarget.className = "hidden"
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

- [ ] **Step 2: Update the Unit Tests**
Modify `spec/javascript/controllers/remote_template_preview_controller.test.js` to ensure that it has 100% test coverage and passes fully, mocking out any debounced/timeout timers if needed.
(Use `vi.useFakeTimers()` to test the `debouncedLoadPreview` 1000ms delay).

- [ ] **Step 3: Run the Controller Unit Tests**
Run: `npx vitest run spec/javascript/controllers/remote_template_preview_controller.test.js --coverage`
Expected: PASS with 100% line/branch coverage.

- [ ] **Step 4: Stage files**
Run: `git add app/javascript/controllers/remote_template_preview_controller.js spec/javascript/controllers/remote_template_preview_controller.test.js`

---

### Task 4: Add Localization Strings

**Files:**
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`

- [ ] **Step 1: Edit English Translations**
Add layout switching and workspace messages to `config/locales/admin_modules.en.yml` under `en.admin_modules.emails.templates.form`:
```yaml
        workspace:
          layout_split: "Split View"
          layout_compose: "Write Focus"
          layout_preview: "Preview Focus"
          auto_refresh: "Auto-refresh"
          variables_board_title: "Variables Board (Click to copy)"
          variables_board_hint: "Click any variable badge to copy it to your clipboard. You can paste it into the Subject, HTML editor, or Plain Text fallback."
```

- [ ] **Step 2: Edit Chinese Translations**
Add matching keys to `config/locales/admin_modules.zh-CN.yml` under `zh-CN.admin_modules.emails.templates.form`:
```yaml
        workspace:
          layout_split: "分栏视图"
          layout_compose: "聚焦编辑"
          layout_preview: "聚焦预览"
          auto_refresh: "自动刷新"
          variables_board_title: "变量面板 (点击复制)"
          variables_board_hint: "点击任何变量徽章以将其复制到剪贴板。您可以将其粘贴到主题、HTML编辑器或纯文本退路中。"
```

- [ ] **Step 3: Stage files**
Run: `git add config/locales/admin_modules.en.yml config/locales/admin_modules.zh-CN.yml`

---

### Task 5: Refactor the Form Template Layout View

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

- [ ] **Step 1: Rewrite `_form.html.erb`**
Modify the template view code to wrap everything in `template-workspace-layout` and hook inputs to `remote-template-preview`'s `debouncedLoadPreview` action:
- Add Focus Mode Button Group.
- Render the Variables click-to-copy board cards using `click-to-copy` controller.
- Render Settings Block on BOTH `new` and `edit` in a clean, modern form container.

Here is the exact code structure to place in `app/views/admin/modules/emails/templates/_form.html.erb`:
```erb
<%= form_with model: template, scope: :email_template, url: url, method: method, local: true, class: "space-y-8" do |f| %>
  <% if template.errors.any? %>
    <%= render "shared/form_errors", resource: template %>
  <% end %>

  <% if @lint_warnings.present? && @lint_warnings[:unknown].any? %>
    <div class="rounded-md bg-yellow-50 p-4 border border-yellow-200 mb-6">
      <div class="flex">
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800"><%= t("admin_modules.emails.templates.form.lint.unknown_title") %></h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p><%= t("admin_modules.emails.templates.form.lint.unknown_message", vars: @lint_warnings[:unknown].map { |v| "<code class='font-mono bg-yellow-100 px-1 py-0.5 rounded'>#{v}</code>" }).join(", ").html_safe %></p>
          </div>
        </div>
      </div>
    </div>
  <% end %>

  <%# ===== Section 1: Basic Information ===== %>
  <div class="card p-8 space-y-6">
    <h2 class="section-header text-xl"><%= t("admin_modules.emails.templates.form.details_title") %></h2>
    
    <div class="space-y-4">
      <div>
        <%= f.label :name, t("common.labels.name"), class: "form-label text-base font-semibold" %>
        <%= f.text_field :name, placeholder: t("admin_modules.emails.templates.form.name_placeholder"), 
              class: "input-field mt-1.5 w-full py-3 px-4 text-base rounded-lg",
              data: { action: "input->remote-template-preview#debouncedLoadPreview" } %>
      </div>

      <div>
        <%= f.label :subject, t("common.labels.subject"), class: "form-label text-base font-semibold" %>
        <%= f.text_field :subject, placeholder: t("admin_modules.emails.templates.form.subject_placeholder"), 
              class: "input-field mt-1.5 w-full py-3 px-4 text-base rounded-lg",
              data: { action: "input->remote-template-preview#debouncedLoadPreview" } %>
        <p class="mt-1.5 text-caption text-sm">
          <%= t("admin_modules.emails.templates.form.use_variable_prefix") %>
          <code class="text-code bg-gray-100 px-1.5 py-0.5 rounded text-sm font-mono">{{variable}}</code>
          <%= t("admin_modules.emails.templates.form.use_variable_suffix") %>
        </p>
      </div>
    </div>
  </div>

  <%# ===== Section 2: Workspace Layout with Focus Modes & Auto-refresh ===== %>
  <%
    preview_url = template.persisted? ? 
      preview_admin_modules_emails_template_path(current_customer_id, template) : 
      preview_admin_modules_emails_templates_path(current_customer_id)

    test_send_url = template.persisted? ? 
      test_send_admin_modules_emails_template_path(current_customer_id, template) : 
      test_send_admin_modules_emails_templates_path(current_customer_id)
  %>
  
  <div data-controller="template-workspace-layout" data-template-workspace-layout-current-value="split" class="space-y-4">
    <%# Focus Mode Controls Button Group %>
    <div class="flex items-center justify-between flex-wrap gap-4 bg-gray-50 p-3 rounded-xl border border-gray-200">
      <span class="text-sm font-semibold text-gray-700">Workspace Layout:</span>
      <div class="inline-flex rounded-md shadow-sm" role="group">
        <button type="button"
                data-template-workspace-layout-target="btnSplit"
                data-action="click->template-workspace-layout#switchToSplit"
                class="px-4 py-2 text-sm font-medium rounded-l-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 focus:z-10 cursor-pointer">
          👥 <%= t("admin_modules.emails.templates.form.workspace.layout_split") %>
        </button>
        <button type="button"
                data-template-workspace-layout-target="btnCompose"
                data-action="click->template-workspace-layout#switchToCompose"
                class="px-4 py-2 text-sm font-medium border-t border-b border-gray-300 bg-white text-gray-700 hover:bg-gray-50 focus:z-10 cursor-pointer">
          ✍️ <%= t("admin_modules.emails.templates.form.workspace.layout_compose") %>
        </button>
        <button type="button"
                data-template-workspace-layout-target="btnPreview"
                data-action="click->template-workspace-layout#switchToPreview"
                class="px-4 py-2 text-sm font-medium rounded-r-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 focus:z-10 cursor-pointer">
          👁️ <%= t("admin_modules.emails.templates.form.workspace.layout_preview") %>
        </button>
      </div>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-2 gap-8"
         data-template-workspace-layout-target="container"
         data-controller="remote-template-preview"
         data-remote-template-preview-url-value="<%= preview_url %>"
         data-remote-template-preview-test-send-url-value="<%= test_send_url %>">
         
      <%# ----- Left Column: Composer ----- %>
      <div data-template-workspace-layout-target="composer"
           class="card p-8 space-y-6"
           data-controller="template-editor-mode"
           data-template-editor-mode-initial-value="<%= template.editor_type %>">
        
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-4 border-b border-border-subtle">
          <div>
            <h2 class="section-header text-xl"><%= t("admin_modules.emails.templates.form.body_title") %></h2>
            <p class="text-body-sm text-text-muted mt-1"><%= t("admin_modules.emails.templates.form.body_subtitle") %></p>
          </div>
          <div class="w-full sm:w-56">
            <%= f.label :editor_type, t("admin_modules.emails.templates.form.editor_label"), class: "form-label font-semibold" %>
            <%= f.select :editor_type, Emails::Template::EDITOR_TYPES.map { |type| [t("admin_modules.emails.templates.form.editor_types.#{type}"), type] }, {},
                  class: "input-field mt-1.5 py-2 px-3 text-sm rounded-lg w-full",
                  data: { action: "change->template-editor-mode#switch change->remote-template-preview#loadPreview", template_editor_mode_target: "select" } %>
          </div>
        </div>

        <%# --- Rich Text (Lexxy Mode) --- %>
        <div data-template-editor-mode-target="richContainer"
             class="<%= template.editor_type == 'rich_text' ? '' : 'hidden' %> space-y-4">
          <div data-controller="template-variable-picker">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
              <label class="form-label text-base font-semibold mb-0"><%= t("admin_modules.emails.templates.form.rich_text_body") %></label>
              <div class="flex flex-wrap items-center gap-2">
                <label class="text-caption text-sm whitespace-nowrap"><%= t("admin_modules.emails.templates.form.insert_variable") %></label>
                <select data-template-variable-picker-target="picker"
                        data-action="change->template-variable-picker#insert change->remote-template-preview#debouncedLoadPreview"
                        class="input-field py-1.5 px-2.5 text-sm w-44 rounded-lg">
                  <option value=""><%= t("admin_modules.emails.templates.form.choose_option") %></option>
                  <% catalog_fields = Emails::Campaigns::FieldCatalog.new.fields %>
                  <% catalog_fields.each do |fld| %>
                    <option value="<%= fld[:field] %>"><%= fld[:label] %></option>
                  <% end %>
                </select>
              </div>
            </div>

            <div class="prose-editor-wrapper" data-action="trix-change->remote-template-preview#debouncedLoadPreview">
              <%= f.rich_text_area :body, class: "block w-full min-h-[350px] rounded-lg border border-border p-4 bg-white" %>
            </div>
            <p class="mt-2 text-caption text-sm"><%= t("admin_modules.emails.templates.form.rich_hint") %></p>
          </div>
        </div>

        <%# --- HTML Code (Source Mode) --- %>
        <div data-template-editor-mode-target="codeContainer"
             class="<%= template.editor_type == 'code' ? '' : 'hidden' %> space-y-4">
          <div>
            <label class="form-label text-base font-semibold mb-3 block"><%= t("admin_modules.emails.templates.form.html_code") %></label>
            <%= f.text_area :body_html,
                  rows: 18,
                  class: "input-field text-mono text-sm w-full p-4 rounded-lg bg-gray-50 focus:bg-white border-border",
                  data: { action: "input->remote-template-preview#debouncedLoadPreview" } %>
            <p class="mt-2 text-caption text-sm"><%= t("admin_modules.emails.templates.form.use_variable_prefix") %><code class="text-code bg-gray-100 px-1.5 py-0.5 rounded font-mono text-sm">{{variable}}</code><%= t("admin_modules.emails.templates.form.use_variable_suffix") %></p>
          </div>
        </div>

        <%# --- Click-to-Copy Variables Board Card --- %>
        <div class="p-6 bg-slate-50 border border-slate-200 rounded-xl space-y-3">
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-200 pb-2">
            <h3 class="text-sm font-semibold text-slate-800 flex items-center gap-1.5">
              📋 <%= t("admin_modules.emails.templates.form.workspace.variables_board_title") %>
            </h3>
          </div>
          <p class="text-xs text-slate-500 leading-relaxed">
            <%= t("admin_modules.emails.templates.form.workspace.variables_board_hint") %>
          </p>
          <div class="flex flex-wrap gap-2 pt-1">
            <% Emails::Campaigns::FieldCatalog.new.fields.each do |fld| %>
              <button type="button"
                      data-controller="click-to-copy"
                      data-click-to-copy-text-value="{{<%= fld[:field] %>}}"
                      data-action="click->click-to-copy#copy"
                      class="inline-flex items-center px-2.5 py-1.5 rounded-md text-xs font-mono bg-white border border-gray-200 hover:bg-gray-100 hover:border-gray-300 text-gray-700 transition cursor-pointer">
                <%= fld[:field] %>
              </button>
            <% end %>
          </div>
        </div>

        <%# --- Plain Text Fallback --- %>
        <div class="pt-6 border-t border-border-subtle">
          <%= f.label :body_text, t("admin_modules.emails.templates.form.plain_text_fallback"), class: "form-label text-base font-semibold" %>
          <%= f.text_area :body_text, rows: 4, placeholder: t("admin_modules.emails.templates.form.plain_text_placeholder"), 
                class: "input-field text-mono text-sm mt-2 w-full p-4 rounded-lg",
                data: { action: "input->remote-template-preview#debouncedLoadPreview" } %>
          <p class="mt-2 text-caption text-sm"><%= t("admin_modules.emails.templates.form.plain_text_hint_html") %></p>
        </div>
      </div>

      <%# ----- Right Column: Previews & Test-Send ----- %>
      <div data-template-workspace-layout-target="preview" class="space-y-6">
        <%# Previews and Client Frame Card %>
        <div class="card p-8 space-y-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-4 border-b border-border-subtle">
            <div class="flex items-center gap-3">
              <h2 class="section-header text-xl mb-0"><%= t("email.preview.title") %></h2>
              <label class="inline-flex items-center gap-1.5 text-xs text-gray-600 bg-gray-100 hover:bg-gray-200 py-1.5 px-2.5 rounded-lg border border-gray-200 cursor-pointer select-none">
                <input type="checkbox"
                       checked
                       data-remote-template-preview-target="autoRefresh"
                       class="h-3.5 w-3.5 text-primary rounded border-gray-300 focus:ring-primary cursor-pointer" />
                <span><%= t("admin_modules.emails.templates.form.workspace.auto_refresh") %></span>
              </label>
            </div>
            <div class="flex items-center gap-2">
              <button type="submit" 
                      formaction="<%= preview_url %><%= preview_url.include?('?') ? '&' : '?' %>preview_mode=full_page" 
                      formtarget="_blank" 
                      class="btn btn-secondary py-2 px-4 text-xs font-semibold inline-flex items-center gap-1.5 rounded-lg shadow-sm border-gray-300 hover:bg-gray-100 cursor-pointer self-start sm:self-auto">
                <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                </svg>
                <%= t("email.preview.new_tab", default: "New Tab") %>
              </button>
              <button type="button"
                      class="btn btn-primary py-2 px-4 text-xs font-semibold inline-flex items-center gap-1.5 rounded-lg shadow-sm cursor-pointer"
                      data-remote-template-preview-target="button"
                      data-action="click->remote-template-preview#loadPreview">
                <%= t("email.preview.load_button") %>
              </button>
            </div>
          </div>

          <%# Simulated Mini Desktop Email Client UI %>
          <div class="border border-border rounded-xl overflow-hidden bg-white shadow-sm flex flex-col min-h-[400px]">
            <%# Top Control Headers %>
            <div class="bg-gray-50 border-b border-border p-3 space-y-2">
              <div class="flex items-center text-xs gap-2">
                <span class="font-semibold text-text-muted w-16">Subject:</span>
                <div data-remote-template-preview-target="subjectPane" class="text-text font-medium flex-grow bg-white border border-border rounded py-1 px-2 text-xs">
                  <em class="text-text-muted font-normal"><%= t("email.preview.empty_placeholder") %></em>
                </div>
              </div>
            </div>

            <%# View Mode Tabs (HTML, Plain Text) %>
            <div class="bg-gray-50 px-3 pt-2 border-b border-border flex items-center justify-between">
              <nav class="-mb-px flex space-x-4" aria-label="Tabs">
                <button type="button" data-action="click->remote-template-preview#showTab" data-tab="subject" data-remote-template-preview-target="tabSubject" class="whitespace-nowrap pb-2 px-1 border-b-2 font-medium text-xs border-primary text-primary hidden">
                  Subject
                </button>
                <button type="button" data-action="click->remote-template-preview#showTab" data-tab="html" data-remote-template-preview-target="tabHtml" class="whitespace-nowrap pb-2 px-1 border-b-2 font-semibold text-xs border-primary text-primary">
                  <%= t("email.preview.tab_html") %>
                </button>
                <button type="button" data-action="click->remote-template-preview#showTab" data-tab="text" data-remote-template-preview-target="tabText" class="whitespace-nowrap pb-2 px-1 border-b-2 font-semibold text-xs border-transparent text-text-muted hover:text-text hover:border-border">
                  <%= t("email.preview.tab_text") %>
                </button>
              </nav>
            </div>

            <%# Interactive Previews Viewports %>
            <div class="flex-grow p-4 bg-gray-50 min-h-[300px] flex flex-col">
              <div data-remote-template-preview-target="htmlPane" class="flex-grow flex flex-col">
                <iframe data-remote-template-preview-target="iframe" class="w-full flex-grow min-h-[300px] border border-border rounded-lg bg-white shadow-inner"></iframe>
              </div>

              <div data-remote-template-preview-target="textPane" class="hidden flex-grow p-3 bg-white rounded-lg text-mono text-xs whitespace-pre-wrap border border-border min-h-[300px] overflow-y-auto shadow-inner"></div>
            </div>
          </div>
        </div>

        <%# Test-Send Card %>
        <div class="card p-8 space-y-4">
          <div class="flex items-start gap-3">
            <div class="p-2 bg-green-50 text-green-600 rounded-lg">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 2 9 18zm0 0v-8"></path>
              </svg>
            </div>
            <div class="space-y-1">
              <h3 class="text-lg font-semibold text-text"><%= t("admin_modules.emails.templates.edit.send_test_label") %></h3>
              <p class="text-caption text-xs">Instantly test-send this template to an inbox with mock preview variables.</p>
            </div>
          </div>

          <div class="flex flex-col sm:flex-row gap-2">
            <%= email_field_tag :to, current_user.email, 
                  id: "dry_run_to",
                  placeholder: t("admin_modules.emails.templates.edit.send_test_placeholder"),
                  data: { remote_template_preview_target: "testEmailInput" },
                  class: "input-field text-sm py-2 px-3 flex-grow rounded-lg shadow-sm bg-white border-border" %>
            <button type="button"
                    data-remote-template-preview-target="testSendButton"
                    data-action="click->remote-template-preview#sendTestEmail"
                    class="btn btn-secondary text-sm py-2 px-4 font-semibold whitespace-nowrap rounded-lg shadow-sm border-gray-300 hover:bg-gray-100 cursor-pointer inline-flex items-center justify-center">
              <span><%= t("admin_modules.emails.templates.edit.send_test_submit") %></span>
            </button>
          </div>
          <div data-remote-template-preview-target="testStatus" class="hidden"></div>
        </div>
      </div>
    </div>
  </div>

  <%# ===== Section 3: Settings & Delivery Configuration (Shown on BOTH new and edit) ===== %>
  <div class="card p-8 space-y-6">
    <h2 class="section-header text-xl pb-4 border-b border-border-subtle">
      <%= t("admin_modules.emails.templates.form.details_title") %> (<%= t("common.labels.settings", default: "Settings") %>)
    </h2>
    
    <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
      <div>
        <%= f.label :status, t("common.labels.status"), class: "form-label font-semibold" %>
        <%= f.select :status, Emails::Template::STATUSES.map { |status| [t("admin_modules.emails.templates.form.statuses.#{status}"), status] }, {}, class: "input-field mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full" %>
      </div>

      <div>
        <%= f.label :key, t("common.labels.key"), class: "form-label font-semibold" %>
        <%= f.text_field :key, placeholder: "lowercase_with_underscores", 
              class: "input-field text-mono mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full",
              readonly: template.persisted? %>
        <p class="mt-1.5 text-caption text-sm">
          <%= template.persisted? ? t("admin_modules.emails.templates.form.key_readonly_hint", default: "The key cannot be changed after creation.") : t("admin_modules.emails.templates.form.key_hint") %>
        </p>
      </div>

      <div>
        <%= f.label :template_type, t("common.labels.type"), class: "form-label font-semibold" %>
        <%= f.select :template_type, Emails::Template::TEMPLATE_TYPES.map { |type| [t("admin_modules.emails.templates.form.template_types.#{type}"), type] }, {}, class: "input-field mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full" %>
      </div>

      <div>
        <%= f.label :category, t("admin_modules.emails.templates.form.category_label"), class: "form-label font-semibold" %>
        <%= f.select :category, Emails::Template::CATEGORIES.map { |cat| [t("admin_modules.emails.templates.form.categories.#{cat}"), cat] }, {}, class: "input-field mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full" %>
      </div>

      <div>
        <%= f.label :email_stream_id, t("admin_modules.emails.templates.form.stream_label"), class: "form-label font-semibold" %>
        <%= f.select :email_stream_id,
              Emails::Stream.for_current_customer.active.map { |s| [s.name, s.id] },
              { include_blank: t("common.labels.none") },
              class: "input-field mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full" %>
      </div>

      <div>
        <%= f.label :variables, t("admin_modules.emails.templates.form.variables_label"), class: "form-label font-semibold" %>
        <%= f.text_field :variables, value: Array(template.variables).join(", "), placeholder: "first_name, order_id", class: "input-field mt-1.5 py-2.5 px-3.5 text-sm rounded-lg w-full" %>
        <p class="mt-1.5 text-caption text-sm"><%= t("admin_modules.emails.templates.form.variables_hint") %></p>
      </div>
    </div>
  </div>

  <%# ===== Form Footer Submit Actions ===== %>
  <div class="flex justify-end gap-3 pt-6 border-t border-border-subtle">
    <%= link_to t("common.actions.cancel"), admin_modules_emails_templates_path(current_customer_id), class: "btn btn-secondary px-5 py-2.5 text-sm" %>
    <%= f.submit (template.persisted? ? t("admin_modules.emails.templates.form.update_submit") : t("admin_modules.emails.templates.form.create_submit")), class: "btn btn-primary px-6 py-2.5 text-sm font-semibold" %>
  </div>
<% end %>
```

- [ ] **Step 2: Stage files**
Run: `git add app/views/admin/modules/emails/templates/_form.html.erb`

---

### Task 6: Verify and Run All Tests

**Files:**
- Test: All relevant Rails and Vitest test suites.

- [ ] **Step 1: Run Vitest Suite**
Run: `npx vitest run --coverage`
Expected: PASS with 100% line/branch coverage of modified/new controllers.

- [ ] **Step 2: Run RSpec Request Tests**
Run: `bundle exec rspec spec/requests/admin/modules/emails/template_previews_spec.rb spec/requests/admin/modules/emails/template_test_sends_spec.rb`
Expected: PASS.
