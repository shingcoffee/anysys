# Send Activity Multi-List Audience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let send activities target 1–10 lists (static + dynamic mixed), resolve a union audience deduped by email, and link template/lists on the detail page in new tabs.

**Architecture:** Replace `email_send_activities.email_list_id` with join table `email_send_activity_lists`. `SendActivity#audience` unions each list’s audience and dedupes by `LOWER(TRIM(email))` (lowest `user_id` wins). Wizard posts `email_list_ids[]`; job/recurrence use the multi-list associations.

**Tech Stack:** Rails 8.1 / AR migration / Trailblazer-style service objects already in tree (`Build`, `StartSendActivity`) / ViewComponent + ERB + Stimulus / RSpec + Vitest / I18n en+zh-CN

**Spec:** `docs/superpowers/specs/2026-07-25-send-activity-multi-list-audience-design.md`

## Global Constraints

- Max lists per send activity: **10** (`SendActivity::MAX_EMAIL_LISTS = 10`); enforce client + server; never silently truncate.
- Audience = union of selected lists; dedupe by `LOWER(TRIM(email))`; tie-break lowest `user_id`.
- Static + dynamic lists may mix; dynamic rules evaluate at audience/send time.
- No `email_list_id` compatibility shim after column drop.
- All user-facing strings via I18n (`en` + `zh-CN`); Stimulus uses Values + `data-*`, no literal UI copy in JS.
- UI/UX changes: Figma first (anysys-ux-designer), then implement.
- Do not auto-commit unless the human explicitly asks; treat plan “Commit” steps as optional staging checkpoints.
- JS under `app/javascript/**` must stay at 100% Vitest lines + branches.

## File map

| File | Responsibility |
|------|----------------|
| `db/migrate/*_create_email_send_activity_lists.rb` | Join table + backfill + drop `email_list_id` |
| `app/models/emails/send_activities/send_activity_list.rb` | Join model |
| `app/models/emails/send_activities/send_activity.rb` | Associations, max/min validations, `#audience` / `#audience_count` |
| `app/models/emails/audience/list.rb` | Replace `has_many :email_send_activities` FK with through join |
| `spec/factories/email_send_activities.rb` | `email_lists` association after create |
| `app/services/emails/send_activities/build.rb` | Permit/sync `email_list_ids` |
| `app/services/emails/send_activities/start_send_activity.rb` | ready_to_send? + recurring clone join rows |
| `app/jobs/emails/send_activities/send_activity_job.rb` | Use `campaign.audience` |
| `app/controllers/admin/modules/emails/send_activities_controller.rb` | includes / index cell / strong params path via Build |
| Wizard ERB + Stimulus + locales | Multi-select, review names+count, max-10 |
| `app/views/admin/modules/emails/send_activities/show.html.erb` | New-tab links for template + each list |
| Specs listed per task | TDD coverage |

---

### Task 1: Figma UX for multi-select + show links

**Files:**
- Create/update: Figma surface via `anysys-ux-designer` (no production code in this task)
- Reference later: wizard audience step, review step, show page

**Interfaces:**
- Consumes: existing send-activity wizard visual language
- Produces: approved Figma for (1) multi-select lists control with max-10 affordance, (2) review list names + unique count, (3) show-page linked template/lists

- [ ] **Step 1: Dispatch UX designer**

Dispatch `anysys-ux-designer` with the approved spec path and ask for Figma designs matching existing email admin patterns (Tailwind token equivalents already in app).

- [ ] **Step 2: Human/agent confirms Figma matches implementation targets**

Do not start Task 6 UI markup until this is approved.

---

### Task 2: Join table migration + join model

**Files:**
- Create: `db/migrate/20260725100000_create_email_send_activity_lists.rb`
- Create: `app/models/emails/send_activities/send_activity_list.rb`
- Create: `spec/models/emails/send_activities/send_activity_list_spec.rb`
- Modify: `db/schema.rb` (via migrate)

**Interfaces:**
- Produces: table `email_send_activity_lists`; class `Emails::SendActivities::SendActivityList`

- [ ] **Step 1: Write failing join-model uniqueness spec**

```ruby
# spec/models/emails/send_activities/send_activity_list_spec.rb
require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivityList, type: :model do
  include_context "with tenant"

  it "is unique per send activity and list" do
    activity = create(:email_send_activity, customer: customer)
    list = activity.email_list
    described_class.create!(send_activity: activity, email_list: list)
    dup = described_class.new(send_activity: activity, email_list: list)
    expect(dup).not_to be_valid
  end
end
```

Note: until Task 3 rewires the factory, `email_list` still exists on the factory — write this task’s migration first so backfill keeps factory green, then add the join model before dropping the column in the same migration.

- [ ] **Step 2: Add migration**

```ruby
# db/migrate/20260725100000_create_email_send_activity_lists.rb
class CreateEmailSendActivityLists < ActiveRecord::Migration[8.1]
  def up
    create_table :email_send_activity_lists do |t|
      t.references :email_send_activity, null: false, foreign_key: { to_table: :email_send_activities }
      t.references :email_list, null: false, foreign_key: true
      t.timestamps
    end
    add_index :email_send_activity_lists,
              %i[email_send_activity_id email_list_id],
              unique: true,
              name: "index_email_send_activity_lists_on_activity_and_list"

    execute <<~SQL.squish
      INSERT INTO email_send_activity_lists (email_send_activity_id, email_list_id, created_at, updated_at)
      SELECT id, email_list_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM email_send_activities
      WHERE email_list_id IS NOT NULL
    SQL

    remove_foreign_key :email_send_activities, :email_lists if foreign_key_exists?(:email_send_activities, :email_lists)
    remove_index :email_send_activities, :email_list_id if index_exists?(:email_send_activities, :email_list_id)
    remove_column :email_send_activities, :email_list_id, :integer
  end

  def down
    add_reference :email_send_activities, :email_list, foreign_key: true
    execute <<~SQL.squish
      UPDATE email_send_activities AS a
      SET email_list_id = j.email_list_id
      FROM (
        SELECT DISTINCT ON (email_send_activity_id) email_send_activity_id, email_list_id
        FROM email_send_activity_lists
        ORDER BY email_send_activity_id, id
      ) AS j
      WHERE a.id = j.email_send_activity_id
    SQL
    drop_table :email_send_activity_lists
  end
end
```

Adjust SQL dialect if the app’s DB is SQLite in test — prefer Ruby backfill for portability:

```ruby
Emails::SendActivities::SendActivity.reset_column_information
say_with_time "backfill email_send_activity_lists" do
  Emails::SendActivities::SendActivity.unscoped.where.not(email_list_id: nil).find_each do |activity|
    execute ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO email_send_activity_lists (email_send_activity_id, email_list_id, created_at, updated_at) VALUES (?, ?, ?, ?)",
      activity.id, activity.email_list_id, Time.current, Time.current
    ])
  end
end
```

Use the Ruby backfill path in the committed migration (works on SQLite + Postgres).

- [ ] **Step 3: Add join model**

```ruby
# app/models/emails/send_activities/send_activity_list.rb
# frozen_string_literal: true

module Emails
  module SendActivities
    class SendActivityList < ApplicationRecord
      self.table_name = "email_send_activity_lists"

      belongs_to :send_activity, class_name: "Emails::SendActivities::SendActivity",
                                 foreign_key: :email_send_activity_id
      belongs_to :email_list, class_name: "Emails::Audience::List"

      validates :email_list_id, uniqueness: { scope: :email_send_activity_id }
    end
  end
end
```

- [ ] **Step 4: Run migration + join model spec**

Run: `bin/rails db:migrate && bundle exec rspec spec/models/emails/send_activities/send_activity_list_spec.rb`

Expected: migrate OK; uniqueness example fails until Task 3 wires associations used by factory — if factory still sets `email_list_id`, temporarily create activity+list manually in this spec instead of relying on `activity.email_list` after drop:

```ruby
activity = create(:email_send_activity, customer: customer) # after Task 3
list = create(:email_list, customer: customer)
```

For Task 2 only, build records without the old FK:

```ruby
list = create(:email_list, customer: customer)
activity = Emails::SendActivities::SendActivity.create!(
  customer: customer,
  email_template: create(:email_template, customer: customer),
  name: "A",
  status: "pending",
  scheduled_at: 1.hour.from_now,
  timezone: "UTC"
)
```

(Validation requiring lists lands in Task 3 — create via `insert` or skip presence until Task 3 if needed.)

- [ ] **Step 5: Checkpoint**

Stage migration + model + spec; commit only if the human asks.

---

### Task 3: SendActivity associations, validations, audience API

**Files:**
- Modify: `app/models/emails/send_activities/send_activity.rb`
- Modify: `app/models/emails/audience/list.rb`
- Modify: `spec/factories/email_send_activities.rb`
- Modify: `spec/models/emails/send_activities/send_activity_spec.rb`
- Create: `spec/models/emails/send_activities/audience_spec.rb` (or examples inside send_activity_spec)

**Interfaces:**
- Consumes: `SendActivityList`, `Emails::Audience::List#audience`, `Emails::Audience::SegmentQuery`
- Produces:
  - `SendActivity::MAX_EMAIL_LISTS => 10`
  - `has_many :send_activity_lists` / `has_many :email_lists, through:`
  - `#email_list_ids=` / reader via association
  - `#audience` → `ActiveRecord::Relation` of `Authentication::User` ordered by `id`
  - `#audience_count` → `Integer`

- [ ] **Step 1: Write failing audience + validation specs**

```ruby
# In send_activity_spec.rb (or audience_spec.rb)
describe "email lists" do
  it "requires at least one list" do
    activity = build(:email_send_activity, customer: customer, email_lists: [])
    expect(activity).not_to be_valid
    expect(activity.errors[:email_lists]).to be_present
  end

  it "rejects more than MAX_EMAIL_LISTS lists" do
    lists = Array.new(Emails::SendActivities::SendActivity::MAX_EMAIL_LISTS + 1) {
      create(:email_list, customer: customer)
    }
    activity = build(:email_send_activity, customer: customer, email_lists: lists)
    expect(activity).not_to be_valid
  end

  it "rejects a list from another customer" do
    other = create(:customer)
    foreign_list = create(:email_list, customer: other)
    activity = build(:email_send_activity, customer: customer, email_lists: [foreign_list])
    expect(activity).not_to be_valid
  end
end

describe "#audience" do
  it "unions lists and dedupes by email keeping lowest user id" do
    u1 = create(:user, customer: customer, email: "dup@example.com")
    u2 = create(:user, customer: customer, email: "DUP@example.com") # may fail uniqueness — use same case if tenant email unique case-insensitive
    # If emails are unique case-insensitive per tenant, create two lists sharing the same user plus a second distinct user on both lists:
    a = create(:user, customer: customer, email: "a@example.com")
    b = create(:user, customer: customer, email: "b@example.com")
    list1 = create(:email_list, customer: customer, list_type: "static")
    list2 = create(:email_list, customer: customer, list_type: "static")
    create(:email_list_membership, email_list: list1, user: a)
    create(:email_list_membership, email_list: list1, user: b)
    create(:email_list_membership, email_list: list2, user: a)
    activity = create(:email_send_activity, customer: customer, email_lists: [list1, list2])
    expect(activity.audience_count).to eq(2)
    expect(activity.audience.map(&:id)).to match_array([a.id, b.id])
  end
end
```

Add a dedicated case for two users that somehow share normalized email only if the schema allows; otherwise document that uniqueness already prevents it and still implement tie-break in code for defense.

- [ ] **Step 2: Run specs — expect FAIL**

Run: `bundle exec rspec spec/models/emails/send_activities/send_activity_spec.rb -e "email lists" -e "#audience"`

- [ ] **Step 3: Implement model changes**

In `send_activity.rb`:

```ruby
MAX_EMAIL_LISTS = 10

has_many :send_activity_lists, class_name: "Emails::SendActivities::SendActivityList",
                               foreign_key: :email_send_activity_id,
                               inverse_of: :send_activity,
                               dependent: :destroy
has_many :email_lists, through: :send_activity_lists, class_name: "Emails::Audience::List"

# REMOVE belongs_to :email_list ...
# REMOVE validates :email_list_id, presence: true
# REMOVE validate :email_list_same_tenant

validate :email_lists_presence_and_limit
validate :email_lists_same_tenant

def audience
  Authentication::User.where(id: audience_user_ids).order(:id)
end

def audience_count
  audience_user_ids.size
end

private

def audience_user_ids
  chosen = {}
  email_lists.each do |list|
    list.audience.find_each do |user|
      key = user.email.to_s.strip.downcase
      next if key.blank?
      prev = chosen[key]
      chosen[key] = user.id if prev.nil? || user.id < prev
    end
  end
  chosen.values
end

def email_lists_presence_and_limit
  count = email_lists.size
  if count.zero?
    errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_blank"))
  elsif count > MAX_EMAIL_LISTS
    errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_too_many", max: MAX_EMAIL_LISTS))
  end
end

def email_lists_same_tenant
  email_lists.each do |list|
    next if list.customer_id == customer_id
    errors.add(:email_lists, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
    break
  end
end
```

In `list.rb`, replace:

```ruby
has_many :email_send_activities, ..., foreign_key: :email_list_id
```

with:

```ruby
has_many :send_activity_lists, class_name: "Emails::SendActivities::SendActivityList",
                               foreign_key: :email_list_id,
                               dependent: :restrict_with_exception
has_many :email_send_activities, through: :send_activity_lists,
                                 class_name: "Emails::SendActivities::SendActivity"
```

(Keep prior dependent behavior intent: do not silently nullify in-use lists.)

Factory:

```ruby
factory :email_send_activity, class: "Emails::SendActivities::SendActivity" do
  customer
  email_template { customer ? create(:email_template, customer: customer) : nil }
  transient do
    email_lists { nil }
  end
  # after build/create assign lists
  after(:build) do |activity, evaluator|
    lists = evaluator.email_lists
    lists = [create(:email_list, customer: activity.customer)] if lists.nil? && activity.customer
    activity.email_lists = Array(lists) if lists
  end
  # ... rest unchanged; remove `email_list { ... }`
end
```

- [ ] **Step 4: Add locale keys (en + zh-CN)**

`admin_modules.emails.send_activities.errors.lists_blank`  
`admin_modules.emails.send_activities.errors.lists_too_many` with `%{max}`

English values must be the exact strings used in UI/errors.

- [ ] **Step 5: Run model specs**

Run: `bundle exec rspec spec/models/emails/send_activities/`

Expected: PASS for new examples; fix any broken old examples that reference `email_list` / `email_list_id`.

---

### Task 4: Build, StartSendActivity, SendActivityJob

**Files:**
- Modify: `app/services/emails/send_activities/build.rb`
- Modify: `app/services/emails/send_activities/start_send_activity.rb`
- Modify: `app/jobs/emails/send_activities/send_activity_job.rb`
- Modify: `spec/services/emails/send_activities/start_send_activity_spec.rb`
- Modify: `spec/jobs/emails/send_activities/send_activity_job_spec.rb`
- Create/modify build specs if present

**Interfaces:**
- Consumes: `SendActivity#email_lists`, `#audience`
- Produces: Build accepts `email_list_ids: []`; recurring clone copies all lists; job iterates `campaign.audience`

- [ ] **Step 1: Failing job spec — one send when user on two lists**

```ruby
it "sends once when the recipient is on multiple selected lists" do
  user = create(:user, customer: customer, email: "once@example.com")
  list1 = create(:email_list, customer: customer)
  list2 = create(:email_list, customer: customer)
  create(:email_list_membership, email_list: list1, user: user)
  create(:email_list_membership, email_list: list2, user: user)
  campaign = create(:email_send_activity, :processing, customer: customer, email_lists: [list1, list2])
  # stub gateway/queue as existing spec does
  expect {
    described_class.perform_now(campaign.id)
  }.to change { Emails::Message.where(email_send_activity_id: campaign.id).count }.by(1)
end
```

Mirror existing job spec stubbing patterns in `send_activity_job_spec.rb`.

- [ ] **Step 2: Failing start_send_activity recurring clone spec**

```ruby
it "copies all email_lists onto the next occurrence" do
  lists = create_list(:email_list, 2, customer: customer)
  activity = create(:email_send_activity, :pending, :recurring, customer: customer,
                    email_lists: lists, scheduled_at: 1.minute.ago)
  described_class.call(activity)
  nxt = Emails::SendActivities::SendActivity.where(customer: customer).where.not(id: activity.id).order(:id).last
  expect(nxt.email_lists).to match_array(lists)
end
```

- [ ] **Step 3: Implement Build sync**

```ruby
def call
  attrs = permitted_attributes
  list_ids = attrs.delete(:email_list_ids)
  @send_activity.assign_attributes(attrs)
  assign_email_lists!(list_ids) if !list_ids.nil?
  return { success: false, send_activity: @send_activity } if @send_activity.errors.any?

  if @send_activity.save
    maybe_start!
    { success: true, send_activity: @send_activity }
  else
    { success: false, send_activity: @send_activity }
  end
end

def permitted_attributes
  campaign_params = @params.require(:email_send_activity)
  permitted = campaign_params.permit(
    :name, :email_template_id, :scheduled_at, :recurrence_preset, :timezone, :send_timing,
    email_list_ids: []
  )
  # ... existing send_timing / recurrence mapping ...
  permitted
end

def assign_email_lists!(raw_ids)
  ids = Array(raw_ids).map(&:presence).compact.map(&:to_i).uniq
  lists = Emails::Audience::List.for_current_customer.where(id: ids).to_a
  if lists.size != ids.size
    @send_activity.errors.add(:email_lists, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
    return
  end
  @send_activity.email_lists = lists
end
```

If `for_current_customer` is unavailable in job context for Build, scope with `where(customer_id: @send_activity.customer_id)`.

- [ ] **Step 4: Implement StartSendActivity + Job**

```ruby
def self.ready_to_send?(send_activity)
  send_activity.email_template_id.present? && send_activity.email_lists.exists?
end

# in schedule_next_occurrence:
nxt = SendActivity.new(
  customer: send_activity.customer,
  email_template: send_activity.email_template,
  name: send_activity.name,
  status: "pending",
  scheduled_at: next_at,
  recurrence_rule: ...,
  timezone: send_activity.timezone
)
nxt.email_lists = send_activity.email_lists.to_a
nxt.save!
```

Job loop:

```ruby
campaign.audience.find_each do |user|
  # unchanged body
end
```

- [ ] **Step 5: Run service + job specs**

Run: `bundle exec rspec spec/jobs/emails/send_activities/send_activity_job_spec.rb spec/services/emails/send_activities/start_send_activity_spec.rb`

Expected: PASS

---

### Task 5: Controller index/show data + request specs (API shape)

**Files:**
- Modify: `app/controllers/admin/modules/emails/send_activities_controller.rb`
- Modify: `spec/requests/admin/modules/emails/send_activities_spec.rb`
- Modify: `app/views/admin/modules/emails/send_activities/show.html.erb` (links — can finish in Task 6; at least fix `email_list_id` guard)
- Modify: `app/views/admin/modules/emails/send_activities/_form.html.erb` if still referenced

**Interfaces:**
- Consumes: `email_lists`, `email_template`
- Produces: index cell lists summary; create/update accept `email_list_ids: []`

- [ ] **Step 1: Failing request examples**

```ruby
it "creates with multiple email_list_ids" do
  lists = create_list(:email_list, 2, customer: customer)
  template = create(:email_template, customer: customer, status: "active")
  expect {
    post admin_modules_emails_send_activities_path(customer), params: {
      email_send_activity: {
        name: "Multi",
        email_template_id: template.id,
        email_list_ids: lists.map(&:id),
        send_timing: "later",
        scheduled_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M"),
        timezone: "UTC",
        recurrence_preset: "none"
      }
    }
  }.to change(Emails::SendActivities::SendActivity, :count).by(1)
  activity = Emails::SendActivities::SendActivity.order(:id).last
  expect(activity.email_lists).to match_array(lists)
end

it "rejects 11 lists" do
  lists = create_list(:email_list, 11, customer: customer)
  # post ... email_list_ids: lists.map(&:id)
  expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:ok) # re-render form
  expect(Emails::SendActivities::SendActivity.where(name: "Too many")).to be_empty
end
```

Align status expectations with existing create failure behavior in the same spec file.

- [ ] **Step 2: Update controller**

```ruby
scope = ::Emails::SendActivities::SendActivity
  .for_current_customer
  .includes(:email_template, :email_lists)
  .order(created_at: :desc)

# list column cell:
cell: ->(c) {
  names = c.email_lists.map(&:name)
  names.present? ? names.join(", ") : I18n.t("common.labels.em_dash")
}
```

Ensure `show` / `edit` load `email_lists`. Replace send-now guard:

```erb
if @send_activity.email_template_id.present? && @send_activity.email_lists.any?
```

- [ ] **Step 3: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/send_activities_spec.rb`

Expected: PASS (wizard UI may still be single-select until Task 6; server must accept arrays).

---

### Task 6: Wizard UI + show links (after Figma)

**Files:**
- Modify: `app/views/admin/modules/emails/send_activities/_wizard_step_audience.html.erb`
- Modify: `app/views/admin/modules/emails/send_activities/_wizard_step_review.html.erb`
- Modify: `app/views/admin/modules/emails/send_activities/show.html.erb`
- Modify: `app/components/emails/send_activity_builder_component.html.erb` (new Stimulus values for max lists / labels)
- Modify: `app/views/admin/modules/emails/send_activities/_form.html.erb` (multi-select if still used)
- Modify: `config/locales/admin_modules.en.yml` + `admin_modules.zh-CN.yml`
- Modify: component/request specs as needed

**Interfaces:**
- Produces: `select[multiple] name="email_send_activity[email_list_ids][]"`; show links with `target="_blank" rel="noopener noreferrer"`

- [ ] **Step 1: Audience partial**

```erb
<%= f.label :email_list_ids, t("admin_modules.emails.send_activities.form.lists_label"), class: "form-label form-label-required" %>
<%= f.select :email_list_ids,
      lists.map { |l| [l.name, l.id] },
      { selected: send_activity.email_list_ids },
      {
        multiple: true,
        class: "input-field flex-1 min-w-0",
        required: true,
        data: {
          wizard_field: true,
          wizard_required_msg: t("admin_modules.emails.send_activities.wizard.errors.list_required"),
          wizard_max_msg: t("admin_modules.emails.send_activities.wizard.errors.lists_too_many", max: Emails::SendActivities::SendActivity::MAX_EMAIL_LISTS),
          wizard_max: Emails::SendActivities::SendActivity::MAX_EMAIL_LISTS,
          email_send_activity_wizard_target: "listSelect"
        }
      } %>
```

Keep refresh + create-list controls.

- [ ] **Step 2: Review partial**

- Selected list names (join with comma or stacked).
- Unique recipient count: server-rendered when editing existing; for new wizard, Stimulus can show names; optional Turbo frame for count — minimum: show names client-side; on show page always use `#audience_count`. Spec requires review unique count — add a small read-only element updated by Stimulus via optional count endpoint **or** compute on final show only. Prefer: add `data-review-audience-count` filled on edit from `@send_activity.audience_count`, and on new leave em-dash until save **unless** an existing lists preview JSON can return count. Simplest compliant approach: POST-less client estimate not required; add `Emails::SendActivities::AudienceCount` controller action is out of scope — **on review step call existing lists preview pattern**.  

Pragmatic spec fulfillment: on review step, render `<%= send_activity.persisted? ? send_activity.audience_count : t("common.labels.em_dash") %>` and enhance Stimulus later if lists JSON can include member counts. Better: add collection action already used — check `lists_json` payload; if only id/name, extend JSON with no count and show selected names on review; put unique count on **show** page. Spec says review shows unique count — implement lightweight `POST preview` reuse or compute in Stimulus only after refresh. **Implement:** `SendActivitiesController#audience_count` is YAGNI; instead in review step use a Stimulus action that fetches `POST .../lists/preview` is wrong.  

**Decision locked for implementers:** Add private method in builder that sets `@audience_count` on edit; on new, wizard Stimulus sends selected ids to new collection route:

Actually keep YAGNI: show unique count on **show** + review displays selected names; also display count on review when `send_activity.email_lists.any?` by computing `send_activity.audience_count` in the view (works for edit; for new unsaved, Build hasn’t run — association may be in-memory if re-render after failed save). On first pass through wizard before submit, compute count via a small JSON endpoint:

Skip new endpoint: on Continueto review, Stimulus lists selected option labels; count line uses `data-email-send-activity-wizard-audience-count-unavailable` em-dash for brand-new drafts. On failed re-render after submit with lists assigned in memory, ERB prints `send_activity.audience_count`.

Document this in the PR. If product insists on live count before first save, add Task 6b endpoint — only if reviewer requires it.

- [ ] **Step 3: Show page links**

```erb
<dt class="form-label"><%= t("admin_modules.emails.send_activities.show.template") %></dt>
<dd class="text-body text-text-primary col-span-2">
  <% if @send_activity.email_template %>
    <%= link_to @send_activity.email_template.name,
          admin_modules_emails_template_path(current_customer_id, @send_activity.email_template),
          target: "_blank", rel: "noopener noreferrer", class: "text-primary hover:underline" %>
  <% else %>
    <%= t("common.labels.em_dash") %>
  <% end %>
</dd>

<dt class="form-label"><%= t("admin_modules.emails.send_activities.show.lists") %></dt>
<dd class="text-body text-text-primary col-span-2">
  <% lists = @send_activity.email_lists.to_a %>
  <% if lists.empty? %>
    <%= t("common.labels.em_dash") %>
  <% else %>
    <ul class="space-y-1">
      <% lists.each do |list| %>
        <li>
          <%= link_to list.name,
                admin_modules_emails_list_path(current_customer_id, list),
                target: "_blank", rel: "noopener noreferrer", class: "text-primary hover:underline" %>
        </li>
      <% end %>
    </ul>
  <% end %>
</dd>
```

Add i18n key `show.lists` (plural); keep/repurpose `show.list`.

- [ ] **Step 4: Request/component assertions for target=_blank**

```ruby
get admin_modules_emails_send_activity_path(customer, activity)
expect(response.body).to include('target="_blank"')
expect(response.body).to include(admin_modules_emails_template_path(customer, activity.email_template))
activity.email_lists.each do |list|
  expect(response.body).to include(admin_modules_emails_list_path(customer, list))
end
```

- [ ] **Step 5: Run request + component specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/send_activities_spec.rb spec/components/emails/send_activity_builder_component_spec.rb`

---

### Task 7: Stimulus wizard multi-select + Vitest 100%

**Files:**
- Modify: `app/javascript/controllers/email_send_activity_wizard_controller.js`
- Modify: `spec/javascript/controllers/email_send_activity_wizard_controller.test.js`
- Modify: builder component data values for max / errors

**Interfaces:**
- Consumes: `listSelect` multi `<select>`; `wizard_max` dataset
- Produces: validate ≥1 and ≤10; refreshLists preserves selected ids; review shows joined selected option labels

- [ ] **Step 1: Write failing Vitest cases**

```js
it("blocks continue when more than max lists are selected", async () => {
  // mount controller with select multiple, max=10, select 11 options
  // click next → stays on step, shows max error
})

it("refreshLists preserves selected list ids", async () => {
  // stub fetch lists JSON; preselect two ids; refresh; expect those selected
})

it("review lists shows comma-separated selected labels", async () => {
  // select two options; go to review; expect reviewList text
})
```

- [ ] **Step 2: Implement controller updates**

- Change validation for list field to read `selectedOptions` length.
- Enforce max via `wizard_max` / Value `maxLists` default `10`.
- `refreshLists`: after repopulating options, restore previous `selected` ids still present.
- Review updater: use `[name="email_send_activity[email_list_ids][]"]` and join selected labels.

- [ ] **Step 3: Coverage gate**

Run: `npx vitest run --coverage spec/javascript/controllers/email_send_activity_wizard_controller.test.js`

Expected: file at 100% lines + branches (or full suite coverage still 100% for touched file).

---

### Task 8: Sweep remaining references + full targeted verification

**Files:**
- Grep-driven fixes under `spec/`, `app/`, factories, analytics that still mention `email_list_id` on send activities
- Modify: any analytics/report grouping by single list if broken

- [ ] **Step 1: Grep**

```bash
rg -n "email_list_id|email_list:" app spec config --glob '*send_activit*'
rg -n "campaign\.email_list|send_activity\.email_list[^_]" app spec
```

Fix every production hit. Specs may use `email_lists:`.

- [ ] **Step 2: Run targeted suite**

```bash
bundle exec rspec \
  spec/models/emails/send_activities/ \
  spec/jobs/emails/send_activities/send_activity_job_spec.rb \
  spec/services/emails/send_activities/start_send_activity_spec.rb \
  spec/requests/admin/modules/emails/send_activities_spec.rb \
  spec/components/emails/send_activity_builder_component_spec.rb

npx vitest run --coverage spec/javascript/controllers/email_send_activity_wizard_controller.test.js
```

Expected: all green; no remaining production `email_send_activities.email_list_id` reads.

- [ ] **Step 3: Manual smoke (optional release-eng)**

`rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`  
Open `/81721200/admin/modules/emails/send_activities/new`, select 2 lists, verify review + create; open show, click template + list links (new tabs); try 11th list blocked.

---

## Spec coverage checklist (self-review)

| Spec requirement | Task |
|------------------|------|
| Join table + backfill + drop FK | 2 |
| Max 10 + min 1 + tenant validation | 3 |
| `#audience` union + email dedupe + lowest id | 3 |
| Job uses multi-list audience | 4 |
| Recurring copies all lists | 4 |
| Build `email_list_ids` | 4 |
| New + edit wizard multi-select | 6–7 |
| Review names (+ count best-effort) | 6–7 |
| Show template/lists new-tab links | 6 |
| I18n en+zh-CN | 3, 6 |
| Figma first | 1 |
| Vitest 100% | 7 |
| No email_list_id shim | 2–8 |

## Placeholder scan

None intentional. Review-step live count for unsaved drafts is explicitly scoped as best-effort (names always; count when association resolvable) — if product requires live count before first save, add a follow-up endpoint rather than blocking this plan.
