# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Analytics::Health do
  let(:customer) { create(:customer) }

  def health_for
    described_class.for(customer, since: 3.days.ago.beginning_of_day, until_date: Time.current.end_of_day)
  end

  it "reports delivery ledger failures and bounce codes within the tenant and date boundary" do
    create(:email_message, customer: customer, status: "failed", failure_code: "SEND_ERROR", created_at: 1.day.ago)
    create(:email_message, customer: customer, status: "bounced", failure_code: "BOUNCE_ERROR", created_at: 1.day.ago)
    create(:email_message, customer: customer, status: "failed", failure_code: nil, created_at: 1.day.ago)
    create(:email_message, customer: customer, status: "failed", failure_code: "OLD_ERROR", created_at: 10.days.ago)
    create(:email_message, customer: create(:customer), status: "failed", failure_code: "FOREIGN_ERROR", created_at: 1.day.ago)

    expect(health_for[:totals]).to include(failed: 2, bounced: 1)
    expect(health_for[:failure_breakdown]).to eq("SEND_ERROR" => 1, "BOUNCE_ERROR" => 1)
  end

  it "aggregates open events into device categories" do
    tablet = create(:email_message, customer: customer, created_at: 1.day.ago)
    mobile = create(:email_message, customer: customer, created_at: 1.day.ago)
    desktop = create(:email_message, customer: customer, created_at: 1.day.ago)
    create(:email_message_event, message: tablet, event_type: "open",
           user_agent: "Mozilla/5.0 (iPad; CPU OS 17_0)", occurred_at: 1.day.ago)
    create(:email_message_event, message: mobile, event_type: "open",
           user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Mobile", occurred_at: 1.day.ago)
    create(:email_message_event, message: desktop, event_type: "open",
           user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X)", occurred_at: 1.day.ago)

    expect(health_for[:devices]).to eq("tablet" => 1, "mobile" => 1, "desktop" => 1)
  end

  it "counts devices in SQL instead of loading every open event" do
    message = create(:email_message, customer: customer, created_at: 1.day.ago)
    create(:email_message_event, message: message, event_type: "open",
           user_agent: "Mozilla/5.0", occurred_at: 1.day.ago)

    sqls = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sqls << payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { health_for }

    event_sql = sqls.select { |sql| sql.include?("email_message_events") }.join(" ")
    expect(event_sql).to match(/CASE/i)
    expect(event_sql).to match(/COUNT/i)
  end
end
