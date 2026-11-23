# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ImageBannerComponent, type: :component do
  let(:props) do
    {
      "kicker" => "Fall collection",
      "headline" => "Move as one.\nLeave no trace.",
      "body" => "Recycled down. Built for the ridge.",
      "button_label" => "Shop the edit",
      "button_href" => "about",
      "image_url" => "https://images.unsplash.com/photo-banner"
    }
  end

  it "renders white copy over the photograph and resolves the button" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: /Move as one/)
    expect(page).to have_text("Leave no trace.")
    expect(page).to have_text("Fall collection")
    expect(page).to have_link("Shop the edit", href: "/12345678/about")
    expect(page).to have_css("img[src='https://images.unsplash.com/photo-banner']")
    expect(page.find("h2")[:class]).to include("whitespace-pre-line")
    expect(page.find("section")[:class]).to include("md:min-h-[80vh]")
  end

  it "uses a shorter frame for medium height and centers copy when asked" do
    component = described_class.new(props: props.merge("height" => "medium", "placement" => "center"), theme: website_theme("appearance" => "dark"), customer_id: 42)
    render_inline(component)

    expect(component.tall?).to be(false)
    expect(component.centered?).to be(true)
    expect(page.find("section")[:class]).to include("md:min-h-[32rem]")
    expect(page.find("section").find("div.max-w-3xl")[:class]).to include("text-center")
  end

  it "defaults blank height to tall and blank placement to the bottom" do
    component = described_class.new(props: {}, theme: website_theme, customer_id: 42)
    render_inline(component)

    expect(component.tall?).to be(true)
    expect(component.centered?).to be(false)
    expect(page).to have_css("section")
    expect(page).not_to have_css("a")
  end

  it "renders a button label without a href as a span" do
    render_inline(described_class.new(props: props.merge("button_href" => ""), theme: website_theme, customer_id: 42))

    expect(page).to have_text("Shop the edit")
    expect(page).not_to have_link("Shop the edit")
  end

  it "applies a style override to the headline" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end

