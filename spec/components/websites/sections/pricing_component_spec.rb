# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::PricingComponent, type: :component do
  let(:props) do
    { "heading" => "Plans", "tiers" => [
        { "name" => "Starter", "price" => "$0", "features" => "One\nTwo", "button_label" => "Start", "button_href" => "about", "highlight" => "standard" },
        { "name" => "Team", "price" => "$12", "cadence" => "per seat", "features" => "Three", "button_label" => "Trial", "button_href" => "about", "highlight" => "featured" }
      ] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h3", text: "Team")
    expect(page).to have_css("li", text: "Two")
    expect(page).to have_text(I18n.t("website.public.pricing.featured"), count: 1)
    expect(page).to have_link("Trial", href: "/12345678/about")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 12345678))

    expect(page).to have_css("section")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "tiers.price" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='tiers.price'][style*='#be123c']")
  end

  it "uses a supplied label only on the featured tier" do
    render_inline(described_class.new(props: props.merge("featured_label" => "Recommended"), theme: website_theme))

    expect(page).to have_css("article span", text: "Recommended", count: 1)
    expect(page).not_to have_text(I18n.t("website.public.pricing.featured"))
    expect(page.all("article").last).to have_css("h3", text: "Team")
    expect(page.all("article").first).not_to have_text("Recommended")
  end

  it "falls back to the request locale when the featured label is blank" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(props: props.merge("featured_label" => " "), theme: website_theme))

      expect(page).to have_text(I18n.t("website.public.pricing.featured"), count: 1)
    end
  end
end
