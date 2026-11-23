# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::AnnouncementPresenter do
  let(:now) { Time.zone.parse("2026-08-29 12:00:00") }

  def present(announcement) = described_class.new(announcement)

  describe "#severity_badge" do
    {
      "info" => :info, "warning" => :warning, "critical" => :danger
    }.each do |severity, variant|
      it "maps #{severity} to the #{variant} variant" do
        badge = present(build(:platform_announcement, severity: severity)).severity_badge

        expect(badge[:variant]).to eq(variant)
        expect(badge[:label]).to eq(I18n.t("maint_platform.announcements.severities.#{severity}"))
      end
    end

    it "falls back to the default variant and the raw value for an unknown severity" do
      badge = present(build(:platform_announcement, severity: "nope")).severity_badge

      expect(badge[:variant]).to eq(:default)
      expect(badge[:label]).to eq("nope")
    end
  end

  describe "#status_badge" do
    it "maps published to success and draft to default" do
      expect(present(build(:platform_announcement, :published)).status_badge[:variant]).to eq(:success)
      expect(present(build(:platform_announcement, :draft)).status_badge[:variant]).to eq(:default)
    end
  end

  describe "#lifecycle_badge" do
    it "reports draft" do
      badge = present(build(:platform_announcement, :draft)).lifecycle_badge(now: now)

      expect(badge[:variant]).to eq(:default)
      expect(badge[:label]).to eq(I18n.t("maint_platform.announcements.lifecycle.draft"))
    end

    it "reports scheduled before the window opens" do
      announcement = build(:platform_announcement, :published, starts_at: now + 1.hour)

      expect(present(announcement).lifecycle_badge(now: now)[:label])
        .to eq(I18n.t("maint_platform.announcements.lifecycle.scheduled"))
    end

    it "reports live inside the window" do
      announcement = build(:platform_announcement, :published, starts_at: now - 1.hour, ends_at: now + 1.hour)
      badge = present(announcement).lifecycle_badge(now: now)

      expect(badge[:variant]).to eq(:success)
      expect(badge[:label]).to eq(I18n.t("maint_platform.announcements.lifecycle.live"))
    end

    it "reports ended after the window closes" do
      announcement = build(:platform_announcement, :published, ends_at: now - 1.hour)

      expect(present(announcement).lifecycle_badge(now: now)[:label])
        .to eq(I18n.t("maint_platform.announcements.lifecycle.ended"))
    end
  end

  describe "#audience_label" do
    it "does not run a segment count, so index rows stay cheap" do
      announcement = build(:platform_announcement, :selected)
      expect(announcement).not_to receive(:matching_customers)

      expect(present(announcement).audience_label)
        .to eq(I18n.t("maint_platform.announcements.audience.selected"))
    end

    it "labels an all-customers broadcast" do
      expect(present(build(:platform_announcement, :all_customers)).audience_label)
        .to eq(I18n.t("maint_platform.announcements.audience.all"))
    end
  end

  describe "timestamps" do
    it "formats present values and dashes blank ones" do
      announcement = build(:platform_announcement, starts_at: now, ends_at: nil)
      presenter = present(announcement)

      expect(presenter.starts_at).to eq(I18n.l(now, format: :long))
      expect(presenter.ends_at).to eq(I18n.t("common.labels.em_dash"))
    end

    it "localizes timestamps in zh-CN" do
      announcement = build(:platform_announcement, starts_at: now)
      I18n.with_locale(:"zh-CN") do
        expect(present(announcement).starts_at).to eq(I18n.l(now, format: :long))
      end
    end
  end

  describe "#link_url" do
    it "normalizes a blank link to nil" do
      expect(present(build(:platform_announcement, link_url: "")).link_url).to be_nil
      expect(present(build(:platform_announcement, link_url: "https://x.test")).link_url).to eq("https://x.test")
    end
  end
end
