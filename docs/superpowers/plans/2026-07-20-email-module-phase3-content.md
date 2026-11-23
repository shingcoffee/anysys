# Email Module Phase 3 — Content Hub: Template Categories, Asset Library, Template Enhancements

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phase 1.

**Goal:** Enrich the content area with template categories, a shared asset library, and improved template building/preview tools.

**Architecture:** Add `category` to templates. Introduce `Emails::Asset` backed by Active Storage. Extend preview and test-send capabilities. Add an asset picker to the template form.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, Active Storage, RSpec.

## Global Constraints

- All user-facing strings I18n in `en` and `zh-CN`.
- TailwindCSS only; StimulusJS only.
- Admin routes require admin/owner.
- Cross-tenant scoping enforced.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/emails/asset.rb` | Active Storage-backed asset metadata. |
| `app/controllers/admin/modules/emails/assets_controller.rb` | Asset CRUD. |
| `app/controllers/admin/modules/emails/templates_controller.rb` | Updated for category and asset picker. |
| `app/components/emails/asset_picker_component.rb` | Asset picker for template form. |
| `db/migrate/20260722000000_create_email_assets.rb` | Assets table. |
| `db/migrate/20260722000001_add_category_and_stream_id_to_email_templates.rb` | Template additions. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Content UI keys. |

---

## Task 1: Create asset library

**Files:**
- Create: `db/migrate/20260722000000_create_email_assets.rb`
- Create: `app/models/emails/asset.rb`
- Create: `app/controllers/admin/modules/emails/assets_controller.rb`
- Create views: `app/views/admin/modules/emails/assets/index|new|edit/_form.html.erb`
- Test: `spec/models/emails/asset_spec.rb`, `spec/requests/admin/modules/emails/assets_spec.rb`

- [ ] **Step 1: Write migration**

```ruby
class CreateEmailAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :email_assets do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "image"
      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Implement model**

```ruby
# app/models/emails/asset.rb
module Emails
  class Asset < ApplicationRecord
    self.table_name = "email_assets"
    include TenantScoped
    has_one_attached :file
    belongs_to :customer
    validates :customer_id, :name, presence: true
    validates :kind, inclusion: { in: %w[image file] }
    validate :file_attached

    def file_attached
      errors.add(:file, I18n.t("admin_modules.emails.assets.file_required")) unless file.attached?
    end

    def image? = kind == "image"
  end
end
```

- [ ] **Step 3: Implement controller**

Standard CRUD with Active Storage file upload. Ensure tenant-scoped file access.

- [ ] **Step 4: Add routes**

```ruby
resources :assets
```

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/models/emails/asset_spec.rb spec/requests/admin/modules/emails/assets_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(email): add asset library for images and files"
```

---

## Task 2: Add template category and stream linkage

**Files:**
- Create: `db/migrate/20260722000001_add_category_and_stream_id_to_email_templates.rb`
- Modify: `app/models/emails/template.rb`
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb`
- Test: `spec/models/emails/template_spec.rb`

- [ ] **Step 1: Write migration**

```ruby
class AddCategoryAndStreamIdToEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :email_templates, :category, :string
    add_reference :email_templates, :email_stream, foreign_key: true, index: true
  end
end
```

- [ ] **Step 2: Update model**

```ruby
# app/models/emails/template.rb
CATEGORIES = %w[account notification marketing receipt other].freeze

belongs_to :email_stream, optional: true, class_name: "Emails::Stream"
validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

def category_name
  category.presence || "other"
end
```

- [ ] **Step 3: Update controller params**

Add `:category, :email_stream_id` to `template_params`.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/models/emails/template_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add category and stream linkage to templates"
```

---

## Task 3: Asset picker and template form enhancements

**Files:**
- Create: `app/components/emails/asset_picker_component.rb` + `.html.erb`
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`
- Test: `spec/components/emails/asset_picker_component_spec.rb`

- [ ] **Step 1: Implement asset picker component**

Lists tenant assets with thumbnail, emits selected asset URL via Stimulus event or data attribute.

- [ ] **Step 2: Integrate into template form**

Add a button to open the asset picker; on selection insert `<img src="...">` into the rich-text editor or code editor.

- [ ] **Step 3: Run component specs**

Run: `bundle exec rspec spec/components/emails/asset_picker_component_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): integrate asset picker into template form"
```

---

## Task 4: Enhance template preview and test send

**Files:**
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb`
- Modify: `app/services/emails/template_renderer.rb`
- Test: existing preview/test specs

- [ ] **Step 1: Preview with stream context**

`preview` action uses the template's stream (or default transactional) to render tracking pixel/links.

- [ ] **Step 2: Multi-recipient test send**

Allow comma-separated test addresses; send to each.

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb spec/services/emails/template_renderer_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): enhance template preview and multi-recipient test send"
```

---

## Task 5: Phase 3 integration

- [ ] **Step 1: Run content-area specs**

Run: `bundle exec rspec spec/models/emails/asset_spec.rb spec/models/emails/template_spec.rb spec/requests/admin/modules/emails/templates_spec.rb spec/requests/admin/modules/emails/assets_spec.rb spec/components/emails/asset_picker_component_spec.rb`
Expected: PASS.

- [ ] **Step 2: Stage**

```bash
git add -A
```

Phase 3 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 3 — content hub with categories, asset library, template enhancements"
```
