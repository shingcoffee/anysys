# Email Module Phase 7 — Settings: Streams UI, Suppressions, Preference Center

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phases 1–6.

**Goal:** Complete the settings area with message stream management, enhanced suppressions, and a preference center with topic-level unsubscribe.

**Architecture:** `Emails::Stream` CRUD under Settings. Suppressions moved to settings with filters/bulk actions. `Emails::PreferenceTopic` defines topics; public preference center lets users manage subscriptions.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec.

## Global Constraints

- All user-facing strings I18n in `en` and `zh-CN`.
- TailwindCSS only; StimulusJS only.
- Admin routes require admin/owner; public preference center is token-scoped.
- Cross-tenant scoping enforced.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/controllers/admin/modules/emails/streams_controller.rb` | Stream CRUD. |
| `app/controllers/admin/modules/emails/suppressions_controller.rb` | Enhanced suppression UI (moved from top-level). |
| `app/controllers/admin/modules/emails/preference_topics_controller.rb` | Topic CRUD. |
| `app/controllers/emails/preferences_controller.rb` | Public preference center. |
| `app/models/emails/preference_topic.rb` | Topic definition. |
| `app/models/emails/user_preference.rb` | Per-user topic subscription. |
| `app/services/emails/preferences/update.rb` | Update user preferences. |
| `db/migrate/20260725000000_create_email_preference_tables.rb` | Preference tables. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Settings UI keys. |

---

## Task 1: Message streams admin UI

**Files:**
- Create: `app/controllers/admin/modules/emails/streams_controller.rb`
- Create views: `app/views/admin/modules/emails/streams/index|new|edit/_form.html.erb`
- Test: `spec/requests/admin/modules/emails/streams_spec.rb`

- [ ] **Step 1: Implement controller**

Standard CRUD for `Emails::Stream` with tenant scoping. Enforce at least one default per kind.

- [ ] **Step 2: Implement views**

Form fields: name, key (readonly after create), kind, provider, mode, from_email, reply_to, tracking_enabled, throttle_per_minute, default_for_kind.

- [ ] **Step 3: Add i18n keys**

Add stream UI keys in both locales.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/streams_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add message streams admin UI"
```

---

## Task 2: Enhance suppressions UI

**Files:**
- Modify: `app/controllers/admin/modules/emails/suppressions_controller.rb`
- Update views: `app/views/admin/modules/emails/suppressions/index.html.erb`
- Test: `spec/requests/admin/modules/emails/suppressions_spec.rb`

- [ ] **Step 1: Add filter and bulk actions**

```ruby
# app/controllers/admin/modules/emails/suppressions_controller.rb
def index
  scope = Emails::Suppression.for_customer(current_customer.id)
  scope = scope.where(reason: params[:reason]) if params[:reason].present?
  scope = scope.where(provider: params[:provider]) if params[:provider].present?
  @suppressions = scope.order(created_at: :desc).page(params[:page])
end

def batch_unblock
  ids = params[:suppression_ids] || []
  Emails::Suppression.where(id: ids, customer_id: [nil, current_customer.id]).destroy_all
  redirect_to admin_modules_emails_suppressions_path(current_customer_id), notice: t("admin_modules.flash.suppressions.unblocked")
end
```

- [ ] **Step 2: Update view**

Add reason/provider filters, checkboxes, bulk unblock button, and event history link.

- [ ] **Step 3: Add i18n keys**

Add suppression UI keys.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/suppressions_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): enhance suppressions UI with filters and bulk actions"
```

---

## Task 3: Preference topics and public preference center

**Files:**
- Create: `db/migrate/20260725000000_create_email_preference_tables.rb`
- Create: `app/models/emails/preference_topic.rb`
- Create: `app/models/emails/user_preference.rb`
- Create: `app/services/emails/preferences/update.rb`
- Create: `app/controllers/admin/modules/emails/preference_topics_controller.rb`
- Create: `app/controllers/emails/preferences_controller.rb`
- Create views: `app/views/emails/preferences/show.html.erb`
- Test: specs for model/service/request

- [ ] **Step 1: Write migration**

```ruby
class CreateEmailPreferenceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :email_preference_topics do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :default_subscribed, null: false, default: true
      t.boolean :required, null: false, default: false
      t.timestamps
    end
    add_index :email_preference_topics, %i[customer_id key], unique: true

    create_table :email_user_preferences do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :authentication_users }
      t.references :email_preference_topic, null: false, foreign_key: true
      t.boolean :subscribed, null: false, default: true
      t.timestamps
    end
    add_index :email_user_preferences, %i[user_id email_preference_topic_id], unique: true
  end
end
```

- [ ] **Step 2: Implement models**

```ruby
# app/models/emails/preference_topic.rb
module Emails
  class PreferenceTopic < ApplicationRecord
    self.table_name = "email_preference_topics"
    include TenantScoped
    belongs_to :customer
    has_many :user_preferences, class_name: "Emails::UserPreference", foreign_key: :email_preference_topic_id, dependent: :destroy
    validates :customer_id, :key, :name, presence: true
    validates :key, uniqueness: { scope: :customer_id }
  end
end
```

```ruby
# app/models/emails/user_preference.rb
module Emails
  class UserPreference < ApplicationRecord
    self.table_name = "email_user_preferences"
    include TenantScoped
    belongs_to :user, class_name: "Authentication::User"
    belongs_to :preference_topic, class_name: "Emails::PreferenceTopic", foreign_key: :email_preference_topic_id
    validates :user_id, uniqueness: { scope: :email_preference_topic_id }
  end
end
```

- [ ] **Step 3: Implement preference update service**

```ruby
# app/services/emails/preferences/update.rb
module Emails
  module Preferences
    class Update
      def self.call(user:, topic_subscriptions:)
        new(user: user, topic_subscriptions: topic_subscriptions).call
      end

      def initialize(user:, topic_subscriptions:)
        @user = user
        @topic_subscriptions = topic_subscriptions
      end

      def call
        Emails::PreferenceTopic.for_current_customer.find_each do |topic|
          next if topic.required?
          subscribed = @topic_subscriptions.fetch(topic.id.to_s, topic.default_subscribed?).to_s == "true"
          pref = Emails::UserPreference.find_or_initialize_by(user: @user, preference_topic: topic)
          pref.update!(subscribed: subscribed)
        end
        true
      end
    end
  end
end
```

- [ ] **Step 4: Implement public controller**

```ruby
# app/controllers/emails/preferences_controller.rb
module Emails
  class PreferencesController < ActionController::Base
    skip_forgery_protection if respond_to?(:skip_forgery_protection)
    before_action :load_user

    def show
      @topics = Emails::PreferenceTopic.for_current_customer.order(:name)
    end

    def update
      Emails::Preferences::Update.call(user: @user, topic_subscriptions: params[:topics] || {})
      redirect_to email_preferences_path(token: params[:token]), notice: I18n.t("emails.preferences.updated")
    end

    private

    def load_user
      @user = Authentication::User.find_by_email_preferences_token(params[:token])
      redirect_to root_path, alert: I18n.t("emails.preferences.invalid_token") unless @user
    end
  end
end
```

Note: Add `email_preferences_token` to users or use existing unsubscribe token mechanism.

- [ ] **Step 5: Add routes**

```ruby
get "/email/preferences", to: "emails/preferences#show", as: :email_preferences
patch "/email/preferences", to: "emails/preferences#update"
```

- [ ] **Step 6: Run specs**

Run: `bundle exec rspec spec/models/emails/preference_topic_spec.rb spec/services/emails/preferences/update_spec.rb spec/requests/emails/preferences_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(email): add preference topics and public preference center"
```

---

## Task 4: Preference topic admin UI

**Files:**
- Create: `app/controllers/admin/modules/emails/preference_topics_controller.rb`
- Create views
- Test: `spec/requests/admin/modules/emails/preference_topics_spec.rb`

- [ ] **Step 1: Implement controller**

Standard CRUD for `Emails::PreferenceTopic`.

- [ ] **Step 2: Add i18n keys**

Add preference topic UI keys.

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/preference_topics_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add preference topic admin UI"
```

---

## Task 5: Phase 7 integration and full-suite run

- [ ] **Step 1: Run settings specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/streams_spec.rb spec/requests/admin/modules/emails/suppressions_spec.rb spec/requests/admin/modules/emails/preference_topics_spec.rb spec/requests/emails/preferences_spec.rb`
Expected: PASS.

- [ ] **Step 2: Run full email suite**

Run: `bundle exec rspec spec/models/emails spec/services/emails spec/jobs/emails spec/requests/admin/modules/emails spec/requests/emails`
Expected: PASS.

- [ ] **Step 3: Stage**

```bash
git add -A
```

Phase 7 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 7 — settings, streams, suppressions, preference center"
```
