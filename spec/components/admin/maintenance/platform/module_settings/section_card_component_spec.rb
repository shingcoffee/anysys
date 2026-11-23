# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::SectionCardComponent, type: :component do
  it "renders a labeled section with description, action, and content slot" do
    render_inline(described_class.new(
      title: "Delivery",
      description: "Choose the active provider.",
      action: ActionController::Base.helpers.link_to("Change provider", "#")
    )) { "Section body" }

    expect(page).to have_css("section[aria-labelledby]")
    expect(page).to have_css("h2", text: "Delivery")
    expect(page).to have_text("Choose the active provider.")
    expect(page).to have_link("Change provider")
    expect(page).to have_text("Section body")
  end
end
