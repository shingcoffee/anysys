# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::SettingRowComponent, type: :component do
  it "renders field-like content with state and an accessible disabled explanation" do
    component = described_class.new(
      label: "Required module",
      description: "Enabled for every customer.",
      description_id: "required-module-description",
      state: "Active",
      disabled_reason: "The module is mandatory."
    )
    render_inline(component) do
      ActionController::Base.helpers.check_box_tag(
        "required",
        "1",
        true,
        disabled: true,
        **component.control_html_attributes
      )
    end

    expect(page).to have_css("[data-module-settings-setting-row='true']")
    expect(page).to have_css("[data-setting-state]", text: "Active")
    note = page.find("[role='note']", text: "The module is mandatory.")
    description = page.find("#required-module-description", text: "Enabled for every customer.")
    expect(page).to have_field("required", disabled: true)
    expect(page).to have_css("input#required[aria-describedby='#{description[:id]} #{note[:id]}']")
    expect(page).not_to have_css("[data-module-settings-setting-row][aria-describedby]")
    expect(page).to have_text("Enabled for every customer.")
  end
end
