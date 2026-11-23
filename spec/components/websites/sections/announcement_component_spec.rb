# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::AnnouncementComponent, type: :component do
  let(:props) do
    { "badge" => "New", "body" => "Introducing Fluid compute", "link_label" => "Read the post", "href" => "about" }
  end

  it "renders the pill with badge, body and a resolved link" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_text("New")
    expect(page).to have_text("Introducing Fluid compute")
    expect(page).to have_link("Read the post", href: "/12345678/about")
  end

  it "renders a static pill in a dark theme when the href is blank" do
    render_inline(described_class.new(props: props.merge("href" => ""), theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_text("Introducing Fluid compute")
    expect(page).not_to have_css("a")
    expect(page.find("section")[:class]).to include("py-4")
  end

  it "labels a chevron-only link when badge and href are the only copy" do
    render_inline(described_class.new(props: { "badge" => "Beta", "href" => "about" }, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("a[href='/12345678/about'][aria-label='#{I18n.t("website.public.announcement.learn_more")}']")
    expect(page).to have_text("Beta")
  end

  it "renders nothing awkward when every prop is blank" do
    render_inline(described_class.new(props: {}, theme: website_theme, customer_id: 42))

    expect(page).to have_css("section")
    expect(page).not_to have_css("a")
    expect(page).not_to have_text("New")
  end

  it "drops an unsafe href and escapes authored markup" do
    render_inline(described_class.new(
      props: { "badge" => "<script>alert(1)</script>", "body" => "Launch", "link_label" => "Go", "href" => "javascript:alert(1)" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("<script>alert(1)</script>")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
  end

  it "renders a style override on the body" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "body" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='body'][style*='#be123c']")
  end
end
