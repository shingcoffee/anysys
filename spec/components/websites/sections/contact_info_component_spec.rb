# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ContactInfoComponent, type: :component do
  it "renders the heading from props without a form or inputs" do
    html = render_inline(described_class.new(
      props: {
        "heading" => "Get in touch",
        "address" => "1200 Market Street",
        "email" => "hello@example.com",
        "phone" => "+1 415 555 0100",
        "hours" => "Mon–Fri, 9–5"
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Get in touch")
    expect(page).to have_text("1200 Market Street")
    expect(page).to have_link("hello@example.com", href: "mailto:hello@example.com")
    expect(page).to have_link("+1 415 555 0100", href: "tel:+14155550100")
    expect(html.to_html).not_to include("<form")
    expect(html.to_html).not_to include("<input")
    expect(html.to_html).not_to include("<textarea")
    expect(html.to_html).not_to include("<select")
  end

  it "omits blank fields" do
    render_inline(described_class.new(
      props: { "heading" => "Get in touch", "email" => "hello@example.com" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Email")
    expect(page).not_to have_text("Address")
    expect(page).not_to have_text("Phone")
  end

  it "renders a style override on the heading" do
    render_inline(described_class.new(
      props: {
        "heading" => "Get in touch",
        "email" => "hello@example.com",
        "styles" => { "heading" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
