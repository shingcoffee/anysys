# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ProofStripComponent, type: :component do
  it "renders values from props" do
    render_inline(described_class.new(
      props: { "items" => [{ "label" => "Orgs", "value" => "12k+" }, { "label" => "Uptime", "value" => "99.9%" }] },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("12k+")
    expect(page).to have_text("Orgs")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: { "items" => [{ "label" => "Orgs", "value" => "12k+" }], "styles" => { "items.value" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.value'][style*='#be123c']")
  end
end
