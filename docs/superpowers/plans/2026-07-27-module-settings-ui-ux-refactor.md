# Module Settings UI/UX Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Platform Owner Module Settings page (`/81721200/admin/maintenance/platform/module_settings/:id`) so that toggle labels are moved to section headers, attribute data types are replaced with descriptive attribute labels, template token toggles use AJAX checkboxes with inline feedback, and model attribute tables are folded by default.

**Architecture:** Extend `ModuleToggleComponent` to support hiding inline labels (`show_label: false`), add `human_attribute_name` labels in `ModuleModelDiscovery`, add JSON responses to `ModuleSettingsController#update`, implement a Stimulus `template_token_checkbox_controller.js` with 100% Vitest test coverage, and update `show.html.erb` with folded `<details>` cards and title-level badges.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec, Vitest.

## Global Constraints
- **TailwindCSS & StimulusJS**: Use only TailwindCSS classes and StimulusJS controllers. No custom CSS/JS libraries.
- **I18n Compliance**: All user-facing strings MUST use I18n translation keys with both `en` and `zh-CN` translations present.
- **JS Test Coverage**: All JS source code under `app/javascript/**` MUST have 100% test coverage (lines and branches) measured by Vitest (`npx vitest run --coverage`).

---

### Task 1: Update `ModuleToggleComponent` and `ModuleModelDiscovery`

**Files:**
- Modify: `app/components/admin/maintenance/platform/module_toggle_component.rb`
- Modify: `app/components/admin/maintenance/platform/module_toggle_component.html.erb`
- Modify: `app/services/module_model_discovery.rb`
- Test: `spec/components/admin/maintenance/platform/module_toggle_component_spec.rb` (if exists or create)

**Interfaces:**
- `ModuleToggleComponent#initialize(..., show_label: true)`
- `ModuleModelDiscovery.call(module_key)` returns array of model hashes, each with `columns: [{ name:, type:, label:, nullable:, default: }]`

- [ ] **Step 1: Write failing spec for `ModuleToggleComponent` with `show_label: false`**

Create/update `spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleToggleComponent, type: :component do
  it "renders label when show_label is true" do
    render_inline(described_class.new(url: "/test", field: "active", on: true, on_label: "Active"))
    expect(page).to have_content("Active")
  end

  it "omits label when show_label is false" do
    render_inline(described_class.new(url: "/test", field: "active", on: true, on_label: "Active", show_label: false))
    expect(page).not_to have_content("Active")
  end
end
```

- [ ] **Step 2: Run component spec to verify failure**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`
Expected: FAIL (unknown keyword: show_label or label still rendered)

- [ ] **Step 3: Update `ModuleToggleComponent` implementation**

In `app/components/admin/maintenance/platform/module_toggle_component.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class ModuleToggleComponent < ApplicationComponent
        def initialize(url:, field:, on:, disabled: false, confirm: nil, on_label: nil, off_label: nil, extra_params: {}, show_label: true)
          @url = url
          @field = field
          @on = on
          @disabled = disabled
          @confirm = confirm
          @on_label = on_label
          @off_label = off_label
          @extra_params = extra_params
          @show_label = show_label
        end

        attr_reader :url, :field, :on, :disabled, :confirm, :on_label, :off_label, :extra_params

        def on? = @on
        def disabled? = @disabled
        def show_label? = @show_label
        def next_value = on? ? "0" : "1"

        def track_classes
          base = "relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
          state = on? ? "bg-accent" : "bg-border"
          cursor = disabled? ? "opacity-50 cursor-not-allowed" : "cursor-pointer"
          "#{base} #{state} #{cursor}"
        end

        def knob_classes
          pos = on? ? "translate-x-5" : "translate-x-0"
          "#{pos} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-surface shadow ring-0 transition duration-200 ease-in-out"
        end

        def label
          if on?
            on_label || I18n.t("comp_admin.module_toggle.on")
          else
            off_label || I18n.t("comp_admin.module_toggle.off")
          end
        end
      end
    end
  end
end
```

In `app/components/admin/maintenance/platform/module_toggle_component.html.erb`:
```erb
<%# app/components/admin/maintenance/platform/module_toggle_component.html.erb %>
<div class="flex items-center justify-end gap-3 whitespace-nowrap flex-shrink-0 ml-auto">
  <% if disabled? %>
    <button type="button" disabled class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
      <span class="<%= knob_classes %>"></span>
    </button>
  <% else %>
    <%= form_with url: url, method: :patch, local: true, class: "inline" do %>
      <input type="hidden" name="<%= field %>" value="<%= next_value %>">
      <% extra_params.each do |key, value| %>
        <input type="hidden" name="<%= key %>" value="<%= value %>">
      <% end %>
      <button type="submit"
              <% if confirm.present? %>data-turbo-confirm="<%= confirm %>"<% end %>
              class="<%= track_classes %>" role="switch" aria-checked="<%= on? %>">
        <span class="<%= knob_classes %>"></span>
      </button>
    <% end %>
  <% end %>
  <% if show_label? %>
    <span class="text-body-sm text-text-primary"><%= label %></span>
  <% end %>
</div>
```

- [ ] **Step 4: Update `ModuleModelDiscovery` to include `label`**

In `app/services/module_model_discovery.rb`:
```ruby
  def extract_columns(klass)
    klass.columns.map do |col|
      {
        name: col.name,
        type: col.type.to_s,
        label: klass.human_attribute_name(col.name),
        nullable: col.null,
        default: col.default
      }
    end
  end
```

- [ ] **Step 5: Run specs to verify pass**

Run: `bundle exec rspec spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/admin/maintenance/platform/module_toggle_component.rb app/components/admin/maintenance/platform/module_toggle_component.html.erb app/services/module_model_discovery.rb spec/components/admin/maintenance/platform/module_toggle_component_spec.rb
git commit -m "feat: add show_label to ModuleToggleComponent and attribute labels to ModuleModelDiscovery"
```

---

### Task 2: Add I18n Translations for `attribute_label`

**Files:**
- Modify: `config/locales/maint_platform.en.yml`
- Modify: `config/locales/maint_platform.zh-CN.yml`

- [ ] **Step 1: Add translation key to `maint_platform.en.yml`**

Under `maint_platform.module_settings.show.tokens`:
```yaml
        attribute_label: "Attribute Label"
```

- [ ] **Step 2: Add translation key to `maint_platform.zh-CN.yml`**

Under `maint_platform.module_settings.show.tokens`:
```yaml
        attribute_label: "属性标签"
```

- [ ] **Step 3: Commit**

```bash
git add config/locales/maint_platform.en.yml config/locales/maint_platform.zh-CN.yml
git commit -m "i18n: add attribute_label translations to maint_platform"
```

---

### Task 3: Support JSON/AJAX in `ModuleSettingsController#update`

**Files:**
- Modify: `app/controllers/admin/maintenance/platform/module_settings_controller.rb`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

- [ ] **Step 1: Write failing request spec for JSON PATCH update**

In `spec/requests/admin/maintenance/platform/module_settings_spec.rb`:
```ruby
  describe "PATCH /:customer_id/admin/maintenance/platform/module_settings/:id (JSON)" do
    let(:feature_module) { FeatureModules::Module.find_by!(key: "authentication") }

    it "updates token attribute asynchronously and returns JSON" do
      patch admin_maintenance_platform_module_setting_path("81721200", feature_module),
            params: { token_model: "User", token_attribute: "email", token_enabled: "1" },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["enabled"]).to be true
      expect(Emails::TemplateToken.platform.where(source_key: "user.email")).to exist
    end
  end
```

- [ ] **Step 2: Run request spec to verify failure**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: FAIL (Redirect 302 instead of 200 JSON)

- [ ] **Step 3: Update `ModuleSettingsController#update`**

In `app/controllers/admin/maintenance/platform/module_settings_controller.rb`:
```ruby
    def update
      @feature_module = FeatureModules::Module.find(params[:id])

      apply_status!         if params.key?(:status_active) || params.key?("status_active")
      apply_required!       if params.key?(:required) || params.key?("required")
      apply_handoff_enabled! if params.key?(:handoff_enabled) || params.key?("handoff_enabled")
      apply_extendable_model! if params.key?(:extendable_model) || params.key?("extendable_model")
      apply_config_defaults!  if params.key?(:config_defaults) || params.key?("config_defaults")
      apply_token_attribute! if params[:token_model].present? && params[:token_attribute].present?

      respond_to do |format|
        format.html { redirect_to show_path, notice: t("maint_platform.flash.module_settings.updated", name: @feature_module.name) }
        format.json { render json: { success: true, enabled: params[:token_enabled] == "1" } }
      end
    rescue StandardError => e
      respond_to do |format|
        format.html { redirect_to show_path, alert: t("maint_platform.flash.module_settings.update_failed", error: e.message) }
        format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      end
    end
```

- [ ] **Step 4: Run request spec to verify pass**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/platform/module_settings_controller.rb spec/requests/admin/maintenance/platform/module_settings_spec.rb
git commit -m "feat: add JSON response support to ModuleSettingsController#update for AJAX operations"
```

---

### Task 4: Create `template_token_checkbox_controller.js` and Vitest Suite

**Files:**
- Create: `app/javascript/controllers/template_token_checkbox_controller.js`
- Create: `spec/javascript/controllers/template_token_checkbox_controller.test.js`

- [ ] **Step 1: Write failing Vitest unit test**

Create `spec/javascript/controllers/template_token_checkbox_controller.test.js`:
```js
import { describe, it, expect, beforeEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import TemplateTokenCheckboxController from "../../app/javascript/controllers/template_token_checkbox_controller"

describe("TemplateTokenCheckboxController", () => {
  let application

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="template-token-checkbox"
           data-template-token-checkbox-url-value="/81721200/admin/maintenance/platform/module_settings/1"
           data-template-token-checkbox-token-model-value="User"
           data-template-token-checkbox-token-attribute-value="email">
        <input type="checkbox"
               data-template-token-checkbox-target="checkbox"
               data-action="change->template-token-checkbox#toggle" />
        <span data-template-token-checkbox-target="status" class="hidden"></span>
      </div>
    `
    application = Application.start()
    application.register("template-token-checkbox", TemplateTokenCheckboxController)
  })

  it "sends AJAX PATCH request on toggle change", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ success: true, enabled: true })
    })

    const checkbox = document.querySelector('input[type="checkbox"]')
    checkbox.checked = true
    checkbox.dispatchEvent(new Event("change"))

    expect(fetchSpy).toHaveBeenCalledWith(
      "/81721200/admin/maintenance/platform/module_settings/1",
      expect.objectContaining({
        method: "PATCH",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
          "Accept": "application/json"
        }),
        body: JSON.stringify({
          token_model: "User",
          token_attribute: "email",
          token_enabled: "1"
        })
      })
    )
  })

  it "handles fetch failure gracefully", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: false,
      json: async () => ({ success: false, error: "Failed" })
    })

    const checkbox = document.querySelector('input[type="checkbox"]')
    checkbox.checked = false
    checkbox.dispatchEvent(new Event("change"))

    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(checkbox.checked).toBe(true) // Reverts on error
  })
})
```

- [ ] **Step 2: Run Vitest to verify failure**

Run: `npx vitest run spec/javascript/controllers/template_token_checkbox_controller.test.js`
Expected: FAIL (Cannot find module template_token_checkbox_controller)

- [ ] **Step 3: Create `template_token_checkbox_controller.js`**

Create `app/javascript/controllers/template_token_checkbox_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "status"]
  static values = {
    url: String,
    tokenModel: String,
    tokenAttribute: String
  }

  async toggle() {
    const isChecked = this.checkboxTarget.checked
    this.showStatus("saving")

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        },
        body: JSON.stringify({
          token_model: this.tokenModelValue,
          token_attribute: this.tokenAttributeValue,
          token_enabled: isChecked ? "1" : "0"
        })
      })

      if (!response.ok) {
        throw new Error("HTTP error")
      }

      this.showStatus("saved")
    } catch (error) {
      this.checkboxTarget.checked = !isChecked
      this.showStatus("error")
    }
  }

  showStatus(state) {
    if (!this.hasStatusTarget) return

    this.statusTarget.classList.remove("hidden")
    if (state === "saving") {
      this.statusTarget.textContent = "..."
      this.statusTarget.className = "text-xs text-text-muted transition-opacity"
    } else if (state === "saved") {
      this.statusTarget.textContent = "✓"
      this.statusTarget.className = "text-xs text-success font-bold transition-opacity"
      setTimeout(() => {
        if (this.hasStatusTarget) this.statusTarget.classList.add("hidden")
      }, 1500)
    } else if (state === "error") {
      this.statusTarget.textContent = "!"
      this.statusTarget.className = "text-xs text-danger font-bold transition-opacity"
    }
  }
}
```

- [ ] **Step 4: Run Vitest to verify 100% lines & branches pass**

Run: `npx vitest run --coverage`
Expected: 100% lines & branches coverage across all JavaScript files.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/template_token_checkbox_controller.js spec/javascript/controllers/template_token_checkbox_controller.test.js
git commit -m "feat: add template_token_checkbox_controller with 100% vitest coverage"
```

---

### Task 5: Refactor Module Settings View (`show.html.erb`)

**Files:**
- Modify: `app/views/admin/maintenance/platform/module_settings/show.html.erb`
- Test: `spec/requests/admin/maintenance/platform/module_settings_spec.rb`

- [ ] **Step 1: Refactor Module Controls, Folded Models, Attribute Labels, and Checkboxes**

In `app/views/admin/maintenance/platform/module_settings/show.html.erb`:

1. **Module Controls Card**:
   - Update headers to position status badges alongside titles:
     ```erb
     <h3 class="text-body text-text-primary font-medium flex items-center gap-2">
       <%= t("maint_platform.module_settings.show.module_status") %>
       <% if @feature_module.active? %>
         <%= render BadgeComponent.new(variant: :success, size: :sm) do %><%= t("common.status.active") %><% end %>
       <% else %>
         <%= render BadgeComponent.new(variant: :default, size: :sm) do %><%= t("common.status.inactive") %><% end %>
       <% end %>
     </h3>
     ```
   - Render `ModuleToggleComponent` with `show_label: false`:
     ```erb
     <%= render Admin::Maintenance::Platform::ModuleToggleComponent.new(
           url: admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module),
           field: "status_active",
           on: @feature_module.active?,
           disabled: @feature_module.mandatory?,
           show_label: false
         ) %>
     ```
   - Repeat for `Required Module` and `Handoff Target`.

2. **Model Attributes & Template Tokens Card**:
   - Wrap each model in a `<details>` collapsible details card:
     ```erb
     <details class="group rounded-lg border border-border-subtle bg-surface mb-3 overflow-hidden">
       <summary class="flex items-center justify-between px-6 py-4 cursor-pointer select-none bg-surface hover:bg-surface-active transition-colors">
         <div class="flex items-center gap-3">
           <svg class="w-4 h-4 text-text-muted transform group-open:rotate-90 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
             <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
           </svg>
           <span class="text-body font-medium text-text-primary"><%= model[:name] %></span>
           <span class="text-mono text-xs bg-surface-active px-1.5 py-0.5 rounded text-text-muted"><%= model[:table_name] %></span>
         </div>
         <span class="text-caption"><%= model[:columns].size %> <%= t("maint_platform.module_settings.show.models.columns") %></span>
       </summary>
       <div class="border-t border-border-subtle p-4">
         <div class="overflow-x-auto">
           <table class="min-w-full divide-y divide-border-subtle">
             <thead class="table-header">
               <tr>
                 <th class="px-4 py-2 text-left text-label"><%= t("maint_platform.module_settings.show.tokens.attribute") %></th>
                 <th class="px-4 py-2 text-left text-label"><%= t("maint_platform.module_settings.show.tokens.attribute_label") %></th>
                 <th class="px-4 py-2 text-center text-label w-48"><%= t("maint_platform.module_settings.show.tokens.token_status") %></th>
               </tr>
             </thead>
             <tbody class="bg-surface divide-y divide-border-subtle">
               <% model[:columns].each do |col| %>
                 <% source_key = "#{model[:name].underscore.tr('/', '_')}.#{col[:name]}" %>
                 <% token_active = platform_token_keys.include?(source_key) %>
                 <tr class="table-row">
                   <td class="px-4 py-2.5 whitespace-nowrap text-mono text-sm text-text-primary">
                     <%= col[:name] %>
                   </td>
                   <td class="px-4 py-2.5 whitespace-nowrap text-body-sm text-text-primary">
                     <%= col[:label] %>
                   </td>
                   <td class="px-4 py-2.5 whitespace-nowrap text-center">
                     <div data-controller="template-token-checkbox"
                          data-template-token-checkbox-url-value="<%= admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module) %>"
                          data-template-token-checkbox-token-model-value="<%= model[:name] %>"
                          data-template-token-checkbox-token-attribute-value="<%= col[:name] %>"
                          class="inline-flex items-center justify-center gap-2">
                       <input type="checkbox"
                              data-template-token-checkbox-target="checkbox"
                              data-action="change->template-token-checkbox#toggle"
                              <%= "checked" if token_active %>
                              class="rounded border-border text-accent focus:ring-accent h-4 w-4 cursor-pointer" />
                       <span data-template-token-checkbox-target="status" class="hidden text-xs"></span>
                     </div>
                   </td>
                 </tr>
               <% end %>
             </tbody>
           </table>
         </div>
       </div>
     </details>
     ```

- [ ] **Step 2: Run RSpec request specs**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/maintenance/platform/module_settings/show.html.erb
git commit -m "refactor: update module settings UI/UX with title labels, attribute labels, AJAX checkboxes, and folded details"
```

---

### Task 6: Full Verification & Smoke Test

**Files:**
- All touched files

- [ ] **Step 1: Run targeted RSpec test suite**

Run: `bundle exec rspec spec/requests/admin/maintenance/platform/module_settings_spec.rb spec/components/admin/maintenance/platform/module_toggle_component_spec.rb`
Expected: All tests PASS.

- [ ] **Step 2: Run Vitest JS test suite and verify 100% coverage**

Run: `npx vitest run --coverage`
Expected: 100% lines & branches test coverage.

- [ ] **Step 3: Clean assets and verify dev server reboot sequence**

Run: `rm -f public/assets/.manifest.json`
Expected: Cleaned manifest for latest asset loading.

- [ ] **Step 4: Final Git Status Check**

Run: `git status`
Expected: Working tree clean or staged ready for reviewer commit.
