# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Quota do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:email_credential) }

  def raw(**options)
    Emails::Gateway.send_raw(**{ customer: customer, to: "a@example.com", subject: "Notice", body_html: "<p>Notice</p>" }.merge(options))
  end

  it "uses one daily budget across transactional and campaign mail" do
    allow(Emails::Activities::Send).to receive(:daily_cap_for).and_return(1)
    create(:email_message, customer: customer, message_type: "campaign", status: "queued")

    expect { raw }.to raise_error(Email::Errors::DailyCapExceeded)
    expect(Emails::Message.where(customer_id: customer.id).count).to eq(1)
  end

  it "returns an idempotent result before cap, content validation, and credential selection" do
    allow(Emails::Activities::Send).to receive(:daily_cap_for).and_return(1)
    message = raw(idempotency_key: "replay")
    credential.update!(status: "disabled")

    expect(raw(idempotency_key: "replay", subject: "", body_html: "").id).to eq(message.id)
    expect(Emails::Activities::Send.call(customer: customer, to: "", template_id: -1, vars: {}, idempotency_key: "replay").id)
      .to eq(message.id)
  end

  it "rechecks the last slot after another producer used a previously observed allowance" do
    allow(Emails::Activities::Send).to receive(:daily_cap_for).and_return(1)
    first_view = described_class.remaining_daily(customer)
    second_view = described_class.remaining_daily(Customer.find(customer.id))
    expect([first_view, second_view]).to eq([1, 1])
    raw(idempotency_key: "first")

    expect { raw(idempotency_key: "second") }.to raise_error(Email::Errors::DailyCapExceeded)
  end

  it "reserves the minute allowance across different campaigns" do
    first = create(:email_send_activity, :processing, customer: customer)
    second = create(:email_send_activity, :processing, customer: customer)
    user = create(:user, customer: customer)
    other_user = create(:user, customer: customer)
    Emails::Gateway.queue_for_send_activity(send_activity: first, user: user, campaign_limit: 1)

    expect {
      Emails::Gateway.queue_for_send_activity(send_activity: second, user: other_user, campaign_limit: 1)
    }.to raise_error(Emails::Quota::Throttled)
  end

  it "handles a duplicate detected by the actual uniqueness validation" do
    attrs = { customer: customer, to: "a@example.com", from: "s@example.com", subject: "Hi", body_html: "<p>Hi</p>",
              status: "queued", message_type: "transactional", idempotency_key: "validation-race" }
    existing = Emails::Message.create!(attrs)
    allow(Emails::PersistMessage).to receive(:existing).and_return(nil, existing)

    message, created = Emails::PersistMessage.call(attrs)

    expect(message.id).to eq(existing.id)
    expect(created).to be(false)
  end

  it "does not hide an unrelated validation failure in duplicate recovery" do
    attrs = { customer: customer, to: "a@example.com", from: "s@example.com", subject: "", body_html: "<p>Hi</p>",
              status: "queued", message_type: "transactional" }
    expect { Emails::PersistMessage.call(attrs) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
