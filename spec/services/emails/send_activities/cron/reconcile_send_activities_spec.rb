# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::Cron::ReconcileSendActivities do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }
  let_it_be(:email_module) { enable_module!("email", customer_a, name: "Email") }

  before { enable_module!("email", customer_b, name: "Email") }

  def stalled_campaign(customer:, claimed_at: 1.hour.ago, started_at: 5.minutes.ago)
    campaign = create(:email_send_activity, :processing, customer: customer)
    campaign.update_columns(claimed_at: claimed_at, started_at: started_at)
    campaign
  end

  # Older than MAX_SENDING_AGE — a deterministically-failing campaign that would
  # otherwise be reclaimed + re-driven every cycle forever.
  def stuck_campaign(customer:)
    stalled_campaign(customer: customer, started_at: (Emails::SendActivities::SendActivity::MAX_SENDING_AGE + 1.hour).ago)
  end

  it "re-enqueues SendActivityJob for a campaign stuck 'sending' past CLAIM_TTL" do
    stalled = stalled_campaign(customer: customer_a)

    expect { described_class.call }
      .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(stalled.id)
  end

  it "does not re-drive a stalled campaign when the Email module is disabled" do
    stalled = stalled_campaign(customer: customer_a)
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer_a, feature_module: email_module
    ).update!(status: :suspended)

    expect { described_class.call }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
    expect(stalled.reload.status).to eq("processing")
  end

  it "refreshes claimed_at on the reclaimed campaign" do
    stalled = stalled_campaign(customer: customer_a)
    freeze_time do
      described_class.call
      expect(stalled.reload.claimed_at).to eq(Time.current)
    end
  end

  it "re-enqueues a campaign with a nil claimed_at (never claimed / legacy row)" do
    stalled = create(:email_send_activity, :processing, customer: customer_a)
    stalled.update_columns(claimed_at: nil)

    expect { described_class.call }
      .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(stalled.id)
  end

  it "does not touch a campaign whose claim is still live (within CLAIM_TTL)" do
    live = stalled_campaign(customer: customer_a, claimed_at: 1.minute.ago)

    expect { described_class.call }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
    expect(live.reload.claimed_at).to be_within(2.seconds).of(1.minute.ago)
  end

  it "ignores campaigns that are not in the 'processing' status" do
    scheduled = create(:email_send_activity, :pending, customer: customer_a)
    cancelled = create(:email_send_activity, customer: customer_a, status: "cancelled")

    expect { described_class.call }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
  end

  it "runs cross-tenant in one sweep (no Current.customer tenant filter)" do
    Current.customer = nil
    a = stalled_campaign(customer: customer_a)
    b = stalled_campaign(customer: customer_b)

    freeze_time do
      described_class.call
      expect(a.reload.claimed_at).to eq(Time.current)
      expect(b.reload.claimed_at).to eq(Time.current)
    end
  end

  it "rescues an error reclaiming one stalled campaign and continues re-driving the rest" do
    bad  = stalled_campaign(customer: customer_a)
    good = stalled_campaign(customer: customer_b)

    allow(Emails::SendActivities::SendActivity).to receive(:reclaim_stalled!).and_call_original
    allow(Emails::SendActivities::SendActivity).to receive(:reclaim_stalled!).with(bad.id).and_raise(StandardError, "boom")

    expect { described_class.call }.not_to raise_error

    expect(
      ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |j| j["arguments"] == [good.id] }
    ).to be true
  end

  # B6: only the winner of two overlapping reaper sweeps re-drives a given
  # stalled campaign — reclaim_stalled! is the same atomic conditional
  # update_all pattern as Campaign.claim!.
  describe "atomic reclaim across concurrent reaper sweeps" do
    it "only one of two concurrent reclaim attempts on the same campaign succeeds" do
      stalled = stalled_campaign(customer: customer_a)

      expect(Emails::SendActivities::SendActivity.reclaim_stalled!(stalled.id)).to be true
      expect(Emails::SendActivities::SendActivity.reclaim_stalled!(stalled.id)).to be false
    end

    it "a campaign already reclaimed by a concurrent sweep is not re-enqueued a second time" do
      stalled = stalled_campaign(customer: customer_a)
      expect(Emails::SendActivities::SendActivity.reclaim_stalled!(stalled.id)).to be true

      # This sweep's stalled_sending scope was captured before the concurrent
      # reclaim above; its own reclaim_stalled! call must lose.
      expect { described_class.call }
        .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(stalled.id).exactly(0).times
    end
  end

  # B6 dead-letter cap: a campaign stuck `sending` past MAX_SENDING_AGE is
  # failed instead of re-driven forever.
  describe "dead-letter cap for a deterministically-failing campaign" do
    it "transitions a campaign stuck past MAX_SENDING_AGE to 'failed' and does NOT re-enqueue" do
      stuck = stuck_campaign(customer: customer_a)

      expect { described_class.call }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      stuck.reload
      expect(stuck.status).to eq("failed")
      expect(stuck.stats["failure_reason"]).to be_present
    end

    it "does not re-drive the campaign on a subsequent reaper cycle once dead-lettered" do
      stuck = stuck_campaign(customer: customer_a)
      described_class.call
      expect(stuck.reload.status).to eq("failed")

      # Second cycle: already terminal, no longer in stalled_sending, nothing enqueued.
      expect { described_class.call }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
    end

    it "still reclaims + re-enqueues a freshly-stalled campaign under MAX_SENDING_AGE" do
      fresh = stalled_campaign(customer: customer_a, started_at: 5.minutes.ago)

      expect { described_class.call }
        .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(fresh.id)
      expect(fresh.reload.status).to eq("processing")
    end

    it "does not dead-letter a campaign that is only waiting on the daily send cap" do
      stuck = stuck_campaign(customer: customer_a)
      allow(Emails::SendActivities::SendActivityJob).to receive(:remaining_daily_cap)
        .and_return(0)

      expect { described_class.call }
        .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(stuck.id)
      expect(stuck.reload.status).to eq("processing")
    end
  end
end
