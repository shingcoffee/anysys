# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncement, type: :model do
  describe "constants" do
    it "exposes the locked severity, status, and audience sets" do
      expect(described_class::SEVERITIES).to eq(%w[info warning critical])
      expect(described_class::STATUSES).to eq(%w[draft published])
      expect(described_class::AUDIENCES).to eq(%w[all selected])
    end
  end

  describe "#live?" do
    let(:now) { Time.zone.parse("2026-08-29 12:00:00") }

    it "is hidden when starts_at is in the future" do
      announcement = build(:platform_announcement, :published, starts_at: now + 1.hour)
      expect(announcement.live?(now: now)).to be false
    end

    it "is hidden when ends_at is in the past" do
      announcement = build(:platform_announcement, :published, ends_at: now)
      expect(announcement.live?(now: now)).to be false
    end

    it "is live when the window is nil" do
      announcement = build(:platform_announcement, :published, starts_at: nil, ends_at: nil)
      expect(announcement.live?(now: now)).to be true
    end

    it "is live when now is inside the window" do
      announcement = build(
        :platform_announcement, :published,
        starts_at: now - 1.hour, ends_at: now + 1.hour
      )
      expect(announcement.live?(now: now)).to be true
    end

    it "is not live when status is draft" do
      announcement = build(:platform_announcement, :draft)
      expect(announcement.live?(now: now)).to be false
    end

    it "is not live when deleted_at is present" do
      announcement = build(:platform_announcement, :published, deleted_at: now)
      expect(announcement.live?(now: now)).to be false
    end
  end

  describe "#targeted_at?" do
    it "returns true for any customer when audience is all" do
      announcement = create(:platform_announcement, :published, :all_customers)
      later = create(:customer)
      expect(announcement.targeted_at?(later.id)).to be true
    end

    it "returns true only for customers matching selected target_rules" do
      targeted = create(:customer)
      other = create(:customer)
      announcement = create(
        :platform_announcement, :published, :selected,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => targeted.id.to_s }
          ]
        }
      )

      expect(announcement.targeted_at?(targeted.id)).to be true
      expect(announcement.targeted_at?(other.id)).to be false
    end
  end

  describe "#body_for" do
    let(:announcement) { build(:platform_announcement, body_en: "Hello", body_zh: "你好") }

    it "returns body_zh for zh locales" do
      expect(announcement.body_for(:zh)).to eq("你好")
      expect(announcement.body_for("zh-CN")).to eq("你好")
    end

    it "returns body_en for non-zh locales" do
      expect(announcement.body_for(:en)).to eq("Hello")
      expect(announcement.body_for("en-US")).to eq("Hello")
    end
  end

  describe "#matching_customers" do
    it "returns customers that currently match selected target_rules" do
      matching = create(:customer, name: "Acme")
      create(:customer, name: "Other")
      announcement = create(
        :platform_announcement, :selected,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => matching.id.to_s }
          ]
        }
      )

      expect(announcement.matching_customers).to eq([ matching ])
    end

    it "returns none when audience is all" do
      create(:customer)
      announcement = create(:platform_announcement, :all_customers)
      expect(announcement.matching_customers).to be_empty
    end
  end

  describe "lifecycle" do
    let(:now) { Time.zone.parse("2026-08-29 12:00:00") }

    it "is :draft while unpublished, whatever the window says" do
      announcement = build(:platform_announcement, :draft, starts_at: now - 1.hour, ends_at: now + 1.hour)
      expect(announcement.lifecycle(now: now)).to eq(:draft)
      expect(announcement.scheduled?(now: now)).to be false
      expect(announcement.ended?(now: now)).to be false
    end

    it "is :scheduled before the window opens" do
      announcement = build(:platform_announcement, :published, starts_at: now + 1.hour)
      expect(announcement.lifecycle(now: now)).to eq(:scheduled)
      expect(announcement.scheduled?(now: now)).to be true
    end

    it "is :live inside the window" do
      announcement = build(:platform_announcement, :published, starts_at: now - 1.hour, ends_at: now + 1.hour)
      expect(announcement.lifecycle(now: now)).to eq(:live)
    end

    it "is :ended once the window closes" do
      announcement = build(:platform_announcement, :published, ends_at: now)
      expect(announcement.lifecycle(now: now)).to eq(:ended)
      expect(announcement.ended?(now: now)).to be true
    end

    it "is :live with an open-ended window" do
      expect(build(:platform_announcement, :published).lifecycle(now: now)).to eq(:live)
    end
  end

  describe "audience predicates" do
    it "distinguishes an all-customers broadcast from a segment" do
      broadcast = build(:platform_announcement, :all_customers)
      segment   = build(:platform_announcement, :selected)

      expect(broadcast.all_customers?).to be true
      expect(broadcast.segmented?).to be false
      expect(segment.all_customers?).to be false
      expect(segment.segmented?).to be true
    end
  end

  describe "scopes" do
    let(:now) { Time.zone.parse("2026-08-29 12:00:00") }

    it ".live keeps only published rows inside their window" do
      live      = create(:platform_announcement, :published, starts_at: now - 1.hour, ends_at: now + 1.hour)
      create(:platform_announcement, :draft)
      create(:platform_announcement, :published, starts_at: now + 1.hour)
      create(:platform_announcement, :published, ends_at: now)

      expect(described_class.live(now)).to eq([ live ])
    end

    it ".live excludes discarded rows even when still inside the window" do
      live = create(:platform_announcement, :published, starts_at: now - 1.hour, ends_at: now + 1.hour)
      discarded = create(:platform_announcement, :published, starts_at: now - 1.hour, ends_at: now + 1.hour)
      discarded.update_column(:deleted_at, now)

      expect(described_class.live(now)).to eq([ live ])
    end

    it ".kept excludes discarded rows without hiding them from the unscoped relation" do
      kept = create(:platform_announcement, :published)
      discarded = create(:platform_announcement, :published)
      discarded.update_column(:deleted_at, now)

      expect(described_class.kept).to eq([ kept ])
      expect(described_class.all).to include(kept, discarded)
    end

    it ".newest_first orders by creation, newest first" do
      old = create(:platform_announcement, :published)
      new = create(:platform_announcement, :published)
      old.update_column(:created_at, 2.days.ago)
      new.update_column(:created_at, 1.day.ago)

      expect(described_class.newest_first.to_a).to eq([ new, old ])
    end

    it ".dismissed_by selects only what that user dismissed in that tenant" do
      customer     = create(:customer)
      admin        = create(:user, :admin, customer: customer)
      dismissed    = create(:platform_announcement, :published)
      create(:platform_announcement, :published)
      PlatformAnnouncementDismissal.record!(announcement: dismissed, user_id: admin.id, customer_id: customer.id)

      expect(described_class.dismissed_by(admin.id, customer.id)).to eq([ dismissed ])
    end
  end

  describe "#discard_or_destroy!" do
    let(:now) { Time.zone.parse("2026-08-31 12:00:00") }

    it "soft-deletes a live announcement and stamps left_live_at" do
      record = create(:platform_announcement, :published)

      travel_to(now) { record.discard_or_destroy! }

      record.reload
      expect(record.deleted_at).to be_within(1.second).of(now)
      expect(record.left_live_at).to be_within(1.second).of(now)
      expect(described_class.exists?(record.id)).to be true
    end

    it "soft-deletes an ended announcement and sets left_live_at to ends_at" do
      ends_at = now - 1.hour
      record = create(:platform_announcement, :published, ends_at: ends_at)

      travel_to(now) { record.discard_or_destroy! }

      record.reload
      expect(record.deleted_at).to be_within(1.second).of(now)
      expect(record.left_live_at).to be_within(1.second).of(ends_at)
      expect(described_class.exists?(record.id)).to be true
    end

    it "soft-deletes a previously unpublished row and keeps left_live_at" do
      stamped = now - 2.days
      record = create(:platform_announcement, :draft, left_live_at: stamped)

      travel_to(now) { record.discard_or_destroy! }

      record.reload
      expect(record.deleted_at).to be_within(1.second).of(now)
      expect(record.left_live_at).to be_within(1.second).of(stamped)
    end

    it "hard-destroys a never-live draft" do
      record = create(:platform_announcement, :draft)

      record.discard_or_destroy!

      expect(described_class.find_by(id: record.id)).to be_nil
    end

    it "hard-destroys a scheduled announcement that never went live" do
      travel_to(now) do
        record = create(:platform_announcement, :published, starts_at: now + 1.day)
        expect(record).to be_scheduled

        record.discard_or_destroy!

        expect(described_class.find_by(id: record.id)).to be_nil
      end
    end

    it "retains a rescheduled announcement's prior live history when discarded" do
      travel_to(now) do
        stamp = now - 2.days
        record = create(:platform_announcement, :published, starts_at: now + 1.day, left_live_at: stamp)
        expect(record).to be_scheduled

        record.discard_or_destroy!

        expect(record.reload.deleted_at).to eq(now)
        expect(record.left_live_at).to eq(stamp)
        expect(described_class.exists?(record.id)).to be(true)
      end
    end
  end
end
