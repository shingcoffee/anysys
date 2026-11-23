# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::PlaceholderImageComponent, type: :component do
  it "renders a decorative gradient with no img tag" do
    render_inline(described_class.new(appearance: "light", class: "min-h-40"))

    expect(page).to have_css("[aria-hidden='true']")
    expect(page).not_to have_css("img")
  end
end
