# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::StartSendActivity do
  let_it_be(:customer) { create(:customer) }

  around { |ex| Current.set(customer: customer) { ex.run } }

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  describe ".call" do
    it "atomically claims a scheduled campaign, enqueues the send, and returns true" do
      campaign = create(:email_send_activity, :pending, customer: customer, scheduled_at: 1.minute.ago)

      expect { expect(described_class.call(campaign)).to be(true) }
        .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(campaign.id)
      expect(campaign.reload.status).to eq("processing")
    end

    it "starts a draft campaign" do
      campaign = create(:email_send_activity, customer: customer, status: "pending")
      expect(described_class.call(campaign)).to be(true)
      expect(campaign.reload.status).to eq("processing")
    end

    it "is a no-op (false) when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)
      campaign = create(:email_send_activity, :pending, customer: customer, scheduled_at: 1.minute.ago)

      expect { expect(described_class.call(campaign)).to be(false) }
        .not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      expect(campaign.reload.status).to eq("pending")
    end

    it "is a no-op (false) for a non-pending campaign and enqueues nothing" do
      %w[processing succeed cancelled failed].each do |status|
        campaign = create(:email_send_activity, customer: customer, status: status)
        expect { expect(described_class.call(campaign)).to be(false) }
          .not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      end
    end

    it "only one of two concurrent calls wins the claim" do
      campaign = create(:email_send_activity, :pending, customer: customer, scheduled_at: 1.minute.ago)
      results = [described_class.call(campaign), described_class.call(Emails::SendActivities::SendActivity.find(campaign.id))]
      expect(results).to contain_exactly(true, false)
    end

    it "rejects Aliyun campaign transport before a claim, fan-out enqueue, or recurrence successor" do
      credential.update!(status: "disabled")
      aliyun = create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
                      config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
      campaign = create(:email_send_activity, :recurring, customer: customer, scheduled_at: 1.minute.ago)

      expect {
        expect { expect(described_class.call(campaign)).to be(false) }
          .not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      }.not_to change(Emails::SendActivities::SendActivity, :count)
      expect(campaign.errors[:base]).to include(I18n.t("email.providers.errors.unsupported_campaign", provider: aliyun.provider_class.display_name))
      expect(campaign.reload.status).to eq("pending")
      expect(campaign.started_at).to be_nil
    end

    it "rechecks capability after a scheduled campaign was built with another vendor" do
      campaign = create(:email_send_activity, customer: customer, scheduled_at: 1.minute.ago)
      credential.update!(status: "disabled")
      create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
             config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })

      expect(described_class.call(campaign, due_only: true)).to be(false)
      expect(campaign.reload.status).to eq("pending")
    end

    context "recurring campaign started manually (the recurrence-chain bug)" do
      it "schedules the next occurrence even on a manual/immediate start" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago, recurrence_rule: "FREQ=DAILY;INTERVAL=1")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)
        expect(nxt.count).to eq(1)
        expect(nxt.first.scheduled_at).to be > Time.current
        expect(nxt.first.recurrence_rule).to eq("FREQ=DAILY;INTERVAL=1")
      end
    end

    context "multi-list recurring campaign" do
      it "copies all email_lists onto the next occurrence" do
        lists = create_list(:email_list, 2, customer: customer)
        activity = create(:email_send_activity, :pending, :recurring, customer: customer,
                          email_lists: lists, scheduled_at: 1.minute.ago)

        described_class.call(activity)

        nxt = Emails::SendActivities::SendActivity.where(customer: customer).where.not(id: activity.id).order(:id).last
        expect(nxt.email_lists).to match_array(lists)
      end
    end

    context "COUNT-bounded recurrence" do
      it "decrements COUNT on the cloned next occurrence" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago, recurrence_rule: "FREQ=DAILY;COUNT=3")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id).sole
        expect(nxt.recurrence_rule).to eq("FREQ=DAILY;COUNT=2")
      end

      it "schedules no next occurrence once COUNT reaches 1" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago, recurrence_rule: "FREQ=DAILY;COUNT=1")

        described_class.call(campaign)

        expect(Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)).to be_none
      end
    end

    context "UNTIL-bounded recurrence" do
      it "schedules the next occurrence when it falls on or before UNTIL" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago, recurrence_rule: "FREQ=DAILY;UNTIL=#{2.days.from_now.strftime('%Y%m%d')}")

        described_class.call(campaign)

        expect(Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)).to be_one
      end

      it "schedules no next occurrence once it would fall after UNTIL" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago, recurrence_rule: "FREQ=DAILY;UNTIL=#{Date.current.strftime('%Y%m%d')}")

        described_class.call(campaign)

        expect(Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)).to be_none
      end

      it "schedules the next occurrence when it falls on or before a full UTC date-time UNTIL" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago,
                          recurrence_rule: "FREQ=DAILY;UNTIL=#{2.days.from_now.strftime('%Y%m%dT%H%M%SZ')}")

        described_class.call(campaign)

        expect(Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)).to be_one
      end

      it "schedules no next occurrence once it would fall after a full UTC date-time UNTIL" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 1.minute.ago,
                          recurrence_rule: "FREQ=DAILY;UNTIL=#{Time.current.strftime('%Y%m%dT%H%M%SZ')}")

        described_class.call(campaign)

        expect(Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id)).to be_none
      end
    end

    context "MONTHLY and HOURLY FREQ arms" do
      it "advances a MONTHLY rule by INTERVAL months" do
        base = 1.minute.ago
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: base, recurrence_rule: "FREQ=MONTHLY;INTERVAL=1")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id).sole
        expect(nxt.scheduled_at).to be_within(1.minute).of(base + 1.month)
      end

      it "advances an HOURLY rule by INTERVAL hours" do
        base = 1.minute.ago
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: base, recurrence_rule: "FREQ=HOURLY;INTERVAL=2")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id).sole
        expect(nxt.scheduled_at).to be_within(1.minute).of(base + 2.hours)
      end
    end

    context "catch-up loop (a run delayed past several occurrences must not emit a past occurrence)" do
      it "advances a DAILY rule strictly into the future, skipping already-past occurrences" do
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: 3.days.ago, recurrence_rule: "FREQ=DAILY;INTERVAL=1")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id).sole
        expect(nxt.scheduled_at).to be > Time.current
        expect(nxt.scheduled_at).to be <= Time.current + 1.day
      end
    end

    context "timezone-aware recurrence arithmetic (DST safety)" do
      it "advances in the campaign's own timezone so a WEEKLY step crossing a US DST boundary preserves local wall-clock time" do
        # 2026-03-01 09:00 America/New_York is EST (UTC-5); one week later,
        # 2026-03-08 09:00, is after the March 8 2026 US spring-forward and is
        # EDT (UTC-4). A naive UTC + 7.days would land at 08:00 local instead.
        base = ActiveSupport::TimeZone["America/New_York"].parse("2026-03-01 09:00:00")
        campaign = create(:email_send_activity, :pending, customer: customer,
                          scheduled_at: base, timezone: "America/New_York",
                          recurrence_rule: "FREQ=WEEKLY;INTERVAL=1")

        described_class.call(campaign)

        nxt = Emails::SendActivities::SendActivity.where(status: "pending").where.not(id: campaign.id).sole
        local = nxt.scheduled_at.in_time_zone("America/New_York")
        expect(local.hour).to eq(9)
        expect(local.min).to eq(0)
      end
    end
  end

  describe ".timezone_preview" do
    it "returns the next N occurrences considering the campaign timezone" do
      base = ActiveSupport::TimeZone["America/New_York"].parse("2026-03-01 09:00:00")
      campaign = create(:email_send_activity, :pending, customer: customer,
                        scheduled_at: base, timezone: "America/New_York",
                        recurrence_rule: "FREQ=WEEKLY;INTERVAL=1;COUNT=3")

      preview = described_class.timezone_preview(campaign, limit: 5)

      expect(preview.length).to eq(3)
      expect(preview[0]).to eq(base)
      expect(preview[1].in_time_zone("America/New_York").hour).to eq(9)
      expect(preview[2].in_time_zone("America/New_York").hour).to eq(9)
    end

    it "returns empty array if not recurring" do
      campaign = create(:email_send_activity, customer: customer)
      expect(described_class.timezone_preview(campaign)).to eq([])
    end
  end
end
