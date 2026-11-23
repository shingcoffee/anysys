# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::AuthorizationStepperComponent, type: :component do
  def render_steps(payment_method)
    render_inline described_class.new(payment_method: payment_method)
  end

  def step_items
    page.all("nav[aria-label='Authorization progress'] li")
  end

  it "marks provider selection current when no payment method exists" do
    render_steps(nil)
    expect(step_items.map { |item| item.text.squish }).to eq(
      ["1 Select provider", "2 Authorize mandate", "3 Ready for billing"]
    )
    expect(page).to have_css("li.ring-accent", text: "Select provider")
    expect(page).not_to have_css("li.ring-accent", text: "Ready for billing")
  end

  it "completes provider selection while authorization is pending" do
    render_steps(double(status: "pending"))
    items = step_items
    expect(items[0]).to have_css("svg")
    expect(items[0]).to have_text("Select provider")
    expect(items[1].text.squish).to eq("2 Authorize mandate")
    expect(items[2].text.squish).to eq("3 Ready for billing")
    expect(items[1][:class]).to include("ring-accent")
  end

  it "marks every step complete for an active payment method" do
    render_steps(double(status: "active"))
    expect(page).to have_css("nav li svg", count: 3)
    expect(page).to have_css("li.ring-accent", text: "Ready for billing")
    expect(page).not_to have_text("1")
  end

  it "localizes step labels without missing translations" do
    I18n.with_locale(:"zh-CN") do
      render_steps(nil)
      expect(page).to have_css("nav[aria-label='#{I18n.t('settings_billing.payment_methods.steps.aria_label')}']")
      expect(page).to have_text(I18n.t("settings_billing.payment_methods.steps.select_provider"))
      expect(page).to have_text(I18n.t("settings_billing.payment_methods.steps.authorize_provider"))
      expect(page).to have_text(I18n.t("settings_billing.payment_methods.steps.ready"))
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
