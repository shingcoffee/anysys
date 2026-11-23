# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::CtaBandComponent, type: :component do
  it "renders the headline from props" do
    render_inline(described_class.new(
      props: { "headline" => "Ready when you are.", "body" => "One line of supporting copy.", "button_label" => "Talk to us", "button_href" => "contact" },
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_text("Ready when you are.")
    expect(page).to have_link("Talk to us", href: "/12345678/contact")
  end

  it "applies a style override to the headline" do
    render_inline(described_class.new(
      props: { "headline" => "Ready when you are.", "styles" => { "headline" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end

