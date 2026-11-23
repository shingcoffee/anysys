# frozen_string_literal: true

require "rails_helper"
require "timeout"
require_relative "helpers"

RSpec.describe "SMS campaign committed outbox and concurrent final starts" do
  self.use_transactional_tests = false
  include_context "SMS campaign engine"

  after do
    Sms::CampaignRecipient.where(customer_id: customer.id).delete_all
    Sms::Message.where(customer_id: customer.id).delete_all
    Sms::Campaign.where(customer_id: customer.id).delete_all
    Sms::ConsentEvent.where(customer_id: customer.id).delete_all
    Sms::Contact.where(customer_id: customer.id).delete_all
    Sms::OptOut.where(customer_id: customer.id).delete_all
    template.destroy!
    credential.destroy!
    customer.destroy!
  end

  def race(*operations)
    ready = Queue.new
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
    Timeout.timeout(20) do
      operations.size.times { ready.pop }
      operations.size.times { start << true }
      threads.map(&:value)
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end

  it "rolls back message, recipient link and all queue accelerators with the outer admission transaction" do
    travel_to(Time.utc(2026, 10, 13, 14))
    campaign = launch_campaign
    run_campaign(campaign)
    recipient = campaign.recipients.first!
    expect(recipient.status).to eq("pending")
    travel_to(Time.utc(2026, 10, 14, 1))
    clear_enqueued_jobs
    Sms::Message.transaction do
      Sms::Gateway.send_campaign(customer: customer, recipient: recipient)
      expect(Sms::Message.count).to eq(1)
      expect(recipient.reload.message_id).to be_present
      expect(enqueued_jobs).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(recipient.reload.message_id).to be_nil
    expect(Sms::Message.count).to eq(0)
    expect(enqueued_jobs).to be_empty
    Sms::Gateway.send_campaign(customer: customer, recipient: recipient)
    expect(enqueued_jobs.count { |job| job[:job] == Sms::DeliverMessageJob }).to eq(1)
  end

  it "commits dispatch authorization before the adapter observes it on an independent connection" do
    campaign = launch_campaign
    run_campaign(campaign)
    message = campaign.messages.first!
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      state = Thread.new do
        ApplicationRecord.connection_pool.with_connection { Sms::Message.find(message.id).dispatch_started_at }
      end.value
      expect(state).to eq(Time.current)
      { vendor_message_id: "committed-attempt", raw: {} }
    end
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload).to have_attributes(delivery_attempts: 1, status: "sent")
  end

  it "allows exactly one due start for two concurrent messages using the same credential" do
    transactional = create(:sms_template)
    messages = %w[+8613800138000 +8613800138001].map do |phone|
      Sms::Gateway.send(customer: customer, to: phone, template_key: transactional.key, vars: { code: "1", minutes: 5 })
    end
    claims = messages.map { |message| Sms::DeliveryDispatch.claim(message.id) }
    decisions = race(*claims.map do |message, token|
      -> { Sms::DispatchLimiter.acquire(credential: Sms::Credential.find(credential.id), message: Sms::Message.find(message.id), claim_token: token, at: Time.current) }
    end)
    expect(decisions.map { |result| result[:action] }.sort).to eq(%i[defer started])
    expect(messages.map { |message| message.reload.delivery_attempts }.sum).to eq(1)
    expect(credential.reload.dispatch_next_at).to eq(1.second.from_now)
  ensure
    Sms::Message.where(sms_template_id: transactional&.id).delete_all
    transactional&.destroy!
  end

  it "serializes cancellation and final start so either cancellation wins or one immutable attempt remains" do
    campaign = launch_campaign
    run_campaign(campaign)
    message = campaign.messages.first!
    _claimed, token = Sms::DeliveryDispatch.claim(message.id)
    race(
      -> { Sms::Campaigns::Cancel.call(customer: Customer.find(customer.id), actor: actor, campaign: Sms::Campaign.find(campaign.id)) },
      -> { Sms::DispatchLimiter.acquire(credential: Sms::Credential.find(credential.id), message: Sms::Message.find(message.id), claim_token: token, at: Time.current) }
    )
    expect(campaign.reload.status).to eq("cancelled")
    recipient = campaign.recipients.first!
    if message.reload.dispatch_started_at
      expect(message.delivery_attempts).to eq(1)
      expect(message.status).to eq("queued")
      expect(recipient.status).to eq("admitted")
    else
      expect(message).to have_attributes(status: "suppressed", delivery_attempts: 0)
      expect(recipient).to have_attributes(status: "cancelled", skip_reason: "campaign_cancelled")
    end
  end
end
