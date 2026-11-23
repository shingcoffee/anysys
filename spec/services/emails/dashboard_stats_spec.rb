require "rails_helper"

RSpec.describe Emails::DashboardStats do
  let(:customer) { create(:customer) }

  describe ".for" do
    it "excludes failed and suppressed attempts from sent counts and reports ledger failures separately" do
      %w[pending queued sent delivered bounced complained failed suppressed].each do |status|
        create(:email_message, customer: customer, status: status, created_at: 1.day.ago)
      end
      create(:email_message, customer: create(:customer), status: "failed", created_at: 1.day.ago)
      create(:email_message, customer: customer, status: "failed", created_at: 10.days.ago)

      stats = described_class.for(customer, since: 2.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

      expect(stats[:totals]).to include(sent: 4, failed: 1, suppressed: 1)
      expect(stats[:daily].find { |day| day[:date] == 1.day.ago.to_date }).to include(sent: 4, failed: 1)
    end

    it "returns correctly aggregated totals and daily stats" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        create(:email_message, customer: customer, status: "delivered", created_at: 2.days.ago)
        create(:email_message, customer: customer, status: "bounced", created_at: 1.day.ago)
        create(:email_message, customer: customer, status: "pending", created_at: 1.day.ago)

        msg = create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)
        Emails::MessageEvent.create!(message: msg, event_type: "open", occurred_at: 1.day.ago)

        Emails::Suppression.create!(customer_id: customer.id, email: "test@example.com", reason: "unsubscribe", created_at: 1.day.ago)

        stats = Emails::DashboardStats.for(customer, since: 5.days.ago)

        expect(stats[:totals][:sent]).to eq(3)
        expect(stats[:totals][:delivered]).to eq(2)
        expect(stats[:totals][:bounced]).to eq(1)
        expect(stats[:totals][:opened]).to eq(1)
        expect(stats[:totals][:unsubscribed]).to eq(1)

        daily = stats[:daily]
        expect(daily.size).to eq(6)

        # 1 day ago
        day_stat = daily.find { |d| d[:date] == 1.day.ago.to_date }
        expect(day_stat[:sent]).to eq(2)
        expect(day_stat[:delivered]).to eq(1)
        expect(day_stat[:bounced]).to eq(1)
        expect(day_stat[:opened]).to eq(1)
      end
    end

    it "excludes records after until_date from totals and daily stats" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        in_range_message = create(:email_message, customer: customer, status: "delivered", created_at: 2.days.ago)
        Emails::MessageEvent.create!(
          message: in_range_message,
          event_type: "open",
          occurred_at: 2.days.ago
        )
        Emails::Suppression.create!(
          customer_id: customer.id,
          email: "in-range@example.com",
          reason: "unsubscribe",
          created_at: 2.days.ago
        )

        create(:email_message, customer: customer, status: "bounced", created_at: 1.day.ago)
        Emails::MessageEvent.create!(
          message: create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago),
          event_type: "click",
          occurred_at: 1.day.ago
        )
        Emails::Suppression.create!(
          customer_id: customer.id,
          email: "after-range@example.com",
          reason: "unsubscribe",
          created_at: 1.day.ago
        )

        stats = described_class.for(customer, since: 5.days.ago, until_date: 2.days.ago.end_of_day)

        expect(stats[:totals]).to include(sent: 1, delivered: 1, bounced: 0, opened: 1, clicked: 0, unsubscribed: 1)
        expect(stats[:daily]).to all(satisfy { |day| day[:date] <= 2.days.ago.to_date })
      end
    end

    it "does not expand a millennia-wide window into millions of daily rows" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        stats = described_class.for(
          customer,
          since: Date.new(1, 1, 1),
          until_date: Date.new(9999, 12, 31)
        )

        expect(stats[:daily].size).to eq(Emails::Analytics::DateRange::MAX_SPAN_DAYS + 1)
      end
    end
  end
end
