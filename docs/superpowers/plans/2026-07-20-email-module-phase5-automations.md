# Email Module Phase 5 — Automations: Workflows, Triggers, and Step Execution

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phases 1–4.

**Goal:** Add a basic automation/journey builder that sends triggered email sequences.

**Architecture:** `Emails::Automations::Workflow` defines triggers and ordered steps. `Emails::Automations::Enrollment` tracks a user's position. Jobs evaluate triggers and execute steps. Messages use the `automated` stream kind.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec.

## Global Constraints

- All user-facing strings I18n in `en` and `zh-CN`.
- TailwindCSS only; StimulusJS only.
- Admin routes require admin/owner.
- Cross-tenant scoping enforced.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/emails/automations/workflow.rb` | Workflow definition. |
| `app/models/emails/automations/step.rb` | Step within a workflow. |
| `app/models/emails/automations/enrollment.rb` | User's current position in a workflow. |
| `app/services/emails/automations/trigger.rb` | Evaluate triggers and create enrollments. |
| `app/services/emails/automations/process_step.rb` | Execute a single step. |
| `app/jobs/emails/automations/enqueue_job.rb` | Poll triggers. |
| `app/jobs/emails/automations/process_step_job.rb` | Execute steps. |
| `app/controllers/admin/modules/emails/automations_controller.rb` | Workflow CRUD. |
| `db/migrate/20260724000000_create_email_automations.rb` | Automation tables. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Automation UI keys. |

---

## Task 1: Create automation tables and models

**Files:**
- Create: `db/migrate/20260724000000_create_email_automations.rb`
- Create: `app/models/emails/automations/workflow.rb`
- Create: `app/models/emails/automations/step.rb`
- Create: `app/models/emails/automations/enrollment.rb`
- Test: `spec/models/emails/automations/workflow_spec.rb`

- [ ] **Step 1: Write migration**

```ruby
class CreateEmailAutomations < ActiveRecord::Migration[8.1]
  def change
    create_table :email_automations do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.string :trigger_kind, null: false
      t.json :trigger_config, null: false, default: {}
      t.timestamps
    end

    create_table :email_automation_steps do |t|
      t.references :email_automation, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :step_type, null: false
      t.json :config, null: false, default: {}
      t.references :email_template, foreign_key: true
      t.timestamps
    end
    add_index :email_automation_steps, %i[email_automation_id position], unique: true

    create_table :email_automation_enrollments do |t|
      t.references :email_automation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: { to_table: :authentication_users }
      t.integer :current_step_position, null: false, default: 0
      t.datetime :next_step_at
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :email_automation_enrollments, %i[email_automation_id user_id], unique: true
  end
end
```

- [ ] **Step 2: Implement models**

```ruby
# app/models/emails/automations/workflow.rb
module Emails
  module Automations
    class Workflow < ApplicationRecord
      self.table_name = "email_automations"
      include TenantScoped
      belongs_to :customer
      has_many :steps, class_name: "Emails::Automations::Step", foreign_key: :email_automation_id, dependent: :destroy
      has_many :enrollments, class_name: "Emails::Automations::Enrollment", foreign_key: :email_automation_id, dependent: :destroy
      validates :customer_id, :name, :trigger_kind, presence: true
      validates :trigger_kind, inclusion: { in: %w[user_created tag_added] }
      validates :status, inclusion: { in: %w[draft active paused] }
    end
  end
end
```

```ruby
# app/models/emails/automations/step.rb
module Emails
  module Automations
    class Step < ApplicationRecord
      self.table_name = "email_automation_steps"
      belongs_to :workflow, class_name: "Emails::Automations::Workflow", foreign_key: :email_automation_id
      belongs_to :email_template, optional: true, class_name: "Emails::Template"
      validates :position, :step_type, presence: true
      validates :step_type, inclusion: { in: %w[delay send_email add_tag] }
    end
  end
end
```

```ruby
# app/models/emails/automations/enrollment.rb
module Emails
  module Automations
    class Enrollment < ApplicationRecord
      self.table_name = "email_automation_enrollments"
      belongs_to :workflow, class_name: "Emails::Automations::Workflow", foreign_key: :email_automation_id
      belongs_to :user, class_name: "Authentication::User"
      validates :user_id, uniqueness: { scope: :email_automation_id }
    end
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/models/emails/automations/workflow_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add automation workflow tables and models"
```

---

## Task 2: Implement trigger evaluation

**Files:**
- Create: `app/services/emails/automations/trigger.rb`
- Create: `app/jobs/emails/automations/enqueue_job.rb`
- Test: `spec/services/emails/automations/trigger_spec.rb`

- [ ] **Step 1: Implement service**

```ruby
# app/services/emails/automations/trigger.rb
module Emails
  module Automations
    class Trigger
      def self.user_created(user)
        workflows = Emails::Automations::Workflow.active.where(trigger_kind: "user_created", customer: user.customer)
        workflows.find_each { |wf| enroll(user, wf) }
      end

      def self.tag_added(user, tag)
        workflows = Emails::Automations::Workflow.active.where(trigger_kind: "tag_added", customer: user.customer)
        workflows.find_each do |wf|
          next unless Array(wf.trigger_config["tag_ids"]).map(&:to_s).include?(tag.id.to_s)
          enroll(user, wf)
        end
      end

      def self.enroll(user, workflow)
        return if Emails::Automations::Enrollment.exists?(workflow: workflow, user: user)
        Emails::Automations::Enrollment.create!(workflow: workflow, user: user, current_step_position: 0, next_step_at: Time.current)
      end
    end
  end
end
```

- [ ] **Step 2: Implement enqueue job**

```ruby
# app/jobs/emails/automations/enqueue_job.rb
module Emails
  module Automations
    class EnqueueJob < ApplicationJob
      queue_as :default
      def perform
        Emails::Automations::Enrollment
          .where(status: "active")
          .where("next_step_at <= ?", Time.current)
          .find_each { |enrollment| ProcessStepJob.perform_later(enrollment.id) }
      end
    end
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/emails/automations/trigger_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add automation trigger evaluation and enqueue job"
```

---

## Task 3: Implement step processing

**Files:**
- Create: `app/services/emails/automations/process_step.rb`
- Create: `app/jobs/emails/automations/process_step_job.rb`
- Test: `spec/services/emails/automations/process_step_spec.rb`

- [ ] **Step 1: Implement service**

```ruby
# app/services/emails/automations/process_step.rb
module Emails
  module Automations
    class ProcessStep
      def self.call(enrollment_id)
        enrollment = Emails::Automations::Enrollment.find(enrollment_id)
        return unless enrollment.status == "active"

        step = enrollment.workflow.steps.find_by(position: enrollment.current_step_position)
        if step.nil?
          enrollment.update!(status: "completed")
          return
        end

        case step.step_type
        when "delay"
          minutes = step.config["delay_minutes"].to_i
          enrollment.update!(current_step_position: enrollment.current_step_position + 1, next_step_at: Time.current + minutes.minutes)
        when "send_email"
          send_email(enrollment, step)
          enrollment.update!(current_step_position: enrollment.current_step_position + 1, next_step_at: Time.current)
        when "add_tag"
          tag = Emails::Audience::Tag.find_by(id: step.config["tag_id"])
          Emails::Audience::Tagging.find_or_create_by!(tag: tag, taggable: enrollment.user) if tag
          enrollment.update!(current_step_position: enrollment.current_step_position + 1, next_step_at: Time.current)
        end
      end

      private

      def self.send_email(enrollment, step)
        template = step.email_template
        return unless template
        Emails::Gateway.send(
          customer: enrollment.workflow.customer,
          to: enrollment.user.email,
          template_key: template.key,
          vars: Emails::VariableContext.for(user: enrollment.user),
          stream_key: "automated"
        )
      end
    end
  end
end
```

- [ ] **Step 2: Implement job**

```ruby
# app/jobs/emails/automations/process_step_job.rb
module Emails
  module Automations
    class ProcessStepJob < ApplicationJob
      queue_as :default
      def perform(enrollment_id)
        ProcessStep.call(enrollment_id)
      end
    end
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/emails/automations/process_step_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add automation step processing"
```

---

## Task 4: Build automation admin UI

**Files:**
- Create: `app/controllers/admin/modules/emails/automations_controller.rb`
- Create views: `app/views/admin/modules/emails/automations/index|new|edit|show.html.erb` and `_step_fields.html.erb`
- Test: `spec/requests/admin/modules/emails/automations_spec.rb`

- [ ] **Step 1: Implement controller**

Standard CRUD for `Emails::Automations::Workflow` with nested step attributes.

- [ ] **Step 2: Add nested steps form**

Use Stimulus to add/remove step fields dynamically.

- [ ] **Step 3: Add i18n keys**

Add automation UI keys in both locales.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/automations_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add automation admin UI"
```

---

## Task 5: Phase 5 integration

- [ ] **Step 1: Run automation specs**

Run: `bundle exec rspec spec/models/emails/automations spec/services/emails/automations spec/jobs/emails/automations spec/requests/admin/modules/emails/automations_spec.rb`
Expected: PASS.

- [ ] **Step 2: Stage**

```bash
git add -A
```

Phase 5 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 5 — automations with triggers and step execution"
```
