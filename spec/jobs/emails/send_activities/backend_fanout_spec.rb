# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivityJob, "backend fan-out", type: :job do
  let(:customer) { create(:customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential) }
  let(:campaign) { create(:email_send_activity, :processing, customer: customer) }

  def add_recipients(count)
    create_list(:user, count, customer: customer).each do |user|
      create(:email_list_membership, email_list: campaign.email_lists.first, user: user)
    end
  end

  it "bounds a fresh minute's batch rather than bursting the full batch size" do
    stub_const("#{described_class}::THROTTLE_PER_MINUTE", 2)
    add_recipients(3)

    described_class.new.perform(campaign.id)

    expect(Emails::Message.where(email_send_activity_id: campaign.id).count).to eq(2)
    expect(campaign.reload.status).to eq("processing")
    expect(campaign.deferred_until).to be_present
    expect(campaign.fanout_claim_token).to be_nil
  end

  it "propagates a transient recipient error and retries only recipients without ledger rows" do
    add_recipients(2)
    calls = 0
    allow(Emails::Gateway).to receive(:queue_for_send_activity).and_wrap_original do |method, **arguments|
      calls += 1
      raise IOError, "temporary persistence outage" if calls == 2

      method.call(**arguments)
    end

    expect { described_class.new.perform(campaign.id) }.to raise_error(IOError)
    expect(campaign.reload.status).to eq("processing")
    expect(campaign.fanout_claim_token).to be_nil
    expect(Emails::Message.where(email_send_activity_id: campaign.id).count).to eq(1)

    described_class.new.perform(campaign.id)

    expect(campaign.reload.status).to eq("succeed")
    expect(Emails::Message.where(email_send_activity_id: campaign.id).count).to eq(2)
  end

  it "recovers an expired daily-cap deferral after reset instead of dead-lettering it" do
    campaign.update_columns(started_at: 1.day.ago, claimed_at: 4.hours.ago,
                            deferred_reason: "daily_cap", deferred_until: 1.minute.ago)
    expect {
      Emails::SendActivities::Cron::ReconcileSendActivities.call
    }.to have_enqueued_job(described_class).with(campaign.id)
    expect(campaign.reload.status).to eq("processing")
  end

  it "does not reap a future deferral even when its old claim is expired" do
    campaign.update_columns(started_at: 1.day.ago, claimed_at: 4.hours.ago,
                            deferred_reason: "daily_cap", deferred_until: 1.day.from_now)

    expect { Emails::SendActivities::Cron::ReconcileSendActivities.call }.not_to have_enqueued_job(described_class)
    expect(campaign.reload.status).to eq("processing")
  end

  it "completes a fully materialized audience even if the remaining quota is zero" do
    add_recipients(1)
    user = campaign.audience.first
    Emails::Gateway.queue_for_send_activity(send_activity: campaign, user: user,
                                            idempotency_key: "send-activity-#{campaign.id}-user-#{user.id}")
    allow(Emails::Activities::Send).to receive(:daily_cap_for).and_return(1)

    described_class.new.perform(campaign.id)

    expect(campaign.reload.status).to eq("succeed")
    expect(campaign.deferred_reason).to be_nil
  end

  it "keeps a live fan-out claim exclusive" do
    add_recipients(1)
    token = Emails::SendActivities::RunDispatch.claim(campaign)

    expect { described_class.new.perform(campaign.id) }.not_to change(Emails::Message, :count)
    expect(campaign.reload.fanout_claim_token).to eq(token)
  end
end
