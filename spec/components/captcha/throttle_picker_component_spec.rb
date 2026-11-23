# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::ThrottlePickerComponent, type: :component do
  def render_picker(**opts)
    render_inline(described_class.new(
      url: "/settings/captcha",
      preset: Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
      **opts
    ))
  end

  it "renders the current rate as editable text and keeps the select closed" do
    render_picker
    expect(page).to have_css("input[type=hidden][name='preset'][value='100_per_5min']", visible: :hidden)
    expect(page).to have_css("[data-captcha-throttle-picker-target='display']", text: "100 / 5 min / IP")
    expect(page).to have_css("select[data-captcha-throttle-picker-target='choice']", visible: :hidden)
    expect(page).to have_css("option[value='5_per_1min']", visible: :hidden)
    expect(page).to have_css("option[value='custom']", visible: :hidden)
    expect(page).to have_css("option[value='100_per_5min'][selected]", visible: :hidden)
    expect(page).to have_css("[data-captcha-throttle-picker-target='customFields']", visible: :hidden)
    expect(page).not_to have_css("option[value='skip']", visible: :all)
    expect(page).not_to have_css("input[name='skipped']")
  end

  it "shows a custom rate as text and keeps custom fields closed until edit" do
    render_picker(preset: Captcha::ThrottlePresets::PRESET_CUSTOM, limit_count: 50, period_minutes: 2)
    expect(page).to have_css("[data-captcha-throttle-picker-target='display']", text: "50 / 2 min / IP")
    expect(page).to have_css("option[value='custom'][selected]", visible: :hidden)
    expect(page).to have_css("[data-captcha-throttle-picker-target='customFields']", visible: :hidden)
    expect(page).to have_css("input[name='limit_count'][value='50']", visible: :hidden)
    expect(page).to have_css("input[name='period_minutes'][value='2']", visible: :hidden)
    expect(page).to have_css("label", text: "Requests", visible: :hidden)
    expect(page).to have_css("label", text: "Minutes", visible: :hidden)
    expect(page).to have_button("Apply", visible: :hidden)
    expect(page).to have_css("[data-captcha-throttle-picker-target='customFields'].justify-end", visible: :hidden)
    expect(page).to have_css("input[name='limit_count'].text-xs", visible: :hidden)
    expect(page).to have_css("input[name='period_minutes'].text-xs", visible: :hidden)
    expect(page).to have_css("p.text-caption.text-right", text: "Per IP. 1–10,000 requests in a 1–60 minute window.", visible: :hidden)
  end

  it "falls back to the Custom label when a custom rate has no numbers" do
    render_picker(preset: Captcha::ThrottlePresets::PRESET_CUSTOM)
    expect(page).to have_css("[data-captcha-throttle-picker-target='display']", text: "Custom…")
  end

  it "renders identity content in the same form as the rate control" do
    render_inline(described_class.new(
      url: "/settings/captcha",
      preset: Captcha::ThrottlePresets::PRESET_CUSTOM,
      limit_count: 50,
      period_minutes: 2
    )) { "Sign in" }
    expect(page).to have_css("form.flex.flex-col", text: "Sign in")
    expect(page).to have_css("[data-captcha-throttle-picker-target='display']", text: "50 / 2 min / IP")
  end

  it "includes Skip captcha as the last option and shows it as the display when skipped" do
    render_picker(include_skip: true, skipped: true, preset: "5_per_1min")
    expect(page).to have_css("[data-captcha-throttle-picker-target='display']", text: "Skip captcha")
    expect(page).to have_css("option[value='skip'][selected]", text: "Skip captcha", visible: :hidden)
    expect(page).to have_css("input[type=hidden][name='skipped'][value='true']", visible: :hidden)
    expect(page).to have_css("input[type=hidden][name='preset'][value='5_per_1min']", visible: :hidden)
    expect(page).to have_css("[data-captcha-throttle-picker-target='customFields']", visible: :hidden)
    values = page.all("select option", visible: :all).map { |option| option[:value] }
    expect(values.last).to eq("skip")
    expect(values).to include("custom", "5_per_1min")
  end

  it "uses readable customer controls while preserving the preset and custom payloads" do
    render_picker(customer_context: true, preset: "custom", limit_count: 50, period_minutes: 2)
    expect(page).to have_button("50 requests / 2 minutes / IP")
    expect(page).to have_css("input[name='preset'][value='custom']", visible: :all)
    expect(page).to have_css("input[name='limit_count'][value='50'].min-h-11", visible: :all)
    expect(page).to have_css("input[name='period_minutes'][value='2'].min-h-11", visible: :all)
    expect(page).to have_css("option[value='every_hit']", text: "Verify every request", visible: :all)
    expect(page).to have_css("button[type='button'][data-action='click->captcha-throttle-picker#apply']", visible: :all)
  end
end
