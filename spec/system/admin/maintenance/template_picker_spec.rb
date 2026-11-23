# spec/system/admin/maintenance/template_picker_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Covers the end-to-end lazy-load flow for the TemplatePickerComponent on the
# entity create form:
#   1. The initial page load does NOT include inline template cards.
#   2. Clicking "Choose Template" opens the modal and fetches cards via the
#      lazy-load endpoint.
#   3. Clicking a card sets the pending highlight.
#   4. Clicking "Use Template" commits the selection and shows the
#      triggerSelected panel.
RSpec.describe "Entity template picker", :js, type: :system do
  let(:owner)    { find_or_create_platform_owner }
  let(:customer) { owner.customer }

  before do
    skip "headless Chrome not available in this environment" unless system("which google-chrome > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in owner
  end

  it "lazy-loads cards on first open and commits on confirm" do
    visit "/#{customer.id}/admin/maintenance/entities/new"

    # Cards must NOT be present in the initial page payload — they are deferred.
    expect(page).not_to have_css("[data-template-key][data-template-name]", visible: :all)

    # Opening the modal triggers the lazy fetch.
    click_button "Choose Template"
    expect(page).to have_css("[data-template-key][data-template-name]", wait: 5) # cards injected after fetch

    # Click the first card (sets pending highlight only).
    first("[data-template-key][data-template-name]").click

    # Confirm the selection to commit it.
    click_button "Use Template"

    # The trigger should now show the selected state.
    expect(page).to have_css("[data-template-selector-target='triggerSelected']:not(.hidden)")
  end
end
