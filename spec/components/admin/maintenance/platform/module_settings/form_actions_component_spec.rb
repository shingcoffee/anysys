# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::FormActionsComponent, type: :component do
  it "uses full-width mobile actions and intrinsic-width desktop actions" do
    render_inline(described_class.new(cancel_path: "/cancel", submit_label: "Save"))

    expect(page).to have_css("[data-module-settings-form-actions] a.w-full.sm\\:w-auto")
    expect(page).to have_css("[data-module-settings-form-actions] button.w-full.sm\\:w-auto")
  end
  it "renders cancel and submit actions with an optional sticky landmark" do
    render_inline(described_class.new(cancel_path: "/cancel", submit_label: "Save changes", sticky: true))

    expect(page).to have_css("[data-module-settings-form-actions='true'][data-sticky='true']")
    expect(page).to have_css("[role='group'][aria-label='#{I18n.t("maint_platform.module_settings.workspace.form_actions_label")}']")
    expect(page).to have_link(I18n.t("maint_platform.module_settings.workspace.cancel"), href: "/cancel")
    expect(page).to have_button("Save changes")
  end
end
