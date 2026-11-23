# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Captcha::StatusComponent, type: :component do
  let(:configured_settings) { build(:captcha_provider_settings) }
  let(:unconfigured_settings) { build(:captcha_provider_settings, access_key_id: nil, config: {}.to_json) }
  let(:unknown_provider_settings) { build(:captcha_provider_settings, provider: "my_custom_provider") }
  let(:customer_id) { "81721200" }

  let(:pages) do
    [
      { id: 1, name: "Contact us", public_path: "/81721200/page/aaa-111", launched: true, update_url: "/81721200/admin/settings/modules/captcha/pages/1", preset: "5_per_1min" },
      { id: 2, name: "Event RSVP", public_path: "/81721200/page/bbb-222", launched: false, update_url: "/81721200/admin/settings/modules/captcha/pages/2", preset: "100_per_5min" },
      { id: 3, name: "Survey", public_path: "/81721200/page/ccc-333", launched: true, update_url: "/81721200/admin/settings/modules/captcha/pages/3", preset: "every_hit" }
    ]
  end

  def build_status(settings:, module_enabled:, pages: self.pages)
    described_class.new(
      settings: settings,
      module_enabled: module_enabled,
      pages: pages,
      customer_id: customer_id
    )
  end

  describe "enabled and configured" do
    before do
      render_inline(build_status(settings: configured_settings, module_enabled: true))
    end

    it "renders the provider name on the pages card" do
      expect(page).to have_text("Public page request limits")
      expect(page).to have_text("Platform-managed provider: Aliyun Captcha")
    end

    it "does not render the module-disabled warning" do
      expect(page).not_to have_text("This module is disabled")
    end

    it "does not render the credentials-missing warning" do
      expect(page).not_to have_text("Captcha credentials are not configured")
    end

    it "renders page search and explains the two save behaviors" do
      expect(page).to have_css("h2", text: "Public page request limits")
      expect(page).to have_css("[data-controller='captcha-page-list']")
      expect(page).to have_field("Search public pages")
      expect(page).to have_text("Preset choices save immediately; custom limits save when you select Apply.")
      expect(page).not_to have_css(".text-label", text: "URL")
      expect(page).not_to have_css(".text-label", text: "Rate")
      expect(page).not_to have_text("3 protected")
      expect(page).not_to have_text("pages have captcha enabled")
    end

    it "renders launched and not-launched badges" do
      expect(page).to have_text("Contact us")
      expect(page).to have_text("Launched")
      expect(page).to have_text("Event RSVP")
      expect(page).to have_text("Not launched")
    end

    it "keeps public addresses in named links instead of exposing internal IDs" do
      expect(page).to have_link("Open page", href: "/81721200/page/aaa-111")
      expect(page).to have_link("Open page", href: "/81721200/page/bbb-222")
      expect(page).not_to have_text("aaa-111")
      expect(page).not_to have_text("bbb-222")
    end

    it "renders throttle pickers with aria-labels and the tenant page PATCH path" do
      expect(page).to have_css('button[aria-label="Access throttle for Contact us"]')
      expect(page).to have_css("form[action='/81721200/admin/settings/modules/captcha/pages/1']")
    end

    it "does not include Skip captcha in the tenant rate picker" do
      expect(page).not_to have_css("option[value='skip']", visible: :all)
    end
  end

  describe "module disabled" do
    before do
      render_inline(build_status(settings: configured_settings, module_enabled: false, pages: []))
    end

    it "renders the module-disabled warning" do
      expect(page).to have_text("Protection disabled")
    end

    it "renders the empty public-pages state" do
      expect(page).to have_text("No public pages yet. Pages set to Public will appear here, including unpublished ones.")
      expect(page).not_to have_text("0 protected")
      expect(page).not_to have_css("button[role=switch]")
      expect(page).not_to have_css("select")
      expect(page).not_to have_field("Search public pages")
    end
  end

  describe "credentials not configured" do
    before do
      render_inline(build_status(settings: unconfigured_settings, module_enabled: true, pages: [pages.first]))
    end

    it "renders the credentials-missing warning" do
      expect(page).to have_text("Setup unavailable")
      expect(page).not_to have_text("Provider configured")
    end

    it "does not render the module-disabled warning" do
      expect(page).not_to have_text("This module is disabled")
    end

    it "still renders the page throttle picker" do
      expect(page).to have_css('button[aria-label="Access throttle for Contact us"]')
    end
  end

  describe "#provider_name" do
    it "returns the registered provider display name" do
      component = build_status(settings: configured_settings, module_enabled: true, pages: [])
      expect(component.provider_name).to eq("Aliyun Captcha")
    end

    it "uses a translated unavailable state for an unknown provider" do
      component = build_status(settings: unknown_provider_settings, module_enabled: true, pages: [])
      expect(component.provider_name).to eq("Provider unavailable")
    end

    it "does not expose an unknown provider's internal key" do
      render_inline(build_status(settings: unknown_provider_settings, module_enabled: true, pages: []))
      expect(page).to have_text("Provider unavailable")
      expect(page).not_to have_text("my_custom_provider")
      expect(page).not_to have_text("My Custom Provider")
    end

    it "renders None when settings are missing" do
      render_inline(build_status(settings: nil, module_enabled: true, pages: []))
      expect(page).to have_text("Platform-managed provider: None")
      expect(page).to have_text("Setup unavailable")
    end
  end
end
