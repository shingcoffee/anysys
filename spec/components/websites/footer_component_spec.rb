# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::FooterComponent, type: :component do
  let(:theme) { website_theme }
  let(:website) { website_record }

  it "renders the site name, blurb, and column links" do
    render_inline(described_class.new(website: website, theme: theme))

    expect(page).to have_text("Acme Institute")
    expect(page).to have_text("Quiet rooms for ambitious work.")
    expect(page).to have_text("Visit")
    expect(page).to have_link("About", href: "/12345678/about")
  end

  it "still renders the compact name row when footer is empty" do
    site = website_record(footer: {})
    render_inline(described_class.new(website: site, theme: theme))

    expect(page).to have_css("footer", text: "Acme Institute")
    expect(page).not_to have_text("Visit")
  end
end
