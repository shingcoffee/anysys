# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::DisclosureComponent, type: :component do
  def render_disclosure(**overrides, &block)
    render_inline(described_class.new(id: "plans", title: "Plan catalog", **overrides), &block)
  end

  it "renders a closed card section with stimulus wiring and no hidden panel" do
    render_disclosure { "Panel body" }

    section = page.find("section#plans[aria-label='Plan catalog'][data-controller='billing-disclosure']")
    expect(section[:class]).to include("card", "min-w-0", "overflow-hidden")
    expect(section[:"data-billing-disclosure-open-value"]).to eq("false")
    expect(JSON.parse(section[:"data-billing-disclosure-hashes-value"])).to eq([])

    trigger = page.find("button[data-billing-disclosure-target='trigger']")
    expect(trigger[:type]).to eq("button")
    expect(trigger[:"data-action"]).to eq("billing-disclosure#toggle")
    expect(trigger[:"aria-expanded"]).to eq("false")
    expect(trigger[:"aria-controls"]).to eq("plans-panel")
    expect(page).to have_css("h2.m-0 button[data-billing-disclosure-target='trigger']")
    expect(page).to have_css("h2", text: "Plan catalog")
    expect(page).to have_css("button span.section-header", text: "Plan catalog")
    expect(page).not_to have_css("button h2")
    expect(page).not_to have_css("p.text-caption")
    expect(page).not_to have_css("span.block.text-caption.font-normal")

    icon = page.find("[data-billing-disclosure-target='icon']")
    expect(icon[:class]).to include("text-text-muted", "transition-transform")
    expect(icon[:class]).not_to include("rotate-90")
    expect(page).to have_css("[data-billing-disclosure-target='icon'] svg[aria-hidden='true']", visible: :all)

    panel = page.find("#plans-panel[data-billing-disclosure-target='panel']")
    expect(panel[:class]).to include("border-t", "border-border-subtle", "px-4", "py-4", "sm:px-6")
    expect(panel[:class]).not_to include("hidden")
    expect(panel).to have_text("Panel body")
  end

  it "marks an open disclosure expanded and rotates the chevron" do
    render_disclosure(open: true) { "Open body" }

    expect(page).to have_css("section[data-billing-disclosure-open-value='true']")
    expect(page).to have_css("button[data-billing-disclosure-target='trigger'][aria-expanded='true']")
    expect(page).to have_css("[data-billing-disclosure-target='icon'].rotate-90")
    expect(page).not_to have_css("[data-billing-disclosure-target='panel'].hidden")
    expect(page).to have_text("Open body")
  end

  it "renders a description, summary slot, custom hashes, and a nested heading" do
    render_inline(described_class.new(
      id: "coupon", title: "Redeem a coupon", description: "Apply a code to this subscription",
      hashes: %w[coupon-form redeem], heading_tag: :h3, heading_class: "text-body-sm font-medium"
    )) do |disclosure|
      disclosure.with_summary { "SAVE20" }
      "Coupon fields"
    end

    section = page.find("section#coupon")
    expect(JSON.parse(section[:"data-billing-disclosure-hashes-value"])).to eq(%w[coupon-form redeem])
    expect(page).to have_css("h3.m-0 button[data-billing-disclosure-target='trigger']")
    expect(page).to have_css("h3", text: "Redeem a coupon")
    expect(page).to have_css("button span.text-body-sm.font-medium", text: "Redeem a coupon")
    expect(page).to have_css("span.block.text-caption.font-normal", text: "Apply a code to this subscription")
    expect(page).to have_css("[data-billing-disclosure-target='trigger']", text: "SAVE20")
    expect(page).to have_css("#coupon-panel", text: "Coupon fields")
  end

  it "supports an h4 heading" do
    render_disclosure(heading_tag: "h4") { "Nested" }
    expect(page).to have_css("h4.m-0 button[data-billing-disclosure-target='trigger']")
    expect(page).to have_css("h4", text: "Plan catalog")
    expect(page).to have_css("h4 .section-header", text: "Plan catalog")
  end

  it "drops panel padding when flush and uses the unframed shell when card is false" do
    render_disclosure(flush: true, card: false) { "Flush body" }

    section = page.find("section#plans")
    expect(section[:class]).to include("rounded-xl", "border", "border-border-subtle", "bg-surface")
    expect(section[:class]).not_to include("card")

    panel = page.find("#plans-panel")
    expect(panel[:class]).to include("border-t", "border-border-subtle")
    expect(panel[:class]).not_to include("px-4", "py-4", "sm:px-6")
    expect(page).to have_text("Flush body")
  end

  it "rejects an untrusted heading tag" do
    expect { described_class.new(id: "plans", title: "Plan catalog", heading_tag: :h1) }
      .to raise_error(ArgumentError, /unsupported heading_tag/)
    expect { described_class.new(id: "plans", title: "Plan catalog", heading_tag: :div) }
      .to raise_error(ArgumentError)
  end

  it "drops its own frame when nested in another card" do
    render_disclosure(card: false, bordered: false) { "Nested body" }
    expect(page.find("section#plans")[:class]).to eq("min-w-0")
  end
end
