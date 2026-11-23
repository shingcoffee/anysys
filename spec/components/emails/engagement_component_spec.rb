# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::EngagementComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:since) { 2.days.ago.beginning_of_day }
  let(:until_date) { Time.current.end_of_day }

  around do |example|
    Current.set(customer: customer) { example.run }
  end

  it "renders empty states" do
    render_inline(described_class.new(
      since: since,
      until_date: until_date,
      top_links: {},
      opens_by_hour: {},
      opens_by_day: {},
      devices: {}
    ))

    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.title"))
    expect(page).to have_css("h3", text: I18n.t("admin_modules.emails.analytics.engagement.devices_heading"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.empty_top_links"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.empty_devices"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.empty_opens_by_hour"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.empty_opens_by_day"))
  end

  it "renders engagement data" do
    render_inline(described_class.new(
      since: since,
      until_date: until_date,
      top_links: { "https://example.com/a" => 5, "https://example.com/b" => 3 },
      opens_by_hour: { 9 => 2, 14 => 4 },
      opens_by_day: { 1.day.ago.to_date => 3, Time.current.to_date => 5 },
      devices: { "desktop" => 5, "mobile" => 3 }
    ))

    expect(page).to have_text("https://example.com/a")
    expect(page).to have_text("5")
    expect(page).to have_text("09:00")
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.devices.desktop"))
    expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.devices.mobile"))
    expect(page).to have_css("svg polyline")
  end

  it "keeps the zh-CN device heading distinct from the device label map" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(
        since: since, until_date: until_date, top_links: {}, opens_by_hour: {}, opens_by_day: {},
        devices: { "desktop" => 1 }
      ))

      expect(page).to have_css("h3", text: I18n.t("admin_modules.emails.analytics.engagement.devices_heading"))
      expect(page).to have_text(I18n.t("admin_modules.emails.analytics.engagement.devices.desktop"))
      expect(page).not_to have_text("translation missing")
    end
  end
end
