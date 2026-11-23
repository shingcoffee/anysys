# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Captcha::ProtectedPagesComponent, type: :component do
  let(:toggle_url) { "/81721200/admin/maintenance/platform/module_settings/captcha/surfaces" }

  let(:surfaces) do
    [
      { key: "authentication/sessions", group: "authentication", path: "/auth/sign_in", preset: "5_per_1min" },
      { key: "authentication/confirmations", group: "authentication", path: "/auth/confirmation/new", preset: "100_per_5min" },
      { key: "authentication/registrations#account", group: "account", path: "/auth/edit", preset: "every_hit" }
    ]
  end

  def render_pages(surfaces: self.surfaces, **opts)
    render_inline(described_class.new(
      surfaces: surfaces,
      toggle_url: toggle_url,
      **opts
    ))
  end

  describe "grouped list" do
    before { render_pages }

    it "renders the card title and subtitle" do
      expect(page).to have_text("Protected public pages")
      expect(page).to have_text("Rate-limit these public URLs per IP. Captcha appears after the limit. Default 100 / 5 min.")
    end

    it "renders the skip section as a separate stacked card" do
      expect(page).to have_text("Skip captcha")
      expect(page).to have_text("These URLs never show a captcha. Move one back to restore its rate.")
      expect(page).to have_text("No URLs skip captcha. Move a protected URL here to turn the challenge off.")
    end

    it "renders group headers and omits empty groups" do
      expect(page).to have_css("h3", text: "Authentication")
      expect(page).to have_css("h3", text: "Account")
      expect(page).not_to have_css("h3", text: "Other")
    end

    it "renders surface names and path chips" do
      expect(page).to have_text("Sign in")
      expect(page).to have_text("/auth/sign_in")
      expect(page).to have_text("Resend confirmation")
      expect(page).to have_text("/auth/confirmation/new")
      expect(page).to have_text("Account settings")
      expect(page).to have_text("/auth/edit")
    end

    it "renders one mutable form and Stimulus instance per resource" do
      expect(page).to have_css("form[data-controller='captcha-throttle-picker']", count: surfaces.size)
      expect(page).to have_css("form[action='#{toggle_url}']", count: surfaces.size)
      expect(page).to have_css("[data-responsive-collection-record]", count: surfaces.size)
    end

    it "uses unique control IDs and one matching label per custom field" do
      ids = page.all("[id]", visible: :all).map { |element| element[:id] }
      expect(ids).to eq(ids.uniq)

      page.all("input[id^='captcha-throttle-']", visible: :all).each do |input|
        expect(page).to have_css("label[for='#{input[:id]}']", count: 1, visible: :all)
      end
    end

    it "provides desktop table-like headers and mobile summary labels around the same records" do
      expect(page).to have_css("[data-responsive-collection-desktop-header]", text: "Resource")
      expect(page).to have_css("[data-responsive-collection-mobile-label]", text: "Path")
      expect(page).to have_css("[data-responsive-collection-record]", text: "Sign in")
      expect(page).to have_css("[data-responsive-collection-record]", text: "/auth/sign_in")
      expect(page).to have_css("[role='table'] [role='columnheader']", count: 3, visible: :all)
      expect(page).to have_css("[data-responsive-collection-record][role='row']", count: surfaces.size)
      expect(page).to have_css("[data-responsive-collection-record][role='row'] > [role='cell']", count: surfaces.size * 3)
      expect(page).to have_css("[data-responsive-collection-record] [role='cell'] form[data-controller='captcha-throttle-picker']", count: surfaces.size)
    end

    it "renders a throttle picker with aria-label per row" do
      expect(page).to have_css('button[aria-label="Access throttle for Sign in"]')
      expect(page).to have_css('button[aria-label="Access throttle for Resend confirmation"]')
    end

    it "PATCHes the toggle URL with surface_key" do
      expect(page).to have_css("form[action='#{toggle_url}']")
      expect(page).to have_css("input[type=hidden][name='surface_key'][value='authentication/sessions']", visible: :hidden)
    end

    it "puts Skip captcha last in the same rate select" do
      expect(page).to have_css("option[value='skip']", text: "Skip captcha", visible: :hidden)
      expect(page).to have_css("input[type=hidden][name='skipped'][value='false']", visible: :hidden)
      expect(page).not_to have_button("Skip")
      values = page.first("select", visible: :all).all("option", visible: :all).map { |option| option[:value] }
      expect(values.last).to eq("skip")
    end
  end

  describe "empty catalog" do
    before { render_pages(surfaces: []) }

    it "renders the empty copy" do
      expect(page).to have_text("No public platform forms were discovered.")
      expect(page).to have_css("[data-module-settings-empty-section='true']")
      expect(page).not_to have_text("Skip captcha")
      expect(page).not_to have_css("button[role=switch]")
    end
  end

  describe "i18n names" do
    let(:raw) do
      [
        { key: "authentication/sessions", path: "/auth/sign_in", preset: "5_per_1min" },
        { key: "payments/checkouts", path: "/:customer_id/payments/checkout", preset: "100_per_5min" },
        { key: "discovered/widget", path: "/widgets/new", preset: "100_per_5min" }
      ]
    end

    before { render_pages(surfaces: raw) }

    it "groups by catalog family and looks up i18n names" do
      expect(page).to have_css("h3", text: "Authentication")
      expect(page).to have_css("h3", text: "Payments")
      expect(page).to have_css("h3", text: "Other")
      expect(page).to have_text("Sign in")
      expect(page).to have_text("Payment checkout")
      expect(page).to have_text("discovered/widget")
    end

    it "does not render a leftover protected-count badge" do
      expect(page).not_to have_text("3 protected")
    end
  end

  describe "shared pages" do
    it "renders shared pages in the protected section under a group heading" do
      render_pages(pages: [
        { id: 1, name: "Donate", public_path: "/:customer_id/page/abc", launched: true, update_url: "/pages/1", preset: "100_per_5min" }
      ])

      expect(page).to have_text("Shared pages")
      expect(page).to have_text("Donate")
      expect(page).to have_text("/:customer_id/page/abc")
      expect(page).to have_text("Launched")
      expect(page).to have_css("form[action='/pages/1']")
    end
  end

  describe "skipped identities" do
    it "places a skipped auth surface in the skip section with a warning and Skip selected" do
      render_pages(surfaces: [
        { key: "authentication/sessions", group: "authentication", path: "/auth/sign_in", preset: "5_per_1min", skipped: true, fail_closed: true },
        { key: "payments/checkouts", group: "payments", path: "/:customer_id/payments/checkout", preset: "100_per_5min" }
      ])

      expect(page).to have_text("Skip captcha")
      expect(page).to have_text("Sensitive")
      expect(page).to have_css("input[type=hidden][name='skipped'][value='true']", visible: :hidden)
      expect(page).to have_css("option[value='skip'][selected]", visible: :hidden)
      expect(page).to have_text("Payment checkout")
      expect(page).to have_css('button[aria-label="Access throttle for Payment checkout"]')
      expect(page).to have_css('button[aria-label="Access throttle for Sign in"]')
      expect(page).not_to have_button("Protect")
    end

    it "shows the protected empty copy when every URL is skipped" do
      render_pages(surfaces: [
        { key: "authentication/sessions", group: "authentication", path: "/auth/sign_in", preset: "100_per_5min", skipped: true }
      ])

      expect(page).to have_text("No URLs are captcha-protected. Move a skipped URL here to set a rate.")
      expect(page).to have_css("[data-module-settings-empty-section='true']", text: "No URLs are captcha-protected")
      expect(page).not_to have_text("No URLs skip captcha. Move a protected URL here to turn the challenge off.")
    end
  end
end
