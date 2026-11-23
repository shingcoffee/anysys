# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::HeroCinematicComponent, type: :component do
  let(:theme) { website_theme }
  let(:props) do
    {
      "kicker" => "PRODUCT",
      "headline" => "Designed to be remembered.",
      "subhead" => "A chapter, not a banner.",
      "primary_label" => "Explore",
      "primary_href" => "about",
      "tone" => "dark"
    }
  end

  it "renders the headline from props" do
    render_inline(described_class.new(props: props, theme: theme, customer_id: 12345678))

    expect(page).to have_text("Designed to be remembered.")
    expect(page).to have_text("PRODUCT")
    expect(page).to have_link("Explore", href: "/12345678/about")
    expect(rendered_content).to include("md:text-site-7xl")
    expect(rendered_content).to include("lg:text-site-8xl")
  end

  it "uses a placeholder instead of an empty image" do
    render_inline(described_class.new(props: props, theme: theme, customer_id: 12345678))

    expect(page).to have_css("[aria-hidden='true']")
    expect(page).not_to have_css("img[src='']")
  end

  it "applies a style override to the headline" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end

