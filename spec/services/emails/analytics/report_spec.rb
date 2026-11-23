# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Analytics::Report do
  let(:customer) { create(:customer) }
  let(:campaign) { create(:email_send_activity, customer: customer) }

  describe ".for" do
    it "returns zeroed totals and daily series when no messages exist" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        report = described_class.for(customer, since: 2.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

        expect(report[:totals]).to eq(
          sent: 0, delivered: 0, bounced: 0, complained: 0, suppressed: 0, failed: 0, opened: 0, clicked: 0
        )
        expect(report[:daily].size).to eq(3)
      end
    end

    it "aggregates message totals and event totals" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        delivered = create(:email_message, customer: customer, status: "delivered", created_at: 2.days.ago)
        bounced = create(:email_message, customer: customer, status: "bounced", created_at: 1.day.ago)
        create(:email_message, customer: customer, status: "pending", created_at: 1.day.ago)

        Emails::MessageEvent.create!(message: delivered, event_type: "open", occurred_at: 2.days.ago)
        Emails::MessageEvent.create!(message: delivered, event_type: "click", occurred_at: 1.day.ago)

        report = described_class.for(customer, since: 3.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

        expect(report[:totals][:sent]).to eq(2)
        expect(report[:totals][:delivered]).to eq(1)
        expect(report[:totals][:bounced]).to eq(1)
        expect(report[:totals][:opened]).to eq(1)
        expect(report[:totals][:clicked]).to eq(1)
      end
    end

    it "counts only accepted send states and exposes failures separately in totals and daily series" do
      %w[pending queued sent delivered bounced complained failed suppressed].each do |status|
        create(:email_message, customer: customer, status: status, email_send_activity_id: campaign.id, created_at: 1.day.ago)
      end
      create(:email_message, customer: create(:customer), status: "failed", created_at: 1.day.ago)
      create(:email_message, customer: customer, status: "failed", created_at: 10.days.ago)

      report = described_class.for(customer, since: 2.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

      expect(report[:totals]).to include(sent: 4, failed: 1, suppressed: 1)
      expect(report[:daily].find { |day| day[:date] == 1.day.ago.to_date }).to include(sent: 4, failed: 1)
      expect(report[:send_activities]).to eq(campaign.id => 4)
    end

    it "filters by send activity" do
      other_campaign = create(:email_send_activity, customer: customer)
      create(:email_message, customer: customer, status: "delivered", email_send_activity_id: campaign.id, created_at: 1.day.ago)
      create(:email_message, customer: customer, status: "delivered", email_send_activity_id: other_campaign.id, created_at: 1.day.ago)

      report = described_class.for(
        customer,
        since: 2.days.ago.beginning_of_day,
        until_date: Time.current.end_of_day,
        send_activity_ids: [campaign.id]
      )

      expect(report[:totals][:sent]).to eq(1)
      expect(report[:send_activities]).to eq({ campaign.id => 1 })
    end

    it "returns daily stats matching the date range" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)
        create(:email_message, customer: customer, status: "bounced", created_at: 1.day.ago)

        report = described_class.for(customer, since: 2.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

        day_stat = report[:daily].find { |d| d[:date] == 1.day.ago.to_date }
        expect(day_stat[:sent]).to eq(2)
        expect(day_stat[:delivered]).to eq(1)
        expect(day_stat[:bounced]).to eq(1)
      end
    end

    it "scopes data to the customer" do
      other_customer = create(:customer)
      create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)
      create(:email_message, customer: other_customer, status: "delivered", created_at: 1.day.ago)

      report = described_class.for(customer, since: 2.days.ago.beginning_of_day, until_date: Time.current.end_of_day)

      expect(report[:totals][:sent]).to eq(1)
    end

    it "does not expand a millennia-wide window into millions of daily rows" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        report = described_class.for(
          customer,
          since: Date.new(1, 1, 1),
          until_date: Date.new(9999, 12, 31)
        )

        expect(report[:daily].size).to eq(Emails::Analytics::DateRange::MAX_SPAN_DAYS + 1)
      end
    end
  end
end
