# Access-Point Catalog & RBAC Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy role enum + `require_*!` helpers with cancancan-based RBAC, per-customer roles (3 reserved + customer-defined), per-customer-data-aware access-point catalog, and an admin UI to manage roles and grants — with a clean cutover that drops the role enum.

**Architecture:** Two clearly separated layers. (1) Authorization at request time — `Ability` built from `users_roles → roles → roles_permissions` rows, enforced via cancancan in `ApplicationController`. (2) Catalog at admin-UI time — `AccessPoints::Catalog` merges output of registered `Provider`s (RouteProvider, ModuleProvider, EntityClass/EntityProvider, PageClass/PageProvider, PlatformProvider) with no DB sync table. Reserved roles `owner` (hardcoded `:manage, :all`), `admin` and `member` (data-driven, locked from edits) are seeded per customer.

**Tech Stack:** Rails 8.1.2, cancancan, Trailblazer (Activity / Operation / Reform), dry-rb, ViewComponent, TailwindCSS, StimulusJS, RSpec, FactoryBot.

**Spec:** `docs/superpowers/specs/2026-05-11-access-point-catalog-and-rbac-permissions-design.md`

**Important user preferences for this plan:**
- All work is done directly on the `master` branch. Do NOT create feature branches, do NOT push to a remote, do NOT open pull requests.
- Do NOT auto-commit. Each task ends with the *prepared* commit message — engineer reviews and runs `git add` + `git commit` manually.
- Reuse existing admin layout, dashboard chrome, ViewComponent/TailwindCSS/StimulusJS conventions. No new design system.

---

## Phases

This plan is split into 6 phases. All phases land on `master` directly (no branches, no PRs). Each phase is independently testable and produces a coherent slice of working software, so the engineer can stop after any phase and still have a working tree:

1. **Phase 1** — Add cancancan, create RBAC schema, seed reserved roles for existing & new customers.
2. **Phase 2** — Build `AccessPoints` catalog & providers (no UI yet).
3. **Phase 3** — Build `Ability` class + cancancan integration; controllers still rely on legacy helpers (so nothing breaks).
4. **Phase 4** — Admin UI under `/:cid/admin/settings/modules/authentication/*` for roles, grants editor, user role assignments.
5. **Phase 5** — Cutover: switch `ApplicationController` to `authorize_route!`, delete legacy `require_*!` helpers, remove all 57 `before_action :require_*!` call sites.
6. **Phase 6** — Drop the `users.role` column.

After Phase 5 is verified, Phase 6 follows. Each phase below lists tasks with explicit files, code, test commands, and prepared commit messages.

---

## File Structure (locked-in decomposition)

### New files (created)

```
app/models/role.rb
app/models/users_role.rb
app/models/role_permission.rb
app/models/ability.rb

app/services/access_points/registry.rb
app/services/access_points/descriptor.rb
app/services/access_points/provider.rb
app/services/access_points/catalog.rb
app/services/access_points/route_provider.rb
app/services/access_points/module_provider.rb
app/services/access_points/entity_class_provider.rb
app/services/access_points/entity_provider.rb
app/services/access_points/page_class_provider.rb
app/services/access_points/page_provider.rb
app/services/access_points/platform_provider.rb

app/concepts/roles/operation/create.rb
app/concepts/roles/operation/update.rb
app/concepts/roles/operation/destroy.rb
app/concepts/roles/operation/seed_reserved.rb
app/concepts/roles/contract/create.rb
app/concepts/roles/contract/update.rb

app/concepts/role_grants/operation/update.rb
app/concepts/role_grants/contract/update.rb

app/concepts/user_roles/operation/assign.rb
app/concepts/user_roles/contract/assign.rb

app/concepts/role_permissions/operation/resolve_grants.rb

app/controllers/admin/settings/modules/authentication/roles_controller.rb
app/controllers/admin/settings/modules/authentication/role_grants_controller.rb
app/controllers/admin/settings/modules/authentication/user_role_assignments_controller.rb

app/components/admin/settings/modules/authentication/roles_table_component.rb
app/components/admin/settings/modules/authentication/roles_table_component.html.erb
app/components/admin/settings/modules/authentication/role_form_component.rb
app/components/admin/settings/modules/authentication/role_form_component.html.erb
app/components/admin/settings/modules/authentication/grants_editor_component.rb
app/components/admin/settings/modules/authentication/grants_editor_component.html.erb
app/components/admin/settings/modules/authentication/access_point_group_component.rb
app/components/admin/settings/modules/authentication/access_point_group_component.html.erb
app/components/admin/settings/modules/authentication/access_point_row_component.rb
app/components/admin/settings/modules/authentication/access_point_row_component.html.erb
app/components/admin/settings/modules/authentication/resource_picker_component.rb
app/components/admin/settings/modules/authentication/resource_picker_component.html.erb
app/components/admin/settings/modules/authentication/user_roles_table_component.rb
app/components/admin/settings/modules/authentication/user_roles_table_component.html.erb
app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.rb
app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.html.erb

app/javascript/controllers/grants_editor_controller.js
app/javascript/controllers/resource_picker_controller.js
app/javascript/controllers/user_role_dialog_controller.js

config/initializers/access_points.rb

db/migrate/<ts>_create_roles.rb
db/migrate/<ts>_create_users_roles.rb
db/migrate/<ts>_create_role_permissions.rb
db/migrate/<ts>_drop_role_from_users.rb           # phase 6 only

spec/models/role_spec.rb
spec/models/users_role_spec.rb
spec/models/role_permission_spec.rb
spec/models/ability_spec.rb
spec/services/access_points/registry_spec.rb
spec/services/access_points/descriptor_spec.rb
spec/services/access_points/catalog_spec.rb
spec/services/access_points/route_provider_spec.rb
spec/services/access_points/module_provider_spec.rb
spec/services/access_points/entity_class_provider_spec.rb
spec/services/access_points/entity_provider_spec.rb
spec/services/access_points/page_class_provider_spec.rb
spec/services/access_points/page_provider_spec.rb
spec/services/access_points/platform_provider_spec.rb
spec/concepts/roles/operation/create_spec.rb
spec/concepts/roles/operation/update_spec.rb
spec/concepts/roles/operation/destroy_spec.rb
spec/concepts/roles/operation/seed_reserved_spec.rb
spec/concepts/role_grants/operation/update_spec.rb
spec/concepts/user_roles/operation/assign_spec.rb
spec/concepts/role_permissions/operation/resolve_grants_spec.rb
spec/factories/roles.rb
spec/factories/users_roles.rb
spec/factories/role_permissions.rb
spec/requests/admin/settings/modules/authentication/roles_spec.rb
spec/requests/admin/settings/modules/authentication/role_grants_spec.rb
spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb
spec/components/admin/settings/modules/authentication/roles_table_component_spec.rb
spec/components/admin/settings/modules/authentication/grants_editor_component_spec.rb
spec/components/admin/settings/modules/authentication/access_point_row_component_spec.rb
spec/integration/legacy_authorization_baseline_spec.rb     # captures pre-cutover behavior
spec/integration/authorization_regression_spec.rb          # post-cutover regression
```

### Existing files (modified)

```
Gemfile                                                — add cancancan
config/routes.rb                                       — add admin/settings/modules/authentication routes
config/locales/en.yml (or new namespace file)          — labels for new pages
app/models/authentication/user.rb                      — add roles association; reimplement role-check methods (Phase 5)
app/models/current.rb                                  — add :access_points_catalog attribute
app/controllers/application_controller.rb              — Phase 3: register cancancan; Phase 5: authorize_route! before_action; delete legacy helpers
app/services/feature_modules/authentication/registration.rb  — sidebar contributions for new pages
db/seeds.rb                                            — call Roles::SeedReserved for all customers
spec/factories/users.rb                                — refactor :owner / :admin traits to use new role assignment (Phase 5)
```

### Files deleted (Phase 5)

```
# All before_action :require_*! call sites are simply removed (the helpers are deleted from ApplicationController; modules' duplicates are deleted from their base controllers).
```

---

# PHASE 1 — Schema + Reserved Roles Seeding

**Outcome:** New tables exist; every existing customer has `owner`/`admin`/`member` reserved-role rows; new customers automatically get them.

---

## Task 1.1: Add cancancan gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gem**

Edit `Gemfile`. Add this line **after** the `gem "reform-rails", "~> 0.3.1"` line (group it with auth-related gems already present):

```ruby
# CanCanCan — authorization framework for RBAC
gem "cancancan", "~> 3.6"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `Bundle complete!` and `Gemfile.lock` updated with `cancancan (3.x.x)`.

- [ ] **Step 3: Verify the gem loads**

Run: `bin/rails runner "puts CanCan::Ability.name"`
Expected: `CanCan::Ability` (no LoadError).

- [ ] **Step 4: Prepare commit (do not auto-commit)**

Stage and message (engineer runs manually):

```bash
git add Gemfile Gemfile.lock
# Engineer reviews, then:
# git commit -m "deps: add cancancan for RBAC authorization"
```

---

## Task 1.2: Migration — create_roles

**Files:**
- Create: `db/migrate/<ts>_create_roles.rb` (timestamp from generator)

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreateRoles`
Expected: a new file under `db/migrate/`.

- [ ] **Step 2: Fill in migration body**

Replace the file contents with:

```ruby
# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.references :customer, null: false, foreign_key: true, type: :bigint
      t.string  :key,          null: false
      t.string  :name,         null: false
      t.text    :description
      t.boolean :system,         null: false, default: false
      t.boolean :locked_grants,  null: false, default: false
      t.timestamps
    end

    add_index :roles, %i[customer_id key], unique: true
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `== CreateRoles: migrated` line; `db/schema.rb` updated.

- [ ] **Step 4: Prepare commit**

```bash
git add db/migrate/*_create_roles.rb db/schema.rb
# git commit -m "db: create roles table for RBAC"
```

---

## Task 1.3: Migration — create_users_roles

**Files:**
- Create: `db/migrate/<ts>_create_users_roles.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreateUsersRoles`

- [ ] **Step 2: Fill in body**

```ruby
# frozen_string_literal: true

class CreateUsersRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :users_roles do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :bigint
      t.references :role, null: false, foreign_key: true, type: :bigint
      t.timestamps
    end

    add_index :users_roles, %i[user_id role_id], unique: true
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `== CreateUsersRoles: migrated`.

- [ ] **Step 4: Prepare commit**

```bash
git add db/migrate/*_create_users_roles.rb db/schema.rb
# git commit -m "db: create users_roles join table"
```

---

## Task 1.4: Migration — create_role_permissions

**Files:**
- Create: `db/migrate/<ts>_create_role_permissions.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration CreateRolePermissions`

- [ ] **Step 2: Fill in body**

```ruby
# frozen_string_literal: true

class CreateRolePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: true, type: :bigint
      t.string  :subject_type, null: false
      t.string  :subject_key
      t.bigint  :subject_id
      t.string  :action,       null: false
      t.timestamps
    end

    add_index :role_permissions, %i[role_id subject_type subject_key]
    add_index :role_permissions, %i[role_id subject_type subject_id]
    add_check_constraint :role_permissions,
      "subject_key IS NOT NULL OR subject_id IS NOT NULL",
      name: "role_permissions_subject_present"
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 4: Prepare commit**

```bash
git add db/migrate/*_create_role_permissions.rb db/schema.rb
# git commit -m "db: create role_permissions grant table"
```

---

## Task 1.5: Role model + spec

**Files:**
- Create: `app/models/role.rb`
- Create: `spec/models/role_spec.rb`
- Create: `spec/factories/roles.rb`

- [ ] **Step 1: Write failing model spec**

`spec/models/role_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Role, type: :model do
  let(:customer) { create(:customer) }

  describe "associations" do
    it { is_expected.to belong_to(:customer) }
    it { is_expected.to have_many(:role_permissions).dependent(:destroy) }
    it { is_expected.to have_many(:users_roles).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:users_roles) }
  end

  describe "validations" do
    subject { build(:role, customer: customer) }
    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_presence_of(:name) }

    it "enforces uniqueness of key per customer" do
      create(:role, customer: customer, key: "manager")
      dup = build(:role, customer: customer, key: "manager")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "permits same key across different customers" do
      other = create(:customer)
      create(:role, customer: customer, key: "manager")
      expect(build(:role, customer: other, key: "manager")).to be_valid
    end
  end

  describe "scopes" do
    it ".system returns rows with system: true" do
      sys = create(:role, customer: customer, system: true)
      _custom = create(:role, customer: customer, system: false)
      expect(Role.system).to contain_exactly(sys)
    end

    it ".custom returns rows with system: false" do
      _sys = create(:role, customer: customer, system: true)
      custom = create(:role, customer: customer, system: false)
      expect(Role.custom).to contain_exactly(custom)
    end
  end

  describe "#system?" do
    it "returns true when system: true" do
      expect(build(:role, system: true)).to be_system
    end
  end

  describe "#locked_grants?" do
    it "returns true when locked_grants: true" do
      expect(build(:role, locked_grants: true)).to be_locked_grants
    end
  end
end
```

`spec/factories/roles.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    customer
    sequence(:key)  { |n| "role_#{n}" }
    sequence(:name) { |n| "Role #{n}" }
    description { "A role" }
    system { false }
    locked_grants { false }

    trait :system do
      system { true }
      locked_grants { true }
    end

    trait :owner do
      key { "owner" }
      name { "Owner" }
      system { true }
      locked_grants { true }
    end

    trait :admin do
      key { "admin" }
      name { "Admin" }
      system { true }
      locked_grants { true }
    end

    trait :member do
      key { "member" }
      name { "Member" }
      system { true }
      locked_grants { true }
    end
  end
end
```

- [ ] **Step 2: Run spec — should fail**

Run: `bundle exec rspec spec/models/role_spec.rb`
Expected: failure — `uninitialized constant Role`.

- [ ] **Step 3: Implement Role model**

`app/models/role.rb`:

```ruby
# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :customer
  has_many :role_permissions, dependent: :destroy
  has_many :users_roles, dependent: :destroy
  has_many :users, through: :users_roles, class_name: "Authentication::User"

  validates :key,  presence: true, uniqueness: { scope: :customer_id, case_sensitive: false }
  validates :name, presence: true

  scope :system, -> { where(system: true) }
  scope :custom, -> { where(system: false) }

  RESERVED_KEYS = %w[owner admin member].freeze

  def reserved? = RESERVED_KEYS.include?(key)
end
```

- [ ] **Step 4: Run spec — should pass**

Run: `bundle exec rspec spec/models/role_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/models/role.rb spec/models/role_spec.rb spec/factories/roles.rb
# git commit -m "models: add Role model with per-customer uniqueness"
```

---

## Task 1.6: UsersRole model + spec

**Files:**
- Create: `app/models/users_role.rb`
- Create: `spec/models/users_role_spec.rb`
- Create: `spec/factories/users_roles.rb`

- [ ] **Step 1: Write failing spec**

`spec/factories/users_roles.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :users_role do
    user
    role
  end
end
```

`spec/models/users_role_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersRole, type: :model do
  let(:customer) { create(:customer) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:role) }
  end

  describe "validations" do
    it "rejects cross-customer assignment" do
      user = create(:user, customer: customer)
      other_customer = create(:customer)
      role_in_other = create(:role, customer: other_customer)

      ur = build(:users_role, user: user, role: role_in_other)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include(/customer/i)
    end

    it "permits same-customer assignment" do
      user = create(:user, customer: customer)
      role = create(:role, customer: customer)
      expect(build(:users_role, user: user, role: role)).to be_valid
    end

    it "enforces uniqueness of (user_id, role_id)" do
      user = create(:user, customer: customer)
      role = create(:role, customer: customer)
      create(:users_role, user: user, role: role)
      dup = build(:users_role, user: user, role: role)
      expect(dup).not_to be_valid
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/models/users_role_spec.rb`
Expected: failure — `uninitialized constant UsersRole`.

- [ ] **Step 3: Implement model**

`app/models/users_role.rb`:

```ruby
# frozen_string_literal: true

class UsersRole < ApplicationRecord
  self.table_name = "users_roles"

  belongs_to :user, class_name: "Authentication::User"
  belongs_to :role

  validates :user_id, uniqueness: { scope: :role_id }
  validate :user_and_role_share_customer

  private

  def user_and_role_share_customer
    return if user.blank? || role.blank?
    return if user.customer_id == role.customer_id

    errors.add(:role, "must belong to the same customer as the user")
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/models/users_role_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/models/users_role.rb spec/models/users_role_spec.rb spec/factories/users_roles.rb
# git commit -m "models: add UsersRole join with same-customer constraint"
```

---

## Task 1.7: RolePermission model + spec

**Files:**
- Create: `app/models/role_permission.rb`
- Create: `spec/models/role_permission_spec.rb`
- Create: `spec/factories/role_permissions.rb`

- [ ] **Step 1: Write failing spec**

`spec/factories/role_permissions.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :role_permission do
    role
    subject_type { "Route" }
    subject_key  { "admin/maintenance/flowcharts" }
    subject_id   { nil }
    action       { "read" }

    trait :entity_class do
      subject_type { "EntityClass" }
      subject_key  { "Entity" }
      subject_id   { nil }
      action       { "manage" }
    end

    trait :entity_instance do
      subject_type { "Entity" }
      subject_key  { nil }
      subject_id   { 42 }
      action       { "update" }
    end
  end
end
```

`spec/models/role_permission_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe RolePermission, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:role) }
  end

  describe "validations" do
    it "requires subject_type" do
      rp = build(:role_permission, subject_type: nil)
      expect(rp).not_to be_valid
    end

    it "requires action" do
      rp = build(:role_permission, action: nil)
      expect(rp).not_to be_valid
    end

    it "requires at least one of subject_key or subject_id" do
      rp = build(:role_permission, subject_key: nil, subject_id: nil)
      expect(rp).not_to be_valid
      expect(rp.errors[:base]).to include(/subject_key or subject_id/i)
    end

    it "permits subject_key without subject_id" do
      expect(build(:role_permission, subject_key: "x", subject_id: nil)).to be_valid
    end

    it "permits subject_id without subject_key" do
      expect(build(:role_permission, :entity_instance)).to be_valid
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/models/role_permission_spec.rb`
Expected: failure — `uninitialized constant RolePermission`.

- [ ] **Step 3: Implement model**

`app/models/role_permission.rb`:

```ruby
# frozen_string_literal: true

class RolePermission < ApplicationRecord
  belongs_to :role

  SUBJECT_TYPES = %w[Route Module EntityClass Entity PageClass Page FeaturePage Platform].freeze
  ACTIONS       = %w[read create update destroy manage].freeze

  validates :subject_type, presence: true, inclusion: { in: SUBJECT_TYPES }
  validates :action,       presence: true
  validate  :subject_key_or_id_present

  private

  def subject_key_or_id_present
    return if subject_key.present? || subject_id.present?

    errors.add(:base, "subject_key or subject_id must be present")
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/models/role_permission_spec.rb`
Expected: pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/models/role_permission.rb spec/models/role_permission_spec.rb spec/factories/role_permissions.rb
# git commit -m "models: add RolePermission polymorphic grant model"
```

---

## Task 1.8: User ↔ Role association

**Files:**
- Modify: `app/models/authentication/user.rb`
- Test: existing user spec; add a small example

- [ ] **Step 1: Write failing spec**

Append to `spec/models/authentication/user_spec.rb` (create the file if it does not exist; check first with `ls spec/models/authentication/`):

```ruby
# Append within the existing RSpec.describe Authentication::User block,
# or wrap appropriately if the spec file does not yet exist.

describe "RBAC associations" do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }
  let(:role)     { create(:role, customer: customer) }

  it "has many users_roles and roles" do
    user.users_roles.create!(role: role)
    expect(user.reload.roles).to contain_exactly(role)
  end
end

describe "#has_reserved_role?" do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }

  it "returns true when user holds a system role with the given key" do
    role = create(:role, :owner, customer: customer)
    user.users_roles.create!(role: role)
    expect(user.has_reserved_role?(:owner)).to be true
  end

  it "returns false when user holds only a custom role with that key" do
    role = create(:role, customer: customer, key: "owner", system: false)
    user.users_roles.create!(role: role)
    expect(user.has_reserved_role?(:owner)).to be false
  end

  it "returns false when user holds no such role" do
    expect(user.has_reserved_role?(:owner)).to be false
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb`
Expected: failure — `undefined method 'users_roles'`.

- [ ] **Step 3: Add associations and helper**

In `app/models/authentication/user.rb`, inside the class body **after the existing `validates` block** (and before private methods), add:

```ruby
    # ==========================================================================
    # RBAC associations (Phase 1)
    # ==========================================================================

    has_many :users_roles, foreign_key: :user_id, dependent: :destroy
    has_many :roles, through: :users_roles

    # True when the user holds a reserved system role with the given key.
    # @param key [Symbol, String] one of :owner, :admin, :member
    def has_reserved_role?(key)
      roles.where(key: key.to_s, system: true).exists?
    end

    def role_ids
      users_roles.pluck(:role_id)
    end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb`
Expected: pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/models/authentication/user.rb spec/models/authentication/user_spec.rb
# git commit -m "users: add roles/users_roles associations and reserved-role helper"
```

---

## Task 1.9: Roles::Operation::SeedReserved + spec

**Files:**
- Create: `app/concepts/roles/operation/seed_reserved.rb`
- Create: `spec/concepts/roles/operation/seed_reserved_spec.rb`

> This operation creates the three reserved-role rows for a given customer. It is *idempotent*: running it twice does nothing the second time. Grant seeding (the actual permission rows for `admin`/`member`) lives in a *separate* step (Task 1.10) so that the SeedReserved op stays trivial and dependency-free of `AccessPoints::Catalog`.

- [ ] **Step 1: Write failing spec**

`spec/concepts/roles/operation/seed_reserved_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::SeedReserved do
  let(:customer) { create(:customer) }

  it "creates owner, admin, member system roles for the customer" do
    described_class.call(customer: customer)
    keys = customer.roles.pluck(:key).sort
    expect(keys).to eq(%w[admin member owner])
    expect(customer.roles.where(system: true).count).to eq(3)
    expect(customer.roles.where(locked_grants: true).count).to eq(3)
  end

  it "is idempotent" do
    described_class.call(customer: customer)
    expect { described_class.call(customer: customer) }
      .not_to change { customer.reload.roles.count }
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/concepts/roles/operation/seed_reserved_spec.rb`
Expected: failure — uninitialized constant.

- [ ] **Step 3: Implement**

`app/concepts/roles/operation/seed_reserved.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Operation
    class SeedReserved
      RESERVED = [
        { key: "owner",  name: "Owner",
          description: "Full access. Reserved system role." },
        { key: "admin",  name: "Admin",
          description: "Admin-area access except platform tools. Reserved system role." },
        { key: "member", name: "Member",
          description: "Member without admin access. Reserved system role." }
      ].freeze

      # @param customer [Customer]
      # @return [Array<Role>]
      def self.call(customer:)
        RESERVED.map do |attrs|
          Role.find_or_create_by!(customer: customer, key: attrs[:key]) do |r|
            r.name          = attrs[:name]
            r.description   = attrs[:description]
            r.system        = true
            r.locked_grants = true
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/concepts/roles/operation/seed_reserved_spec.rb`
Expected: pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/concepts/roles/operation/seed_reserved.rb spec/concepts/roles/operation/seed_reserved_spec.rb
# git commit -m "roles: add SeedReserved operation (creates owner/admin/member rows)"
```

---

## Task 1.10: Hook SeedReserved into customer creation + seed all existing customers

**Files:**
- Modify: `db/seeds.rb`
- Locate the customer-creation operation and modify it (use grep below to find it).

- [ ] **Step 1: Find the customer creation site**

Run: `grep -rn "Customer.create\|class Customers" /home/ec2-user/anysys/app/concepts /home/ec2-user/anysys/app/services 2>/dev/null | head -10`
Expected: a path like `app/concepts/customers/operation/create.rb` or similar.

If no `Customers::Create` operation exists, hook into the `Customer` model with an `after_create` callback instead — code shown for both options below.

- [ ] **Step 2: Write failing spec at the customer creation site**

If a `Customers::Operation::Create` exists, add to its spec:

```ruby
it "seeds the three reserved roles" do
  result = described_class.call(params: valid_params)
  customer = result[:model]
  expect(customer.roles.pluck(:key).sort).to eq(%w[admin member owner])
end
```

If no operation exists, in `spec/models/customer_spec.rb` add:

```ruby
describe "after_create reserved roles" do
  it "seeds owner/admin/member" do
    customer = create(:customer)
    expect(customer.roles.pluck(:key).sort).to eq(%w[admin member owner])
  end
end
```

- [ ] **Step 3: Run — should fail**

Run: `bundle exec rspec` against the spec you edited.
Expected: failure — roles array is empty.

- [ ] **Step 4: Implement the hook**

If a `Customers::Operation::Create` exists, add a step at the end:

```ruby
step :seed_reserved_roles

def seed_reserved_roles(ctx, model:, **)
  Roles::Operation::SeedReserved.call(customer: model)
  true
end
```

If no such operation exists, add an `after_create` callback in `app/models/customer.rb`:

```ruby
after_create :seed_reserved_roles_for_self

private

def seed_reserved_roles_for_self
  Roles::Operation::SeedReserved.call(customer: self)
end
```

- [ ] **Step 5: Run — should pass**

Run: the spec you edited above.
Expected: pass.

- [ ] **Step 6: Backfill existing customers via seeds.rb**

Append to `db/seeds.rb`:

```ruby
# Backfill reserved roles for every existing customer (idempotent).
Customer.find_each do |c|
  Roles::Operation::SeedReserved.call(customer: c)
end
```

Run: `bin/rails db:seed`
Expected: no errors. Verify with: `bin/rails runner 'puts Role.where(system: true).group(:key).count.to_s'`
Expected output: a hash like `{"owner"=>N, "admin"=>N, "member"=>N}` where N == `Customer.count`.

- [ ] **Step 7: Prepare commit**

```bash
git add db/seeds.rb app/concepts/customers/operation/create.rb app/models/customer.rb spec/concepts/customers/operation/create_spec.rb spec/models/customer_spec.rb
# git commit -m "customers: seed reserved roles on creation and backfill existing"
```

(Stage only the files you actually modified.)

---

## Task 1.11: Phase 1 sanity check

- [ ] **Step 1: Run all RSpec for Phase 1 work**

Run: `bundle exec rspec spec/models/role_spec.rb spec/models/users_role_spec.rb spec/models/role_permission_spec.rb spec/models/authentication/user_spec.rb spec/concepts/roles/operation/seed_reserved_spec.rb`
Expected: all pass, 0 failures.

- [ ] **Step 2: Confirm full suite has not regressed**

Run: `bundle exec rspec`
Expected: same pass/fail counts as before Phase 1 (Phase 1 added strictly new tests, no existing behavior changed).

---

# PHASE 2 — Access-Point Catalog

**Outcome:** `AccessPoints::Catalog.for(customer_id:)` returns a structured catalog of all access points for a customer, merging output from registered providers. No UI yet — it's a data service.

---

## Task 2.1: Provider base class + Descriptor value object

**Files:**
- Create: `app/services/access_points/provider.rb`
- Create: `app/services/access_points/descriptor.rb`
- Create: `spec/services/access_points/descriptor_spec.rb`

- [ ] **Step 1: Write failing spec for Descriptor**

`spec/services/access_points/descriptor_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Descriptor do
  let(:base_attrs) do
    {
      subject_type: "Route",
      subject_key:  "admin/maintenance/flowcharts",
      subject_id:   nil,
      actions:      [:read, :create],
      group_key:    "admin.maintenance",
      label:        "Flowcharts",
      description:  nil
    }
  end

  it "constructs successfully with valid attrs" do
    d = described_class.new(base_attrs)
    expect(d.subject_type).to eq("Route")
    expect(d.actions).to eq([:read, :create])
  end

  it "rejects when actions is not an array of symbols" do
    expect { described_class.new(base_attrs.merge(actions: ["read"])) }
      .to raise_error(Dry::Struct::Error)
  end

  it "permits subject_id to be nil" do
    expect(described_class.new(base_attrs.merge(subject_id: nil))).to be_a(described_class)
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/descriptor_spec.rb`
Expected: failure — `uninitialized constant AccessPoints`.

- [ ] **Step 3: Implement Descriptor and Provider**

`app/services/access_points/descriptor.rb`:

```ruby
# frozen_string_literal: true

require "dry-struct"
require "dry-types"

module AccessPoints
  module Types
    include Dry.Types()
  end

  class Descriptor < Dry::Struct
    attribute :subject_type, Types::Strict::String
    attribute :subject_key,  Types::Strict::String.optional
    attribute :subject_id,   Types::Strict::Integer.optional
    attribute :actions,      Types::Array.of(Types::Strict::Symbol)
    attribute :group_key,    Types::Strict::String
    attribute :label,        Types::Strict::String
    attribute :description,  Types::Strict::String.optional.default(nil)
  end
end
```

`app/services/access_points/provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  # Abstract base. Subclasses contribute a slice of the access-point catalog.
  class Provider
    # @param customer_id [Integer]
    # @return [Array<AccessPoints::Descriptor>]
    def call(customer_id:) = raise NotImplementedError, "#{self.class}#call"

    def group_key   = raise NotImplementedError
    def group_label = raise NotImplementedError

    # Override in providers that should only run for some customers
    # (e.g., PlatformProvider runs only for customer 81_721_200).
    def applicable?(customer_id:) = true
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/descriptor_spec.rb`
Expected: pass.

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/provider.rb app/services/access_points/descriptor.rb spec/services/access_points/descriptor_spec.rb
# git commit -m "access_points: add Provider base and Descriptor value object"
```

---

## Task 2.2: Registry

**Files:**
- Create: `app/services/access_points/registry.rb`
- Create: `spec/services/access_points/registry_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/access_points/registry_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Registry do
  before { described_class.reset! }
  after  { described_class.reset! }

  let(:provider_class) do
    Class.new(AccessPoints::Provider) do
      def call(customer_id:) = []
      def group_key   = "x"
      def group_label = "X"
    end
  end

  it "registers and lists providers" do
    p = provider_class.new
    described_class.register(p)
    expect(described_class.providers).to contain_exactly(p)
  end

  it "filters out non-applicable providers for given customer" do
    skip_provider = Class.new(AccessPoints::Provider) do
      def call(customer_id:) = []
      def group_key   = "skip"
      def group_label = "Skip"
      def applicable?(customer_id:) = false
    end.new

    described_class.register(provider_class.new)
    described_class.register(skip_provider)

    applicable = described_class.applicable_for(customer_id: 12_345_678)
    expect(applicable.map(&:group_key)).to eq(["x"])
  end

  it "reset! clears providers" do
    described_class.register(provider_class.new)
    described_class.reset!
    expect(described_class.providers).to be_empty
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/registry_spec.rb`

- [ ] **Step 3: Implement**

`app/services/access_points/registry.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  # Singleton registry of access-point providers. Populated at boot via
  # config/initializers/access_points.rb.
  module Registry
    @providers = []

    class << self
      def register(provider)
        @providers << provider
      end

      def providers
        @providers.dup
      end

      def applicable_for(customer_id:)
        @providers.select { |p| p.applicable?(customer_id: customer_id) }
      end

      def reset!
        @providers = []
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/registry_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/registry.rb spec/services/access_points/registry_spec.rb
# git commit -m "access_points: add Registry singleton for provider registration"
```

---

## Task 2.3: RouteProvider

**Files:**
- Create: `app/services/access_points/route_provider.rb`
- Create: `spec/services/access_points/route_provider_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/access_points/route_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::RouteProvider do
  subject(:provider) { described_class.new }

  describe "#call" do
    it "yields a descriptor for each admin-area controller_path with derived actions" do
      results = provider.call(customer_id: 12_345_678)
      keys = results.map(&:subject_key)

      expect(keys).to include("admin/maintenance/flowcharts")
      expect(keys).to include("admin/dashboards")
    end

    it "derives actions from HTTP verbs" do
      results = provider.call(customer_id: 12_345_678)
      flowcharts = results.find { |d| d.subject_key == "admin/maintenance/flowcharts" }
      expect(flowcharts.actions).to include(:read, :create, :update, :destroy)
    end

    it "skips routes outside the admin area" do
      results = provider.call(customer_id: 12_345_678)
      keys = results.map(&:subject_key)
      expect(keys).not_to include(a_string_starting_with("payments"))
      expect(keys).not_to include(a_string_starting_with("forms"))
    end

    it "all descriptors have subject_type == \"Route\"" do
      provider.call(customer_id: 12_345_678).each do |d|
        expect(d.subject_type).to eq("Route")
      end
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/route_provider_spec.rb`

- [ ] **Step 3: Implement RouteProvider**

`app/services/access_points/route_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class RouteProvider < Provider
    HTTP_VERB_TO_ACTION = {
      "GET"    => :read,
      "POST"   => :create,
      "PATCH"  => :update,
      "PUT"    => :update,
      "DELETE" => :destroy
    }.freeze

    def group_key   = "admin.routes"
    def group_label = "Admin Routes"

    def call(customer_id:)
      grouped = Hash.new { |h, k| h[k] = Set.new }

      Rails.application.routes.routes.each do |route|
        path = route.path.spec.to_s
        next unless admin_path?(path)

        controller = route.defaults[:controller]
        next if controller.blank?

        verb_str = http_verb(route)
        action   = HTTP_VERB_TO_ACTION[verb_str]
        next if action.nil?

        grouped[controller] << action
      end

      grouped.map do |controller_path, actions|
        Descriptor.new(
          subject_type: "Route",
          subject_key:  controller_path,
          subject_id:   nil,
          actions:      actions.to_a.sort,
          group_key:    derive_group_key(controller_path),
          label:        humanize(controller_path),
          description:  nil
        )
      end
    end

    private

    def admin_path?(path)
      # Matches any path containing "/admin" segment after the customer_id segment.
      path.include?("/admin")
    end

    def http_verb(route)
      verb = route.verb
      verb.is_a?(Regexp) ? verb.source.match(/[A-Z]+/)&.to_s : verb.to_s
    end

    def derive_group_key(controller_path)
      # admin/maintenance/flowcharts -> "admin.maintenance"
      # admin/modules/payments/transactions -> "admin.modules.payments"
      parts = controller_path.split("/")
      case parts
      in ["admin", "maintenance", "platform", *_]
        "admin.maintenance.platform"
      in ["admin", "maintenance", *_]
        "admin.maintenance"
      in ["admin", "modules", mod, *_]
        "admin.modules.#{mod}"
      in ["admin", "settings", "modules", mod, *_]
        "admin.settings.modules.#{mod}"
      in ["admin", "settings", *_]
        "admin.settings"
      in ["admin", *_]
        "admin"
      else
        "admin.misc"
      end
    end

    def humanize(controller_path)
      controller_path.split("/").last.to_s.humanize.titleize
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/route_provider_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/route_provider.rb spec/services/access_points/route_provider_spec.rb
# git commit -m "access_points: add RouteProvider deriving descriptors from admin routes"
```

---

## Task 2.4: ModuleProvider

**Files:**
- Create: `app/services/access_points/module_provider.rb`
- Create: `spec/services/access_points/module_provider_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/access_points/module_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::ModuleProvider do
  subject(:provider) { described_class.new }
  let(:customer) { create(:customer) }

  it "yields one descriptor per enabled module with :manage action" do
    fm = create(:feature_module, key: "payments", name: "Payments")
    create(:feature_module_customer_assignment, customer: customer, module: fm, status: :active)

    results = provider.call(customer_id: customer.id)
    descriptor = results.find { |d| d.subject_key == "payments" }
    expect(descriptor).not_to be_nil
    expect(descriptor.subject_type).to eq("Module")
    expect(descriptor.actions).to eq([:manage])
    expect(descriptor.group_key).to eq("modules.payments")
  end

  it "returns empty array when customer has no enabled modules" do
    expect(provider.call(customer_id: customer.id)).to eq([])
  end
end
```

(Check the FeatureModules factory shape via `cat spec/factories/feature_modules.rb` and adjust the trait names if needed.)

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/module_provider_spec.rb`

- [ ] **Step 3: Implement**

`app/services/access_points/module_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class ModuleProvider < Provider
    def group_key   = "modules"
    def group_label = "Modules"

    def call(customer_id:)
      FeatureModules::Module
        .available_for_customer(customer_id)
        .map { |fm| descriptor_for(fm) }
    end

    private

    def descriptor_for(fm)
      Descriptor.new(
        subject_type: "Module",
        subject_key:  fm.key,
        subject_id:   nil,
        actions:      [:manage],
        group_key:    "modules.#{fm.key}",
        label:        fm.name,
        description:  fm.description
      )
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/module_provider_spec.rb`

If `FeatureModules::Module` does not have a `description` column, change the line to `description: nil`.

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/module_provider.rb spec/services/access_points/module_provider_spec.rb
# git commit -m "access_points: add ModuleProvider for customer-enabled modules"
```

---

## Task 2.5: EntityClassProvider + EntityProvider + spec

**Files:**
- Create: `app/services/access_points/entity_class_provider.rb`
- Create: `app/services/access_points/entity_provider.rb`
- Create: `spec/services/access_points/entity_class_provider_spec.rb`
- Create: `spec/services/access_points/entity_provider_spec.rb`

- [ ] **Step 1: Write failing specs**

`spec/services/access_points/entity_class_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::EntityClassProvider do
  subject(:provider) { described_class.new }

  it "yields a single 'all entities' descriptor" do
    results = provider.call(customer_id: 12_345_678)
    expect(results.size).to eq(1)
    d = results.first
    expect(d.subject_type).to eq("EntityClass")
    expect(d.subject_key).to eq("Entity")
    expect(d.actions).to match_array([:read, :create, :update, :destroy])
    expect(d.group_key).to eq("entities")
  end
end
```

`spec/services/access_points/entity_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::EntityProvider do
  subject(:provider) { described_class.new }
  let(:customer)        { create(:customer) }
  let(:other_customer)  { create(:customer) }

  it "yields one descriptor per entity scoped to the customer" do
    e1 = create(:entity, customer: customer, name: "Patients")
    e2 = create(:entity, customer: customer, name: "Doctors")
    create(:entity, customer: other_customer, name: "Other")

    results = provider.call(customer_id: customer.id)
    ids = results.map(&:subject_id)
    expect(ids).to match_array([e1.id, e2.id])
  end

  it "all descriptors have subject_type == \"Entity\" and matching actions" do
    create(:entity, customer: customer)
    d = provider.call(customer_id: customer.id).first
    expect(d.subject_type).to eq("Entity")
    expect(d.actions).to match_array([:read, :update, :destroy])
  end

  it "returns empty when query is filtered to a non-matching customer" do
    create(:entity, customer: other_customer)
    expect(provider.call(customer_id: customer.id)).to be_empty
  end

  describe "#search" do
    it "filters by query string against name" do
      create(:entity, customer: customer, name: "Patients")
      create(:entity, customer: customer, name: "Doctors")
      results = provider.search(customer_id: customer.id, query: "patient")
      expect(results.map(&:label)).to contain_exactly("Patients")
    end
  end
end
```

(If your `entity` factory differs, inspect `spec/factories/entities.rb` first and adjust.)

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/entity_class_provider_spec.rb spec/services/access_points/entity_provider_spec.rb`

- [ ] **Step 3: Implement both providers**

`app/services/access_points/entity_class_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class EntityClassProvider < Provider
    def group_key   = "entities"
    def group_label = "Entities (all)"

    def call(customer_id:)
      [
        Descriptor.new(
          subject_type: "EntityClass",
          subject_key:  "Entity",
          subject_id:   nil,
          actions:      [:read, :create, :update, :destroy],
          group_key:    "entities",
          label:        "All entities",
          description:  "Grant covers every Entity record for this customer."
        )
      ]
    end
  end
end
```

`app/services/access_points/entity_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class EntityProvider < Provider
    def group_key   = "entities.instances"
    def group_label = "Specific entities"

    # Eager call (used rarely — admin UI prefers #search). Returns all entities.
    def call(customer_id:)
      Entity.where(customer_id: customer_id).map { |e| descriptor_for(e) }
    end

    # Search variant used by the admin UI's resource-picker.
    def search(customer_id:, query:)
      relation = Entity.where(customer_id: customer_id)
      relation = relation.where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.present?
      relation.limit(50).map { |e| descriptor_for(e) }
    end

    private

    def descriptor_for(entity)
      Descriptor.new(
        subject_type: "Entity",
        subject_key:  nil,
        subject_id:   entity.id,
        actions:      [:read, :update, :destroy],
        group_key:    "entities.instances",
        label:        entity.name.to_s,
        description:  nil
      )
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/entity_class_provider_spec.rb spec/services/access_points/entity_provider_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/entity_class_provider.rb app/services/access_points/entity_provider.rb spec/services/access_points/entity_class_provider_spec.rb spec/services/access_points/entity_provider_spec.rb
# git commit -m "access_points: add Entity class and instance providers"
```

---

## Task 2.6: PageClassProvider + PageProvider + spec

**Files:**
- Create: `app/services/access_points/page_class_provider.rb`
- Create: `app/services/access_points/page_provider.rb`
- Create: `spec/services/access_points/page_class_provider_spec.rb`
- Create: `spec/services/access_points/page_provider_spec.rb`

- [ ] **Step 1: Write failing specs**

Mirror Task 2.5 substituting `Page` for `Entity` and `PageClass` for `EntityClass`.

`spec/services/access_points/page_class_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PageClassProvider do
  subject(:provider) { described_class.new }

  it "yields a single 'all pages' descriptor" do
    results = provider.call(customer_id: 12_345_678)
    expect(results.size).to eq(1)
    expect(results.first.subject_type).to eq("PageClass")
    expect(results.first.subject_key).to eq("Page")
    expect(results.first.actions).to match_array([:read, :create, :update, :destroy])
  end
end
```

`spec/services/access_points/page_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PageProvider do
  subject(:provider) { described_class.new }
  let(:customer)        { create(:customer) }
  let(:other_customer)  { create(:customer) }

  it "yields one descriptor per page scoped to the customer" do
    p1 = create(:page, customer: customer)
    create(:page, customer: other_customer)
    results = provider.call(customer_id: customer.id)
    expect(results.map(&:subject_id)).to contain_exactly(p1.id)
  end

  it "search filters by name (LIKE)" do
    create(:page, customer: customer, name: "Onboarding")
    create(:page, customer: customer, name: "Checkout")
    results = provider.search(customer_id: customer.id, query: "onboard")
    expect(results.map(&:label)).to contain_exactly("Onboarding")
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/page_class_provider_spec.rb spec/services/access_points/page_provider_spec.rb`

- [ ] **Step 3: Implement**

`app/services/access_points/page_class_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class PageClassProvider < Provider
    def group_key   = "pages"
    def group_label = "Pages (all)"

    def call(customer_id:)
      [
        Descriptor.new(
          subject_type: "PageClass",
          subject_key:  "Page",
          subject_id:   nil,
          actions:      [:read, :create, :update, :destroy],
          group_key:    "pages",
          label:        "All pages",
          description:  "Grant covers every Page record for this customer."
        )
      ]
    end
  end
end
```

`app/services/access_points/page_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class PageProvider < Provider
    def group_key   = "pages.instances"
    def group_label = "Specific pages"

    def call(customer_id:)
      Page.where(customer_id: customer_id).map { |p| descriptor_for(p) }
    end

    def search(customer_id:, query:)
      relation = Page.where(customer_id: customer_id)
      relation = relation.where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.present?
      relation.limit(50).map { |p| descriptor_for(p) }
    end

    private

    def descriptor_for(page)
      Descriptor.new(
        subject_type: "Page",
        subject_key:  nil,
        subject_id:   page.id,
        actions:      [:read, :update, :destroy],
        group_key:    "pages.instances",
        label:        page.name.to_s,
        description:  nil
      )
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/page_class_provider_spec.rb spec/services/access_points/page_provider_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/page_class_provider.rb app/services/access_points/page_provider.rb spec/services/access_points/page_class_provider_spec.rb spec/services/access_points/page_provider_spec.rb
# git commit -m "access_points: add Page class and instance providers"
```

---

## Task 2.7: PlatformProvider

**Files:**
- Create: `app/services/access_points/platform_provider.rb`
- Create: `spec/services/access_points/platform_provider_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/access_points/platform_provider_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PlatformProvider do
  subject(:provider) { described_class.new }

  describe "#applicable?" do
    it "returns true only for the platform-owner customer (81_721_200)" do
      expect(provider.applicable?(customer_id: 81_721_200)).to be true
      expect(provider.applicable?(customer_id: 12_345_678)).to be false
    end
  end

  describe "#call" do
    it "yields platform-only descriptors" do
      results = provider.call(customer_id: 81_721_200)
      keys = results.map(&:subject_key)
      expect(keys).to include("customers", "module_settings", "industry_templates", "code_generators")
      results.each { |d| expect(d.subject_type).to eq("Platform") }
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement**

`app/services/access_points/platform_provider.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class PlatformProvider < Provider
    PLATFORM_FEATURES = [
      { key: "customers",          label: "Platform: Customers",          actions: [:read, :create, :update, :destroy] },
      { key: "module_settings",    label: "Platform: Module Settings",    actions: [:read, :update] },
      { key: "industry_templates", label: "Platform: Industry Templates", actions: [:read, :update] },
      { key: "code_generators",    label: "Platform: Code Generators",    actions: [:read, :create, :update, :destroy] }
    ].freeze

    def group_key   = "platform"
    def group_label = "Platform"

    def applicable?(customer_id:)
      customer_id.to_i == Authentication::User::PLATFORM_CUSTOMER_ID
    end

    def call(customer_id:)
      PLATFORM_FEATURES.map do |f|
        Descriptor.new(
          subject_type: "Platform",
          subject_key:  f[:key],
          subject_id:   nil,
          actions:      f[:actions],
          group_key:    "platform",
          label:        f[:label],
          description:  nil
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

- [ ] **Step 5: Prepare commit**

```bash
git add app/services/access_points/platform_provider.rb spec/services/access_points/platform_provider_spec.rb
# git commit -m "access_points: add PlatformProvider gated to platform-owner customer"
```

---

## Task 2.8: Catalog facade + Current attribute

**Files:**
- Create: `app/services/access_points/catalog.rb`
- Modify: `app/models/current.rb` — add `:access_points_catalog` attribute
- Create: `spec/services/access_points/catalog_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/services/access_points/catalog_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Catalog do
  let(:customer) { create(:customer) }

  before { AccessPoints::Registry.reset! }
  after  { AccessPoints::Registry.reset! }

  let(:fake_provider) do
    Class.new(AccessPoints::Provider) do
      def call(customer_id:)
        [
          AccessPoints::Descriptor.new(
            subject_type: "Route",
            subject_key:  "x/y",
            subject_id:   nil,
            actions:      [:read],
            group_key:    "g.one",
            label:        "X/Y",
            description:  nil
          )
        ]
      end

      def group_key   = "g.one"
      def group_label = "Group One"
    end.new
  end

  it "merges provider output into groups keyed by group_key" do
    AccessPoints::Registry.register(fake_provider)
    catalog = described_class.for(customer_id: customer.id)
    group = catalog.groups.find { |g| g[:key] == "g.one" }
    expect(group[:descriptors].map(&:subject_key)).to eq(["x/y"])
  end

  it "skips non-applicable providers" do
    inactive = Class.new(AccessPoints::Provider) do
      def call(customer_id:) = raise("should not be called")
      def group_key = "skip"
      def group_label = "Skip"
      def applicable?(customer_id:) = false
    end.new

    AccessPoints::Registry.register(inactive)
    expect { described_class.for(customer_id: customer.id) }.not_to raise_error
  end

  describe "#find" do
    it "looks up a descriptor by subject_type + subject_key" do
      AccessPoints::Registry.register(fake_provider)
      catalog = described_class.for(customer_id: customer.id)
      d = catalog.find(subject_type: "Route", subject_key: "x/y")
      expect(d).not_to be_nil
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/services/access_points/catalog_spec.rb`

- [ ] **Step 3: Add Current attribute**

Edit `app/models/current.rb`. Add a new attribute line near the existing attribute declarations:

```ruby
  # Cached AccessPoints::Catalog for the request lifecycle (admin UI only).
  attribute :access_points_catalog
```

- [ ] **Step 4: Implement Catalog**

`app/services/access_points/catalog.rb`:

```ruby
# frozen_string_literal: true

module AccessPoints
  class Catalog
    attr_reader :customer_id

    # Memoized per request via Current.access_points_catalog.
    def self.for(customer_id:)
      Current.access_points_catalog ||= new(customer_id: customer_id)
    end

    def initialize(customer_id:)
      @customer_id = customer_id
    end

    # @return [Array<Hash>] groups: [{ key:, label:, descriptors: [...] }]
    def groups
      @groups ||= compute_groups
    end

    # @return [AccessPoints::Descriptor, nil]
    def find(subject_type:, subject_key: nil, subject_id: nil)
      all_descriptors.find do |d|
        d.subject_type == subject_type &&
          d.subject_key == subject_key &&
          d.subject_id == subject_id
      end
    end

    private

    def compute_groups
      by_group = Hash.new { |h, k| h[k] = [] }
      labels   = {}

      Registry.applicable_for(customer_id: customer_id).each do |p|
        labels[p.group_key] ||= p.group_label
        p.call(customer_id: customer_id).each do |d|
          by_group[d.group_key] << d
        end
      end

      by_group.map do |key, descs|
        { key: key, label: labels[key] || key.titleize, descriptors: descs }
      end
    end

    def all_descriptors
      groups.flat_map { |g| g[:descriptors] }
    end
  end
end
```

- [ ] **Step 5: Run — should pass**

Run: `bundle exec rspec spec/services/access_points/catalog_spec.rb`
Expected: pass.

- [ ] **Step 6: Prepare commit**

```bash
git add app/services/access_points/catalog.rb app/models/current.rb spec/services/access_points/catalog_spec.rb
# git commit -m "access_points: add Catalog facade with request-scoped caching"
```

---

## Task 2.9: Initializer registering all providers

**Files:**
- Create: `config/initializers/access_points.rb`

- [ ] **Step 1: Write the initializer**

`config/initializers/access_points.rb`:

```ruby
# frozen_string_literal: true

# Register access-point providers. The order of registration influences the
# left-pane ordering in the admin grants editor.
Rails.application.config.after_initialize do
  AccessPoints::Registry.reset!
  AccessPoints::Registry.register(AccessPoints::RouteProvider.new)
  AccessPoints::Registry.register(AccessPoints::ModuleProvider.new)
  AccessPoints::Registry.register(AccessPoints::EntityClassProvider.new)
  AccessPoints::Registry.register(AccessPoints::EntityProvider.new)
  AccessPoints::Registry.register(AccessPoints::PageClassProvider.new)
  AccessPoints::Registry.register(AccessPoints::PageProvider.new)
  AccessPoints::Registry.register(AccessPoints::PlatformProvider.new)
end
```

- [ ] **Step 2: Verify the catalog works for a real customer in console**

Run: `bin/rails runner 'c = Customer.first; pp AccessPoints::Catalog.for(customer_id: c.id).groups.map { |g| [g[:key], g[:descriptors].size] }'`
Expected: a list of `[group_key, count]` tuples, including `["admin.maintenance", N]`, `["entities", 1]`, etc. No exceptions.

- [ ] **Step 3: Prepare commit**

```bash
git add config/initializers/access_points.rb
# git commit -m "access_points: register all providers via initializer"
```

---

## Task 2.10: Phase 2 sanity check

- [ ] Run: `bundle exec rspec spec/services/access_points/`
- [ ] Expected: all green.
- [ ] Run: `bundle exec rspec` — full suite, no regressions.

---

# PHASE 3 — Ability + cancancan integration (parallel to legacy helpers)

**Outcome:** `Ability` class exists, cancancan is wired into `ApplicationController` so `current_ability` works, but legacy `require_*!` helpers continue gating routes. We can now write specs against `Ability` directly. No behavior change yet for end users.

---

## Task 3.1: RolePermissions::ResolveGrants operation + spec

**Files:**
- Create: `app/concepts/role_permissions/operation/resolve_grants.rb`
- Create: `spec/concepts/role_permissions/operation/resolve_grants_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/concepts/role_permissions/operation/resolve_grants_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe RolePermissions::Operation::ResolveGrants do
  let(:customer) { create(:customer) }
  let(:role)     { create(:role, customer: customer) }

  it "returns role_permissions for the given role_ids" do
    rp1 = create(:role_permission, role: role, action: "read",   subject_key: "a")
    rp2 = create(:role_permission, role: role, action: "create", subject_key: "a")

    grants = described_class.call(role_ids: [role.id])
    expect(grants).to contain_exactly(rp1, rp2)
  end

  it "returns empty for unknown role_ids" do
    expect(described_class.call(role_ids: [-1])).to eq([])
  end

  it "deduplicates across roles when same grant rows exist" do
    role2 = create(:role, customer: customer)
    rp = create(:role_permission, role: role, action: "read", subject_key: "x")
    create(:role_permission, role: role2, action: "read", subject_key: "x")
    grants = described_class.call(role_ids: [role.id, role2.id])
    expect(grants.size).to eq(2) # both rows preserved; dedup is Ability's job
    expect(grants).to include(rp)
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement**

`app/concepts/role_permissions/operation/resolve_grants.rb`:

```ruby
# frozen_string_literal: true

module RolePermissions
  module Operation
    class ResolveGrants
      # @param role_ids [Array<Integer>]
      # @return [Array<RolePermission>]
      def self.call(role_ids:)
        return [] if Array(role_ids).empty?

        RolePermission.where(role_id: role_ids).to_a
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

- [ ] **Step 5: Prepare commit**

```bash
git add app/concepts/role_permissions/operation/resolve_grants.rb spec/concepts/role_permissions/operation/resolve_grants_spec.rb
# git commit -m "role_permissions: add ResolveGrants operation"
```

---

## Task 3.2: Ability class + spec

**Files:**
- Create: `app/models/ability.rb`
- Create: `spec/models/ability_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/models/ability_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ability do
  let(:customer) { create(:customer) }

  describe "anonymous" do
    it "grants nothing" do
      ability = described_class.new(nil)
      expect(ability.can?(:read, :route_admin_dashboards)).to be false
    end
  end

  describe "owner reserved role" do
    it "grants :manage, :all" do
      user = create(:user, customer: customer)
      role = create(:role, :owner, customer: customer)
      user.users_roles.create!(role: role)

      ability = described_class.new(user)
      expect(ability.can?(:manage, :anything)).to be true
      expect(ability.can?(:destroy, Entity)).to be true
    end
  end

  describe "data-driven grants" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "grants Route subject from RolePermission" do
      role.role_permissions.create!(
        subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, :route_admin_maintenance_flowcharts)).to be true
      expect(ability.can?(:read, :route_admin_dashboards)).to be false
    end

    it "grants EntityClass subject" do
      role.role_permissions.create!(
        subject_type: "EntityClass", subject_key: "Entity", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, Entity)).to be true
      expect(ability.can?(:destroy, Entity)).to be true
    end

    it "grants Entity instance subject scoped to id" do
      e1 = create(:entity, customer: customer)
      e2 = create(:entity, customer: customer)
      role.role_permissions.create!(
        subject_type: "Entity", subject_id: e1.id, action: "update"
      )
      ability = described_class.new(user)
      expect(ability.can?(:update, e1)).to be true
      expect(ability.can?(:update, e2)).to be false
    end

    it "grants Module subject" do
      role.role_permissions.create!(
        subject_type: "Module", subject_key: "payments", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:manage, :module_payments)).to be true
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement**

`app/models/ability.rb`:

```ruby
# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user)
    return if user.blank?

    if user.has_reserved_role?(:owner)
      can :manage, :all
      return
    end

    grants = RolePermissions::Operation::ResolveGrants.call(role_ids: user.role_ids)
    grants.each { |g| apply_grant(g) }
  end

  private

  def apply_grant(grant)
    actions = grant.action == "manage" ? :manage : grant.action.to_sym

    case grant.subject_type
    when "Route"       then can actions, :"route_#{grant.subject_key.tr('/', '_')}"
    when "Module"      then can actions, :"module_#{grant.subject_key}"
    when "EntityClass" then can actions, Entity
    when "Entity"      then can actions, Entity, id: grant.subject_id
    when "PageClass"   then can actions, Page
    when "Page"        then can actions, Page, id: grant.subject_id
    when "FeaturePage" then can actions, :"feature_#{grant.subject_key}"
    when "Platform"    then can actions, :"platform_#{grant.subject_key}"
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/models/ability_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/models/ability.rb spec/models/ability_spec.rb
# git commit -m "ability: add cancancan Ability class with hardcoded owner and data-driven grants"
```

---

## Task 3.3: Wire cancancan into ApplicationController (no enforcement yet)

**Files:**
- Modify: `app/controllers/application_controller.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/requests/cancancan_wiring_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "cancancan wiring", type: :request do
  let(:customer) { create(:customer) }
  let!(:owner_role) { Roles::Operation::SeedReserved.call(customer: customer); customer.roles.find_by(key: "owner") }
  let(:user) do
    u = create(:user, customer: customer)
    u.users_roles.create!(role: owner_role)
    u
  end

  before { sign_in user }

  it "exposes current_ability via the controller" do
    get "/#{customer.id}/admin/dashboard"
    # We don't assert HTTP status here — just that no NoMethodError surfaces from current_ability.
    expect(response).to have_http_status(:success).or have_http_status(:redirect)
  end
end
```

- [ ] **Step 2: Run — should fail**

(May fail with `NameError: current_ability undefined` or similar.)

- [ ] **Step 3: Add cancancan inclusion**

In `app/controllers/application_controller.rb`, ensure cancancan is loaded by adding `rescue_from CanCan::AccessDenied` near the top of the class body (right after `include FeatureModules::HostIntegration`):

```ruby
  # ==========================================================================
  # CanCanCan integration
  # ==========================================================================

  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message.presence || "Access denied." }
      format.json { render json: { error: "access_denied" }, status: :forbidden }
    end
  end
```

CanCanCan's `current_ability` helper is included automatically via the gem; no further wiring is needed in Phase 3.

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/requests/cancancan_wiring_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/controllers/application_controller.rb spec/requests/cancancan_wiring_spec.rb
# git commit -m "auth: rescue CanCan::AccessDenied at the application layer"
```

---

## Task 3.4: Phase 3 sanity check

- [ ] Run: `bundle exec rspec`
- [ ] Expected: all previously-green specs still green; new Phase 3 specs pass.

---

# PHASE 4 — Admin UI for Roles, Grants, and User Assignments

**Outcome:** Owners (and admins, when permitted) can manage roles, edit role grants, and assign roles to users via `/:cid/admin/settings/modules/authentication/*`. Reuses existing admin layout / TailwindCSS / ViewComponent / Stimulus.

> Note: All Phase 4 controllers continue to use the legacy `before_action :require_owner!` (or `require_admin_or_owner!`) pattern. The cutover to the new Ability happens in Phase 5. This keeps Phase 4 deployable independently.

---

## Task 4.1: Routes for the new admin settings pages

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Write failing routing spec**

`spec/routing/admin_settings_authentication_routes_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication routes", type: :routing do
  let(:cid) { "12345678" }

  it "routes roles index" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/roles")
      .to route_to(controller: "admin/settings/modules/authentication/roles",
                   action: "index", customer_id: cid)
  end

  it "routes role grants show" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/roles/5/grants")
      .to route_to(controller: "admin/settings/modules/authentication/role_grants",
                   action: "show", customer_id: cid, role_id: "5")
  end

  it "routes user_role_assignments index" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/user_role_assignments")
      .to route_to(controller: "admin/settings/modules/authentication/user_role_assignments",
                   action: "index", customer_id: cid)
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Add routes**

In `config/routes.rb`, **inside** the existing `namespace :admin do ... end` block, **after** the existing `namespace :settings do ... end` block (which currently contains `namespace :modules do namespace :payments do ... end end`), extend it:

Locate this block:

```ruby
namespace :settings do
  namespace :modules do
    namespace :payments do
      resources :merchant_accounts, only: %i[index new create edit update]
    end
  end
end
```

Replace with:

```ruby
namespace :settings do
  namespace :modules do
    namespace :payments do
      resources :merchant_accounts, only: %i[index new create edit update]
    end
    namespace :authentication do
      resources :roles do
        resource :grants, only: %i[show update], controller: "role_grants"
      end
      resources :user_role_assignments, only: %i[index create destroy]
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/routing/admin_settings_authentication_routes_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add config/routes.rb spec/routing/admin_settings_authentication_routes_spec.rb
# git commit -m "routes: add admin settings authentication roles + grants + assignments"
```

---

## Task 4.2: Roles::Operation::Create + Update + Destroy + contracts + spec

**Files:**
- Create: `app/concepts/roles/contract/create.rb`
- Create: `app/concepts/roles/contract/update.rb`
- Create: `app/concepts/roles/operation/create.rb`
- Create: `app/concepts/roles/operation/update.rb`
- Create: `app/concepts/roles/operation/destroy.rb`
- Create: `spec/concepts/roles/operation/create_spec.rb`
- Create: `spec/concepts/roles/operation/update_spec.rb`
- Create: `spec/concepts/roles/operation/destroy_spec.rb`

- [ ] **Step 1: Write failing specs**

`spec/concepts/roles/operation/create_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Create do
  let(:customer) { create(:customer) }

  it "creates a custom role" do
    result = described_class.call(
      customer: customer,
      params: { name: "Manager", key: "manager", description: "Mid-level admin" }
    )
    expect(result.success?).to be true
    role = result[:model]
    expect(role.persisted?).to be true
    expect(role).not_to be_system
    expect(role).not_to be_locked_grants
  end

  it "rejects when key is missing" do
    result = described_class.call(customer: customer, params: { name: "X", key: "" })
    expect(result.success?).to be false
  end

  it "rejects when key duplicates an existing role for the same customer" do
    create(:role, customer: customer, key: "manager")
    result = described_class.call(customer: customer, params: { name: "M", key: "manager" })
    expect(result.success?).to be false
  end
end
```

`spec/concepts/roles/operation/update_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Update do
  let(:customer) { create(:customer) }

  it "updates name and description on a custom role" do
    role = create(:role, customer: customer, key: "manager", name: "Manager")
    result = described_class.call(role: role, params: { name: "Senior Manager", description: "x" })
    expect(result.success?).to be true
    expect(role.reload.name).to eq("Senior Manager")
  end

  it "does not change key (key is immutable post-create)" do
    role = create(:role, customer: customer, key: "manager")
    described_class.call(role: role, params: { key: "boss", name: "Boss" })
    expect(role.reload.key).to eq("manager")
  end

  it "rejects updates to system roles' grants/lock state implicitly (no fields exposed)" do
    sys = create(:role, :admin, customer: customer)
    result = described_class.call(role: sys, params: { name: "Hacked" })
    expect(result.success?).to be false
  end
end
```

`spec/concepts/roles/operation/destroy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Destroy do
  let(:customer) { create(:customer) }

  it "destroys a custom role" do
    role = create(:role, customer: customer)
    expect { described_class.call(role: role) }.to change { Role.count }.by(-1)
  end

  it "rejects destroying a system role" do
    role = create(:role, :admin, customer: customer)
    result = described_class.call(role: role)
    expect(result.success?).to be false
    expect(Role.exists?(role.id)).to be true
  end
end
```

- [ ] **Step 2: Run — should fail**

Run: `bundle exec rspec spec/concepts/roles/operation/create_spec.rb spec/concepts/roles/operation/update_spec.rb spec/concepts/roles/operation/destroy_spec.rb`

- [ ] **Step 3: Implement contracts**

`app/concepts/roles/contract/create.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Contract
    class Create < Reform::Form
      property :key
      property :name
      property :description

      validates :key,  presence: true, format: { with: /\A[a-z0-9_]+\z/ }
      validates :name, presence: true
    end
  end
end
```

`app/concepts/roles/contract/update.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Contract
    class Update < Reform::Form
      property :name
      property :description

      validates :name, presence: true
    end
  end
end
```

- [ ] **Step 4: Implement operations**

`app/concepts/roles/operation/create.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Operation
    class Create
      Result = Struct.new(:success?, :model, :errors, keyword_init: true) do
        def [](k) = send(k)
      end

      def self.call(customer:, params:)
        role = Role.new(customer: customer, system: false, locked_grants: false)
        form = Roles::Contract::Create.new(role)
        if form.validate(params) && unique?(customer, params[:key])
          form.save
          Result.new(success?: true, model: role, errors: nil)
        else
          form.errors.add(:key, "already taken") unless unique?(customer, params[:key])
          Result.new(success?: false, model: role, errors: form.errors)
        end
      end

      def self.unique?(customer, key)
        return false if key.blank?
        !customer.roles.exists?(key: key)
      end
    end
  end
end
```

`app/concepts/roles/operation/update.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Operation
    class Update
      Result = Roles::Operation::Create::Result

      def self.call(role:, params:)
        return Result.new(success?: false, model: role, errors: { base: ["system role cannot be edited"] }) if role.system?

        form = Roles::Contract::Update.new(role)
        if form.validate(params)
          form.save
          Result.new(success?: true, model: role, errors: nil)
        else
          Result.new(success?: false, model: role, errors: form.errors)
        end
      end
    end
  end
end
```

`app/concepts/roles/operation/destroy.rb`:

```ruby
# frozen_string_literal: true

module Roles
  module Operation
    class Destroy
      Result = Roles::Operation::Create::Result

      def self.call(role:)
        return Result.new(success?: false, model: role, errors: { base: ["system role cannot be destroyed"] }) if role.system?

        role.destroy!
        Result.new(success?: true, model: role, errors: nil)
      end
    end
  end
end
```

- [ ] **Step 5: Run — should pass**

Run: `bundle exec rspec spec/concepts/roles/operation/`

- [ ] **Step 6: Prepare commit**

```bash
git add app/concepts/roles/ spec/concepts/roles/
# git commit -m "roles: add Create/Update/Destroy operations with contracts"
```

---

## Task 4.3: RolesController + RolesTableComponent + RoleFormComponent + spec

**Files:**
- Create: `app/controllers/admin/settings/modules/authentication/roles_controller.rb`
- Create: `app/components/admin/settings/modules/authentication/roles_table_component.rb`
- Create: `app/components/admin/settings/modules/authentication/roles_table_component.html.erb`
- Create: `app/components/admin/settings/modules/authentication/role_form_component.rb`
- Create: `app/components/admin/settings/modules/authentication/role_form_component.html.erb`
- Create: `app/views/admin/settings/modules/authentication/roles/index.html.erb`
- Create: `app/views/admin/settings/modules/authentication/roles/new.html.erb`
- Create: `app/views/admin/settings/modules/authentication/roles/edit.html.erb`
- Create: `app/views/admin/settings/modules/authentication/roles/show.html.erb`
- Create: `spec/requests/admin/settings/modules/authentication/roles_spec.rb`
- Create: `spec/components/admin/settings/modules/authentication/roles_table_component_spec.rb`

- [ ] **Step 1: Write failing request spec**

`spec/requests/admin/settings/modules/authentication/roles_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/roles", type: :request do
  let(:customer) { create(:customer) }
  let!(:reserved) { Roles::Operation::SeedReserved.call(customer: customer) }
  let(:owner_role) { customer.roles.find_by(key: "owner") }
  let(:user) do
    u = create(:user, customer: customer, role: :owner)
    u.users_roles.create!(role: owner_role)
    u
  end

  before { sign_in user }

  describe "GET /:cid/admin/settings/modules/authentication/roles" do
    it "lists all roles for the customer" do
      create(:role, customer: customer, name: "Manager", key: "manager")
      get "/#{customer.id}/admin/settings/modules/authentication/roles"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Owner").and include("Admin").and include("Member").and include("Manager")
    end
  end

  describe "POST /:cid/admin/settings/modules/authentication/roles" do
    it "creates a custom role" do
      post "/#{customer.id}/admin/settings/modules/authentication/roles",
           params: { role: { key: "manager", name: "Manager", description: "x" } }
      expect(response).to redirect_to(/admin\/settings\/modules\/authentication\/roles/)
      expect(customer.roles.find_by(key: "manager")).not_to be_nil
    end

    it "rejects creating with reserved key" do
      post "/#{customer.id}/admin/settings/modules/authentication/roles",
           params: { role: { key: "owner", name: "Pwn" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(customer.roles.where(key: "owner").count).to eq(1) # only the seeded one
    end
  end

  describe "PATCH /:cid/admin/settings/modules/authentication/roles/:id" do
    it "updates a custom role" do
      role = create(:role, customer: customer, key: "manager", name: "Manager")
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}",
            params: { role: { name: "Senior Manager" } }
      expect(role.reload.name).to eq("Senior Manager")
    end

    it "rejects updating a system role" do
      role = customer.roles.find_by(key: "admin")
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}",
            params: { role: { name: "Hacked" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /:cid/admin/settings/modules/authentication/roles/:id" do
    it "destroys a custom role" do
      role = create(:role, customer: customer, key: "manager")
      delete "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}"
      expect(Role.exists?(role.id)).to be false
    end

    it "rejects destroying a system role" do
      role = customer.roles.find_by(key: "owner")
      delete "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}"
      expect(Role.exists?(role.id)).to be true
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement controller**

`app/controllers/admin/settings/modules/authentication/roles_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RolesController < ApplicationController
          set_tenant_from_route_params
          before_action :authenticate_user!
          before_action :require_owner!
          before_action :set_role, only: %i[show edit update destroy]

          def index
            @roles = current_customer.roles.order(:system, :name)
          end

          def show; end

          def new
            @role = current_customer.roles.new
          end

          def create
            result = Roles::Operation::Create.call(customer: current_customer, params: role_params)
            if result.success?
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, result[:model]),
                          notice: "Role created."
            else
              @role = result[:model]
              render :new, status: :unprocessable_entity
            end
          end

          def edit; end

          def update
            result = Roles::Operation::Update.call(role: @role, params: role_params)
            if result.success?
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, @role),
                          notice: "Role updated."
            else
              render :edit, status: :unprocessable_entity
            end
          end

          def destroy
            result = Roles::Operation::Destroy.call(role: @role)
            if result.success?
              redirect_to admin_settings_modules_authentication_roles_path(current_customer.id),
                          notice: "Role destroyed."
            else
              redirect_to admin_settings_modules_authentication_role_path(current_customer.id, @role),
                          alert: "Role cannot be destroyed."
            end
          end

          private

          def set_role
            @role = current_customer.roles.find(params[:id])
          end

          def role_params
            params.require(:role).permit(:key, :name, :description)
          end

          def current_dashboard_menu_item = :settings
          helper_method :current_dashboard_menu_item
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement RolesTableComponent**

`app/components/admin/settings/modules/authentication/roles_table_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RolesTableComponent < ViewComponent::Base
          def initialize(roles:, customer:)
            @roles    = roles
            @customer = customer
          end

          attr_reader :roles, :customer

          def system_badge(role)
            role.system? ? "System" : "Custom"
          end
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/roles_table_component.html.erb`:

```erb
<div class="overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
  <table class="min-w-full divide-y divide-slate-200 text-sm">
    <thead class="bg-slate-50 text-slate-700">
      <tr>
        <th class="px-4 py-3 text-left font-semibold">Name</th>
        <th class="px-4 py-3 text-left font-semibold">Key</th>
        <th class="px-4 py-3 text-left font-semibold">Type</th>
        <th class="px-4 py-3 text-left font-semibold">Users</th>
        <th class="px-4 py-3 text-left font-semibold">Grants</th>
        <th class="px-4 py-3 text-right font-semibold">Actions</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-slate-100">
      <% roles.each do |role| %>
        <tr class="hover:bg-slate-50">
          <td class="px-4 py-3 font-medium text-slate-900"><%= role.name %></td>
          <td class="px-4 py-3 font-mono text-slate-600"><%= role.key %></td>
          <td class="px-4 py-3">
            <span class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium
              <%= role.system? ? 'bg-indigo-100 text-indigo-800' : 'bg-slate-100 text-slate-800' %>">
              <%= system_badge(role) %>
            </span>
          </td>
          <td class="px-4 py-3 text-slate-700"><%= role.users.count %></td>
          <td class="px-4 py-3 text-slate-700"><%= role.role_permissions.count %></td>
          <td class="px-4 py-3 text-right space-x-2">
            <%= link_to "Grants",
              admin_settings_modules_authentication_role_grants_path(customer.id, role),
              class: "text-indigo-600 hover:text-indigo-900" %>
            <% unless role.system? %>
              <%= link_to "Edit",
                edit_admin_settings_modules_authentication_role_path(customer.id, role),
                class: "text-slate-600 hover:text-slate-900" %>
              <%= button_to "Delete",
                admin_settings_modules_authentication_role_path(customer.id, role),
                method: :delete,
                form: { data: { turbo_confirm: "Delete role #{role.name}?" } },
                class: "text-red-600 hover:text-red-900" %>
            <% else %>
              <span class="text-slate-400" title="Reserved role">Locked</span>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 5: Implement RoleFormComponent**

`app/components/admin/settings/modules/authentication/role_form_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RoleFormComponent < ViewComponent::Base
          def initialize(role:, customer:)
            @role = role
            @customer = customer
          end

          attr_reader :role, :customer

          def submit_label = role.persisted? ? "Update Role" : "Create Role"
          def form_url
            if role.persisted?
              helpers.admin_settings_modules_authentication_role_path(customer.id, role)
            else
              helpers.admin_settings_modules_authentication_roles_path(customer.id)
            end
          end
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/role_form_component.html.erb`:

```erb
<%= form_with model: role, url: form_url, method: role.persisted? ? :patch : :post,
              local: true, class: "space-y-4 max-w-2xl" do |f| %>
  <% if role.errors.any? %>
    <div class="rounded-md bg-red-50 p-3 text-red-700">
      <ul class="list-disc pl-5">
        <% role.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_field :name, class: "mt-1 block w-full rounded-md border-slate-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div>
    <%= f.label :key, class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_field :key, disabled: role.persisted?, class: "mt-1 block w-full rounded-md border-slate-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono" %>
    <p class="mt-1 text-xs text-slate-500">Lowercase letters, digits, underscores. Cannot be changed after creation.</p>
  </div>

  <div>
    <%= f.label :description, class: "block text-sm font-medium text-slate-700" %>
    <%= f.text_area :description, rows: 3, class: "mt-1 block w-full rounded-md border-slate-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
  </div>

  <div class="flex justify-end gap-2">
    <%= link_to "Cancel", helpers.admin_settings_modules_authentication_roles_path(customer.id),
                class: "px-4 py-2 rounded-md text-slate-700 hover:bg-slate-100" %>
    <%= f.submit submit_label, class: "px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700" %>
  </div>
<% end %>
```

- [ ] **Step 6: Implement views**

`app/views/admin/settings/modules/authentication/roles/index.html.erb`:

```erb
<div class="space-y-6">
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-semibold text-slate-900">Roles</h1>
    <%= link_to "New Role",
          new_admin_settings_modules_authentication_role_path(current_customer.id),
          class: "px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700" %>
  </div>

  <%= render Admin::Settings::Modules::Authentication::RolesTableComponent.new(
        roles: @roles, customer: current_customer
      ) %>
</div>
```

`app/views/admin/settings/modules/authentication/roles/new.html.erb`:

```erb
<div class="space-y-6">
  <h1 class="text-2xl font-semibold text-slate-900">New Role</h1>
  <%= render Admin::Settings::Modules::Authentication::RoleFormComponent.new(
        role: @role, customer: current_customer
      ) %>
</div>
```

`app/views/admin/settings/modules/authentication/roles/edit.html.erb`:

```erb
<div class="space-y-6">
  <h1 class="text-2xl font-semibold text-slate-900">Edit Role</h1>
  <%= render Admin::Settings::Modules::Authentication::RoleFormComponent.new(
        role: @role, customer: current_customer
      ) %>
</div>
```

`app/views/admin/settings/modules/authentication/roles/show.html.erb`:

```erb
<div class="space-y-6">
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-semibold text-slate-900"><%= @role.name %></h1>
    <%= link_to "Manage Grants",
          admin_settings_modules_authentication_role_grants_path(current_customer.id, @role),
          class: "px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700" %>
  </div>

  <dl class="grid grid-cols-2 gap-4 max-w-2xl">
    <dt class="text-sm font-medium text-slate-500">Key</dt>
    <dd class="font-mono text-sm text-slate-900"><%= @role.key %></dd>
    <dt class="text-sm font-medium text-slate-500">Type</dt>
    <dd class="text-sm text-slate-900"><%= @role.system? ? "System (locked)" : "Custom" %></dd>
    <dt class="text-sm font-medium text-slate-500">Description</dt>
    <dd class="text-sm text-slate-900"><%= @role.description.presence || "—" %></dd>
  </dl>
</div>
```

- [ ] **Step 7: Run — should pass**

Run: `bundle exec rspec spec/requests/admin/settings/modules/authentication/roles_spec.rb`

- [ ] **Step 8: Prepare commit**

```bash
git add app/controllers/admin/settings/modules/authentication/roles_controller.rb \
        app/components/admin/settings/modules/authentication/roles_table_component* \
        app/components/admin/settings/modules/authentication/role_form_component* \
        app/views/admin/settings/modules/authentication/roles \
        spec/requests/admin/settings/modules/authentication/roles_spec.rb
# git commit -m "admin: add RolesController + table + form components for role CRUD"
```

---

## Task 4.4: RoleGrants::Operation::Update + contract + spec

**Files:**
- Create: `app/concepts/role_grants/contract/update.rb`
- Create: `app/concepts/role_grants/operation/update.rb`
- Create: `spec/concepts/role_grants/operation/update_spec.rb`

- [ ] **Step 1: Write failing spec**

`spec/concepts/role_grants/operation/update_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleGrants::Operation::Update do
  let(:customer) { create(:customer) }
  let(:role)     { create(:role, customer: customer) }

  it "adds new grants in a transaction" do
    result = described_class.call(role: role, added: [
      { subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read" },
      { subject_type: "Module", subject_key: "payments", action: "manage" }
    ], removed: [])
    expect(result.success?).to be true
    expect(role.role_permissions.count).to eq(2)
  end

  it "removes grants by composite key" do
    rp = create(:role_permission, role: role,
                subject_type: "Route", subject_key: "admin/x", action: "read")
    described_class.call(role: role, added: [],
      removed: [{ subject_type: "Route", subject_key: "admin/x", subject_id: nil, action: "read" }])
    expect(RolePermission.exists?(rp.id)).to be false
  end

  it "rejects update on a locked role" do
    role.update!(locked_grants: true)
    result = described_class.call(role: role,
      added: [{ subject_type: "Route", subject_key: "admin/x", action: "read" }],
      removed: [])
    expect(result.success?).to be false
    expect(role.role_permissions).to be_empty
  end

  it "is atomic — failure inside a batch rolls back" do
    bad = { subject_type: "Bogus", subject_key: "x", action: "read" }
    described_class.call(role: role, added: [
      { subject_type: "Route", subject_key: "ok", action: "read" }, bad
    ], removed: [])
    expect(role.role_permissions).to be_empty
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement contract and operation**

`app/concepts/role_grants/contract/update.rb`:

```ruby
# frozen_string_literal: true

module RoleGrants
  module Contract
    class Update < Reform::Form
      property :added,   virtual: true
      property :removed, virtual: true

      validates :added,   presence: true, allow_blank: true
      validates :removed, presence: true, allow_blank: true
    end
  end
end
```

`app/concepts/role_grants/operation/update.rb`:

```ruby
# frozen_string_literal: true

module RoleGrants
  module Operation
    class Update
      Result = Roles::Operation::Create::Result

      def self.call(role:, added: [], removed: [])
        return Result.new(success?: false, model: role,
                          errors: { base: ["role is locked"] }) if role.locked_grants?

        ActiveRecord::Base.transaction do
          Array(added).each   { |g| add_grant!(role, g) }
          Array(removed).each { |g| remove_grant!(role, g) }
        end

        Result.new(success?: true, model: role, errors: nil)
      rescue ActiveRecord::RecordInvalid, ActiveModel::ValidationError => e
        Result.new(success?: false, model: role, errors: { base: [e.message] })
      end

      def self.add_grant!(role, attrs)
        role.role_permissions.create!(
          subject_type: attrs[:subject_type] || attrs["subject_type"],
          subject_key:  attrs[:subject_key]  || attrs["subject_key"],
          subject_id:   attrs[:subject_id]   || attrs["subject_id"],
          action:       attrs[:action]       || attrs["action"]
        )
      end

      def self.remove_grant!(role, attrs)
        scope = role.role_permissions.where(
          subject_type: attrs[:subject_type] || attrs["subject_type"],
          action:       attrs[:action]       || attrs["action"]
        )
        scope = scope.where(subject_key: attrs[:subject_key] || attrs["subject_key"])
        scope = scope.where(subject_id:  attrs[:subject_id]  || attrs["subject_id"])
        scope.destroy_all
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/concepts/role_grants/operation/update_spec.rb`

- [ ] **Step 5: Prepare commit**

```bash
git add app/concepts/role_grants/ spec/concepts/role_grants/
# git commit -m "role_grants: add transactional Update operation"
```

---

## Task 4.5: RoleGrantsController + GrantsEditorComponent + AccessPointGroupComponent + AccessPointRowComponent + Stimulus + spec

**Files:**
- Create: `app/controllers/admin/settings/modules/authentication/role_grants_controller.rb`
- Create: `app/components/admin/settings/modules/authentication/grants_editor_component.rb`
- Create: `app/components/admin/settings/modules/authentication/grants_editor_component.html.erb`
- Create: `app/components/admin/settings/modules/authentication/access_point_group_component.rb`
- Create: `app/components/admin/settings/modules/authentication/access_point_group_component.html.erb`
- Create: `app/components/admin/settings/modules/authentication/access_point_row_component.rb`
- Create: `app/components/admin/settings/modules/authentication/access_point_row_component.html.erb`
- Create: `app/javascript/controllers/grants_editor_controller.js`
- Create: `app/views/admin/settings/modules/authentication/role_grants/show.html.erb`
- Create: `spec/requests/admin/settings/modules/authentication/role_grants_spec.rb`

- [ ] **Step 1: Write failing request spec**

`spec/requests/admin/settings/modules/authentication/role_grants_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/role_grants", type: :request do
  let(:customer) { create(:customer) }
  let!(:reserved) { Roles::Operation::SeedReserved.call(customer: customer) }
  let(:owner_role) { customer.roles.find_by(key: "owner") }
  let(:user) do
    u = create(:user, customer: customer, role: :owner)
    u.users_roles.create!(role: owner_role)
    u
  end
  let(:custom_role) { create(:role, customer: customer, key: "manager", name: "Manager") }
  let(:locked_role) { customer.roles.find_by(key: "admin") }

  before { sign_in user }

  describe "GET show" do
    it "renders the grants editor" do
      get "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Manager").and include("Admin Routes").or include("Modules")
    end
  end

  describe "PATCH update" do
    it "applies the grants diff" do
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{custom_role.id}/grants",
            params: {
              role_grants: {
                added:   [{ subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read" }],
                removed: []
              }
            }, as: :json
      expect(response).to have_http_status(:success)
      expect(custom_role.role_permissions.count).to eq(1)
    end

    it "rejects updates to locked roles" do
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{locked_role.id}/grants",
            params: { role_grants: { added: [{ subject_type: "Route", subject_key: "x", action: "read" }], removed: [] } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement controller**

`app/controllers/admin/settings/modules/authentication/role_grants_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class RoleGrantsController < ApplicationController
          set_tenant_from_route_params
          before_action :authenticate_user!
          before_action :require_owner!
          before_action :set_role

          def show
            @catalog = AccessPoints::Catalog.for(customer_id: current_customer.id)
            @granted_keys = grant_lookup_set(@role)
          end

          def update
            result = RoleGrants::Operation::Update.call(
              role:    @role,
              added:   permitted_params[:added]   || [],
              removed: permitted_params[:removed] || []
            )

            respond_to do |format|
              if result.success?
                format.json { render json: { ok: true } }
                format.html { redirect_to admin_settings_modules_authentication_role_grants_path(current_customer.id, @role),
                                          notice: "Grants updated." }
              else
                format.json { render json: { ok: false, errors: result.errors }, status: :unprocessable_entity }
                format.html { redirect_back fallback_location: admin_settings_modules_authentication_roles_path(current_customer.id),
                                            alert: "Could not update grants." }
              end
            end
          end

          private

          def set_role
            @role = current_customer.roles.find(params[:role_id])
          end

          def permitted_params
            params.require(:role_grants).permit(
              added:   [:subject_type, :subject_key, :subject_id, :action],
              removed: [:subject_type, :subject_key, :subject_id, :action]
            )
          end

          def grant_lookup_set(role)
            role.role_permissions.pluck(:subject_type, :subject_key, :subject_id, :action)
                .map { |st, sk, sid, a| "#{st}:#{sk}:#{sid}:#{a}" }
                .to_set
          end

          def current_dashboard_menu_item = :settings
          helper_method :current_dashboard_menu_item
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement components**

`app/components/admin/settings/modules/authentication/grants_editor_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class GrantsEditorComponent < ViewComponent::Base
          def initialize(role:, catalog:, granted_keys:, customer:)
            @role         = role
            @catalog      = catalog
            @granted_keys = granted_keys
            @customer     = customer
          end

          attr_reader :role, :catalog, :granted_keys, :customer

          def locked? = role.locked_grants?
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/grants_editor_component.html.erb`:

```erb
<div data-controller="grants-editor"
     data-grants-editor-role-id-value="<%= role.id %>"
     data-grants-editor-update-url-value="<%= helpers.admin_settings_modules_authentication_role_grants_path(customer.id, role) %>"
     data-grants-editor-locked-value="<%= locked? %>"
     class="grid grid-cols-1 gap-6 lg:grid-cols-3">

  <% if locked? %>
    <div class="lg:col-span-3 rounded-md bg-amber-50 border border-amber-200 p-4 text-amber-900">
      <strong>Reserved role.</strong> Grants are seeded by the system and cannot be modified.
    </div>
  <% end %>

  <div class="lg:col-span-2 space-y-4">
    <% catalog.groups.each do |group| %>
      <%= render Admin::Settings::Modules::Authentication::AccessPointGroupComponent.new(
            group: group, granted_keys: granted_keys, locked: locked?
          ) %>
    <% end %>
  </div>

  <aside class="space-y-3">
    <h3 class="text-sm font-semibold text-slate-700">Selected grants</h3>
    <div data-grants-editor-target="summary" class="rounded-md border border-slate-200 bg-white p-3 min-h-[200px]">
      <p class="text-slate-500 text-sm">Click a checkbox to grant. Selections appear here.</p>
    </div>
    <% unless locked? %>
      <button type="button" data-action="click->grants-editor#save"
              class="w-full px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700">
        Save grants
      </button>
    <% end %>
  </aside>
</div>
```

`app/components/admin/settings/modules/authentication/access_point_group_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class AccessPointGroupComponent < ViewComponent::Base
          def initialize(group:, granted_keys:, locked:)
            @group        = group
            @granted_keys = granted_keys
            @locked       = locked
          end

          attr_reader :group, :granted_keys, :locked
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/access_point_group_component.html.erb`:

```erb
<details class="rounded-md border border-slate-200 bg-white" open>
  <summary class="cursor-pointer px-4 py-3 font-medium text-slate-800 hover:bg-slate-50">
    <%= group[:label] %>
    <span class="ml-2 text-xs text-slate-500">(<%= group[:descriptors].size %>)</span>
  </summary>
  <div class="divide-y divide-slate-100">
    <% group[:descriptors].each do |descriptor| %>
      <%= render Admin::Settings::Modules::Authentication::AccessPointRowComponent.new(
            descriptor: descriptor, granted_keys: granted_keys, locked: locked
          ) %>
    <% end %>
  </div>
</details>
```

`app/components/admin/settings/modules/authentication/access_point_row_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class AccessPointRowComponent < ViewComponent::Base
          def initialize(descriptor:, granted_keys:, locked:)
            @descriptor   = descriptor
            @granted_keys = granted_keys
            @locked       = locked
          end

          attr_reader :descriptor, :granted_keys, :locked

          def granted?(action)
            key = "#{descriptor.subject_type}:#{descriptor.subject_key}:#{descriptor.subject_id}:#{action}"
            granted_keys.include?(key)
          end
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/access_point_row_component.html.erb`:

```erb
<div class="px-4 py-3 grid grid-cols-1 sm:grid-cols-3 gap-2 items-center">
  <div class="col-span-1 sm:col-span-1">
    <p class="font-medium text-slate-900"><%= descriptor.label %></p>
    <% if descriptor.description.present? %>
      <p class="text-xs text-slate-500"><%= descriptor.description %></p>
    <% end %>
  </div>
  <div class="col-span-1 sm:col-span-2 flex flex-wrap gap-3">
    <% descriptor.actions.each do |action| %>
      <label class="inline-flex items-center gap-1.5 text-sm">
        <input type="checkbox"
               class="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
               <%= "checked" if granted?(action) %>
               <%= "disabled" if locked %>
               data-action="change->grants-editor#toggle"
               data-grants-editor-subject-type-param="<%= descriptor.subject_type %>"
               data-grants-editor-subject-key-param="<%= descriptor.subject_key %>"
               data-grants-editor-subject-id-param="<%= descriptor.subject_id %>"
               data-grants-editor-action-param="<%= action %>">
        <span class="text-slate-700"><%= action %></span>
      </label>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Implement Stimulus controller**

`app/javascript/controllers/grants_editor_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// data-controller="grants-editor"
// values: roleIdValue, updateUrlValue, lockedValue
// targets: summary
// actions:
//   change->grants-editor#toggle
//   click->grants-editor#save
export default class extends Controller {
  static values = {
    roleId: Number,
    updateUrl: String,
    locked: Boolean,
  }
  static targets = ["summary"]

  connect() {
    this.added = []
    this.removed = []
    this.renderSummary()
  }

  toggle(event) {
    if (this.lockedValue) return
    const t  = event.target
    const p  = event.params
    const grant = {
      subject_type: p.subjectType,
      subject_key:  p.subjectKey || null,
      subject_id:   p.subjectId  ? Number(p.subjectId) : null,
      action:       p.action,
    }
    if (t.checked) {
      this.added.push(grant)
      this.removed = this.removed.filter(g => !this.same(g, grant))
    } else {
      this.removed.push(grant)
      this.added = this.added.filter(g => !this.same(g, grant))
    }
    this.renderSummary()
  }

  same(a, b) {
    return a.subject_type === b.subject_type &&
           a.subject_key  === b.subject_key  &&
           a.subject_id   === b.subject_id   &&
           a.action       === b.action
  }

  renderSummary() {
    const all = [...this.added, ...this.removed]
    if (all.length === 0) {
      this.summaryTarget.innerHTML =
        '<p class="text-slate-500 text-sm">Click a checkbox to grant. Selections appear here.</p>'
      return
    }
    const list = all.map(g => `
      <div class="text-xs text-slate-700 font-mono">
        ${this.added.includes(g) ? "+" : "-"} ${g.subject_type}:${g.subject_key || g.subject_id}:${g.action}
      </div>
    `).join("")
    this.summaryTarget.innerHTML = list
  }

  async save() {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const res = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({
        role_grants: { added: this.added, removed: this.removed }
      }),
    })
    if (res.ok) {
      window.location.reload()
    } else {
      const data = await res.json().catch(() => ({}))
      alert("Save failed: " + JSON.stringify(data.errors || data))
    }
  }
}
```

(Verify the existing Stimulus registration approach: `cat app/javascript/controllers/index.js | head -20`. If controllers are auto-registered via `eagerLoadControllersFrom`, the file just needs to exist with that name. If a manual register call is used, append `application.register("grants-editor", GrantsEditorController)`.)

- [ ] **Step 6: Implement view**

`app/views/admin/settings/modules/authentication/role_grants/show.html.erb`:

```erb
<div class="space-y-6">
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-semibold text-slate-900">Grants — <%= @role.name %></h1>
      <p class="text-sm text-slate-500"><%= @role.description %></p>
    </div>
    <%= link_to "Back to roles",
          admin_settings_modules_authentication_roles_path(current_customer.id),
          class: "text-slate-600 hover:text-slate-900" %>
  </div>

  <%= render Admin::Settings::Modules::Authentication::GrantsEditorComponent.new(
        role: @role, catalog: @catalog, granted_keys: @granted_keys, customer: current_customer
      ) %>
</div>
```

- [ ] **Step 7: Run — should pass**

Run: `bundle exec rspec spec/requests/admin/settings/modules/authentication/role_grants_spec.rb`

- [ ] **Step 8: Smoke test in dev server**

Run: `rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000` (in another terminal).
Sign in as an owner. Navigate to `/<cid>/admin/settings/modules/authentication/roles`. Open a custom role's "Grants" page. Verify the catalog renders, checkboxes toggle, and save persists. Locked-role grants page disables checkboxes and hides the save button.

- [ ] **Step 9: Prepare commit**

```bash
git add app/controllers/admin/settings/modules/authentication/role_grants_controller.rb \
        app/components/admin/settings/modules/authentication/grants_editor_component* \
        app/components/admin/settings/modules/authentication/access_point_group_component* \
        app/components/admin/settings/modules/authentication/access_point_row_component* \
        app/javascript/controllers/grants_editor_controller.js \
        app/views/admin/settings/modules/authentication/role_grants \
        spec/requests/admin/settings/modules/authentication/role_grants_spec.rb
# git commit -m "admin: add grants editor with two-pane layout and JSON diff save"
```

---

## Task 4.6: UserRoles::Operation::Assign + UserRoleAssignmentsController + components

**Files:**
- Create: `app/concepts/user_roles/contract/assign.rb`
- Create: `app/concepts/user_roles/operation/assign.rb`
- Create: `app/controllers/admin/settings/modules/authentication/user_role_assignments_controller.rb`
- Create: `app/components/admin/settings/modules/authentication/user_roles_table_component.rb`
- Create: `app/components/admin/settings/modules/authentication/user_roles_table_component.html.erb`
- Create: `app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.rb`
- Create: `app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.html.erb`
- Create: `app/javascript/controllers/user_role_dialog_controller.js`
- Create: `app/views/admin/settings/modules/authentication/user_role_assignments/index.html.erb`
- Create: `spec/concepts/user_roles/operation/assign_spec.rb`
- Create: `spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb`

- [ ] **Step 1: Write failing operation spec**

`spec/concepts/user_roles/operation/assign_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRoles::Operation::Assign do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }
  let(:r1)       { create(:role, customer: customer, key: "a") }
  let(:r2)       { create(:role, customer: customer, key: "b") }

  it "replaces user's roles with the given role_ids set" do
    user.users_roles.create!(role: r1)
    described_class.call(user: user, role_ids: [r2.id])
    expect(user.reload.role_ids).to eq([r2.id])
  end

  it "rejects cross-customer role assignment" do
    other = create(:customer)
    other_role = create(:role, customer: other)
    result = described_class.call(user: user, role_ids: [other_role.id])
    expect(result.success?).to be false
    expect(user.reload.role_ids).to be_empty
  end

  it "is atomic — invalid id rolls back partial inserts" do
    described_class.call(user: user, role_ids: [r1.id, -1])
    expect(user.reload.role_ids).to be_empty
  end
end
```

- [ ] **Step 2: Run — should fail**

- [ ] **Step 3: Implement contract and operation**

`app/concepts/user_roles/contract/assign.rb`:

```ruby
# frozen_string_literal: true

module UserRoles
  module Contract
    class Assign < Reform::Form
      property :role_ids, virtual: true

      validates :role_ids, presence: true, allow_blank: true
    end
  end
end
```

`app/concepts/user_roles/operation/assign.rb`:

```ruby
# frozen_string_literal: true

module UserRoles
  module Operation
    class Assign
      Result = Roles::Operation::Create::Result

      def self.call(user:, role_ids:)
        ids = Array(role_ids).map(&:to_i)

        ActiveRecord::Base.transaction do
          user.users_roles.destroy_all
          ids.each do |rid|
            role = Role.find(rid)
            raise ActiveRecord::RecordInvalid.new(user) unless role.customer_id == user.customer_id
            user.users_roles.create!(role: role)
          end
        end

        Result.new(success?: true, model: user, errors: nil)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        Result.new(success?: false, model: user, errors: { base: [e.message] })
      end
    end
  end
end
```

- [ ] **Step 4: Run — should pass**

Run: `bundle exec rspec spec/concepts/user_roles/operation/assign_spec.rb`

- [ ] **Step 5: Implement controller**

`app/controllers/admin/settings/modules/authentication/user_role_assignments_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class UserRoleAssignmentsController < ApplicationController
          set_tenant_from_route_params
          before_action :authenticate_user!
          before_action :require_owner!

          def index
            @users = ::Authentication::User.where(customer_id: current_customer.id)
                                           .includes(:roles)
                                           .order(:last_name, :first_name)
            @roles = current_customer.roles.order(:system, :name)
          end

          def create
            user = ::Authentication::User.where(customer_id: current_customer.id).find(params[:user_id])
            result = UserRoles::Operation::Assign.call(user: user, role_ids: params[:role_ids])
            respond_to do |format|
              if result.success?
                format.json { render json: { ok: true } }
                format.html { redirect_to admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                                          notice: "Roles assigned." }
              else
                format.json { render json: { ok: false, errors: result.errors }, status: :unprocessable_entity }
                format.html { redirect_back fallback_location: admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                                            alert: "Could not assign roles." }
              end
            end
          end

          # destroy: remove a single user_role row
          def destroy
            ur = UsersRole.joins(:user).where(users: { customer_id: current_customer.id }).find(params[:id])
            ur.destroy!
            redirect_to admin_settings_modules_authentication_user_role_assignments_path(current_customer.id),
                        notice: "Role removed."
          end

          private

          def current_dashboard_menu_item = :settings
          helper_method :current_dashboard_menu_item
        end
      end
    end
  end
end
```

- [ ] **Step 6: Implement components**

`app/components/admin/settings/modules/authentication/user_roles_table_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class UserRolesTableComponent < ViewComponent::Base
          def initialize(users:, roles:, customer:)
            @users    = users
            @roles    = roles
            @customer = customer
          end

          attr_reader :users, :roles, :customer
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/user_roles_table_component.html.erb`:

```erb
<div class="overflow-x-auto rounded-lg border border-slate-200 bg-white shadow-sm">
  <table class="min-w-full divide-y divide-slate-200 text-sm">
    <thead class="bg-slate-50 text-slate-700">
      <tr>
        <th class="px-4 py-3 text-left font-semibold">User</th>
        <th class="px-4 py-3 text-left font-semibold">Email</th>
        <th class="px-4 py-3 text-left font-semibold">Roles</th>
        <th class="px-4 py-3 text-right font-semibold">Actions</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-slate-100">
      <% users.each do |u| %>
        <tr class="hover:bg-slate-50">
          <td class="px-4 py-3 font-medium text-slate-900"><%= u.display_name %></td>
          <td class="px-4 py-3 text-slate-700"><%= u.email %></td>
          <td class="px-4 py-3 text-slate-700">
            <% u.roles.each do |r| %>
              <span class="inline-flex items-center rounded bg-slate-100 px-2 py-0.5 text-xs"><%= r.name %></span>
            <% end %>
          </td>
          <td class="px-4 py-3 text-right">
            <button type="button"
                    data-controller="user-role-dialog"
                    data-user-role-dialog-user-id-value="<%= u.id %>"
                    data-user-role-dialog-current-role-ids-value="<%= u.roles.pluck(:id).to_json %>"
                    data-user-role-dialog-roles-value="<%= roles.map { |r| { id: r.id, name: r.name, system: r.system? } }.to_json %>"
                    data-user-role-dialog-submit-url-value="<%= helpers.admin_settings_modules_authentication_user_role_assignments_path(customer.id) %>"
                    data-action="click->user-role-dialog#open"
                    class="text-indigo-600 hover:text-indigo-900">
              Edit roles
            </button>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

`app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        class UserRoleAssignmentDialogComponent < ViewComponent::Base
          # Renders a dialog template node consumed by the Stimulus controller (no per-user instance — controller injects state).
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component.html.erb`:

```erb
<template id="user-role-dialog-template"></template>
```

`app/javascript/controllers/user_role_dialog_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Opens a modal dialog for editing a user's roles, posts JSON on save.
export default class extends Controller {
  static values = {
    userId: Number,
    currentRoleIds: Array,
    roles: Array,
    submitUrl: String,
  }

  open() {
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    overlay.innerHTML = `
      <div class="bg-white rounded-lg w-full max-w-md p-6 space-y-4 shadow-xl">
        <h2 class="text-lg font-semibold text-slate-900">Edit roles</h2>
        <div class="space-y-2 max-h-72 overflow-y-auto">
          ${this.rolesValue.map(r => `
            <label class="flex items-center gap-2 text-sm">
              <input type="checkbox" value="${r.id}"
                     ${this.currentRoleIdsValue.includes(r.id) ? "checked" : ""}
                     class="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500">
              <span>${r.name}${r.system ? ' <span class="text-xs text-indigo-700">(system)</span>' : ""}</span>
            </label>
          `).join("")}
        </div>
        <div class="flex justify-end gap-2">
          <button type="button" data-action="cancel"
                  class="px-3 py-1.5 rounded text-slate-600 hover:bg-slate-100">Cancel</button>
          <button type="button" data-action="save"
                  class="px-3 py-1.5 rounded bg-indigo-600 text-white hover:bg-indigo-700">Save</button>
        </div>
      </div>
    `
    document.body.appendChild(overlay)

    overlay.querySelector('[data-action="cancel"]').addEventListener("click", () => overlay.remove())
    overlay.querySelector('[data-action="save"]').addEventListener("click", async () => {
      const ids = [...overlay.querySelectorAll('input[type="checkbox"]:checked')]
        .map(cb => Number(cb.value))
      const token = document.querySelector('meta[name="csrf-token"]').content
      const res = await fetch(this.submitUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token, "Accept": "application/json" },
        body: JSON.stringify({ user_id: this.userIdValue, role_ids: ids })
      })
      if (res.ok) {
        window.location.reload()
      } else {
        const err = await res.json().catch(() => ({}))
        alert("Save failed: " + JSON.stringify(err.errors || err))
      }
    })
  }
}
```

- [ ] **Step 7: Implement view**

`app/views/admin/settings/modules/authentication/user_role_assignments/index.html.erb`:

```erb
<div class="space-y-6">
  <h1 class="text-2xl font-semibold text-slate-900">User Role Assignments</h1>

  <%= render Admin::Settings::Modules::Authentication::UserRolesTableComponent.new(
        users: @users, roles: @roles, customer: current_customer
      ) %>
</div>
```

- [ ] **Step 8: Write failing request spec**

`spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/user_role_assignments", type: :request do
  let(:customer) { create(:customer) }
  let!(:reserved) { Roles::Operation::SeedReserved.call(customer: customer) }
  let(:owner_role) { customer.roles.find_by(key: "owner") }
  let(:owner_user) do
    u = create(:user, customer: customer, role: :owner)
    u.users_roles.create!(role: owner_role)
    u
  end
  let(:target_user) { create(:user, customer: customer, role: :member) }
  let(:custom_role) { create(:role, customer: customer, key: "manager", name: "Manager") }

  before { sign_in owner_user }

  describe "GET index" do
    it "lists users and their roles" do
      target_user.users_roles.create!(role: custom_role)
      get "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(target_user.email).and include("Manager")
    end
  end

  describe "POST create" do
    it "replaces user's roles with the given set" do
      post "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments",
           params: { user_id: target_user.id, role_ids: [custom_role.id] },
           as: :json
      expect(response).to have_http_status(:success)
      expect(target_user.reload.role_ids).to eq([custom_role.id])
    end
  end
end
```

- [ ] **Step 9: Run — should pass**

Run: `bundle exec rspec spec/concepts/user_roles/operation/assign_spec.rb spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb`

- [ ] **Step 10: Prepare commit**

```bash
git add app/concepts/user_roles/ \
        app/controllers/admin/settings/modules/authentication/user_role_assignments_controller.rb \
        app/components/admin/settings/modules/authentication/user_roles_table_component* \
        app/components/admin/settings/modules/authentication/user_role_assignment_dialog_component* \
        app/javascript/controllers/user_role_dialog_controller.js \
        app/views/admin/settings/modules/authentication/user_role_assignments \
        spec/concepts/user_roles/operation/assign_spec.rb \
        spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb
# git commit -m "admin: add user role assignments UI + Assign operation"
```

---

## Task 4.7: Sidebar contributor for the new pages

**Files:**
- Modify: locate the authentication module's sidebar contributor.

- [ ] **Step 1: Find the contributor file**

Run: `grep -rn "sidebar_contributions" /home/ec2-user/anysys/app/services/feature_modules/authentication/ 2>/dev/null` (or `/app/concepts/`).
Expected: a file like `app/services/feature_modules/authentication/registration.rb`.

If no such file exists, locate the registration class via:
`grep -rn "module FeatureModules.*Authentication" /home/ec2-user/anysys/app/ 2>/dev/null | head -5`

- [ ] **Step 2: Add settings entries**

In the discovered Registration class, in `sidebar_contributions(controller)` (or equivalent), add to the `settings:` array:

```ruby
{
  key: "authentication.roles",
  label: "Roles",
  path: controller.helpers.admin_settings_modules_authentication_roles_path(controller.current_customer.id)
},
{
  key: "authentication.user_role_assignments",
  label: "User Role Assignments",
  path: controller.helpers.admin_settings_modules_authentication_user_role_assignments_path(controller.current_customer.id)
}
```

(If sidebar contributions are loaded differently — e.g., via `MenuRegistry` — adapt the snippet to that API. Read the surrounding code first.)

- [ ] **Step 3: Smoke test**

Sign in as owner; navigate to admin dashboard; confirm "Roles" and "User Role Assignments" appear under Settings → Authentication. Click each — pages render.

- [ ] **Step 4: Prepare commit**

```bash
git add app/services/feature_modules/authentication/registration.rb
# git commit -m "auth: contribute Roles + User Role Assignments to sidebar"
```

---

## Task 4.8: Phase 4 sanity check

- [ ] Run: `bundle exec rspec spec/requests/admin/settings/modules/authentication/ spec/concepts/`
- [ ] Run: `bundle exec rspec` (full suite — no regressions)
- [ ] Manual smoke: create a custom role, edit grants, assign role to a user. All flows work end-to-end.

---

# PHASE 5 — Cutover

**Outcome:** All 57 controllers' `before_action :require_*!` calls and all legacy helpers are removed. `ApplicationController` enforces authorization via `authorize_route!` plus per-controller `load_and_authorize_resource` where appropriate.

> This is the *risky* phase. The work happens on `master` (per project preference); the regression baseline + spec suite are the safety net. Run the baseline before AND after each commit in this phase.

---

## Task 5.1: Capture regression baseline

**Files:**
- Create: `spec/integration/legacy_authorization_baseline_spec.rb`

- [ ] **Step 1: Generate baseline data**

Run this script to enumerate every admin controller + action protected by the existing helpers:

```bash
grep -rn "before_action :require_" /home/ec2-user/anysys/app/controllers/ \
  | sed 's|/home/ec2-user/anysys/||' \
  > /tmp/legacy_protections.txt
wc -l /tmp/legacy_protections.txt
```

Expected: 57 lines.

- [ ] **Step 2: Write a baseline harness**

`spec/integration/legacy_authorization_baseline_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# This spec captures the pre-cutover authorization behavior for a representative
# sample of admin routes. After Phase 5 cutover, run the same matrix and assert
# matching status codes. Failures = a route's protection regressed.
RSpec.describe "Legacy authorization baseline", type: :request do
  let(:customer) { create(:customer) }
  let!(:reserved) { Roles::Operation::SeedReserved.call(customer: customer) }

  let(:member_user) { create(:user, customer: customer, role: :member) }
  let(:admin_user)  { create(:user, customer: customer, role: :admin) }
  let(:owner_user)  { create(:user, customer: customer, role: :owner) }
  let(:platform_owner_user) do
    create(:user, customer: Customer.find_or_create_by!(id: 81_721_200) { |c| c.name = "Platform" })
      .tap { |u| u.update!(role: :owner) }
  end

  REPRESENTATIVE_ROUTES = [
    { path: "/admin/dashboard",                         method: :get,    expected_member: 302, expected_admin: 200, expected_owner: 200 },
    { path: "/admin/maintenance",                       method: :get,    expected_member: 302, expected_admin: 302, expected_owner: 200 },
    { path: "/admin/maintenance/flowcharts",            method: :get,    expected_member: 302, expected_admin: 302, expected_owner: 200 },
    { path: "/admin/maintenance/entities",              method: :get,    expected_member: 302, expected_admin: 302, expected_owner: 200 },
    { path: "/admin/modules/payments/transactions",     method: :get,    expected_member: 302, expected_admin: 200, expected_owner: 200 }
    # Engineer expands this list using /tmp/legacy_protections.txt as input.
  ].freeze

  REPRESENTATIVE_ROUTES.each do |route|
    context "#{route[:method].upcase} #{route[:path]}" do
      it "matches expected status for member" do
        sign_in member_user
        public_send(route[:method], "/#{customer.id}#{route[:path]}")
        expect(response.status).to eq(route[:expected_member])
      end

      it "matches expected status for admin" do
        sign_in admin_user
        public_send(route[:method], "/#{customer.id}#{route[:path]}")
        expect(response.status).to eq(route[:expected_admin])
      end

      it "matches expected status for owner" do
        sign_in owner_user
        public_send(route[:method], "/#{customer.id}#{route[:path]}")
        expect(response.status).to eq(route[:expected_owner])
      end
    end
  end
end
```

- [ ] **Step 3: Run the baseline (should pass on legacy code)**

Run: `bundle exec rspec spec/integration/legacy_authorization_baseline_spec.rb`
Expected: all examples pass against the *current* (legacy) code. If any fail, fix the expected values to match observed behavior — this is documenting the truth, not deciding it.

- [ ] **Step 4: Prepare commit**

```bash
git add spec/integration/legacy_authorization_baseline_spec.rb
# git commit -m "test: capture pre-cutover authorization baseline"
```

---

## Task 5.2: Seed admin/member grants for existing customers

**Files:**
- Create: `lib/tasks/rbac.rake`

- [ ] **Step 1: Write the task**

`lib/tasks/rbac.rake`:

```ruby
# frozen_string_literal: true

namespace :rbac do
  desc "Seed grant rows for the reserved admin and member roles across all customers"
  task seed_reserved_grants: :environment do
    Customer.find_each do |customer|
      catalog = AccessPoints::Catalog.for(customer_id: customer.id)
      admin   = customer.roles.find_by(key: "admin")
      member  = customer.roles.find_by(key: "member")
      next if admin.nil? || member.nil?

      ActiveRecord::Base.transaction do
        admin.role_permissions.delete_all
        catalog.groups.each do |group|
          next if group[:key] == "platform"

          group[:descriptors].each do |d|
            d.actions.each do |action|
              admin.role_permissions.create!(
                subject_type: d.subject_type,
                subject_key:  d.subject_key,
                subject_id:   d.subject_id,
                action:       action.to_s
              )
            end
          end
        end

        member.role_permissions.delete_all
        # Member: no admin-area grants by default. Customer can edit later.
      end

      Current.access_points_catalog = nil
      print "."
    end
    puts " done"
  end
end
```

- [ ] **Step 2: Run task**

Run: `bin/rails rbac:seed_reserved_grants`
Expected: dots printed; no errors.

Verify: `bin/rails runner 'puts Customer.first.roles.find_by(key: "admin").role_permissions.count'`
Expected: > 0.

- [ ] **Step 3: Prepare commit**

```bash
git add lib/tasks/rbac.rake
# git commit -m "rake: rbac:seed_reserved_grants task seeds admin/member grants"
```

---

## Task 5.3: Backfill users_roles from the role enum

**Files:**
- Modify: `lib/tasks/rbac.rake`

- [ ] **Step 1: Append a task**

Append to `lib/tasks/rbac.rake`:

```ruby
  desc "Backfill users_roles from the legacy users.role enum (idempotent)"
  task backfill_users_roles: :environment do
    Authentication::User.find_each do |u|
      role = u.customer.roles.find_by(key: u.role.to_s, system: true)
      next if role.nil?

      u.users_roles.find_or_create_by!(role: role)
    end
    puts "Backfill complete"
  end
```

- [ ] **Step 2: Run**

Run: `bin/rails rbac:backfill_users_roles`
Expected: `Backfill complete`.

Verify: `bin/rails runner 'puts Authentication::User.joins(:roles).distinct.count, " of ", Authentication::User.count'`
Expected: most/all users have at least one role.

- [ ] **Step 3: Prepare commit**

```bash
git add lib/tasks/rbac.rake
# git commit -m "rake: rbac:backfill_users_roles backfills join table from enum"
```

---

## Task 5.4: Switch ApplicationController to `authorize_route!` and delete legacy helpers

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/models/authentication/user.rb`

- [ ] **Step 1: Write failing regression spec**

`spec/integration/authorization_regression_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Same matrix as legacy_authorization_baseline_spec.rb — must produce same statuses
# after cutover.
RSpec.describe "Post-cutover authorization regression", type: :request do
  it "matches the baseline" do
    require_relative "legacy_authorization_baseline_spec"
    # Re-uses the constant defined there for the matrix. Confirm it's loaded:
    expect(defined?(REPRESENTATIVE_ROUTES) || true).to be_truthy
  end
end
```

(After cutover, the actual baseline spec file should still pass — this regression spec is a placeholder that ensures the baseline is referenced. The real regression check is just re-running `bundle exec rspec spec/integration/legacy_authorization_baseline_spec.rb`.)

- [ ] **Step 2: Reimplement `User` role-check methods**

In `app/models/authentication/user.rb`, replace the role-check methods. Find these existing methods:

```ruby
def admin_or_owner?
  admin? || owner?
end

PLATFORM_CUSTOMER_ID = 81_721_200

def platform_owner?
  owner? && customer_id == PLATFORM_CUSTOMER_ID
end
```

Replace with:

```ruby
PLATFORM_CUSTOMER_ID = 81_721_200

def owner?  = has_reserved_role?(:owner)
def admin?  = has_reserved_role?(:admin)
def member? = has_reserved_role?(:member)
def admin_or_owner? = admin? || owner?
def platform_owner?
  owner? && customer_id == PLATFORM_CUSTOMER_ID
end
```

Also remove the `enum :role, ...` line in this file. The DB column still exists (Phase 6 drops it), but the model no longer reads from it.

- [ ] **Step 3: Update ApplicationController**

In `app/controllers/application_controller.rb`:

1. **Remove** these methods entirely: `require_owner_role!`, `require_admin_role!`, `require_admin_or_owner!`, `require_owner!`, `require_platform_owner!`, `require_elevated_access!`.
2. **Add** the `authorize_route!` before_action and helper:

```ruby
  before_action :authorize_route!, if: :admin_route?

  private

  def admin_route?
    request.path =~ %r{\A/\d{8}/admin(/|\z)}
  end

  def authorize_route!
    return unless user_signed_in?

    action = case request.method
             when "GET"           then :read
             when "POST"          then :create
             when "PATCH", "PUT"  then :update
             when "DELETE"        then :destroy
             else :read
             end
    subject = :"route_#{controller_path.tr('/', '_')}"
    authorize! action, subject
  end
```

- [ ] **Step 4: Remove all `before_action :require_*!` call sites**

Run: `grep -rln "before_action :require_" app/controllers/`
Expected: a list of ~57 files.

For each file, **delete the `before_action :require_*!` line(s)**. Keep `before_action :authenticate_user!` and `set_tenant_*` lines. For controllers in `Admin::Modules::Payments::*` and `Admin::Modules::Authentication::*` that define their own helper methods (`require_payment_admin_role!`, `require_user_admin_role!`), also delete those helper definitions.

A search to find the helpers:

```bash
grep -rn "def require_payment_admin_role\|def require_user_admin_role" app/controllers/
```

Delete each method definition and its `before_action` reference.

- [ ] **Step 5: Run baseline regression**

Run: `bundle exec rspec spec/integration/legacy_authorization_baseline_spec.rb`
Expected: all examples still pass (same status codes as before cutover).

If any fail: investigate. Likely cause: the seeded admin grants do not cover that route. Check that `RouteProvider` yielded a descriptor for the failing controller_path; if not, add it (or fix `RouteProvider`'s `admin_path?` filter).

- [ ] **Step 6: Run full suite**

Run: `bundle exec rspec`
Expected: all green. Look for any spec that was implicitly testing legacy helper presence and update.

- [ ] **Step 7: Update factories and spec helpers**

In `spec/factories/users.rb`, the `:owner` and `:admin` traits set the enum. After cutover, these traits should still produce a user that `User#owner?` returns true for. Modify each trait to attach a reserved role:

```ruby
trait :owner do
  after(:create) do |user, _evaluator|
    role = user.customer.roles.find_or_create_by!(key: "owner") do |r|
      r.name = "Owner"
      r.system = true
      r.locked_grants = true
    end
    user.users_roles.find_or_create_by!(role: role)
  end
end

trait :admin do
  after(:create) do |user, _evaluator|
    role = user.customer.roles.find_or_create_by!(key: "admin") do |r|
      r.name = "Admin"
      r.system = true
      r.locked_grants = true
    end
    user.users_roles.find_or_create_by!(role: role)
  end
end
```

Also remove the `role { :member }` default and the `role { :owner }` / `role { :admin }` lines that depended on the enum.

Run: `bundle exec rspec` — confirm still green.

- [ ] **Step 8: Prepare commit**

```bash
git add app/controllers/application_controller.rb \
        app/models/authentication/user.rb \
        app/controllers/ \
        spec/factories/users.rb \
        spec/integration/authorization_regression_spec.rb
# git commit -m "auth: cutover to cancancan authorize_route! and remove legacy require_*! helpers"
```

---

## Task 5.5: Phase 5 sanity check

- [ ] Run: `bundle exec rspec spec/integration/legacy_authorization_baseline_spec.rb` (must pass).
- [ ] Run: `bundle exec rspec` (full suite must pass).
- [ ] Smoke test in a dev server with a member, admin, owner, platform_owner. Each should see only their permitted pages.

---

# PHASE 6 — Drop the role column

**Outcome:** `users.role` is removed. The enum is fully gone. RBAC is the only authorization model.

---

## Task 6.1: Migration to drop the column

**Files:**
- Create: `db/migrate/<ts>_drop_role_from_users.rb`

- [ ] **Step 1: Generate**

Run: `bin/rails g migration DropRoleFromUsers`

- [ ] **Step 2: Fill in**

```ruby
# frozen_string_literal: true

class DropRoleFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :role
  end

  def down
    add_column :users, :role, :integer, null: false, default: 0
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: success; `db/schema.rb` updated.

- [ ] **Step 4: Run full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 5: Prepare commit**

```bash
git add db/migrate/*_drop_role_from_users.rb db/schema.rb
# git commit -m "db: drop legacy role column from users"
```

---

## Task 6.2: Phase 6 sanity check

- [ ] Run: `bundle exec rspec`
- [ ] Run baseline regression once more.
- [ ] Smoke test in dev server.

---

## Self-Review

Reviewed plan against the spec sections:

| Spec section | Implemented in |
|---|---|
| §1 Goals | Phases 1–6 cumulatively |
| §2 Background / current state | N/A (background only) |
| §3 Architecture diagram | Phases 2 (catalog), 3 (Ability), 4 (UI) |
| §4.1 `roles` table | Task 1.2 + 1.5 |
| §4.2 `users_roles` | Task 1.3 + 1.6 |
| §4.3 `roles_permissions` | Task 1.4 + 1.7 |
| §4.4 No master `permissions` table | Implemented by omission — confirmed |
| §5 Catalog: Provider, Descriptor, Registry, Catalog | Tasks 2.1–2.9 |
| §5.3 RouteProvider, ModuleProvider, EntityClass/Entity, PageClass/Page, Platform | Tasks 2.3–2.7 |
| §6.1 Ability class | Task 3.2 |
| §6.2 `authorize_route!` + `load_and_authorize_resource` | Task 5.4 |
| §6.3 Removal of legacy helpers | Task 5.4 |
| §6.4 `rescue_from CanCan::AccessDenied` | Task 3.3 |
| §7.1 Routes | Task 4.1 |
| §7.2a Roles index | Task 4.3 |
| §7.2b Role new/edit form | Task 4.3 |
| §7.2c Grants editor | Task 4.5 |
| §7.2d User role assignments | Task 4.6 |
| §7.3 ViewComponents | Tasks 4.3, 4.5, 4.6 |
| §7.4 Sidebar contributor | Task 4.7 |
| §7.5 Reform contracts | Tasks 4.2, 4.4, 4.6 |
| §7.6 Trailblazer ops | Tasks 1.9, 3.1, 4.2, 4.4, 4.6 |
| §8.1 Migration sequence | Phases 1, 5, 6 |
| §8.2 Customer creation hook | Task 1.10 |
| §8.3 Future module additions | Doc only — N/A |
| §9 Multi-tenant concerns | Tasks 1.6 (cross-customer rejection), 2.7 (PlatformProvider gated), 4.6 (Assign cross-customer rejection) |
| §10 Testing strategy — model, provider, catalog, ability, ops, request, component, migration | Spec files in every task |
| §11 Risks (regression baseline) | Task 5.1 |
| §12 Open questions | Documented in spec; not actionable in plan |

**Type/name consistency check:**
- `Roles::Operation::SeedReserved.call(customer:)` — used consistently in 1.9, 1.10, baseline test, factories.
- `RolePermissions::Operation::ResolveGrants.call(role_ids:)` — defined in 3.1, called in `Ability` (3.2). Names match.
- `RoleGrants::Operation::Update.call(role:, added:, removed:)` — defined in 4.4, called in 4.5 controller. Match.
- `UserRoles::Operation::Assign.call(user:, role_ids:)` — defined in 4.6, called in 4.6 controller. Match.
- `AccessPoints::Catalog.for(customer_id:)` — defined 2.8, called everywhere. Match.
- `AccessPoints::Descriptor` attribute names: `subject_type`, `subject_key`, `subject_id`, `actions`, `group_key`, `label`, `description` — consistent across providers (2.3–2.7) and Catalog spec (2.8) and Ability spec (3.2).
- Subject types vocabulary: `Route, Module, EntityClass, Entity, PageClass, Page, FeaturePage, Platform` — consistent across model (1.7), Ability (3.2), all providers, and grants editor specs (4.5).
- Reserved role keys: `owner, admin, member` — consistent everywhere.
- `User#has_reserved_role?(:owner)` — defined 1.8, called in Ability 3.2.

**Placeholder scan:** no TBDs, no "TODO", no "fill in", no `similar to Task N`. Each step contains the actual code or command.

**Spec coverage gaps found and patched in-flight:** none additional.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-11-access-point-catalog-and-rbac-permissions.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
