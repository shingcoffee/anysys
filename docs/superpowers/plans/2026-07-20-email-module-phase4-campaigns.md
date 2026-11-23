# Email Module Phase 4 — Campaigns: Wizard Builder and A/B Testing

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phases 1–3.

**Goal:** Replace the single-form campaign UI with a step-by-step wizard and add A/B testing with winner selection.

**Architecture:** Campaigns get `stream_id`, optional `segment_id`, and `ab_test_config_json`. The wizard collects setup/audience/content/review. A/B campaigns split audience into test groups; after the wait period, a job picks the winner and sends to the remainder.

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
| `app/models/emails/campaigns/campaign.rb` | Add stream, segment, A/B config. |
| `app/services/emails/campaigns/build.rb` | Validate/assemble campaign across wizard steps. |
| `app/services/emails/campaigns/pick_winner.rb` | Select A/B winner and send to remainder. |
| `app/jobs/emails/campaigns/pick_winner_job.rb` | Trigger winner selection. |
| `app/controllers/admin/modules/emails/campaigns_controller.rb` | Wizard actions. |
| `app/components/emails/campaign_builder_component.rb` | Stepper component. |
| `db/migrate/20260723000000_add_stream_and_ab_test_to_email_campaigns.rb` | Campaign additions. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Campaign wizard keys. |

---

## Task 1: Extend campaign model

**Files:**
- Create: `db/migrate/20260723000000_add_stream_and_ab_test_to_email_campaigns.rb`
- Modify: `app/models/emails/campaigns/campaign.rb`
- Test: `spec/models/emails/campaigns/campaign_spec.rb`

- [ ] **Step 1: Write migration**

```ruby
class AddStreamAndAbTestToEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_campaigns, :email_stream, foreign_key: true, index: true
    add_reference :email_campaigns, :email_segment, foreign_key: true, index: true
    add_column :email_campaigns, :ab_test_config, :json, null: false, default: {}
    add_column :email_campaigns, :ab_test_winner_variant, :string
    add_column :email_campaigns, :ab_test_completed_at, :datetime
  end
end
```

- [ ] **Step 2: Update model**

```ruby
# app/models/emails/campaigns/campaign.rb
module Emails
  module Campaigns
    class Campaign < ApplicationRecord
      # ... existing ...
      belongs_to :email_stream, optional: true, class_name: "Emails::Stream"
      belongs_to :email_segment, optional: true, class_name: "Emails::Audience::Segment"

      validate :email_segment_same_tenant, if: -> { email_segment.present? }

      def ab_test_enabled? = ab_test_config["enabled"].to_s == "true"

      def variants
        Array(ab_test_config["variants"]).presence || [{ "name" => "A" }]
      end

      private

      def email_segment_same_tenant
        return if email_segment.customer_id == customer_id
        errors.add(:email_segment_id, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
      end
    end
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/models/emails/campaigns/campaign_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add stream, segment, and A/B test fields to campaigns"
```

---

## Task 2: Implement A/B test services and jobs

**Files:**
- Create: `app/services/emails/campaigns/pick_winner.rb`
- Create: `app/jobs/emails/campaigns/pick_winner_job.rb`
- Test: `spec/services/emails/campaigns/pick_winner_spec.rb`

- [ ] **Step 1: Implement pick winner service**

```ruby
# app/services/emails/campaigns/pick_winner.rb
module Emails
  module Campaigns
    class PickWinner
      def self.call(campaign)
        new(campaign).call
      end

      def initialize(campaign)
        @campaign = campaign
      end

      def call
        return false unless @campaign.ab_test_enabled? && @campaign.status == "sending"

        winner = select_winner
        @campaign.update!(ab_test_winner_variant: winner, ab_test_completed_at: Time.current)
        # Trigger remainder send with winner variant
        SendCampaignJob.perform_later(@campaign.id, variant: winner)
        true
      end

      private

      def select_winner
        config = @campaign.ab_test_config
        metric = config["winner_metric"] || "open_rate"
        Array(config["variants"]).max_by { |v| rate_for(v["name"], metric) }["name"]
      end

      def rate_for(variant, metric)
        messages = Emails::Message.where(email_campaign_id: @campaign.id, metadata: { variant: variant })
        sent = messages.where.not(status: %w[suppressed failed]).count
        return 0 if sent.zero?

        if metric == "click_rate"
          clicked = Emails::MessageEvent.where(message_id: messages.select(:id), event_type: "click").distinct.count
          clicked.to_f / sent
        else
          opened = Emails::MessageEvent.where(message_id: messages.select(:id), event_type: "open").distinct.count
          opened.to_f / sent
        end
      end
    end
  end
end
```

- [ ] **Step 2: Implement job**

```ruby
# app/jobs/emails/campaigns/pick_winner_job.rb
module Emails
  module Campaigns
    class PickWinnerJob < ApplicationJob
      queue_as :default
      def perform(campaign_id)
        campaign = Emails::Campaigns::Campaign.find(campaign_id)
        PickWinner.call(campaign)
      end
    end
  end
end
```

- [ ] **Step 3: Update SendCampaignJob to support variant**

Accept optional `variant:` argument; when present, use the variant's subject/body overrides. Store variant in message metadata.

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/services/emails/campaigns/pick_winner_spec.rb spec/jobs/emails/campaigns/send_campaign_job_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add A/B test winner selection"
```

---

## Task 3: Build campaign wizard UI

**Files:**
- Modify: `app/controllers/admin/modules/emails/campaigns_controller.rb`
- Create: `app/components/emails/campaign_builder_component.rb` + `.html.erb`
- Create/update views: `app/views/admin/modules/emails/campaigns/new.html.erb`, `edit.html.erb`, `_wizard_step_*.html.erb`
- Test: `spec/requests/admin/modules/emails/campaigns_spec.rb`

- [ ] **Step 1: Implement wizard controller**

Add `step` param handling. Persist campaign after each step. Steps: `setup`, `audience`, `content`, `review`.

- [ ] **Step 2: Implement builder component**

Stepper navigation with Stimulus; each step renders a partial.

- [ ] **Step 3: Add i18n keys**

Wizard labels in `admin_modules.emails.campaigns.wizard.*` for both locales.

- [ ] **Step 4: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/campaigns_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add campaign wizard builder UI"
```

---

## Task 4: Phase 4 integration

- [ ] **Step 1: Run campaign specs**

Run: `bundle exec rspec spec/models/emails/campaigns spec/services/emails/campaigns spec/jobs/emails/campaigns spec/requests/admin/modules/emails/campaigns_spec.rb`
Expected: PASS.

- [ ] **Step 2: Stage**

```bash
git add -A
```

Phase 4 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 4 — campaign wizard and A/B testing"
```
