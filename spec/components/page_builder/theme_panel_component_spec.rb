require "rails_helper"

RSpec.describe PageBuilder::ThemePanelComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the theme panel target wrapper" do
    expect(page).to have_css("[data-page-builder-target='themePanel']")
  end

  it "renders each control section" do
    %w[Presets Colors Typography].each do |section|
      expect(page).to have_css("h3", text: section)
    end
    expect(page).to have_css("h3", text: "Form Layout")
    expect(page).to have_css("h3", text: "Input Fields")
    expect(page).to have_css("h3", text: "Submit Button")
  end

  it "renders a preset button wired to the page-builder controller" do
    expect(page).to have_css(
      "button[data-action='click->page-builder#applyThemePreset'][data-preset='modern']",
      text: "Modern"
    )
  end

  it "renders theme-property option buttons" do
    expect(page).to have_css(
      "button[data-action='click->page-builder#updateTheme'][data-theme-property='primary_color'][data-theme-value='indigo']"
    )
  end
end
