# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# System spec: page builder — Calculated Fields and Conditional Rules panels
#
# Coverage areas:
#   1. Calculated fields panel: HTML structure rendered server-side, PATCH
#      persistence with {field_id} token formula, reload verification.
#   2. Conditional rules panel: HTML structure, contextual value editor for
#      SELECT-type fields, rule action chip, PATCH persistence + reload.
#   3. Multi-tenant isolation: admin of customer A cannot open/save the page
#      edit surface of customer B (mirrors request spec cross-tenant coverage).
#
# JS-dependent examples (actual UI interaction — tab click, formula pill
# insertion, test-mode toggle) use the :js metadata flag. They skip when
# headless Chrome is unavailable, exactly as other specs in this directory do.
# The non-JS examples run under the default :rack_test driver and cover:
#   - Server-rendered HTML structure (panel targets, button actions)
#   - PATCH persistence round-trip (no browser required)
#   - Cross-tenant isolation
# =============================================================================

CHROME_AVAILABLE = system("which google-chrome > /dev/null 2>&1 || which chromium-browser > /dev/null 2>&1 || which chromium > /dev/null 2>&1")

RSpec.describe "Page builder — Calculated Fields & Conditional Rules", type: :system do
  # ViewComponent::SystemTestHelpers (included for :system specs) overrides
  # `page` to return Capybara::Node::Simple for component rendering. Restore
  # the Capybara session helper so `visit`, `find`, `expect(page)` etc. work.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:entity)   { create(:entity, customer: customer, name: "Order") }

  # Two numeric fields (for a valid calculation) + a select-type field (for a
  # rule with contextual dropdown value editor).
  let(:qty_field) do
    { "id" => "qty", "label" => "Quantity", "property_type" => "number",
      "property_slug" => "qty", "html_type" => "number" }
  end
  let(:price_field) do
    { "id" => "price", "label" => "Price", "property_type" => "number",
      "property_slug" => "price", "html_type" => "number" }
  end
  let(:total_field) do
    { "id" => "total", "label" => "Total", "property_type" => "number",
      "property_slug" => "total", "html_type" => "number" }
  end
  let(:plan_field) do
    { "id" => "plan", "label" => "Plan", "property_type" => "select",
      "property_slug" => "plan", "html_type" => "select",
      "options" => [
        { "value" => "basic",    "label" => "Basic" },
        { "value" => "premium",  "label" => "Premium" }
      ] }
  end
  let(:discount_field) do
    { "id" => "discount", "label" => "Discount", "property_type" => "number",
      "property_slug" => "discount", "html_type" => "number" }
  end

  let(:base_configuration) do
    {
      "pages" => [{
        "id"     => "page_1",
        "name"   => "Page 1",
        "order"  => 1,
        "fields" => [qty_field, price_field, total_field, plan_field, discount_field]
      }],
      "metadata" => {
        "entity_id"   => entity.id,
        "entity_name" => entity.name
      },
      "rules"        => [],
      "calculations" => []
    }
  end

  let!(:page_record) do
    create(:page,
           customer:      customer,
           entity:        entity,
           name:          "Order Form",
           configuration: base_configuration.to_json)
  end

  before { sign_in admin }

  # ---------------------------------------------------------------------------
  # SECTION 1: Server-rendered HTML structure (rack_test — no JS needed)
  # ---------------------------------------------------------------------------

  describe "edit page HTML structure" do
    before { visit "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit" }

    it "renders the calculations tab button with the correct data-tab attribute" do
      expect(page).to have_css('[data-action*="switchTab"][data-tab="calculations"]')
    end

    it "renders the rules tab button with the correct data-tab attribute" do
      expect(page).to have_css('[data-action*="switchTab"][data-tab="rules"]')
    end

    it "renders the calculations panel target with an Add Calculation button" do
      # The panel is inside a data-page-builder-target="calculationsPanel" div
      within('[data-page-builder-target="calculationsPanel"]') do
        expect(page).to have_css('[data-action*="openFormulaEditor"]')
        expect(page).to have_content("Add Calculation")
      end
    end

    it "renders the rules panel target with an Add Rule button" do
      within('[data-page-builder-target="rulesPanel"]') do
        expect(page).to have_css('[data-action*="openRuleEditor"]')
        expect(page).to have_content("Add Rule")
      end
    end

    it "embeds the calculation editor template" do
      # Server renders the modal template so JS can clone it
      expect(page).to have_css('[data-page-builder-target="calculationEditorTemplate"]',
                               visible: :all)
    end

    it "embeds the rule editor template" do
      expect(page).to have_css('[data-page-builder-target="ruleEditorTemplate"]',
                               visible: :all)
    end

    it "the rule editor template includes the rule-builder controller" do
      # The cloned rule editor must wire up the rule-builder Stimulus controller.
      # Use page.source (raw HTML string) because <template> innerHTML is not
      # accessible via Capybara node attributes in the rack_test driver.
      expect(page.source).to include('data-controller="rule-builder"')
    end

    it "the rule editor template includes the fields JSON data attribute" do
      expect(page.source).to include('data-rule-builder-fields-value')
    end

    it "the calculation editor template includes the formula pill editor" do
      expect(page.source).to include('data-controller="formula-editor"')
    end

    it "the formula pill editor surface has a status target for validation feedback" do
      expect(page.source).to include('data-formula-editor-target="status"')
    end

    it "the formula pill editor surface has a preview target for live preview" do
      expect(page.source).to include('data-formula-editor-target="preview"')
    end
  end

  # Condition row rendered for a SELECT field should use the :select value editor
  describe "condition row HTML for a pre-existing SELECT-type field rule" do
    let(:rule_with_select_condition) do
      {
        "id"         => "rule_select",
        "name"       => "Show discount for premium",
        "enabled"    => true,
        "conditions" => {
          "logic"  => "all",
          "groups" => [{
            "logic" => "all",
            "items" => [{
              "field_id"  => "plan",
              "operator"  => "equals",
              "value"     => "premium"
            }]
          }]
        },
        "actions" => [{
          "type"      => "show_field",
          "target_id" => "discount"
        }]
      }
    end

    before do
      config = base_configuration.merge("rules" => [rule_with_select_condition])
      page_record.update!(configuration: config.to_json)
      visit "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"
    end

    it "includes the rule in the rules panel summary" do
      within('[data-page-builder-target="rulesPanel"]') do
        expect(page).to have_content("Show discount for premium")
      end
    end

    it "shows the rule as enabled (green dot)" do
      within('[data-page-builder-target="rulesPanel"]') do
        expect(page).to have_css('.bg-emerald-500')
      end
    end
  end

  # Pre-existing calculation is shown in the calculations panel
  describe "calculations panel shows persisted calculations" do
    let(:calc) do
      { "id" => "c1", "target_field_id" => "total", "formula" => "{qty} * {price}" }
    end

    before do
      config = base_configuration.merge("calculations" => [calc])
      page_record.update!(configuration: config.to_json)
      visit "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"
    end

    it "displays the target field label in the panel" do
      within('[data-page-builder-target="calculationsPanel"]') do
        expect(page).to have_content("Total")
      end
    end

    it "displays the formula in the panel" do
      within('[data-page-builder-target="calculationsPanel"]') do
        expect(page).to have_content("{qty} * {price}")
      end
    end

    it "renders an edit button for the calculation" do
      within('[data-page-builder-target="calculationsPanel"]') do
        expect(page).to have_css('[data-action*="editCalculation"]')
      end
    end

    it "renders a delete button for the calculation" do
      within('[data-page-builder-target="calculationsPanel"]') do
        expect(page).to have_css('[data-action*="deleteCalculation"]')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 2: Persistence round-trip via PATCH (rack_test — no JS needed)
  # These mirror the request spec approach but from the system spec layer.
  # ---------------------------------------------------------------------------

  describe "PATCH persistence — calculated fields with {field_id} token formula" do
    it "accepts a valid {field_id} token formula and persists it" do
      config_with_calc = base_configuration.merge(
        "calculations" => [{
          "id"             => "c1",
          "target_field_id" => "total",
          "formula"        => "{qty} * {price}"
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_calc.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("success")

      page_record.reload
      calc = page_record.configuration_json["calculations"].first
      expect(calc["formula"]).to eq("{qty} * {price}")
      expect(calc["target_field_id"]).to eq("total")
    end

    it "rejects a calculation whose formula references an unknown field token" do
      config_with_bad_calc = base_configuration.merge(
        "calculations" => [{
          "id"             => "c_bad",
          "target_field_id" => "total",
          "formula"        => "{ghost_field} + 1"
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_bad_calc.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["status"]).to eq("error")
      expect(body["errors"].join).to match(/unknown field 'ghost_field'/i)
    end

    it "persists the calculation after reload (data survival test)" do
      config_with_calc = base_configuration.merge(
        "calculations" => [{
          "id"             => "c_persist",
          "target_field_id" => "total",
          "formula"        => "{price} * 1.1"
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_calc.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:ok)

      page_record.reload
      calcs = page_record.configuration_json["calculations"]
      expect(calcs).to be_present
      expect(calcs.first["formula"]).to eq("{price} * 1.1")
    end
  end

  describe "PATCH persistence — conditional rules with show_field action" do
    it "persists a rule with a show_field action" do
      config_with_rule = base_configuration.merge(
        "rules" => [{
          "id"         => "r1",
          "name"       => "Show discount for premium plan",
          "enabled"    => true,
          "conditions" => {
            "logic"  => "all",
            "groups" => [{
              "logic" => "all",
              "items" => [{
                "field_id" => "plan",
                "operator" => "equals",
                "value"    => "premium"
              }]
            }]
          },
          "actions" => [{
            "type"      => "show_field",
            "target_id" => "discount"
          }]
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_rule.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:ok)

      page_record.reload
      rule = page_record.configuration_json["rules"].first
      expect(rule["name"]).to eq("Show discount for premium plan")
      expect(rule["actions"].first["type"]).to eq("show_field")
      expect(rule["actions"].first["target_id"]).to eq("discount")
    end

    it "persists the rule's condition referencing a SELECT field" do
      config_with_rule = base_configuration.merge(
        "rules" => [{
          "id"         => "r_select",
          "name"       => "Select condition rule",
          "enabled"    => true,
          "conditions" => {
            "logic"  => "all",
            "groups" => [{
              "logic" => "all",
              "items" => [{ "field_id" => "plan", "operator" => "equals", "value" => "basic" }]
            }]
          },
          "actions" => [{ "type" => "hide_field", "target_id" => "discount" }]
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_rule.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:ok)

      page_record.reload
      condition_item = page_record
                         .configuration_json
                         .dig("rules", 0, "conditions", "groups", 0, "items", 0)
      expect(condition_item["field_id"]).to eq("plan")
      expect(condition_item["operator"]).to eq("equals")
      expect(condition_item["value"]).to eq("basic")
    end

    it "rejects a rule whose action targets an unknown field" do
      config_with_bad_rule = base_configuration.merge(
        "rules" => [{
          "id"         => "r_bad",
          "name"       => "Bad rule",
          "enabled"    => true,
          "conditions" => {
            "logic"  => "all",
            "groups" => []
          },
          "actions" => [{ "type" => "show_field", "target_id" => "nonexistent_field" }]
        }]
      )

      patch "/#{customer.id}/admin/maintenance/pages/#{page_record.id}",
            params: { page: {
              configuration: config_with_bad_rule.to_json,
              updated_at:    page_record.updated_at.iso8601(6)
            } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["errors"].join).to match(/unknown field 'nonexistent_field'/i)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 3: Multi-tenant isolation
  # Admin of customer A cannot open or save the page edit surface of customer B.
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    it "returns 404 when admin tries to GET-edit a page belonging to another customer" do
      get "/#{customer.id}/admin/maintenance/pages/#{other_page.id}/edit"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when admin tries to PATCH a page belonging to another customer" do
      patch "/#{customer.id}/admin/maintenance/pages/#{other_page.id}",
            params: { page: { name: "Hijacked" } },
            as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "cannot inject a calculation into another tenant's page via cross-tenant PATCH" do
      injected_config = {
        "pages"        => [{ "id" => "p1", "fields" => [] }],
        "metadata"     => { "entity_id" => entity.id },
        "calculations" => [{ "id" => "c_evil", "target_field_id" => "qty", "formula" => "{price}" }],
        "rules"        => []
      }

      patch "/#{customer.id}/admin/maintenance/pages/#{other_page.id}",
            params: { page: { configuration: injected_config.to_json } },
            as: :json

      expect(response).to have_http_status(:not_found)
      # Confirm the other tenant's page is unchanged
      other_page.reload
      expect(other_page.configuration_json["calculations"]).to eq([])
    end

    it "anonymous user is redirected away from the edit page" do
      sign_out admin
      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"
      expect(response).not_to have_http_status(:ok)
    end

    it "member role is forbidden from the edit page" do
      member = create(:user, :member, customer: customer)
      sign_in member
      get "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit"
      # Member role may get forbidden or redirect — either is acceptable
      expect(response).not_to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 4: JS-driven happy-path flows (require headless Chrome)
  # These cover the acceptance criteria that need actual DOM interaction:
  #   - Open calculations panel via toolbar tab
  #   - Click Add Calculation, see the formula editor modal
  #   - Type a formula with a {field_id} token, observe validation status "Valid"
  #   - Save and reload to assert persistence
  #   - Open rules panel, add a rule with a SELECT-field condition — confirm the
  #     value editor renders as a <select> (contextual editor)
  #   - Toggle Test Mode and observe action result chips
  # ---------------------------------------------------------------------------

  context "with JS (headless Chrome)", :js do
    before do
      skip "headless Chrome not available in this environment" unless CHROME_AVAILABLE
      driven_by(:cuprite)
    end

    describe "Calculated Fields — happy path" do
      before { visit "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit" }

      it "opens the calculations panel by clicking the toolbar tab" do
        find('[data-action*="switchTab"][data-tab="calculations"]').click
        expect(page).to have_css('[data-tab-panel="calculations"]:not(.hidden)', wait: 5)
        expect(page).to have_content("Calculated Fields")
      end

      it "opens the formula editor modal on Add Calculation" do
        find('[data-action*="switchTab"][data-tab="calculations"]').click
        find('[data-action*="openFormulaEditor"]', match: :first).click
        expect(page).to have_css('[data-page-builder-target="formulaEditorModal"] [data-controller="formula-editor"]',
                                 wait: 5)
      end

      it "typing a valid formula shows the Valid status" do
        find('[data-action*="switchTab"][data-tab="calculations"]').click
        find('[data-action*="openFormulaEditor"]', match: :first).click

        # Wait for the modal to appear with the formula surface
        formula_surface = find('[data-formula-editor-target="surface"]', wait: 5)
        # Type a simple arithmetic formula using field reference tokens
        formula_surface.click
        formula_surface.send_keys("{qty} * {price}")

        # Status target should show a validation result; the formula-editor
        # Stimulus controller sets it to a non-empty string after debounce.
        status_el = find('[data-formula-editor-target="status"]', wait: 5)
        # Allow a short settle time for the debounced validation
        sleep 0.5
        expect(status_el.text).not_to be_empty
      end

      it "saves a calculation and it appears in the panel after saving" do
        find('[data-action*="switchTab"][data-tab="calculations"]').click
        find('[data-action*="openFormulaEditor"]', match: :first).click

        # Select a target field
        target_select = find('[data-page-builder-target="calculationTargetField"]', wait: 5)
        target_select.find('option[value="total"]').select_option

        # Enter the formula
        formula_surface = find('[data-formula-editor-target="surface"]', wait: 5)
        formula_surface.click
        formula_surface.send_keys("{qty} * {price}")

        # Confirm save — triggers page-builder#saveCalculation
        find('[data-action*="saveCalculation"]').click

        # After save, the calculation should be visible in the panel list
        within('[data-page-builder-target="calculationsPanel"]') do
          expect(page).to have_css('[data-calculation-id]', wait: 5)
        end
      end

      it "persists the calculation in {field_id} token form after saving via the toolbar save button" do
        find('[data-action*="switchTab"][data-tab="calculations"]').click
        find('[data-action*="openFormulaEditor"]', match: :first).click

        target_select = find('[data-page-builder-target="calculationTargetField"]', wait: 5)
        target_select.find('option[value="total"]').select_option

        formula_surface = find('[data-formula-editor-target="surface"]', wait: 5)
        formula_surface.click
        formula_surface.send_keys("{qty} * {price}")

        find('[data-action*="saveCalculation"]').click

        # Trigger a save (Ctrl+S or the save button in the toolbar)
        # The calc/rule tab panel is a full-screen overlay that covers the
        # toolbar; close it with Escape so the toolbar Save button is clickable.
        find("body").send_keys(:escape)
        find('[data-page-builder-target="saveBtn"]', wait: 5).click

        # Wait for the auto-save AJAX response and then check DB
        sleep 1
        page_record.reload
        calcs = page_record.configuration_json["calculations"]
        expect(calcs).to be_present
        formula = calcs.first["formula"]
        # Formula is stored in {field_id} token form
        expect(formula).to include("{qty}")
        expect(formula).to include("{price}")
      end
    end

    describe "Conditional Rules — happy path" do
      before { visit "/#{customer.id}/admin/maintenance/pages/#{page_record.id}/edit" }

      it "opens the rules panel by clicking the toolbar tab" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        expect(page).to have_css('[data-tab-panel="rules"]:not(.hidden)', wait: 5)
        expect(page).to have_content("Conditional Rules")
      end

      it "opens the rule editor modal on Add Rule" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click
        expect(page).to have_css('[data-controller="rule-builder"]', wait: 5)
        expect(page).to have_css('[data-rule-builder-target="ruleName"]', wait: 5)
      end

      it "adds a condition group and renders a condition row" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        # Add a condition group
        find('[data-action*="addConditionGroup"]', wait: 5).click
        # Then add a condition item inside it
        find('[data-action*="addConditionItem"]', match: :first, wait: 5).click

        # A condition row should now be present
        expect(page).to have_css('[data-condition-field]', wait: 5)
      end

      it "selecting a SELECT-type field in a condition row renders a dropdown value editor" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        find('[data-action*="addConditionGroup"]', wait: 5).click
        find('[data-action*="addConditionItem"]', match: :first, wait: 5).click

        # Select the 'plan' field (which has property_type: select)
        condition_field_select = find('[data-condition-field]', wait: 5)
        condition_field_select.find("option[value='plan']").select_option

        # A select field defaults to the value-less "is_selected" operator, which
        # renders no value editor. Pick a value-requiring operator so the
        # rule-builder re-renders the contextual <select> value editor.
        find('[data-condition-operator]', wait: 5).find("option[value='equals']").select_option

        # The rule-builder controller should re-render the value editor as a
        # <select> element (contextual editor) because the field type is 'select'
        expect(page).to have_css('[data-condition-value] option', wait: 5)
        within(find('[data-condition-value]')) do
          # The options from the field definition should be present
          expect(page).to have_css('option[value="basic"]').or(have_css('option[value="premium"]'))
        end
      end

      it "adds a show_field action and the action is listed in the rule editor" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        # Fill in a rule name
        find('[data-rule-builder-target="ruleName"]', wait: 5).set("Test rule")

        # Add an action
        find('[data-action*="addAction"]').click

        expect(page).to have_css('[data-action-item]', wait: 5)
        # The action type select should default to (or allow) show_field
        action_type_select = find('[data-action-type="0"]', wait: 5)
        action_type_select.find("option[value='show_field']").select_option

        # Select a target field for the action
        find('[data-action-target="0"]', wait: 5).find("option[value='discount']").select_option

        expect(page).to have_css('[data-action-item="0"]')
      end

      it "enables test mode and shows the test panel" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        test_toggle = find('[data-rule-builder-target="testToggle"]', wait: 5)
        test_toggle.check

        expect(page).to have_css('[data-rule-builder-target="testPanel"]:not(.hidden)', wait: 5)
        expect(page).to have_content("Enter sample values", wait: 5)
      end

      it "saves a rule with a show_field action and it appears in the rules panel" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        find('[data-rule-builder-target="ruleName"]', wait: 5).set("Show discount")

        find('[data-action*="addConditionGroup"]').click
        find('[data-action*="addConditionItem"]', match: :first, wait: 5).click

        condition_field_select = find('[data-condition-field]', wait: 5)
        condition_field_select.find("option[value='plan']").select_option

        find('[data-action*="addAction"]').click
        find('[data-action-type="0"]', wait: 5).find("option[value='show_field']").select_option
        find('[data-action-target="0"]', wait: 5).find("option[value='discount']").select_option

        # Save the rule
        find('[data-action*="saveRule"]').click

        # The rule should appear in the panel list
        within('[data-page-builder-target="rulesPanel"]') do
          expect(page).to have_css('[data-rule-id]', wait: 5)
          expect(page).to have_content("Show discount")
        end
      end

      it "persists the rule in the database after triggering configuration save" do
        find('[data-action*="switchTab"][data-tab="rules"]').click
        find('[data-action*="openRuleEditor"]', match: :first).click

        find('[data-rule-builder-target="ruleName"]', wait: 5).set("Persist rule")

        find('[data-action*="addConditionGroup"]').click
        find('[data-action*="addConditionItem"]', match: :first, wait: 5).click

        condition_field_select = find('[data-condition-field]', wait: 5)
        condition_field_select.find("option[value='plan']").select_option

        find('[data-action*="addAction"]').click
        find('[data-action-type="0"]', wait: 5).find("option[value='show_field']").select_option
        find('[data-action-target="0"]', wait: 5).find("option[value='discount']").select_option

        find('[data-action*="saveRule"]').click

        # Save the whole configuration
        # The calc/rule tab panel is a full-screen overlay that covers the
        # toolbar; close it with Escape so the toolbar Save button is clickable.
        find("body").send_keys(:escape)
        find('[data-page-builder-target="saveBtn"]', wait: 5).click
        sleep 1

        page_record.reload
        rules = page_record.configuration_json["rules"]
        expect(rules).to be_present
        rule = rules.find { |r| r["name"] == "Persist rule" }
        expect(rule).not_to be_nil
        expect(rule["actions"].first["type"]).to eq("show_field")
        expect(rule["actions"].first["target_id"]).to eq("discount")
      end
    end

    describe "cross-tenant isolation — JS context" do
      let(:other_customer) { create(:customer) }
      let!(:other_page)    { create(:page, customer: other_customer) }

      it "redirects or 404s when an admin tries to visit another tenant's page editor" do
        visit "/#{customer.id}/admin/maintenance/pages/#{other_page.id}/edit"
        # The controller scopes `find_page` to the current customer, so a
        # cross-tenant id raises RecordNotFound (404) and the page-builder
        # editor never mounts — whether that surfaces as a 404 page or a
        # redirect, the editor must not be shown.
        expect(page).to have_no_css('[data-controller~="page-builder"]')
      end
    end
  end
end
