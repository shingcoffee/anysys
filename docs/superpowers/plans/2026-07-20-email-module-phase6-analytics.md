# Email Module Phase 6 — Analytics: Reports, Deliverability, Engagement, CSV Export

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phases 1–5.

**Goal:** Replace the single dashboard with rich analytics: reports with date ranges and filters, deliverability drill-downs, engagement insights, and CSV export.

**Architecture:** `Emails::Analytics::Report` aggregates message/event data. Controllers for reports/deliverability/engagement. CSV export uses `Emails::Analytics::ExportCsv`.

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
| `app/services/emails/analytics/report.rb` | Build analytics dataset. |
| `app/services/emails/analytics/export_csv.rb` | Generate CSV export. |
| `app/controllers/admin/modules/emails/reports_controller.rb` | Reports UI. |
| `app/controllers/admin/modules/emails/deliverability_controller.rb` | Deliverability UI. |
| `app/controllers/admin/modules/emails/engagement_controller.rb` | Engagement UI. |
| `app/components/emails/date_range_picker_component.rb` | Reusable date range picker. |
| `app/components/emails/sparkline_component.rb` | Reusable SVG sparkline/bar chart. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | Analytics UI keys. |

---

## Task 1: Implement analytics report service

**Files:**
- Create: `app/services/emails/analytics/report.rb`
- Test: `spec/services/emails/analytics/report_spec.rb`

- [ ] **Step 1: Implement service**

```ruby
# app/services/emails/analytics/report.rb
module Emails
  module Analytics
    class Report
      def self.for(customer, since:, until:, stream_ids: nil, campaign_ids: nil)
        new(customer: customer, since: since, until: until, stream_ids: stream_ids, campaign_ids: campaign_ids).call
      end

      def initialize(customer:, since:, until:, stream_ids: nil, campaign_ids: nil)
        @customer = customer
        @since = since
        @until = until
        @stream_ids = Array(stream_ids).presence
        @campaign_ids = Array(campaign_ids).presence
      end

      def call
        {
          totals: totals,
          daily: daily_series,
          streams: stream_breakdown,
          campaigns: campaign_breakdown
        }
      end

      private

      def message_scope
        scope = Emails::Message.where(customer_id: @customer.id, created_at: @since..@until)
        scope = scope.where(email_stream_id: @stream_ids) if @stream_ids
        scope = scope.where(email_campaign_id: @campaign_ids) if @campaign_ids
        scope
      end

      def totals
        base = message_scope.select(
          "COUNT(CASE WHEN status NOT IN ('pending','queued') THEN 1 END) AS sent",
          "COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS delivered",
          "COUNT(CASE WHEN status = 'bounced' THEN 1 END) AS bounced",
          "COUNT(CASE WHEN status = 'complained' THEN 1 END) AS complained",
          "COUNT(CASE WHEN status = 'suppressed' THEN 1 END) AS suppressed"
        ).to_a.first

        event_scope = Emails::MessageEvent.joins(:message).where(email_messages: { customer_id: @customer.id }, occurred_at: @since..@until)
        event_scope = event_scope.where(email_messages: { email_stream_id: @stream_ids }) if @stream_ids
        event_scope = event_scope.where(email_messages: { email_campaign_id: @campaign_ids }) if @campaign_ids

        opened = event_scope.where(event_type: "open").distinct.count(:message_id)
        clicked = event_scope.where(event_type: "click").distinct.count(:message_id)

        {
          sent: base.sent || 0,
          delivered: base.delivered || 0,
          bounced: base.bounced || 0,
          complained: base.complained || 0,
          suppressed: base.suppressed || 0,
          opened: opened,
          clicked: clicked
        }
      end

      def daily_series
        # group by date, similar to existing DashboardStats but respecting filters
        dates = (@since.to_date..@until.to_date).to_a
        # ... implementation omitted for brevity; produce array of { date, sent, delivered, bounced, opened, clicked }
        dates.map { |d| { date: d, sent: 0, delivered: 0, bounced: 0, opened: 0, clicked: 0 } }
      end

      def stream_breakdown
        message_scope.group(:email_stream_id).count
      end

      def campaign_breakdown
        return {} unless @campaign_ids
        message_scope.group(:email_campaign_id).count
      end
    end
  end
end
```

- [ ] **Step 2: Run specs**

Run: `bundle exec rspec spec/services/emails/analytics/report_spec.rb`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(email): add analytics report service"
```

---

## Task 2: Implement CSV export

**Files:**
- Create: `app/services/emails/analytics/export_csv.rb`
- Test: `spec/services/emails/analytics/export_csv_spec.rb`

- [ ] **Step 1: Implement service**

```ruby
# app/services/emails/analytics/export_csv.rb
require "csv"

module Emails
  module Analytics
    class ExportCsv
      def self.call(messages)
        new(messages).call
      end

      def initialize(messages)
        @messages = messages
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << %w[id to subject status sent_at delivered_at opened clicked]
          @messages.find_each do |m|
            csv << [m.id, m.to, m.subject, m.status, m.sent_at, m.delivered_at, m.opens_count, m.clicks_count]
          end
        end
      end
    end
  end
end
```

Add `opens_count`/`clicks_count` methods to `Emails::Message` or use associations in export.

- [ ] **Step 2: Run specs**

Run: `bundle exec rspec spec/services/emails/analytics/export_csv_spec.rb`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(email): add message CSV export"
```

---

## Task 3: Build analytics controllers and views

**Files:**
- Create: `app/controllers/admin/modules/emails/reports_controller.rb`
- Create: `app/controllers/admin/modules/emails/deliverability_controller.rb`
- Create: `app/controllers/admin/modules/emails/engagement_controller.rb`
- Create views under `app/views/admin/modules/emails/reports/`, `deliverability/`, `engagement/`
- Test: `spec/requests/admin/modules/emails/reports_spec.rb`, etc.

- [ ] **Step 1: Implement reports controller**

```ruby
# app/controllers/admin/modules/emails/reports_controller.rb
module Admin
  module Modules
    module Emails
      class ReportsController < ApplicationController
        dashboard_menu_item :modules

        def index
          since = parse_date(params[:since], 30.days.ago)
          until_date = parse_date(params[:until], Time.current)
          @report = Emails::Analytics::Report.for(
            current_customer,
            since: since.beginning_of_day,
            until: until_date.end_of_day,
            stream_ids: params[:stream_ids],
            campaign_ids: params[:campaign_ids]
          )
          respond_to do |format|
            format.html
            format.csv { send_data Emails::Analytics::ExportCsv.call(filtered_messages), filename: "email-report.csv" }
          end
        end

        private

        def parse_date(value, default)
          value.present? ? Date.parse(value) : default
        rescue ArgumentError
          default
        end

        def filtered_messages
          Emails::Message.for_current_customer.where(created_at: @report[:range])
        end
      end
    end
  end
end
```

- [ ] **Step 2: Implement deliverability controller**

Shows bounce/complaint breakdown by category and stream. Use `Emails::Suppression` for suppression list with filters.

- [ ] **Step 3: Implement engagement controller**

Shows top clicked links, opens by hour/day, device breakdown parsed from user agent.

- [ ] **Step 4: Add i18n keys**

Add analytics keys in both locales.

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/reports_spec.rb spec/requests/admin/modules/emails/deliverability_spec.rb spec/requests/admin/modules/emails/engagement_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(email): add analytics controllers and views"
```

---

## Task 4: Phase 6 integration

- [ ] **Step 1: Run analytics specs**

Run: `bundle exec rspec spec/services/emails/analytics spec/requests/admin/modules/emails/reports_spec.rb spec/requests/admin/modules/emails/deliverability_spec.rb spec/requests/admin/modules/emails/engagement_spec.rb`
Expected: PASS.

- [ ] **Step 2: Stage**

```bash
git add -A
```

Phase 6 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 6 — analytics, deliverability, engagement, CSV export"
```
