# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::EmptySectionComponent, type: :component do
  it "renders a semantic empty section with an optional action" do
    render_inline(described_class.new(
      title: "No templates registered yet",
      description: "Create a template to start sending SMS messages.",
      action_path: "/templates/new",
      action_label: "New template"
    ))

    expect(page).to have_css("[data-module-settings-empty-section='true'][role='status']")
    expect(page).to have_css("h3", text: "No templates registered yet")
    expect(page).to have_text("Create a template to start sending SMS messages.")
    expect(page).to have_link("New template", href: "/templates/new")
  end

  it "omits the action when no action path is supplied" do
    render_inline(described_class.new(title: "No events", description: "Events appear here."))

    expect(page).not_to have_link
  end
end
