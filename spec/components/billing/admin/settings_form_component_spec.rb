# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::SettingsFormComponent, type: :component do
  let(:settings) { Billing::Settings.new(tax_rate_bps: 600, collection_mode: "gateway", grace_period_days: 7,
    trial_ending_notice_days: 3, dunning_schedule: [1, 3, 7]) }

  it "shows issued-policy semantics and no obsolete global provider setting" do
    render_inline described_class.new(settings: settings, customer_id: 81721200)
    expect(page).to have_text("6%")
    expect(page).to have_text("600 bps")
    expect(page).to have_css("ul[role='list'] li", count: 3)
    expect(page).to have_text("Day 1")
    expect(page).to have_text("Day 7")
    expect(page).to have_text("verified, compatible default payment method")
    expect(page).not_to have_text("Gateway provider")
  end

  it "keeps fractional tax rates and says when no retries are scheduled" do
    settings.tax_rate_bps = 825
    settings.dunning_schedule = []
    render_inline described_class.new(settings: settings, customer_id: 81721200)
    expect(page).to have_text("8.25%")
    expect(page).to have_text("No automatic retries")
  end

  it "groups the edit form into panels with unit adornments and a footer submit" do
    render_inline described_class.new(settings: settings, customer_id: 81721200, mode: :edit)
    expect(page).to have_css("section[aria-label='Invoicing & tax'] input[name='billing_settings[tax_rate_bps]']")
    expect(page).to have_css("section[aria-label='Reminders & recovery'] input[name='billing_settings[dunning_schedule]']")
    expect(page).to have_css("label[for='billing_settings_grace_period_days']", text: "Grace period")
    expect(page).to have_css("footer input[type='submit'][value='Update Settings']")
  end

  it "retains raw invalid offsets and numeric input from Reform without changing the record" do
    form = Billing::Contracts::Settings.new(settings)
    form.dunning_schedule = "1, abc, 1"
    form.tax_rate_bps = "not-a-rate"
    form.errors.add(:dunning_schedule, "is invalid")
    form.errors.add(:tax_rate_bps, "is invalid")
    render_inline described_class.new(settings: settings, customer_id: 81721200, mode: :edit, form: form)
    expect(page).to have_field("billing_settings[dunning_schedule]", with: "1, abc, 1")
    expect(page).to have_field("billing_settings[tax_rate_bps]", with: "not-a-rate")
    expect(page).to have_css('input[aria-invalid="true"][aria-describedby="billing_settings_dunning_schedule_error"]')
    expect(page).to have_link(href: "#billing_settings_dunning_schedule")
    expect(page).not_to have_field("billing_settings[gateway_provider]")
    expect(settings.dunning_schedule).to eq([1, 3, 7])
  end

  it "preserves an empty retry schedule instead of inventing defaults" do
    settings.dunning_schedule = []
    render_inline described_class.new(settings: settings, customer_id: 81721200, mode: :edit)
    expect(page).to have_field("billing_settings[dunning_schedule]", with: "")
    expect(page).to have_text("Leave blank for no automatic retries")
    expect(page).not_to have_css('[data-controller="billing-settings"]')
  end
end
