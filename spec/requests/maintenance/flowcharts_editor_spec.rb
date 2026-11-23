# frozen_string_literal: true

require "rails_helper"

# ---------------------------------------------------------------------------
# Flowchart edit page — QA coverage for the refactored property editor surface
#
# Scope:
#  1. Stable markup assertions: new property-editor skeleton is present
#  2. Removed-markup assertions: old step-modal container and quick-add rows
#     must no longer appear (regression guard against reverting the refactor)
#  3. Authorization matrix: admin OK, member blocked, anonymous redirected,
#     cross-tenant admin blocked
# ---------------------------------------------------------------------------

RSpec.describe "Maintenance::Flowcharts edit page — property editor surface", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:entity)   { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

  def edit_path
    "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit"
  end

  # -------------------------------------------------------------------------
  # Happy-path: markup assertions for the refactored editor
  # -------------------------------------------------------------------------
  context "when signed in as admin (own tenant)" do
    before do
      sign_in platform_owner
      get edit_path
    end

    it "mounts the property-editor Stimulus controller on the sidebar" do
      expect(response.body).to include('data-controller="property-editor panel-resize"')
    end

    # Missing I18n in data-* attributes emits <span class="translation_missing">
    # which breaks out of quoted attributes and corrupts the property-editor mount.
    it "does not emit translation_missing markup in the editor HTML" do
      expect(response.body).not_to include("translation_missing")
    end

    it "includes the property-editor sidebar target" do
      expect(response.body).to include('data-property-editor-target="sidebar"')
    end

    it "no longer renders a branch modal container" do
      expect(response.body).not_to include("branchModalContainer")
    end

    it "includes the tab-bar target for dynamic tab rendering" do
      expect(response.body).to include('data-property-editor-target="tabBar"')
    end

    it "includes the General tab pane target" do
      expect(response.body).to include('data-property-editor-target="tabPaneGeneral"')
    end

    it "includes the Steps tab pane target" do
      expect(response.body).to include('data-property-editor-target="tabPaneSteps"')
    end

    it "includes the formFieldsSteps target (populated by JS step manager)" do
      expect(response.body).to include('data-property-editor-target="formFieldsSteps"')
    end

    it "includes the panel-resize drag handle action binding" do
      expect(response.body).to include('data-action="mousedown->panel-resize#startResize"')
    end

    it "passes step picker, retry, timeout, and error badge translations onto the editor mount" do
      expect(response.body).to include('data-property-editor-step-picker-search-placeholder-value="Search actions…')
      expect(response.body).to include('data-property-editor-step-picker-no-match-label-value="No matching actions"')
      expect(response.body).to include('data-property-editor-step-picker-already-used-label-value="(already used)"')
      expect(response.body).to include('data-property-editor-step-picker-all-categories-label-value="All"')
      expect(response.body).to include('data-property-editor-step-picker-categories-label-value="Filter by category"')
      expect(response.body).to include('data-property-editor-step-picker-recent-label-value="Recently used"')
      expect(response.body).to include('data-property-editor-step-retry-not-idempotent-hint-value=')
      expect(response.body).to include('data-property-editor-step-timeout-gives-up-format-value="Gives up after {seconds} s"')
      expect(response.body).to include('data-property-editor-step-error-badge-label-value="Error"')
      expect(response.body).to include('data-property-editor-step-change-button-label-value="Change"')
      expect(response.body).to include('data-property-editor-step-remove-button-label-value="Remove"')
    end

    it "includes the flowchart-canvas controller wired to the flowchart id" do
      expect(response.body).to include("data-flowchart-canvas-id-value=\"#{flowchart.id}\"")
    end

    it "renders the loaded line head and a hidden save-conflict banner with Reload and Overwrite" do
      page = Nokogiri::HTML(response.body)
      mount = page.at_css("[data-controller~='flowchart-canvas']")
      expect(mount["data-flowchart-canvas-head-version-id-value"]).to eq(flowchart.current_line_head_version_id.to_s)
      expect(mount["data-flowchart-canvas-save-failed-http-format-value"]).to eq("Save failed (HTTP {status})")
      expect(mount["data-flowchart-canvas-restore-failed-http-format-value"]).to eq("Restore failed (HTTP {status})")

      banner = page.at_css("[data-flowchart-canvas-target='saveConflictBanner']")
      expect(banner["role"]).to eq("alert")
      expect(banner["class"].split).to include("hidden")

      notice = page.at_css("[data-flowchart-canvas-target='previewNotice']")
      expect(notice["role"]).to eq("status")
      expect(notice["class"].split).to include("hidden")
      expect(notice.text).to include("Previewing a subflow — fold it to edit")
      expect(banner.at_css("[data-action='click->flowchart-canvas#reloadAfterConflict']").text.strip).to eq("Reload")
      expect(banner.at_css("[data-action='click->flowchart-canvas#overwriteAfterConflict']").text.strip).to eq("Overwrite")
    end

    # -----------------------------------------------------------------------
    # Test Runner tab — enhanced markup (input validation, history, run button)
    # -----------------------------------------------------------------------

    it "includes the test Run button target" do
      expect(response.body).to include('data-flowchart-canvas-target="testRunButton"')
    end

    it "includes the test input inline error target" do
      expect(response.body).to include('data-flowchart-canvas-target="testInputError"')
    end

    it "includes the test run history container target" do
      expect(response.body).to include('data-flowchart-canvas-target="testHistory"')
    end

    it "wires live JSON validation on the test input textarea" do
      expect(response.body).to include('data-action="input->flowchart-canvas#validateTestInput"')
    end

    # -----------------------------------------------------------------------
    # Removed-markup regression guards
    # These assert that the OLD pre-refactor markup is definitively absent.
    # -----------------------------------------------------------------------

    it "does NOT include the removed step-modal container target" do
      expect(response.body).not_to include('data-property-editor-target="stepModalContainer"')
    end

    it "does NOT include any data-step-modal attribute" do
      expect(response.body).not_to include("data-step-modal")
    end

    it "does NOT include any data-branch-quick-add attribute (quick-add row removed)" do
      expect(response.body).not_to include("data-branch-quick-add")
    end

    it "does NOT include any data-step-quick-add attribute (quick-add row removed)" do
      expect(response.body).not_to include("data-step-quick-add")
    end

    it "does NOT include the old property-editor modal overlay (full-screen modal replaced by sidebar)" do
      # The old design used a fixed-position full-screen modal div; the new design
      # uses an inline right sidebar. The 'property-editor' class + 'fixed inset-0'
      # combo is gone.
      expect(response.body).not_to match(/class="[^"]*\bproperty-editor\b[^"]*fixed inset-0/)
    end
  end

  %i[en zh-CN].each do |locale|
    it "embeds the action catalog once on the canvas mount in #{locale}" do
      sign_in platform_owner
      get edit_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-property-editor-action-i18n-value")
      expect(response.body).not_to include("data-property-editor-action-catalog-value")
      html = Nokogiri::HTML(response.body)
      mounts = html.css("[data-flowchart-canvas-action-catalog-value]")
      expect(mounts.size).to eq(1)
      catalog = JSON.parse(mounts.first["data-flowchart-canvas-action-catalog-value"])
      expect(catalog.fetch("locale")).to eq(locale.to_s)
      expect(catalog.fetch("actions")).to be_an(Array)
      find_model = catalog.fetch("actions").find { |action| action["key"] == "find_model" }
      expect(find_model).to be_present
      expect(find_model.fetch("label")).to eq(I18n.t("flowchart_actions.find_model.label", locale: locale))
      expect(find_model.fetch("fields")).to be_an(Array)
      expect(response.body).not_to include("translation_missing")
    end

    it "embeds step-form control strings on the property-editor mount in #{locale}" do
      sign_in platform_owner
      get edit_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      I18n.with_locale(locale) do
        expect(response.body).to include(%(data-property-editor-none-option-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.none_option_label")}"))
        expect(response.body).to include(%(data-property-editor-add-row-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.add_row_label")}"))
        expect(response.body).to include(%(data-property-editor-remove-row-title-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.remove_row_title")}"))
        expect(response.body).to include(%(data-property-editor-search-placeholder-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.search_placeholder")}"))
        expect(response.body).to include(%(data-property-editor-locale-en-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.locale_en_label")}"))
        expect(response.body).to include(%(data-property-editor-locale-zh-cn-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.locale_zh_cn_label")}"))
        expect(response.body).to include(%(data-property-editor-reference-loading-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.reference_loading_label")}"))
        expect(response.body).to include(%(data-property-editor-reference-empty-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.reference_empty_label")}"))
        expect(response.body).to include(%(data-property-editor-reference-error-label-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.reference_error_label")}"))
        expect(response.body).to include(%(data-property-editor-reference-placeholder-value="#{I18n.t("maint_core.flowcharts.editor.property_editor.reference_placeholder")}"))
        expect(response.body).to include("__SOURCE__")
        expect(response.body).to include("reference_options")
        expect(response.body).to include("__SOURCE__.json?exclude_id=#{flowchart.id}")
      end
      expect(response.body).not_to include("translation_missing")
    end

    it "passes the app locale and the readability format strings to the canvas in #{locale}" do
      sign_in platform_owner
      get edit_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      mount = Nokogiri::HTML(response.body).at_css("[data-controller~='flowchart-canvas']")
      I18n.with_locale(locale) do
        {
          "app-locale" => locale.to_s,
          "element-connections-format" => I18n.t("maint_core.flowcharts.editor.element_connections_format"),
          "version-label-format" => I18n.t("maint_core.flowcharts.editor.version_label_format"),
          "subflow-self-reference-toast" => I18n.t("maint_core.flowcharts.editor.subflow_self_reference_toast"),
          "test-query-duration-format" => I18n.t("maint_core.flowcharts.editor.test_query_duration_format")
        }.each do |name, expected|
          expect(mount["data-flowchart-canvas-#{name}-value"]).to eq(expected)
        end
      end
      minimap = Nokogiri::HTML(response.body).at_css("[data-flowchart-canvas-target='minimapContainer']")
      expect(minimap["class"].split).to include("z-30")
    end
  end

  # -------------------------------------------------------------------------
  # Authorization matrix
  # -------------------------------------------------------------------------

  let(:guard_path) { edit_path }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "redirects anonymous away from flowchart editor"

  context "when signed in as admin of a DIFFERENT tenant (cross-tenant isolation)" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, :admin, customer: other_customer) }

    before { sign_in other_admin }

    it "cannot access another tenant's flowchart edit page" do
      get edit_path
      expect(response).not_to have_http_status(:ok)
    end
  end

  context "when signed in as the platform owner (cross-tenant access allowed)" do
    before do
      ensure_platform_customer
      sign_in find_or_create_platform_owner
    end

    it "can access any tenant's flowchart edit page" do
      get edit_path
      follow_redirect! while response.redirect?
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="property-editor')
    end
  end

  # -------------------------------------------------------------------------
  # Launched flowchart: editable, saves stage a draft version
  # -------------------------------------------------------------------------
  context "when the flowchart is launched" do
    let(:flowchart) { create(:flowchart, :simple, :launched_status, customer: customer) }

    before { sign_in platform_owner }

    it "keeps the canvas writable and says saves stage a draft above the live version" do
      get edit_path

      expect(response.body).not_to include('read-only-value="true"')
      expect(response.body).not_to include(I18n.t("maint_core.flowcharts.editor.launched_notice"))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("maint_core.flowcharts.editor.launched_edit_notice", live: 1)))
      expect(response.body).to include(I18n.t("maint_core.flowcharts.launch_latest"))
    end

    it "renders the head revision for the save conflict check" do
      get edit_path

      expect(response.body).to include(%(data-flowchart-canvas-head-revision-value="#{flowchart.current_line_head_revision}"))
    end

    it "names the pending draft once a save forked one" do
      config = JSON.parse(flowchart.configuration).merge("metadata" => { "canvas" => { "width" => 1500 } })
      flowchart.update!(configuration: config.to_json)

      get edit_path

      expect(response.body).to include(CGI.escapeHTML(I18n.t("maint_core.flowcharts.editor.launched_draft_notice", live: 1, draft: 2)))
    end
  end

  # -------------------------------------------------------------------------
  # Shared flowchart: non-platform-owner is blocked from editing
  # -------------------------------------------------------------------------
  context "when the flowchart is shared-type and user is a regular admin" do
    let(:shared_flowchart) { create(:flowchart, :shared_type) }

    before { sign_in platform_owner }

    it "renders the editor so the admin can save a customer override" do
      get "/#{customer.id}/admin/maintenance/flowcharts/#{shared_flowchart.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="property-editor panel-resize"')
      expect(response.body).to include(I18n.t("maint_core.flowcharts.editor.shared_override_notice"))
      expect(response.body).not_to include('read-only-value="true"')
    end

    it "renders the tenant's override head as the expected head once an override exists" do
      config = JSON.parse(shared_flowchart.configuration).merge("metadata" => { "canvas" => { "width" => 1500 } })
      patch "/#{customer.id}/admin/maintenance/flowcharts/#{shared_flowchart.id}.json",
            params: { flowchart: { configuration: config.to_json } }, as: :json
      override_head = FlowchartCustomerHead.find_by!(flowchart_id: shared_flowchart.id, customer_id: customer.id)

      get "/#{customer.id}/admin/maintenance/flowcharts/#{shared_flowchart.id}/edit"

      expect(override_head.current_version_id).not_to eq(shared_flowchart.reload.current_version_id)
      expect(response.body).to include("data-flowchart-canvas-head-version-id-value=\"#{override_head.current_version_id}\"")
    end
  end

  context "when the flowchart is a launched shared-type" do
    let(:shared_flowchart) { create(:flowchart, :shared_type, :simple, :launched_status) }

    before { sign_in platform_owner }

    it "keeps the canvas writable for a tenant override" do
      get "/#{customer.id}/admin/maintenance/flowcharts/#{shared_flowchart.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("maint_core.flowcharts.editor.shared_override_notice"))
      expect(response.body).not_to include(I18n.t("maint_core.flowcharts.editor.launched_notice"))
      expect(response.body).not_to include(I18n.t("maint_core.flowcharts.launch_latest"))
      expect(response.body).not_to include('read-only-value="true"')
    end
  end
end
