# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::RichTextComponent, type: :component do
  it "renders the heading from props and escapes HTML" do
    render_inline(described_class.new(
      props: { "heading" => "Our story", "body" => "First paragraph.\n\n<script>alert(1)</script>" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Our story")
    expect(page).to have_text("First paragraph.")
    expect(page).to have_text("<script>alert(1)</script>")
    expect(page).not_to have_css("script")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: { "heading" => "Our story", "styles" => { "heading" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
