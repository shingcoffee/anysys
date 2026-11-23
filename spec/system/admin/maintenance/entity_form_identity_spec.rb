# frozen_string_literal: true

require "rails_helper"

# System spec for the entity form's configuration behaviour:
#   • "Extend Base Model" renders on both prefixes — optional on the tenant
#     path, required on Platform Shared Resources
#
# Runs against a real browser (Selenium Chrome), matching the other entity
# system specs in this directory.
RSpec.describe "Admin Maintenance — Entity form configuration", :js, type: :system do
  let(:owner)    { find_or_create_platform_owner }
  let(:customer) { owner.customer }

  # Give the owner's customer one owner-approved extendable model so the base
  # model <select> renders (rather than the "no base models" fallback message).
  let!(:extendable_module) do
    mod = create(:feature_module, extendable_models: ["Billing::Invoice"].to_json)
    create(:customer_feature_module, customer: customer, feature_module: mod)
    mod
  end

  before do
    skip "headless Chrome not available in this environment" unless
      system("which google-chrome > /dev/null 2>&1 || which chromium-browser > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in owner
  end

  it "shows an optional base model on tenant new" do
    visit "/#{customer.id}/admin/maintenance/entities/new"
    expect(find("#entity_base_model_section")).to be_visible
    expect(base_model_required?).to be(false)
    expect(page).to have_select("entity_extended_model", with_options: ["Invoice (#{extendable_module.key})"])
  end

  it "shows and requires the base model on Platform Shared Resources new" do
    visit "/#{customer.id}/admin/maintenance/platform/entities/new"
    expect(find("#entity_base_model_section")).to be_visible
    expect(base_model_required?).to be(true)
    expect(page).not_to have_field("entity_type")
  end

  # Read the live DOM property (Selenium stringifies the boolean attribute).
  def base_model_required?
    page.evaluate_script("document.getElementById('entity_extended_model').required")
  end
end
