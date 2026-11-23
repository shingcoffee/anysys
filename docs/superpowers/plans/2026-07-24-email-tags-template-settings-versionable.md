# Email Tags removal + Template Settings prune + Versionable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Email audience Tags entirely; make template edit composer-only with Status actionable (guarded) on the list; migrate templates to shared Versionable + Versions modal; switch Gateway/Send from `template_key` to `template_id`.

**Architecture:** Drop Tags tables/code. Prune `key`/`template_type`/`category`/`variables` from `email_templates`. Keep `status` on the parent with a list `PATCH` + campaign non-terminal guard. Replace custom `Emails::TemplateVersion` snapshots with content-addressed `Versionable` (Pages pattern). Extend Stimulus `versions` with a path-prefix value so the modal works under `/admin/modules/emails/templates`. Send contract resolves by `template_id`.

**Tech Stack:** Rails 8.1 / Versionable + ContentAddressable / Reform / ViewComponent / Stimulus / RSpec / Vitest

**Spec:** `docs/superpowers/specs/2026-07-24-email-tags-template-settings-versionable-design.md`

## Global Constraints

- No hard-coded user-facing strings — `en` + `zh-CN` for every new key; English value byte-identical to what would have been hard-coded.
- Stimulus: no literal UI strings in JS — English `default:` Values + server `data-*-value` when needed.
- Multi-tenant: every query via `for_current_customer` / explicit `customer_id`.
- Auth: admin/owner only on Email module admin controllers; no member access.
- JS under `app/javascript/**` must stay at 100% Vitest lines + branches for touched files.
- Do **not** commit unless the user explicitly asks (repo policy). Skip commit steps.
- No backward-compat aliases for `template_key` or Tags routes.
- Customer Email module settings and platform credentials are out of scope.

## File map

| File | Responsibility |
|------|----------------|
| `db/migrate/20260724180000_drop_email_tags.rb` | Drop `email_taggings`, `email_tags` |
| `db/migrate/20260724190000_email_templates_versionable_and_prune.rb` | Versionable tables; backfill; prune columns; reshape versions |
| `app/models/emails/audience/tag.rb` | **Delete** |
| `app/models/emails/audience/tagging.rb` | **Delete** |
| `app/controllers/admin/modules/emails/tags_controller.rb` | **Delete** |
| `app/views/admin/modules/emails/tags/**` | **Delete** |
| `spec/factories/email_tags.rb` | **Delete** |
| `spec/models/emails/audience/tag_spec.rb` | **Delete** |
| `spec/requests/admin/modules/emails/tags_spec.rb` | **Delete** |
| `app/models/authentication/user.rb` | Remove `email_tags` / `email_taggings` |
| `app/views/admin/modules/emails/shared/_audience_tabs.html.erb` | Remove Tags tab |
| `app/controllers/admin/modules/emails/contacts_controller.rb` | Remove tags column |
| `app/views/admin/modules/emails/contacts/show.html.erb` | Remove tags section |
| `config/routes.rb` | Drop tags; expand template versions; add status member |
| `app/models/emails/template.rb` | Versionable; prune fields; status guard helper |
| `app/models/emails/template_version.rb` | VersionRecord (Pages-shaped) |
| `app/models/emails/template_content.rb` | ContentAddressable store |
| `app/models/emails/template_version.rb` (old snapshot API) | Replaced |
| `app/services/email/contracts/send.rb` | `template_id`; drop vars-vs-variables matching |
| `app/services/emails/activities/send.rb` | `template_id:` kwarg |
| `app/services/emails/gateway.rb` | `template_id:` kwarg |
| `app/services/feature_modules/email/registration.rb` | `template_id` property |
| `app/controllers/admin/modules/emails/templates_controller.rb` | Status action; slim permit; list row actions |
| `app/controllers/admin/modules/emails/template_versions_controller.rb` | BaseVersions-compatible JSON API |
| `app/views/admin/modules/emails/templates/_form.html.erb` | Composer only (no Settings/Versions tabs) |
| `app/views/admin/modules/emails/templates/index.html.erb` | Versions modal + Status actions |
| `app/views/admin/modules/emails/template_versions/**` | Delete HTML views (modal replaces) |
| `app/javascript/controllers/versions_controller.js` | Optional `pathPrefix` value |
| `spec/javascript/controllers/versions_controller.test.js` | Cover pathPrefix branches |
| Locale files | Tags cleanup; status-guard; versions row label |
| Specs | Tags removal; template prune; status guard; send by id; versions JSON |

---

### Task 1: Remove Tags (schema + code + specs)

**Files:**
- Create: `db/migrate/20260724180000_drop_email_tags.rb`
- Delete: models/controllers/views/factories/specs listed in file map for Tags
- Modify: `config/routes.rb` (remove `resources :tags`)
- Modify: `app/models/authentication/user.rb`
- Modify: `app/views/admin/modules/emails/shared/_audience_tabs.html.erb`
- Modify: `app/controllers/admin/modules/emails/contacts_controller.rb`
- Modify: `app/views/admin/modules/emails/contacts/show.html.erb`
- Modify: `config/locales/admin_modules.en.yml` / `.zh-CN.yml` / feature_modules locale keys for tags tabs if unused
- Test: `spec/routing/admin/modules/emails/emails_routing_spec.rb`, contacts request/model specs that referenced tags

**Interfaces:**
- Consumes: existing `email_tags` / `email_taggings`
- Produces: no Tag models; tags routes absent; contacts without tags

- [ ] **Step 1: Write failing routing expectation**

In `spec/routing/admin/modules/emails/emails_routing_spec.rb` (or create if missing tags examples), add:

```ruby
it "does not route email tags" do
  expect(get: "/81721200/admin/modules/emails/tags").not_to be_routable
end
```

- [ ] **Step 2: Run to verify it fails (still routable)**

Run: `bundle exec rspec spec/routing/admin/modules/emails/emails_routing_spec.rb -e "does not route email tags"`

Expected: FAIL (route still exists) or example missing until added against current routes.

- [ ] **Step 3: Migration + delete Tags surface**

```ruby
# db/migrate/20260724180000_drop_email_tags.rb
class DropEmailTags < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :email_taggings, :email_tags if foreign_key_exists?(:email_taggings, :email_tags)
    drop_table :email_taggings, if_exists: true
    drop_table :email_tags, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- Remove `resources :tags` from `config/routes.rb`.
- Delete Tag/Tagging models, TagsController, tags views, factory, tag model/request specs.
- Remove from `Authentication::User`:

```ruby
# DELETE these associations
has_many :email_taggings, as: :taggable, class_name: "Emails::Audience::Tagging", dependent: :destroy
has_many :email_tags, through: :email_taggings, source: :tag
```

- Audience tabs: remove the Tags hash entry.
- Contacts controller: remove `:tags` column and `.includes(:email_tags)`.
- Contacts show: remove the tags section.
- Grep and remove orphaned i18n keys under `admin_modules.emails.tags`, `feature_modules.email.tabs.tags`, `feature_modules.email.entries.tags`, flash `tags.*`, and dead automation `trigger_tag_ids_*` / signup `tag_ids` keys if nothing references them.

- [ ] **Step 4: Run migration + targeted specs**

Run:

```bash
bin/rails db:migrate
bundle exec rspec spec/routing/admin/modules/emails/emails_routing_spec.rb \
  spec/requests/admin/modules/emails/ \
  spec/models/authentication/user_spec.rb --format progress
```

Expected: PASS; no references to deleted Tag constants. Fix any remaining greps of `email_tag` / `Audience::Tag`.

- [ ] **Step 5: Skip commit** (repo policy)

---

### Task 2: Switch Send API to `template_id` (drop variables matching)

**Files:**
- Modify: `app/services/email/contracts/send.rb`
- Modify: `app/services/emails/activities/send.rb`
- Modify: `app/services/emails/gateway.rb`
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `spec/services/emails/activities/send_spec.rb`
- Modify: `spec/services/emails/gateway_spec.rb`
- Modify: any request/webhook specs that pass `template_key:`
- Test: those specs

**Interfaces:**
- Consumes: `Emails::Template` still has `key` until Task 4 (lookup by id now)
- Produces: `Emails::Gateway.send(..., template_id:, vars:)` and contract `template_id`

- [ ] **Step 1: Update specs to `template_id`**

Replace every `template_key: "welcome"` (and similar) with `template_id: template.id` where `template` is the factory record. Example contract expectations:

```ruby
# Email::Contracts::Send
Input = Struct.new(:customer_id, :to, :template_id, :vars, :cc, :bcc, :reply_to, :idempotency_key)
```

In send_spec, for missing template:

```ruby
described_class.call(customer: customer, to: "a@b.com", template_id: 0, vars: { name: "X" })
# raises TemplateVarsInvalid / not found
```

Remove examples that assert vars missing required template variable keys (variables column is going away in Task 4 — drop `vars_shape_matches_template` entirely in this task so send does not depend on `template.variables`).

- [ ] **Step 2: Run specs — expect FAIL**

Run: `bundle exec rspec spec/services/emails/activities/send_spec.rb spec/services/emails/gateway_spec.rb`

Expected: FAIL (unknown keyword `template_id` / missing `template_key`).

- [ ] **Step 3: Implement**

`app/services/email/contracts/send.rb`:

```ruby
property :template_id
validates :template_id, presence: true
# remove property :template_key and vars_shape_matches_template

def template
  @template ||= Emails::Template.active.find_by(customer_id: customer_id, id: template_id)
end

def template_exists_and_active
  return if template_id.blank?
  return if template.present?
  errors.add(:template_id, I18n.t("admin_modules.errors.validations.template_not_active"))
end
```

Add both locale keys if missing (en + zh-CN). Prefer reusing an existing key if English text already matches.

Wire `Activities::Send.call` and `Gateway.send` kwargs to `template_id:`. Update registration:

```ruby
property :template_id, validates: { presence: true }
```

Grep `template_key` under `app/` and `spec/` for Email send paths and update.

- [ ] **Step 4: Run specs — expect PASS**

Run: `bundle exec rspec spec/services/emails/activities/send_spec.rb spec/services/emails/gateway_spec.rb spec/requests/emails/webhooks_spec.rb`

- [ ] **Step 5: Skip commit**

---

### Task 3: Composer-only template edit (remove Settings + Versions tabs)

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` (`template_params` — stop permitting settings-only fields once Task 4 drops them; for now stop permitting `:status` from edit form since Status moves to list in Task 5)
- Modify: request specs that assert Settings/Versions tab copy
- Test: `spec/requests/admin/modules/emails/templates_spec.rb`

**Interfaces:**
- Consumes: workspace partial
- Produces: edit page without Settings/Versions tabs; status not updated via edit form

- [ ] **Step 1: Failing request assertion**

```ruby
it "renders composer without Settings or Version History tabs" do
  get edit_admin_modules_emails_template_path(customer.id, template)
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.form.tabs.settings"))
  expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.form.tabs.versions"))
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb -e "renders composer without"`

- [ ] **Step 3: Slim `_form.html.erb`**

For persisted templates, render workspace directly (same as new) — delete the `data-controller="tabs"` Settings and Versions panels entirely. Keep cancel/submit footer.

In `template_params`, remove `:status` from permit list (Status updated only via Task 5 endpoint). Keep other permits until Task 4 migration drops columns.

- [ ] **Step 4: Run templates request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb`

Expected: PASS after updating any examples that POSTed status/settings fields via edit.

- [ ] **Step 5: Skip commit**

---

### Task 4: Versionable migration + prune template columns

**Files:**
- Create: `db/migrate/20260724190000_email_templates_versionable_and_prune.rb`
- Create/Replace: `app/models/emails/template_content.rb`
- Replace: `app/models/emails/template_version.rb` (VersionRecord)
- Modify: `app/models/emails/template.rb`
- Modify: `spec/factories/email_templates.rb`
- Modify: `spec/models/emails/template_spec.rb`
- Delete old snapshot-only helpers/specs that assert `Emails::TemplateVersion.create_for` / `snapshot` JSON
- Test: template model spec

**Interfaces:**
- Consumes: Pages Versionable pattern (`acts_as_versionable`, `ContentAddressable`, `VersionRecord`)
- Produces: `Emails::Template` with `current_version_id`; payload snapshot of definition; no `key`/`template_type`/`category`/`variables`

- [ ] **Step 1: Model specs for Versionable + pruned attrs**

```ruby
it "does not expose key/template_type/category/variables" do
  t = create(:email_template)
  expect(t.attributes.keys).not_to include("key", "template_type", "category", "variables")
end

it "auto-commits a version when subject changes" do
  t = create(:email_template, subject: "A")
  expect {
    t.update!(subject: "B")
  }.to change { t.template_versions.count }.by(1)
end

it "does not commit a version when only status changes" do
  t = create(:email_template, status: "draft")
  expect {
    t.update!(status: "active")
  }.not_to change { t.template_versions.count }
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bundle exec rspec spec/models/emails/template_spec.rb`

- [ ] **Step 3: Migration**

Implement one migration that:

1. Creates `email_template_contents` (`customer_id`, `content_hash`, `payload`, timestamps) with unique index on `[customer_id, content_hash]`.
2. Creates new table `email_template_versions_new` with Versionable columns (`email_template_id`, `version_number`, `content_id`, `based_on_version_id`, `description`, `customer_id`, timestamps) + unique `[email_template_id, version_number]`.
3. Adds `email_templates.current_version_id` (nullable FK).
4. Backfills: for each `email_templates` row, build payload hash:

```ruby
payload = {
  "subject" => row.subject,
  "body_html" => row.body_html,
  "body_text" => row.body_text,
  "editor_type" => row.editor_type,
  "body_raw" => row.body_html # ActionText body restored from body_html if no separate raw available in SQL
}
```

Store via content hash; insert version_number=1; set `current_version_id`.

5. Drops old `email_template_versions`; renames `email_template_versions_new` → `email_template_versions`.
6. Removes indexes/columns from `email_templates`: `key`, `template_type`, `category`, `variables`.
7. Adds FKs for versions → contents, versions → templates, templates.current_version_id → versions (`on_delete: :nullify`).

- [ ] **Step 4: Models**

`app/models/emails/template_content.rb`:

```ruby
module Emails
  class TemplateContent < ApplicationRecord
    self.table_name = "email_template_contents"
    include ContentAddressable
    has_many :template_versions, class_name: "Emails::TemplateVersion",
             foreign_key: :content_id, inverse_of: :content, dependent: :restrict_with_exception
    def self.version_association = :template_versions
  end
end
```

`app/models/emails/template_version.rb`:

```ruby
module Emails
  class TemplateVersion < ApplicationRecord
    self.table_name = "email_template_versions"
    include VersionRecord
    acts_as_version parent: :email_template, content_class: "Emails::TemplateContent"
  end
end
```

Check `VersionRecord` / `acts_as_version` parent association naming — mirror `PageVersion` (`parent: :page`). If the reflection name must match `has_many` on parent, use `parent: :email_template` and ensure Template declares:

```ruby
acts_as_versionable reflection: :template_versions,
                    version_class: "Emails::TemplateVersion",
                    content_class: "Emails::TemplateContent",
                    snapshot: :definition_snapshot
```

On `Emails::Template`:

```ruby
include Versionable

acts_as_versionable reflection: :template_versions,
                    version_class: "Emails::TemplateVersion",
                    content_class: "Emails::TemplateContent",
                    snapshot: :definition_snapshot

# Remove: TEMPLATE_TYPES, CATEGORIES, key validations, category/variables validations,
# generate_key_if_blank, variables_is_array_of_strings, after_update :snapshot_version!,
# required_vars / category_name if unused.

STATUSES = %w[draft active retired].freeze
EDITOR_TYPES = %w[rich_text code].freeze

def definition_snapshot
  {
    "subject" => subject,
    "body_html" => body_html,
    "body_text" => body_text,
    "editor_type" => editor_type,
    "body_raw" => (editor_type == "rich_text" ? body.to_s : body_html.to_s)
  }.to_json
end

# Override restore application: Versionable restore_as_new! sets snapshot via content;
# implement apply hook if Page has one — read Versionable#restore_as_new! and ensure
# subject/body_html/editor_type/ActionText body are written from payload JSON.
```

Read `Versionable#restore_as_new!` and Page's restore path; implement the same apply-from-payload pattern so rich_text `body_raw` is assigned to `body` before save.

Factory:

```ruby
factory :email_template, class: "Emails::Template" do
  customer
  name { "Welcome Email" }
  subject { "Welcome {{first_name}}!" }
  body_html { "<p>Hello {{first_name}}, welcome to our service.</p>" }
  editor_type { "code" }
  status { "active" }
  # no key / template_type / category / variables
end
```

Update `TemplatesController#template_params` to only permit compose fields:

```ruby
params.require(:email_template).permit(:name, :subject, :body, :body_html, :body_text, :editor_type)
```

Remove `normalize_template_variables`. Fix `new` defaults (drop template_type/variables).

Grep and fix all specs/factories still setting `key:` / `template_type:` / `variables:`.

- [ ] **Step 5: Migrate + run model/request specs**

```bash
bin/rails db:migrate
bundle exec rspec spec/models/emails/template_spec.rb \
  spec/requests/admin/modules/emails/templates_spec.rb \
  spec/services/emails/activities/send_spec.rb \
  spec/jobs/emails/campaigns/send_campaign_job_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Skip commit**

---

### Task 5: Status actionable on templates list (with campaign guard)

**Files:**
- Modify: `config/routes.rb` — `member { patch :status }` on templates
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` — `#status` action + index columns/row_actions
- Modify: `app/models/emails/template.rb` — `in_use_by_non_terminal_campaign?` / `update_status!`
- Modify: `app/views/admin/modules/emails/templates/index.html.erb` if needed for row_actions
- Modify: locales en + zh-CN for guard error + action labels
- Test: `spec/requests/admin/modules/emails/templates_spec.rb`, `spec/models/emails/template_spec.rb`

**Interfaces:**
- Consumes: `Emails::Campaigns::Campaign::NON_TERMINAL_STATUSES`
- Produces: `PATCH /:cid/admin/modules/emails/templates/:id/status` with `status` param

- [ ] **Step 1: Failing specs**

```ruby
describe "PATCH #status" do
  it "updates status when no non-terminal campaign references the template" do
    template = create(:email_template, customer: customer, status: "draft")
    patch status_admin_modules_emails_template_path(customer.id, template), params: { status: "active" }
    expect(response).to redirect_to(admin_modules_emails_templates_path(customer.id))
    expect(template.reload.status).to eq("active")
  end

  it "rejects draft when a non-terminal campaign references the template" do
    template = create(:email_template, customer: customer, status: "active")
    create(:email_campaign, customer: customer, email_template: template, status: "scheduled")
    patch status_admin_modules_emails_template_path(customer.id, template), params: { status: "draft" }
    expect(template.reload.status).to eq("active")
    expect(flash[:alert]).to eq(I18n.t("admin_modules.emails.templates.status.in_use"))
  end

  it "rejects cross-tenant status change" do
    other = create(:email_template, customer: other_customer, status: "draft")
    patch status_admin_modules_emails_template_path(customer.id, other), params: { status: "active" }
    expect(response).to have_http_status(:not_found) # or whatever for_current_customer raises
  end
end
```

Add matching zh-CN / en:

```yaml
# en
emails:
  templates:
    status:
      in_use: "Status can't be changed while a campaign still uses this template."
      actions:
        set_draft: "Set draft"
        set_active: "Set active"
        set_retired: "Set retired"
```

```yaml
# zh-CN
emails:
  templates:
    status:
      in_use: "仍有进行中的活动使用此模板，无法更改状态。"
      actions:
        set_draft: "设为草稿"
        set_active: "设为启用"
        set_retired: "设为停用"
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Routes:

```ruby
resources :templates, only: %i[index new create edit update destroy] do
  member { patch :status }
  # versions routes rewritten in Task 6
  ...
end
```

Model:

```ruby
def in_use_by_non_terminal_campaign?
  Emails::Campaigns::Campaign
    .where(email_template_id: id, status: Emails::Campaigns::Campaign::NON_TERMINAL_STATUSES)
    .exists?
end

def update_status!(new_status)
  new_status = new_status.to_s
  raise ArgumentError, "invalid" unless STATUSES.include?(new_status)
  if %w[draft retired].include?(new_status) && in_use_by_non_terminal_campaign?
    errors.add(:status, I18n.t("admin_modules.emails.templates.status.in_use"))
    return false
  end
  update(status: new_status)
end
```

Controller `#status`:

```ruby
def status
  if @template.update_status!(params.require(:status))
    redirect_to admin_modules_emails_templates_path(current_customer_id),
                notice: t("admin_modules.flash.templates.updated")
  else
    redirect_to admin_modules_emails_templates_path(current_customer_id),
                alert: @template.errors.full_messages.to_sentence.presence ||
                       t("admin_modules.emails.templates.status.in_use")
  end
end
```

Index `row_actions` (in addition to versions action from Task 6):

```ruby
row_actions: ->(t) {
  Emails::Template::STATUSES.reject { |s| s == t.status }.map { |s|
    {
      label: I18n.t("admin_modules.emails.templates.status.actions.set_#{s}"),
      path: status_admin_modules_emails_template_path(current_customer_id, t),
      method: :patch,
      params: { status: s }
    }
  }
}
```

Confirm `AdminTableComponent` supports `method:` + `params:` on row actions (read component). If not, use `button_to`-compatible keys the component already documents, or pass query `?status=` and read `params[:status]` only from permitted patch body via `button_to ..., params: { status: s }`.

- [ ] **Step 4: Run specs — PASS**

Run: `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb spec/models/emails/template_spec.rb`

- [ ] **Step 5: Skip commit**

---

### Task 6: Versions JSON API + list modal (extend Stimulus pathPrefix)

**Files:**
- Modify: `app/javascript/controllers/versions_controller.js` — add `pathPrefix` value (default `admin/maintenance`)
- Modify: `spec/javascript/controllers/versions_controller.test.js` — cover default + custom prefix
- Replace: `app/controllers/admin/modules/emails/template_versions_controller.rb` — BaseVersions-compatible actions
- Modify: `config/routes.rb` — versions nest like Pages (`index show create destroy` + `member { put :default }` + `edit`)
- Modify: `app/views/admin/modules/emails/templates/index.html.erb` — versions Stimulus + modal + row action
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` — `#edit` optional `params[:version]` apply
- Delete: HTML `app/views/admin/modules/emails/template_versions/**` (modal replaces)
- Test: request specs for versions JSON; Vitest coverage 100% on versions_controller.js

**Interfaces:**
- Consumes: `Versionable` on Template; Stimulus `_base()`
- Produces: `GET/POST/PUT/DELETE …/templates/:template_id/versions` JSON contract identical to Pages

- [ ] **Step 1: Vitest for pathPrefix**

```js
it("uses pathPrefix value when set", () => {
  ctrl.pathPrefixValue = "admin/modules/emails"
  ctrl.resourceValue = "templates"
  ctrl.customerIdValue = "42"
  ctrl.parentId = "7"
  expect(ctrl._base()).toBe("/42/admin/modules/emails/templates/7/versions")
})

it("defaults pathPrefix to admin/maintenance", () => {
  ctrl.resourceValue = "flowcharts"
  ctrl.customerIdValue = "42"
  ctrl.parentId = "99"
  expect(ctrl._base()).toBe("/42/admin/maintenance/flowcharts/99/versions")
})
```

- [ ] **Step 2: Run Vitest — expect FAIL**

Run: `npx vitest run spec/javascript/controllers/versions_controller.test.js --coverage`

- [ ] **Step 3: Implement pathPrefix**

```js
static values = {
  customerId: String,
  resource: String,
  pathPrefix: { type: String, default: "admin/maintenance" },
  // ... existing i18n values
}

_base() {
  return `/${this.customerIdValue}/${this.pathPrefixValue}/${this.resourceValue}/${this.parentId}/versions`
}
```

- [ ] **Step 4: Routes + TemplateVersionsController**

```ruby
resources :templates, only: %i[index new create edit update destroy] do
  resources :versions, only: %i[index show create edit destroy], controller: "template_versions" do
    member { put :default }
  end
  member do
    patch :status
    post :test_send
    post :preview
  end
  collection do
    post :test_send
    post :preview
  end
end
```

Controller — subclass or copy `Admin::Maintenance::BaseVersionsController` JSON actions with:

```ruby
module Admin
  module Modules
    module Emails
      class TemplateVersionsController < ApplicationController
        dashboard_menu_item :modules
        before_action :find_template
        before_action :guard_write!, only: %i[create default destroy]

        def index
          versions = @template.current_line_versions.recent.includes(:based_on_version)
          render json: versions.map { |v| index_json(v) }
        end
        # show / create (restore_as_new!) / default (set_current_version!) / destroy
        # mirror BaseVersionsController exactly (including 422 current undeletable)

        def edit
          version = @template.template_versions.find(params[:id])
          redirect_to edit_admin_modules_emails_template_path(current_customer_id, @template, version: version.id)
        end

        private

        def find_template
          @template = ::Emails::Template.for_current_customer.find(params[:template_id])
        end

        def index_json(v)
          # copy from BaseVersionsController#index_json
        end

        def guard_write!
          # same auth as other email module write actions (admin/owner already via RouteAuthorization)
        end
      end
    end
  end
end
```

Prefer extracting a shared concern from `BaseVersionsController` if duplication is large — only if it stays a small diff; otherwise copy the JSON methods once.

`TemplatesController#edit`: if `params[:version]` present, load that version's payload and assign subject/body_html/editor_type/body onto `@template` for the form (unsaved), matching Page editor version open behavior.

- [ ] **Step 5: Index view wiring**

```erb
<%= tag.div(data: {
      controller: "versions",
      "versions-customer-id-value": current_customer_id,
      "versions-resource-value": "templates",
      "versions-path-prefix-value": "admin/modules/emails"
    }.merge(versions_i18n_data)) do %>
  <%= render AdminTableComponent.new(
        ...,
        row_actions: ->(t) {
          status_actions_for(t) + [
            { label: t("maint_core.nav.versions"), path: "#",
              data: { turbo: "false", action: "versions#open",
                      "versions-id-param": t.id,
                      "versions-name-param": t.name } }
          ]
        }
      ) %>
  <%= render VersionsModalComponent.new %>
<% end %>
```

Helper or inline for status_actions_for from Task 5.

Delete obsolete HTML version index/show templates and the old `post :restore` member route.

- [ ] **Step 6: Request specs for versions JSON**

```ruby
it "lists versions as JSON" do
  template = create(:email_template, customer: customer)
  template.update!(subject: "Changed")
  get admin_modules_emails_template_versions_path(customer.id, template), as: :json
  expect(response).to have_http_status(:ok)
  expect(JSON.parse(response.body)).to be_an(Array)
end

it "restores as new via POST" do
  template = create(:email_template, customer: customer, subject: "V1")
  template.update!(subject: "V2")
  v1 = template.template_versions.order(:version_number).first
  post admin_modules_emails_template_versions_path(customer.id, template),
       params: { version_id: v1.id }, as: :json
  expect(response).to have_http_status(:ok)
  expect(template.reload.subject).to eq("V1")
end
```

Also: set default, delete non-current, reject delete current, cross-tenant 404.

- [ ] **Step 7: Run RSpec + Vitest**

```bash
bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb \
  spec/models/emails/template_spec.rb
npx vitest run --coverage
```

Expected: versions_controller.js at 100% lines/branches; request specs PASS.

- [ ] **Step 8: Skip commit**

---

### Task 7: I18n cleanup + release smoke

**Files:**
- Modify: locale files for any remaining orphaned Tags/Settings-tab keys
- Verify: routing spec, registration_spec if template_key referenced

- [ ] **Step 1: Grep leftovers**

```bash
rg -n "template_key|email_tag|Audience::Tag|tabs\.settings|TemplateVersion\.create_for|required_vars" app spec config
```

Fix any hits in scope.

- [ ] **Step 2: Targeted full email module slice**

```bash
bundle exec rspec spec/requests/admin/modules/emails/ \
  spec/models/emails/ \
  spec/services/emails/ \
  spec/services/feature_modules/email/ \
  spec/routing/admin/modules/emails/ \
  spec/jobs/emails/ --format progress
npx vitest run --coverage
```

Expected: PASS.

- [ ] **Step 3: Dev smoke (optional)**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

Hit templates index: Status row actions, Versions modal open, edit composer-only, audience tabs without Tags.

- [ ] **Step 4: Skip commit**

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Full Tags removal (tables + code) | Task 1 |
| Composer-only edit; no Settings/Versions tabs | Task 3 |
| Prune key/type/category/variables | Task 4 |
| Status on list, guarded | Task 5 |
| Gateway/Send `template_id` | Task 2 |
| Versionable + Pages modal parity | Task 4 + 6 |
| Auth/tenant/i18n/tests | Tasks 1–7 |
| Out of scope customer settings | Not scheduled |

No TBD/TODO placeholders remain. `pathPrefix` keeps maintenance Pages/Flowcharts URLs working with default value.
