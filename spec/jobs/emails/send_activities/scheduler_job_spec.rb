# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SchedulerJob, type: :job do
  describe "#perform" do
    let_it_be(:customer) { create(:customer) }
    let!(:due) { create(:email_send_activity, :pending, customer: customer, scheduled_at: 1.minute.ago) }
    let!(:future) { create(:email_send_activity, :pending, customer: customer, scheduled_at: 1.hour.from_now) }
    let!(:already_sent) { create(:email_send_activity, customer: customer, status: "succeed") }
    let!(:email_module) { enable_module!("email", customer, name: "Email") }
    let!(:credential) { create(:email_credential, mode: "sandbox") }

    it "transitions due campaigns to sending" do
      described_class.perform_now
      expect(due.reload.status).to eq("processing")
      expect(future.reload.status).to eq("pending")
      expect(already_sent.reload.status).to eq("succeed")
    end

    it "sets claimed_at when transitioning to sending" do
      freeze_time do
        described_class.perform_now
        expect(due.reload.claimed_at).to eq(Time.current)
      end
    end

    it "enqueues SendActivityJob for each due campaign" do
      expect {
        described_class.perform_now
      }.to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(due.id)
    end

    it "emits a 'started' email_send_activity.lifecycle notification for each claimed campaign" do
      events = []
      callback = ->(*args) { events << ActiveSupport::Notifications::Event.new(*args) }
      ActiveSupport::Notifications.subscribed(callback, "email_send_activity.lifecycle") do
        described_class.perform_now
      end
      started = events.select { |e| e.payload[:event] == "started" }
      expect(started.map { |e| e.payload[:send_activity_id] }).to contain_exactly(due.id)
    end

    context "with recurring campaign" do
      let!(:recurring) {
        create(:email_send_activity, :pending, :recurring,
          customer: customer,
          scheduled_at: 1.minute.ago,
          recurrence_rule: "FREQ=DAILY;INTERVAL=1"
        )
      }

      it "creates next occurrence" do
        expect { described_class.perform_now }
          .to change(Emails::SendActivities::SendActivity, :count).by(1)

        next_occurrence = Emails::SendActivities::SendActivity.where(status: "pending").last
        expect(next_occurrence.scheduled_at).to be > Time.current
        expect(next_occurrence.recurrence_rule).to eq(recurring.recurrence_rule)
      end
    end

    it "rolls a recurring occurrence forward past now when the base time is stale" do
      other_customer = create(:customer)
      ensure_customer_feature_module(other_customer, email_module, status: :active)
      campaign = create(:email_send_activity, :recurring, customer: other_customer,
                        status: "pending", scheduled_at: 5.days.ago)
      described_class.new.perform
      nxt = Emails::SendActivities::SendActivity.where(status: "pending").order(:created_at).last
      expect(nxt.scheduled_at).to be > Time.current
    end

    # ---------------------------------------------------------------------
    # B3: atomic claim eliminates the double-send / duplicate-occurrence race
    # between two overlapping scheduler ticks on the same due campaign.
    # ---------------------------------------------------------------------
    describe "only-winner-sends under a concurrent claim (B3)" do
      it "a campaign already claimed by a concurrent tick is skipped by this tick (no double SendActivityJob)" do
        # Simulate a second, faster scheduler tick that already won the claim
        # before this tick's find_each even looks at the row.
        expect(Emails::SendActivities::SendActivity.claim!(due.id)).to be true
        expect(Emails::SendActivities::SendActivity.claim!(due.id)).to be false

        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(due.id)
      end

      it "creates only one next occurrence for a recurring campaign even when two scheduler ticks race" do
        recurring = create(:email_send_activity, :pending, :recurring,
                           customer: customer, scheduled_at: 1.minute.ago,
                           recurrence_rule: "FREQ=DAILY;INTERVAL=1")

        described_class.perform_now # tick 1: wins the claim, creates the next occurrence
        described_class.perform_now # tick 2: campaign is now 'sending' — not due_for_send, no-op

        expect(
          Emails::SendActivities::SendActivity.where(recurrence_rule: recurring.recurrence_rule).count
        ).to eq(2) # the original occurrence + exactly one next occurrence
        expect(
          Emails::SendActivities::SendActivity.where(status: "pending", recurrence_rule: recurring.recurrence_rule).count
        ).to eq(1)
      end

      it "enqueues SendActivityJob exactly once per due campaign across two overlapping ticks" do
        expect {
          described_class.perform_now
          described_class.perform_now
        }.to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(due.id).exactly(1).times
      end
    end
  end
end
