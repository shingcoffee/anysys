# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivity, type: :model do
  def build_campaign(**overrides)
    build(:email_send_activity, customer: customer, **overrides)
  end

  describe "validations" do
    let_it_be(:customer) { create(:customer) }

    it "requires customer_id" do
      campaign = build(:email_send_activity, customer: nil)
      Current.customer = nil
      expect(campaign).not_to be_valid
    end

    it "requires name" do
      expect(build_campaign(name: nil)).not_to be_valid
    end

    it "requires email_template" do
      expect(build_campaign(email_template: nil)).not_to be_valid
    end

    it "requires at least one email_list" do
      expect(build_campaign(email_lists: [])).not_to be_valid
    end

    it "validates status inclusion" do
      expect(build_campaign(status: "invalid")).not_to be_valid
    end

    it "accepts the 'failed' status (dead-letter)" do
      expect(build_campaign(status: "failed")).to be_valid
    end

    it "validates timezone" do
      expect(build_campaign(timezone: "Invalid/Zone")).not_to be_valid
    end

    it "accepts valid IANA timezone" do
      expect(build_campaign(timezone: "America/New_York")).to be_valid
    end

    it "rejects an email_list belonging to a different customer" do
      other_list = create(:email_list, customer: create(:customer))
      expect {
        build_campaign(email_lists: [other_list])
      }.to raise_error(ActiveRecord::RecordNotSaved)
    end

    it "rejects an email_template belonging to a different customer" do
      other_template = create(:email_template, customer: create(:customer))
      campaign = build_campaign(email_template: other_template)
      expect(campaign).not_to be_valid
      expect(campaign.errors[:email_template_id]).to include(I18n.t("admin_modules.errors.validations.cross_tenant_association"))
    end

    it "accepts an email_list and email_template belonging to the same customer" do
      expect(build_campaign).to be_valid
    end

    it "accepts a recurrence_rule with a supported FREQ/INTERVAL/COUNT" do
      expect(build_campaign(recurrence_rule: "FREQ=WEEKLY;INTERVAL=2;COUNT=5")).to be_valid
    end

    it "accepts a recurrence_rule with a parseable UNTIL (date-only or UTC date-time form)" do
      expect(build_campaign(recurrence_rule: "FREQ=DAILY;UNTIL=20261231")).to be_valid
      expect(build_campaign(recurrence_rule: "FREQ=DAILY;UNTIL=20261231T235900Z")).to be_valid
    end

    it "rejects a recurrence_rule with an unsupported FREQ" do
      campaign = build_campaign(recurrence_rule: "FREQ=YEARLY")
      expect(campaign).not_to be_valid
      expect(campaign.errors[:recurrence_rule]).to include(I18n.t("admin_modules.errors.validations.invalid_recurrence_rule"))
    end

    it "rejects a recurrence_rule with an unsupported part (e.g. BYDAY)" do
      expect(build_campaign(recurrence_rule: "FREQ=WEEKLY;BYDAY=MO")).not_to be_valid
    end

    it "rejects a recurrence_rule with a non-positive INTERVAL" do
      expect(build_campaign(recurrence_rule: "FREQ=DAILY;INTERVAL=0")).not_to be_valid
    end

    it "rejects a recurrence_rule with a non-positive COUNT" do
      expect(build_campaign(recurrence_rule: "FREQ=DAILY;COUNT=-1")).not_to be_valid
    end

    it "rejects a recurrence_rule with an unparseable UNTIL" do
      expect(build_campaign(recurrence_rule: "FREQ=DAILY;UNTIL=not-a-date")).not_to be_valid
    end
  end

  describe "email lists" do
    let(:customer) { create(:customer) }

    it "requires at least one list" do
      activity = build(:email_send_activity, customer: customer, email_lists: [])
      expect(activity).not_to be_valid
      expect(activity.errors[:email_lists]).to include(I18n.t("admin_modules.emails.send_activities.errors.lists_blank"))
    end

    it "rejects assigning more than MAX_EMAIL_LISTS lists via before_add" do
      lists = Array.new(described_class::MAX_EMAIL_LISTS + 1) { create(:email_list, customer: customer) }
      expect {
        build(:email_send_activity, customer: customer, email_lists: lists)
      }.to raise_error(ActiveRecord::RecordNotSaved)
    end

    it "accepts exactly MAX_EMAIL_LISTS lists" do
      lists = Array.new(described_class::MAX_EMAIL_LISTS) { create(:email_list, customer: customer) }
      activity = build(:email_send_activity, customer: customer, email_lists: lists)
      expect(activity).to be_valid
    end

    it "rejects assigning a list from another customer via before_add" do
      other = create(:customer)
      foreign_list = create(:email_list, customer: other)
      expect {
        build(:email_send_activity, customer: customer, email_lists: [foreign_list])
      }.to raise_error(ActiveRecord::RecordNotSaved)
    end

    it "rejects email_lists << when the list belongs to another customer" do
      activity = create(:email_send_activity, customer: customer)
      foreign_list = create(:email_list, customer: create(:customer))

      expect { activity.email_lists << foreign_list }.to raise_error(ActiveRecord::RecordNotSaved)
      expect(activity.reload.email_lists).not_to include(foreign_list)
    end

    it "rejects email_lists << when already at MAX_EMAIL_LISTS" do
      lists = Array.new(described_class::MAX_EMAIL_LISTS) { create(:email_list, customer: customer) }
      activity = create(:email_send_activity, customer: customer, email_lists: lists)
      extra = create(:email_list, customer: customer)

      expect { activity.email_lists << extra }.to raise_error(ActiveRecord::RecordNotSaved)
      expect(activity.reload.email_lists.count).to eq(described_class::MAX_EMAIL_LISTS)
    end

    it "allows replacing email_lists via assignment (clear + re-add)" do
      a = create(:email_list, customer: customer)
      b = create(:email_list, customer: customer)
      c = create(:email_list, customer: customer)
      activity = create(:email_send_activity, customer: customer, email_lists: [a, b])

      activity.email_lists = [b, c]
      activity.save!
      expect(activity.reload.email_lists).to match_array([b, c])
    end
  end

  describe "#audience / #audience_count" do
    let(:customer) { create(:customer) }

    it "unions lists and dedupes by email, keeping the lowest user id, ordered by id" do
      a = create(:user, customer: customer, email: "a@example.com")
      b = create(:user, customer: customer, email: "b@example.com")
      list1 = create(:email_list, customer: customer, list_type: "static")
      list2 = create(:email_list, customer: customer, list_type: "static")
      create(:email_list_membership, email_list: list1, user: a)
      create(:email_list_membership, email_list: list1, user: b)
      create(:email_list_membership, email_list: list2, user: a)
      activity = create(:email_send_activity, customer: customer, email_lists: [ list1, list2 ])

      expect(activity.audience_count).to eq(2)
      expect(activity.audience.map(&:id)).to eq([ a.id, b.id ].sort)
    end

    it "keeps the lowest user id when the same user appears via two lists (defense-in-depth dedupe)" do
      user = create(:user, customer: customer, email: "same@example.com")
      list1 = create(:email_list, customer: customer, list_type: "static")
      list2 = create(:email_list, customer: customer, list_type: "static")
      create(:email_list_membership, email_list: list1, user: user)
      create(:email_list_membership, email_list: list2, user: user)
      activity = create(:email_send_activity, customer: customer, email_lists: [ list1, list2 ])

      expect(activity.audience_count).to eq(1)
      expect(activity.audience.map(&:id)).to eq([ user.id ])
    end

    it "keeps the lowest user id when two users collide on normalized email" do
      low = create(:user, customer: customer, email: "keep@example.com")
      high = create(:user, customer: customer, email: "other@example.com")
      high.update_columns(email: "  KEEP@example.com ")
      list = create(:email_list, customer: customer, list_type: "static")
      create(:email_list_membership, email_list: list, user: low)
      create(:email_list_membership, email_list: list, user: high)
      activity = create(:email_send_activity, customer: customer, email_lists: [list])

      expect(activity.audience_count).to eq(1)
      expect(activity.audience.map(&:id)).to eq([low.id])
    end

    it "unions a static list with a dynamic segment" do
      static_user = create(:user, customer: customer, email: "static@example.com", first_name: "Bob")
      dynamic_user = create(:user, customer: customer, email: "dynamic@example.com", first_name: "Ada")
      static_list = create(:email_list, customer: customer, list_type: "static")
      create(:email_list_membership, email_list: static_list, user: static_user)
      dynamic_list = create(:email_list, :dynamic, customer: customer)
      activity = create(:email_send_activity, customer: customer, email_lists: [static_list, dynamic_list])

      expect(activity.audience_count).to eq(2)
      expect(activity.audience.map(&:id)).to match_array([static_user.id, dynamic_user.id])
    end

    it "returns zero for lists with no members" do
      list = create(:email_list, customer: customer, list_type: "static")
      activity = create(:email_send_activity, customer: customer, email_lists: [ list ])

      expect(activity.audience_count).to eq(0)
      expect(activity.audience.to_a).to eq([])
    end
  end

  describe "STATUSES / TERMINAL_STATUSES" do
    it "includes 'failed' among the statuses" do
      expect(described_class::STATUSES).to include("failed")
    end

    it "treats sent, cancelled, and failed as terminal — nothing else" do
      expect(described_class::TERMINAL_STATUSES).to contain_exactly("succeed", "cancelled", "failed")
    end
  end

  describe "#terminal?" do
    let(:customer) { create(:customer) }

    it "is true for each terminal status" do
      described_class::TERMINAL_STATUSES.each do |status|
        expect(build_campaign(status: status)).to be_terminal
      end
    end

    it "is false for each non-terminal status" do
      (described_class::STATUSES - described_class::TERMINAL_STATUSES).each do |status|
        expect(build_campaign(status: status)).not_to be_terminal
      end
    end
  end

  describe "#status_variant" do
    let(:customer) { create(:customer) }

    described_class::STATUS_BADGE_VARIANTS.each do |status, variant|
      it "maps '#{status}' to :#{variant}" do
        expect(build_campaign(status: status).status_variant).to eq(variant)
      end
    end

    it "falls back to :default for an unmapped status" do
      campaign = build_campaign(status: "pending")
      allow(campaign).to receive(:status).and_return("unmapped")
      expect(campaign.status_variant).to eq(:default)
    end
  end

  describe "#status_label" do
    let(:customer) { create(:customer) }

    it "uses the send-activity pending key, not the generic common pending label" do
      expect(build_campaign(status: "pending").status_label).to eq(
        I18n.t("admin_modules.emails.send_activities.statuses.pending")
      )
    end

    it "localizes pending as 待发送 in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        expect(build_campaign(status: "pending").status_label).to eq("待发送")
      end
    end

    it "returns the raw key for an unknown status" do
      campaign = build_campaign(status: "pending")
      allow(campaign).to receive(:status).and_return("unmapped")
      expect(campaign.status_label).to eq("unmapped")
    end
  end

  describe "scopes" do
    let(:customer) { create(:customer) }
    let!(:scheduled_due) { create(:email_send_activity, customer: customer, status: "pending", scheduled_at: 1.minute.ago) }
    let!(:scheduled_future) { create(:email_send_activity, customer: customer, status: "pending", scheduled_at: 1.hour.from_now) }
    let!(:sent_campaign) { create(:email_send_activity, customer: customer, status: "succeed") }

    it ".due_for_send returns scheduled campaigns past their time" do
      expect(described_class.due_for_send).to contain_exactly(scheduled_due)
    end

    describe ".stalled_sending" do
      let!(:fresh_sending)   { create(:email_send_activity, :processing, customer: customer, claimed_at: 1.minute.ago) }
      let!(:stale_sending)   { create(:email_send_activity, :processing, customer: customer, claimed_at: 1.hour.ago) }
      let!(:unclaimed_sending) do
        c = create(:email_send_activity, :processing, customer: customer)
        c.update_columns(claimed_at: nil)
        c
      end

      it "returns 'sending' campaigns whose claim is stale or nil, excluding a fresh claim" do
        expect(described_class.stalled_sending).to contain_exactly(stale_sending, unclaimed_sending)
      end

      it "honors a custom ttl" do
        expect(described_class.stalled_sending(ttl: 30.seconds)).to include(fresh_sending)
      end
    end
  end

  describe ".claim!" do
    let(:customer) { create(:customer) }
    let(:campaign) { create(:email_send_activity, :pending, customer: customer) }

    it "atomically transitions a scheduled campaign to sending and returns true" do
      freeze_time do
        expect(described_class.claim!(campaign.id)).to be true
        campaign.reload
        expect(campaign.status).to eq("processing")
        expect(campaign.started_at).to eq(Time.current)
        expect(campaign.claimed_at).to eq(Time.current)
      end
    end

    it "returns false and no-ops on a second claim (only the winner proceeds)" do
      expect(described_class.claim!(campaign.id)).to be true
      expect(described_class.claim!(campaign.id)).to be false
    end

    it "returns false for a campaign that isn't 'scheduled'" do
      draft = create(:email_send_activity, customer: customer, status: "succeed")
      expect(described_class.claim!(draft.id)).to be false
    end
  end

  describe ".reclaim_stalled!" do
    let(:customer) { create(:customer) }

    it "reclaims a 'sending' campaign whose claim is stale and returns true" do
      campaign = create(:email_send_activity, :processing, customer: customer, claimed_at: 1.hour.ago)
      freeze_time do
        expect(described_class.reclaim_stalled!(campaign.id)).to be true
        expect(campaign.reload.claimed_at).to eq(Time.current)
      end
    end

    it "reclaims a 'sending' campaign with a nil claim" do
      campaign = create(:email_send_activity, :processing, customer: customer)
      campaign.update_columns(claimed_at: nil)
      expect(described_class.reclaim_stalled!(campaign.id)).to be true
    end

    it "returns false for a campaign whose claim is still live" do
      campaign = create(:email_send_activity, :processing, customer: customer, claimed_at: 1.minute.ago)
      expect(described_class.reclaim_stalled!(campaign.id)).to be false
    end

    it "returns false for a non-processing campaign" do
      campaign = create(:email_send_activity, customer: customer, status: "pending")
      expect(described_class.reclaim_stalled!(campaign.id)).to be false
    end

    it "only the winner of two concurrent reclaim attempts succeeds" do
      campaign = create(:email_send_activity, :processing, customer: customer, claimed_at: 1.hour.ago)
      expect(described_class.reclaim_stalled!(campaign.id)).to be true
      expect(described_class.reclaim_stalled!(campaign.id)).to be false
    end
  end

  describe ".fail_stalled!" do
    let(:customer) { create(:customer) }

    def sending_since(ago, **overrides)
      campaign = create(:email_send_activity, :processing, customer: customer, **overrides)
      campaign.update_columns(started_at: ago)
      campaign
    end

    it "dead-letters a 'sending' campaign older than MAX_SENDING_AGE and records the reason" do
      campaign = sending_since(3.hours.ago)
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be true
      campaign.reload
      expect(campaign.status).to eq("failed")
      expect(campaign.stats["failure_reason"]).to eq("stuck")
    end

    it "preserves existing stats counters when dead-lettering" do
      campaign = sending_since(3.hours.ago, stats: { "sent_count" => 7 })
      described_class.fail_stalled!(campaign, reason: "stuck")
      expect(campaign.reload.stats).to include("sent_count" => 7, "failure_reason" => "stuck")
    end

    it "does NOT fail a 'sending' campaign younger than MAX_SENDING_AGE" do
      campaign = sending_since(5.minutes.ago)
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be false
      expect(campaign.reload.status).to eq("processing")
    end

    it "fails a campaign with a nil started_at (legacy row)" do
      campaign = sending_since(nil)
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be true
    end

    it "returns false for a non-processing campaign" do
      campaign = create(:email_send_activity, customer: customer, status: "cancelled")
      campaign.update_columns(started_at: 3.hours.ago)
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be false
    end

    it "only the winner of two concurrent dead-letter attempts succeeds" do
      campaign = sending_since(3.hours.ago)
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be true
      expect(described_class.fail_stalled!(campaign, reason: "stuck")).to be false
    end
  end

  describe "status transitions" do
    let(:customer) { create(:customer) }
    let(:campaign) { create(:email_send_activity, customer: customer, status: "pending") }

    it "#complete! atomically transitions sending to sent and returns true" do
      campaign.update!(status: "processing")
      freeze_time do
        expect(campaign.complete!).to be true
        expect(campaign.status).to eq("succeed")
        expect(campaign.completed_at).to eq(Time.current)
      end
    end

    it "#complete! is atomic — only the first of two concurrent completes transitions/returns true" do
      campaign.update!(status: "processing")
      expect(campaign.complete!).to be true
      expect(campaign.complete!).to be false
    end

    it "#complete! is a no-op returning false unless the campaign is processing" do
      campaign.update!(status: "pending")
      expect(campaign.complete!).to be false
      expect(campaign.status).to eq("pending")
    end

    it "#cancel! atomically transitions to cancelled and returns true" do
      expect(campaign.cancel!).to be true
      expect(campaign.status).to eq("cancelled")
    end

    described_class::NON_TERMINAL_STATUSES.each do |source_status|
      it "#cancel! transitions from '#{source_status}'" do
        campaign.update!(status: source_status)
        expect(campaign.cancel!).to be true
        expect(campaign.reload.status).to eq("cancelled")
      end
    end

    it "#cancel! is atomic — only the first of two concurrent cancels transitions/returns true" do
      expect(campaign.cancel!).to be true
      expect(campaign.cancel!).to be false
    end

    describe "terminal guard matrix — no transition regresses out of a terminal status" do
      described_class::TERMINAL_STATUSES.each do |terminal_status|
        context "when the campaign is already '#{terminal_status}'" do
          let(:terminal_campaign) { create(:email_send_activity, customer: customer, status: terminal_status) }

          it "#complete! no-ops, returning false" do
            expect(terminal_campaign.complete!).to be false
            expect(terminal_campaign.status).to eq(terminal_status)
          end

          it "#cancel! no-ops, returning false" do
            expect(terminal_campaign.cancel!).to be false
            expect(terminal_campaign.status).to eq(terminal_status)
          end
        end
      end
    end
  end

  describe "#touch_claim!" do
    let(:customer) { create(:customer) }
    let(:campaign) { create(:email_send_activity, :processing, customer: customer, claimed_at: 1.hour.ago) }

    it "refreshes claimed_at to now" do
      freeze_time do
        campaign.touch_claim!
        expect(campaign.reload.claimed_at).to eq(Time.current)
      end
    end
  end

  describe "#recurring?" do
    let(:customer) { create(:customer) }

    it "returns true when recurrence_rule present" do
      expect(build_campaign(recurrence_rule: "FREQ=DAILY").recurring?).to be true
    end

    it "returns false when blank" do
      expect(build_campaign(recurrence_rule: nil).recurring?).to be false
    end
  end

  describe "#increment_stat!" do
    let(:campaign) { create(:email_send_activity, stats: {}) }

    it "increments named stat" do
      campaign.increment_stat!(:sent_count)
      expect(campaign.reload.stats["sent_count"]).to eq(1)
      campaign.increment_stat!(:sent_count)
      expect(campaign.reload.stats["sent_count"]).to eq(2)
    end

    it "increments by an arbitrary amount" do
      campaign.increment_stat!(:sent_count, by: 5)
      expect(campaign.reload.stats["sent_count"]).to eq(5)
    end
  end

  describe "#delivery_counts" do
    let(:customer) { create(:customer) }
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:other_campaign) { create(:email_send_activity, customer: customer) }

    it "rolls up Emails::Message counts by status for this campaign only, via email_send_activity_id" do
      create(:email_message, customer: customer, email_send_activity_id: campaign.id, message_type: "campaign", status: "delivered")
      create(:email_message, customer: customer, email_send_activity_id: campaign.id, message_type: "campaign", status: "delivered")
      create(:email_message, customer: customer, email_send_activity_id: campaign.id, message_type: "campaign", status: "bounced")
      # A message on a different campaign must not bleed into these counts.
      create(:email_message, customer: customer, email_send_activity_id: other_campaign.id, message_type: "campaign", status: "delivered")
      # A transactional message (no email_send_activity_id) must not bleed in either.
      create(:email_message, customer: customer, message_type: "transactional", status: "delivered")

      expect(campaign.delivery_counts).to eq("delivered" => 2, "bounced" => 1)
    end

    it "returns an empty hash when nothing has been sent yet" do
      expect(campaign.delivery_counts).to eq({})
    end
  end
end
