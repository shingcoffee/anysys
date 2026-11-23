# frozen_string_literal: true

require "rails_helper"

# System spec for the entity attribute inline-grouping UI.
# Covers the full user journey: select attributes, create a group, persist it,
# and delete a group — exercised against a real Chrome browser via Cuprite.
#
# DnD (HTML5 native drag-and-drop) is OUT OF SCOPE for this system spec.
# The DnD behaviour is wired through entity_form/dnd_manager.js and was
# covered at the unit level in Tasks 10-14; Capybara/Selenium HTML5 DnD
# is notoriously non-deterministic and no project-wide DnD helper exists.
#
# Memoization note: after seeding test data via update_columns, always
# fetch a fresh Entity.find(id) because JsonSerializable memoizes parsed
# JSON in instance variables that reload does NOT clear.
RSpec.describe "Admin Maintenance — Entity Attribute Inline Grouping", :js, type: :system do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, customer: customer, role: :admin) }

  # Seed an entity with three ungrouped attributes, bypassing callbacks so
  # JsonSerializable memoization on the factory instance is not an issue.
  let!(:entity) do
    e = create(:entity, customer: customer)
    e.attribute_groups_json = []

    e.property_schema_json = [
        { "name" => "First Name", "name_slug" => "first_name", "html_type" => "text",
          "display_label" => "First Name", "type" => "String", "group_id" => nil },
        { "name" => "Last Name",  "name_slug" => "last_name",  "html_type" => "text",
          "display_label" => "Last Name",  "type" => "String", "group_id" => nil },
        { "name" => "Email",      "name_slug" => "email",      "html_type" => "email",
          "display_label" => "Email",      "type" => "String", "group_id" => nil }
      ]

    e.save(validate: false)
    # Fetch a fresh instance so memoized JSON caches are not stale.
    Entity.find(e.id)
  end

  before do
    skip "headless Chrome not available in this environment" unless
      system("which google-chrome > /dev/null 2>&1 || which chromium-browser > /dev/null 2>&1 || which chromium > /dev/null 2>&1")
    sign_in admin
  end

  def entity_edit_url
    "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit"
  end

  def wait_for_entity_form
    # Server-rendered rows can be visible before Stimulus attaches their actions.
    # Capybara's synchronized filter reacquires the live mount until connected.
    find("[data-controller~='entity-form']") do |mount|
      page.evaluate_script(<<~JS, mount)
        (() => {
          const controller = window.Stimulus?.getControllerForElementAndIdentifier(arguments[0], "entity-form")
          return !!(arguments[0].isConnected && controller?.groupManager && controller?.attributeManager)
        })()
      JS
    end
  end

  def expect_no_horizontal_overflow
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end

  # ============================================================================
  # Example 1 — Golden path: create a group, assign attributes, persist + reload
  # ============================================================================

  describe "creating a new group and assigning attributes" do
    it "creates the group, shows the header, persists across page reload" do
      visit entity_edit_url
      wait_for_entity_form

      # The page must load with our three attributes in the "Ungrouped" section.
      expect(page).to have_css("tr[data-attr-name-slug='first_name']")
      expect(page).to have_css("tr[data-attr-name-slug='last_name']")
      expect(page).to have_css("tr[data-attr-name-slug='email']")

      # ---- Step 1: Select two checkboxes ----
      find("tr[data-attr-name-slug='first_name'] input[type=checkbox]").check
      expect(page).to have_css("tr[data-attr-name-slug='first_name'] input[type=checkbox]:checked")
      expect(page).to have_css("[data-entity-form-target='groupingToolbar']", visible: true, text: "1 selected")

      # Reacquire the next checkbox after the first selection updates the UI.
      find("tr[data-attr-name-slug='last_name'] input[type=checkbox]").check
      expect(page).to have_css("[data-entity-form-target='groupingToolbar']", visible: true, text: "2 selected")
      expect(page).to have_css("tr[data-attr-name-slug='first_name'] input[type=checkbox]:checked")
      expect(page).to have_css("tr[data-attr-name-slug='last_name'] input[type=checkbox]:checked")
      expect(page).to have_css("tr[data-attr-name-slug='email'] input[type=checkbox]:not(:checked)")
      expect_no_horizontal_overflow

      # ---- Step 2: The selection toolbar must appear with count "2" ----
      toolbar = find("[data-entity-form-target='groupingToolbar']", visible: true)
      expect(toolbar).to have_text("2 selected")

      # ---- Step 3: Open "Move to group ▾" dropdown ----
      within(toolbar) { click_button "Move to group ▾" }

      # ---- Step 4: Click "+ New group…" ----
      floater = find("[data-entity-form-floater]", visible: true)
      expect_no_horizontal_overflow
      floater.find("button", text: "+ New group…").click

      # ---- Step 5: The group modal appears — fill in the name and submit ----
      group_modal = find("[data-entity-form-target='groupEditModal']", visible: true)
      expect_no_horizontal_overflow
      within(group_modal) do
        expect(page).to have_text("New Group")
        fill_in "group_edit_name", with: "Personal Info"
        click_button "Create Group"
      end

      # ---- Step 6: Assert group header now visible ----
      group_header = find("tr[data-attribute-group-header]", text: "Personal Info")
      expect(group_header).to be_visible

      # ---- Step 7: The two assigned rows must now carry a non-empty data-attr-group-id ----
      fn_row = find("tr[data-attr-name-slug='first_name']")
      ln_row = find("tr[data-attr-name-slug='last_name']")
      expect(fn_row["data-attr-group-id"]).not_to be_empty
      expect(ln_row["data-attr-group-id"]).not_to be_empty

      # Both rows must share the same group id.
      expect(fn_row["data-attr-group-id"]).to eq(ln_row["data-attr-group-id"])

      # The email row is ungrouped (group-id should be blank/nil).
      email_row = find("tr[data-attr-name-slug='email']")
      expect(email_row["data-attr-group-id"]).to be_blank
      expect_no_horizontal_overflow

      # ---- Step 8: Submit the form ----
      click_button "Save Changes"

      # Controller redirects to the entity show page on success.
      expect(page).to have_current_path("/#{customer.id}/admin/maintenance/entities/#{entity.id}", url: false)
      expect_no_horizontal_overflow

      # ---- Step 9: Navigate back to the edit page and verify persistence ----
      fresh_entity = Entity.find(entity.id)
      visit "/#{customer.id}/admin/maintenance/entities/#{fresh_entity.id}/edit"
      wait_for_entity_form

      # The group header with the right name must be re-rendered.
      expect(page).to have_css("tr[data-attribute-group-header]", text: "Personal Info")

      # The two grouped attributes must still carry the group's data-attr-group-id.
      fn_row_reloaded = find("tr[data-attr-name-slug='first_name']")
      expect(fn_row_reloaded["data-attr-group-id"]).not_to be_empty
      ln_row_reloaded = find("tr[data-attr-name-slug='last_name']")
      expect(ln_row_reloaded["data-attr-group-id"]).to eq(fn_row_reloaded["data-attr-group-id"])
      expect(find("tr[data-attr-name-slug='email']")["data-attr-group-id"]).to be_blank

      # The group header row must show the correct attribute count (2 attributes).
      header_row = find("tr[data-attribute-group-header]", text: "Personal Info")
      expect(header_row).to have_text("2 attributes")
      expect_no_horizontal_overflow
    end
  end

  # ============================================================================
  # Example 2 — Delete a group: rows return to Ungrouped, header disappears
  # ============================================================================

  describe "deleting a group" do
    # Pre-seed the entity with one group already created and two attrs assigned.
    let!(:entity) do
      e = create(:entity, customer: customer)
      e.attribute_groups_json = [
          { "id" => "g_abc123", "name" => "Identity",
            "icon" => "folder", "color" => "slate", "description" => "" }
        ]

      e.property_schema_json = [
          { "name" => "First Name", "name_slug" => "first_name", "html_type" => "text",
            "display_label" => "First Name", "type" => "String", "group_id" => "g_abc123" },
          { "name" => "Last Name",  "name_slug" => "last_name",  "html_type" => "text",
            "display_label" => "Last Name",  "type" => "String", "group_id" => "g_abc123" },
          { "name" => "Email",      "name_slug" => "email",      "html_type" => "email",
            "display_label" => "Email",      "type" => "String", "group_id" => nil }
        ]

      e.save(validate: false)
      Entity.find(e.id)
    end

    it "removes the group header and moves rows to Ungrouped" do
      visit entity_edit_url
      wait_for_entity_form

      # Group header must be present before deletion.
      expect(page).to have_css("tr[data-attribute-group-header][data-group-id='g_abc123']")

      # Open the kebab menu for the "Identity" group.
      within("tr[data-attribute-group-header][data-group-id='g_abc123']") do
        find("button[data-action*='openGroupMenu']").click
      end

      # Click "Delete" in the floater menu.
      expect(page).to have_css("[data-entity-form-floater]", visible: true)
      find("[data-entity-form-floater]", visible: true)
        .find("button", text: "Delete").click

      # Group header must be gone.
      expect(page).not_to have_css("tr[data-attribute-group-header][data-group-id='g_abc123']")

      # The two previously-grouped rows must now have an empty group-id.
      fn_row = find("tr[data-attr-name-slug='first_name']")
      ln_row = find("tr[data-attr-name-slug='last_name']")
      expect(fn_row["data-attr-group-id"]).to be_blank
      expect(ln_row["data-attr-group-id"]).to be_blank

      # The Ungrouped header (data-group-id="") must now cover all three attrs.
      expect(page).to have_css("tr[data-attribute-group-header][data-group-id='']", text: "Ungrouped")
      expect_no_horizontal_overflow
    end
  end

  # ============================================================================
  # Example 3 — Editing a grouped attribute must NOT eject it from its group
  # (regression guard: collectModalData used to hardcode group_id: null)
  # ============================================================================

  describe "editing an attribute that belongs to a group" do
    let!(:entity) do
      e = create(:entity, customer: customer)
      e.attribute_groups_json = [
          { "id" => "g_abc123", "name" => "Identity",
            "icon" => "folder", "color" => "slate", "description" => "" }
        ]

      e.property_schema_json = [
          { "name" => "First Name", "name_slug" => "first_name", "html_type" => "text",
            "display_label" => "First Name", "type" => "String", "group_id" => "g_abc123" },
          { "name" => "Email",      "name_slug" => "email",      "html_type" => "email",
            "display_label" => "Email",      "type" => "String", "group_id" => nil }
        ]

      e.save(validate: false)
      Entity.find(e.id)
    end

    it "keeps the attribute in its group after an edit" do
      visit entity_edit_url
      wait_for_entity_form

      fn_row = find("tr[data-attr-name-slug='first_name']")
      expect(fn_row["data-attr-group-id"]).to eq("g_abc123")

      # Open the edit modal for the grouped attribute and change the display label.
      within(fn_row) { find("button[data-action*='editAttribute']").click }
      expect(page).to have_css("[data-entity-form-target='modal']", visible: true)
      within("[data-entity-form-target='modal']") do
        find("input[data-entity-form-target='modalDisplayLabel']").fill_in(with: "Given Name")
        click_button "Save Changes"
      end

      # The row must still carry its original group id (not reset to blank).
      fn_row_after = find("tr[data-attr-name-slug='first_name']")
      expect(fn_row_after["data-attr-group-id"]).to eq("g_abc123")
      expect(fn_row_after).to have_css("[data-field='display_label']", text: "Given Name")

      # And it must remain rendered under the "Identity" group header.
      expect(page).to have_css("tr[data-attribute-group-header][data-group-id='g_abc123']", text: "Identity")
      expect_no_horizontal_overflow
    end
  end

  # ============================================================================
  # Note: DnD example is intentionally omitted.
  # HTML5 native drag-and-drop is extremely hard to drive reliably through
  # Capybara/Selenium. No project-wide drag_to helper for native DnD exists.
  # The DnD manager (entity_form/dnd_manager.js) is already covered by unit
  # tests at the JS layer (Tasks 10–14).
  # ============================================================================
end
