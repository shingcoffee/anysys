# Remove Email Assets Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely and completely deprecate and remove the Email Assets feature from the Email module, including its model, controller, views, routing, components, JS controller, locale entries, and related tests.

**Architecture:** This is a removal/cleanup task. We will delete all dedicated files for the Email Assets feature, clean up references in templates and navigation files, update database schema to drop the table, and make sure all tests pass cleanly.

**Tech Stack:** Rails v8.1.2, TailwindCSS, StimulusJS, Ruby 3.2.8, Rspec, Vitest.

## Global Constraints
- Do not commit changes automatically (the human reviewer will commit after review).
- Ensure 100% JS line/branch test coverage.
- Keep English (`en`) and Simplified Chinese (`zh-CN`) translations in sync.
- Make changes directly on the master branch.

---

### Task 1: Drop Database Table

**Files:**
- Create: `db/migrate/20260721132900_drop_email_assets.rb`

- [ ] **Step 1: Create a migration to drop the email_assets table**
  Create `db/migrate/20260721132900_drop_email_assets.rb`:
  ```ruby
  class DropEmailAssets < ActiveRecord::Migration[8.1]
    def change
      drop_table :email_assets do |t|
        t.references :customer, null: false, foreign_key: true
        t.string :name, null: false
        t.string :kind, null: false, default: "image"
        t.timestamps
      end
    end
  end
  ```

- [ ] **Step 2: Run migration to drop the table**
  Run: `bundle exec rails db:migrate`
  Expected: Success, schema.rb updated.

---

### Task 2: Delete Model, Controller, and Views

**Files:**
- Delete: `app/models/emails/asset.rb`
- Delete: `app/controllers/admin/modules/emails/assets_controller.rb`
- Delete: `app/views/admin/modules/emails/assets/index.html.erb`
- Delete: `app/views/admin/modules/emails/assets/new.html.erb`
- Delete: `app/views/admin/modules/emails/assets/edit.html.erb`
- Delete: `app/views/admin/modules/emails/assets/_form.html.erb`

- [ ] **Step 1: Delete model and controller files**
  Delete:
  - `app/models/emails/asset.rb`
  - `app/controllers/admin/modules/emails/assets_controller.rb`

- [ ] **Step 2: Delete the views directory**
  Delete the entire directory: `app/views/admin/modules/emails/assets/`

---

### Task 3: Delete Component and JS Controller

**Files:**
- Delete: `app/components/emails/asset_picker_component.rb`
- Delete: `app/components/emails/asset_picker_component.html.erb`
- Delete: `app/javascript/controllers/asset_picker_controller.js`

- [ ] **Step 1: Delete components files**
  Delete:
  - `app/components/emails/asset_picker_component.rb`
  - `app/components/emails/asset_picker_component.html.erb`

- [ ] **Step 2: Delete the Stimulus controller**
  Delete: `app/javascript/controllers/asset_picker_controller.js`

---

### Task 4: Clean Up Routing and Registration

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/services/feature_modules/email/registration.rb`

- [ ] **Step 1: Modify routes.rb**
  Remove `resources :assets` from line 496 in `config/routes.rb`.
  Before:
  ```ruby
          resources :automations
          resources :assets
          resources :reports, only: %i[index]
  ```
  After:
  ```ruby
          resources :automations
          resources :reports, only: %i[index]
  ```

- [ ] **Step 2: Modify registration.rb**
  Remove `assets` from tab paths on line 66 in `app/services/feature_modules/email/registration.rb`.
  Before:
  ```ruby
            entry("content", "#{base}/templates", tab_paths: %w[templates assets]),
  ```
  After:
  ```ruby
            entry("content", "#{base}/templates", tab_paths: %w[templates]),
  ```

---

### Task 5: Clean Up Templates, Tabs, and Forms

**Files:**
- Modify: `app/views/admin/modules/emails/shared/_content_tabs.html.erb`
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

- [ ] **Step 1: Modify shared content tabs**
  Remove assets tab from `app/views/admin/modules/emails/shared/_content_tabs.html.erb`:
  ```erb
  <%
    tabs = [
      { label: t("feature_modules.email.tabs.templates"), path: admin_modules_emails_templates_path(current_customer.id), active: active_tab == :templates }
    ]
  %>
  <%= render Emails::TabsComponent.new(tabs: tabs) %>
  ```

- [ ] **Step 2: Remove Asset Picker Component from email templates form**
  Remove the `<%= render Emails::AssetPickerComponent.new(...) %>` lines from `app/views/admin/modules/emails/templates/_form.html.erb` (around lines 115 and 137).

---

### Task 6: Clean Up Locales

**Files:**
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`
- Modify: `config/locales/feature_modules.en.yml`
- Modify: `config/locales/feature_modules.zh-CN.yml`

- [ ] **Step 1: Remove assets keys in admin_modules locales**
  Remove the `assets:` section and `flash: assets:` section completely from `config/locales/admin_modules.en.yml` and `config/locales/admin_modules.zh-CN.yml`.

- [ ] **Step 2: Remove assets keys in feature_modules locales**
  Remove `assets: "Assets"` / `assets: "资源"` from `feature_modules.en.yml` and `feature_modules.zh-CN.yml`.

---

### Task 7: Clean Up Tests

**Files:**
- Delete: `spec/models/emails/asset_spec.rb`
- Delete: `spec/requests/admin/modules/emails/assets_spec.rb`
- Delete: `spec/components/emails/asset_picker_component_spec.rb`
- Delete: `spec/factories/email_assets.rb`
- Delete: `spec/javascript/controllers/asset_picker_controller.test.js`

- [ ] **Step 1: Delete all asset related backend tests**
  Delete:
  - `spec/models/emails/asset_spec.rb`
  - `spec/requests/admin/modules/emails/assets_spec.rb`
  - `spec/components/emails/asset_picker_component_spec.rb`
  - `spec/factories/email_assets.rb`

- [ ] **Step 2: Delete asset related JS test**
  Delete: `spec/javascript/controllers/asset_picker_controller.test.js`

- [ ] **Step 3: Run targeted test suite to verify cleanup**
  Run:
  - `bundle exec rspec spec/services/feature_modules/email/registration_spec.rb`
  - `npx vitest run --coverage`
