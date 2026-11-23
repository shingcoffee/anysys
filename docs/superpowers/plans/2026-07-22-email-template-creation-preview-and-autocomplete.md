# Email Template Creation Live Preview & Variable Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Live Preview & Test-Send on email template creation, and add a searchable `{{` variable autocomplete dropdown in template editor fields.

**Architecture:** 
- Share the 2-column workspace layout (`template-workspace-layout` & `remote-template-preview`) across both creation and edit pages in `_form.html.erb`.
- Implement `editor_variable_autocomplete_controller.js` to handle typing `{{` in text inputs, textareas, and ActionText/Trix editors, opening a floating variable menu with keyboard/mouse selection.

**Tech Stack:** Rails v8.1.2, TailwindCSS, StimulusJS, Vitest, RSpec.

## Global Constraints
- All user-facing text must be translated under both `en` and `zh-CN`.
- Do not auto-commit changes; leave modifications uncommitted for human review.
- All JavaScript code under `app/javascript/**` must achieve 100% test coverage (lines and branches) in Vitest (`npx vitest run --coverage`).

---

### Task 1: Add Autocomplete Locale Keys

**Files:**
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`

**Interfaces:**
- Consumes: Existing locale structure under `admin_modules.emails.templates.form`
- Produces: Autocomplete dropdown placeholder and empty state translations

- [ ] **Step 1: Add translation keys for English locale**
  Edit `config/locales/admin_modules.en.yml` and add `autocomplete` keys under `admin_modules.emails.templates.form`:
  ```yaml
          autocomplete:
            hint: "Type to filter variables"
            empty: "No matching variables"
  ```

- [ ] **Step 2: Add translation keys for Simplified Chinese locale**
  Edit `config/locales/admin_modules.zh-CN.yml` and add `autocomplete` keys in Simplified Chinese:
  ```yaml
          autocomplete:
            hint: "输入以筛选变量"
            empty: "未找到匹配变量"
  ```

- [ ] **Step 3: Verify locales parse cleanly using Ruby YAML parser**
  Run:
  ```bash
  ruby -e "require 'yaml'; YAML.load_file('config/locales/admin_modules.en.yml'); YAML.load_file('config/locales/admin_modules.zh-CN.yml'); puts 'YAML Parsed successfully!'"
  ```
  Expected: `YAML Parsed successfully!`

---

### Task 2: Create Stimulus Variable Autocomplete Controller & Vitest Test Suite

**Files:**
- Create: `app/javascript/controllers/editor_variable_autocomplete_controller.js`
- Create: `spec/javascript/controllers/editor_variable_autocomplete_controller.test.js`

**Interfaces:**
- Consumes: `data-editor-variable-autocomplete-variables-value` JSON array on the element/container
- Produces: Floating dropdown upon typing `{{`, filtering variables, inserting selected variable, and closing on `Esc`/click outside

- [ ] **Step 1: Write failing Vitest test suite**
  Create `spec/javascript/controllers/editor_variable_autocomplete_controller.test.js`:
  ```javascript
  import { Application } from "@hotwired/stimulus"
  import { describe, beforeEach, it, expect, vi } from "vitest"
  import EditorVariableAutocompleteController from "controllers/editor_variable_autocomplete_controller"

  describe("EditorVariableAutocompleteController", () => {
    let application
    let container
    let input

    beforeEach(() => {
      document.body.innerHTML = `
        <div data-controller="editor-variable-autocomplete"
             data-editor-variable-autocomplete-variables-value='[{"field":"first_name","label":"First Name"},{"field":"last_name","label":"Last Name"}]'>
          <input type="text" id="subject" data-action="input->editor-variable-autocomplete#onInput keydown->editor-variable-autocomplete#onKeydown" />
        </div>
      `
      container = document.querySelector("[data-controller='editor-variable-autocomplete']")
      input = document.querySelector("#subject")

      application = Application.start()
      application.register("editor-variable-autocomplete", EditorVariableAutocompleteController)
    })

    it("opens menu when '{{' is typed into input", async () => {
      input.value = "Hello {{"
      input.setSelectionRange(8, 8)
      input.dispatchEvent(new Event("input", { bubbles: true }))

      await new Promise(r => setTimeout(r, 10))
      const menu = container.querySelector(".editor-variable-autocomplete-menu")
      expect(menu).not.toBeNull()
      expect(menu.textContent).toContain("first_name")
    })

    it("inserts variable when option is clicked", async () => {
      input.value = "Hello {{"
      input.setSelectionRange(8, 8)
      input.dispatchEvent(new Event("input", { bubbles: true }))

      await new Promise(r => setTimeout(r, 10))
      const item = container.querySelector(".editor-variable-autocomplete-item")
      item.dispatchEvent(new MouseEvent("click", { bubbles: true }))

      expect(input.value).toBe("Hello {{first_name}} ")
    })
  })
  ```

- [ ] **Step 2: Run Vitest to verify tests fail**
  Run:
  ```bash
  npx vitest run spec/javascript/controllers/editor_variable_autocomplete_controller.test.js --config config/javascript/vitest.config.js
  ```
  Expected: FAIL (controller file missing)

- [ ] **Step 3: Implement EditorVariableAutocompleteController**
  Create `app/javascript/controllers/editor_variable_autocomplete_controller.js`:
  ```javascript
  import { Controller } from "@hotwired/stimulus"

  export default class extends Controller {
    static values = {
      variables: { type: Array, default: [] },
      hintText: { type: String, default: "Type to filter variables" },
      emptyText: { type: String, default: "No matching variables" }
    }

    connect() {
      this.selectedIndex = 0
      this.menuEl = null
      this.activeInput = null
      this.onDocumentClick = this.onDocumentClick.bind(this)
      document.addEventListener("click", this.onDocumentClick)
    }

    disconnect() {
      document.removeEventListener("click", this.onDocumentClick)
      this.closeMenu()
    }

    onInput(event) {
      const el = event.target
      this.activeInput = el
      const val = el.value || ""
      const selectionEnd = el.selectionStart || val.length

      const textBeforeCursor = val.slice(0, selectionEnd)
      const match = textBeforeCursor.match(/\{\{([a-zA-Z0-9_]*)$/)

      if (match) {
        const query = match[1].toLowerCase()
        this.openMenu(el, query, match.index)
      } else {
        this.closeMenu()
      }
    }

    onKeydown(event) {
      if (!this.menuEl) return

      if (event.key === "ArrowDown") {
        event.preventDefault()
        this.moveSelection(1)
      } else if (event.key === "ArrowUp") {
        event.preventDefault()
        this.moveSelection(-1)
      } else if (event.key === "Enter" || event.key === "Tab") {
        const activeItem = this.menuEl.querySelector(".editor-variable-autocomplete-item.active")
        if (activeItem) {
          event.preventDefault()
          const varName = activeItem.dataset.variable
          this.insertVariable(varName)
        }
      } else if (event.key === "Escape") {
        event.preventDefault()
        this.closeMenu()
      }
    }

    openMenu(el, query, triggerIndex) {
      this.currentTriggerIndex = triggerIndex
      const filtered = this.variablesValue.filter(item => {
        const fieldName = (typeof item === "object" ? item.field : item).toLowerCase()
        const label = (typeof item === "object" ? item.label : "").toLowerCase()
        return fieldName.includes(query) || label.includes(query)
      })

      if (!this.menuEl) {
        this.menuEl = document.createElement("div")
        this.menuEl.className = "editor-variable-autocomplete-menu absolute z-50 w-72 bg-white rounded-lg shadow-xl border border-gray-200 py-1 overflow-hidden text-sm"
        this.element.appendChild(this.menuEl)
      }

      this.renderMenu(filtered)
    }

    renderMenu(items) {
      if (items.length === 0) {
        this.menuEl.innerHTML = `<div class="px-3 py-2 text-xs text-gray-400">${this.emptyTextValue}</div>`
        return
      }

      this.selectedIndex = Math.min(this.selectedIndex, items.length - 1)
      this.menuEl.innerHTML = items.map((item, index) => {
        const varName = typeof item === "object" ? item.field : item
        const label = typeof item === "object" ? item.label : varName
        const isActive = index === this.selectedIndex ? "active bg-indigo-50 text-indigo-900 font-semibold border-l-2 border-indigo-600" : "hover:bg-gray-50 text-gray-700"
        return `
          <div class="editor-variable-autocomplete-item ${isActive} px-3 py-2 cursor-pointer flex items-center justify-between text-xs transition-colors"
               data-variable="${varName}"
               data-action="click->editor-variable-autocomplete#selectItem">
            <span class="font-mono bg-gray-100 text-gray-800 px-1.5 py-0.5 rounded border border-gray-200 text-xs">{{${varName}}}</span>
            <span class="text-gray-500 text-xs truncate max-w-[120px]">${label}</span>
          </div>
        `
      }).join("")

      this.menuEl.querySelectorAll(".editor-variable-autocomplete-item").forEach(el => {
        el.addEventListener("click", (e) => {
          const varName = e.currentTarget.dataset.variable
          this.insertVariable(varName)
        })
      })
    }

    moveSelection(delta) {
      const items = this.menuEl.querySelectorAll(".editor-variable-autocomplete-item")
      if (items.length === 0) return
      this.selectedIndex = (this.selectedIndex + delta + items.length) % items.length
      items.forEach((item, idx) => {
        item.classList.toggle("active", idx === this.selectedIndex)
        item.classList.toggle("bg-indigo-50", idx === this.selectedIndex)
        item.classList.toggle("text-indigo-900", idx === this.selectedIndex)
      })
    }

    insertVariable(varName) {
      if (!this.activeInput) return
      const el = this.activeInput
      const val = el.value || ""
      const cursor = el.selectionStart || val.length

      const textBefore = val.slice(0, this.currentTriggerIndex)
      const textAfter = val.slice(cursor)

      const replacement = `{{${varName}}} `
      el.value = textBefore + replacement + textAfter
      const newCursorPos = textBefore.length + replacement.length
      el.setSelectionRange(newCursorPos, newCursorPos)

      el.dispatchEvent(new Event("input", { bubbles: true }))
      this.closeMenu()
    }

    closeMenu() {
      if (this.menuEl) {
        this.menuEl.remove()
        this.menuEl = null
      }
    }

    onDocumentClick(event) {
      if (this.menuEl && !this.element.contains(event.target)) {
        this.closeMenu()
      }
    }
  }
  ```

- [ ] **Step 4: Run Vitest to verify tests pass and coverage is 100%**
  Run:
  ```bash
  npx vitest run --coverage --config config/javascript/vitest.config.js
  ```
  Expected: PASS with 100% lines and branches.

---

### Task 3: Refactor Email Template Form for Creation Preview & Autocomplete

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

**Interfaces:**
- Consumes: `editor-variable-autocomplete` controller and `FieldCatalog.new.fields`
- Produces: Live preview & test-send on creation page + `{{` variable autocomplete on all template inputs

- [ ] **Step 1: Build combined variables JSON for autocomplete**
  In `_form.html.erb`, prepare the catalog fields and custom variables array as a JSON attribute on the form container:
  ```erb
  <%
    catalog_fields = Emails::Campaigns::FieldCatalog.new.fields
    custom_vars = (Array(template.variables) - catalog_fields.map { |f| f[:field] }).map { |v| { field: v, label: v } }
    autocomplete_vars = (catalog_fields + custom_vars).to_json
  %>
  ```

- [ ] **Step 2: Update form container and input bindings**
  Wrap the form sections with `data-controller="editor-variable-autocomplete"` and pass `data-editor-variable-autocomplete-variables-value="<%= autocomplete_vars %>"`.
  Add `data-action="input->editor-variable-autocomplete#onInput keydown->editor-variable-autocomplete#onKeydown"` to Subject text field, `body_html` textarea, and `body_text` textarea.

- [ ] **Step 3: Update Creation View layout (`!template.persisted?`)**
  In `_form.html.erb`, update the `!template.persisted?` block to include Section 1 (Basic Info), Section 2 (Workspace Layout with Split/Compose/Preview toggles, iframe live preview, and test-send box), and Section 3 (Activate immediately checkbox).

- [ ] **Step 4: Verify rendering and functionality in browser**
  Ensure the creation page renders the live preview iframe and test-send card, and typing `{{` in the Subject line or HTML editor opens the variable dropdown.

---

### Task 4: Verify with RSpec Request Specs & Full Test Suite

**Files:**
- Modify/Verify: `spec/requests/admin/modules/emails/templates_spec.rb`

**Interfaces:**
- Consumes: RSpec request test suite
- Produces: Confirmed passing specs covering preview and test-send on creation form

- [ ] **Step 1: Add creation preview test cases in templates_spec.rb**
  In `spec/requests/admin/modules/emails/templates_spec.rb`, add test cases verifying GET new renders the preview iframe container and test-send card.

- [ ] **Step 2: Run targeted request specs**
  Run:
  ```bash
  bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb
  ```
  Expected: PASS with 0 failures.

- [ ] **Step 3: Run Vitest coverage suite**
  Run:
  ```bash
  npx vitest run --coverage --config config/javascript/vitest.config.js
  ```
  Expected: 100% line and branch coverage across all JS files.
