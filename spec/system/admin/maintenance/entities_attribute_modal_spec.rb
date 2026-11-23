# frozen_string_literal: true

require "rails_helper"

# Covers the Add/Edit Attribute modal on /:cid/admin/maintenance/entities/new:
# the new Display Label field (mirrors Name until manually edited) and the
# three Visibility checkboxes (Admin / Member / Public, default checked,
# round-tripped through the hidden visibility JSON input on the row).
RSpec.describe "Admin Maintenance — Entity Attribute Modal", :js, type: :system do
  let(:owner)    { find_or_create_platform_owner }
  let(:customer) { owner.customer }

  before do
    skip "headless Chrome not available in this environment" unless system("which google-chrome > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in owner
  end

  it "defaults visibility checkboxes to all checked when the modal opens" do
    visit "/#{customer.id}/admin/maintenance/entities/new"
    click_button "Add Attribute"

    within("[data-entity-form-target='modal']") do
      click_button "Access"
      expect(find("input[data-entity-form-target='modalVisibilityAdmin']")).to be_checked
      expect(find("input[data-entity-form-target='modalVisibilityMember']")).to be_checked
      expect(find("input[data-entity-form-target='modalVisibilityPublic']")).to be_checked
    end
  end

  it "mirrors Name into Display Label and a hidden Name Slug, then stops mirroring Display Label after a manual edit" do
    visit "/#{customer.id}/admin/maintenance/entities/new"
    click_button "Add Attribute"

    within("[data-entity-form-target='modal']") do
      name_input          = find("input[data-entity-form-target='modalName']")
      display_label_input = find("input[data-entity-form-target='modalDisplayLabel']")
      name_slug_input     = find("input[data-entity-form-target='modalNameSlug']", visible: :all)

      name_input.fill_in(with: "Email")
      expect(display_label_input.value).to eq("Email")
      expect(name_slug_input.value).to eq("email")

      display_label_input.fill_in(with: "Email Address")

      name_input.fill_in(with: "Primary Email")
      expect(display_label_input.value).to eq("Email Address")
      expect(name_slug_input.value).to eq("primary_email")
    end
  end

  it "saves an attribute with member + public unchecked and renders only the Admin badge" do
    visit "/#{customer.id}/admin/maintenance/entities/new"
    click_button "Add Attribute"

    # Scope to the modal so Capybara waits for it to render before interacting —
    # a bare find race-flakes under parallel load when the modal open lags.
    within("[data-entity-form-target='modal']") do
      find("input[data-entity-form-target='modalName']").fill_in(with: "Internal Note")
      click_button "Access"
      find("input[data-entity-form-target='modalVisibilityMember']").click
      find("input[data-entity-form-target='modalVisibilityPublic']").click
      click_button "Add Attribute"
    end

    row = find("[data-attribute-item]", text: "Internal Note")

    within(row) do
      expect(page).to have_text("Admin")
      expect(page).to have_css("span.line-through", text: "Member")
      expect(page).to have_css("span.line-through", text: "Public")
    end

    visibility_json = row.find("input[data-input='visibility']", visible: :all).value
    expect(JSON.parse(visibility_json)).to eq(
      "admin" => true, "member" => false, "public" => false
    )
  end
end
