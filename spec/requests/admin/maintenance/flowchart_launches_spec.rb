# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::FlowchartLaunches", type: :request do
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let!(:flowchart) { create(:flowchart, :simple, customer: customer) }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "POST create — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch" }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  # ---------------------------------------------------------------------------
  # POST create — happy path (launch a valid draft flowchart)
  # ---------------------------------------------------------------------------

  describe "POST create — launch a valid draft flowchart" do
    before do
      sign_in platform_owner
      allow_any_instance_of(FlowchartInputOutputValidator::Result).to receive(:errors).and_return([])
    end

    it "sets the flowchart to launched and redirects to its detail page" do
      post "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch"

      expect(response).to have_http_status(:redirect)
      expect(flowchart.reload.status).to eq("launched")
      expect(flash[:notice]).to match(/launched successfully/i)
    end
  end

  describe "POST create — malformed configuration rows" do
    before { sign_in platform_owner }

    it "does not 500 when an element is not an object" do
      bad = create(:flowchart, customer: customer, configuration: {
        "elements" => ["nope"],
        "connections" => [],
        "metadata" => {}
      }.to_json)

      post "/#{customer.id}/admin/maintenance/flowcharts/#{bad.id}/launch"

      expect(response).not_to have_http_status(:internal_server_error)
      expect(response).to have_http_status(:redirect)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — already launched branch
  # ---------------------------------------------------------------------------

  describe "POST create — flowchart already launched" do
    let!(:launched_flowchart) do
      create(:flowchart, :launched_status, customer: customer)
    end

    before { sign_in platform_owner }

    it "responds with 422 (redirect with unprocessable status) and does not double-launch" do
      post "/#{customer.id}/admin/maintenance/flowcharts/#{launched_flowchart.id}/launch"

      # The controller calls redirect_to ... status: :unprocessable_entity
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to match(/already launched/i)
      expect(launched_flowchart.reload.status).to eq("launched")
    end
  end

  describe "POST create — launched flowchart with a pending draft version" do
    let!(:live) { create(:flowchart, :simple, :launched_status, customer: customer) }
    let(:launch_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{live.id}/launch" }

    before do
      sign_in platform_owner
      config = JSON.parse(live.configuration)
      config["elements"].find { |el| el["id"] == "process_1" }["label"] = "Revised step"
      live.update!(configuration: config.to_json)
    end

    it "publishes the draft version and recompiles the live activity" do
      allow_any_instance_of(FlowchartInputOutputValidator::Result).to receive(:errors).and_return([])
      draft_id = live.reload.current_version_id
      expect(live.launched_version_id).not_to eq(draft_id)

      expect { post launch_path }.to(change { live.reload.activity })

      expect(response).to redirect_to("/#{customer.id}/admin/maintenance/flowcharts/#{live.id}")
      expect(flash[:notice]).to match(/launched successfully/i)
      expect(live.launched_version_id).to eq(draft_id)
      expect(live).not_to be_pending_draft
    end

    it "keeps the launched version live when the draft fails validation" do
      allow(FlowchartInputOutputValidator).to receive(:call)
        .and_return(instance_double(FlowchartInputOutputValidator::Result, errors: ["Missing output: x"]))
      launched_id = live.reload.launched_version_id

      post launch_path

      expect(response).to redirect_to(%r{/flowcharts/#{live.id}/edit})
      expect(live.reload.launched_version_id).to eq(launched_id)
      expect(live).to be_pending_draft
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — validation errors branch
  # ---------------------------------------------------------------------------

  describe "POST create — flowchart has validation errors" do
    before do
      sign_in platform_owner
      fake_result = instance_double(
        FlowchartInputOutputValidator::Result,
        errors: ["Missing output: some_key"]
      )
      allow(FlowchartInputOutputValidator).to receive(:call).and_return(fake_result)
    end

    it "redirects to the edit page with validation error flash" do
      post "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/cannot launch/i)
      expect(flowchart.reload.status).to eq("draft")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — server validation (structure, config, codegen) blocks launch
  # ---------------------------------------------------------------------------

  describe "POST create — server validation" do
    let(:launch_path) { "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch" }

    def problem(severity) = { type: "config_invalid", severity: severity, message: "x" }

    before do
      sign_in platform_owner
      allow_any_instance_of(FlowchartInputOutputValidator::Result).to receive(:errors).and_return([])
    end

    it "blocks the launch on any error and counts only errors in the alert" do
      allow_any_instance_of(FlowchartServerValidator).to receive(:call)
        .and_return([problem("error"), problem("warning"), problem("error")])

      post launch_path

      expect(response).to redirect_to("/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/edit?show_validation=true")
      expect(flash[:alert]).to eq("Fix the 2 problems in the editor before launching.")
      expect(flash[:validation_errors]).to be_nil
      expect(flowchart.reload.status).to eq("draft")
    end

    it "uses the singular alert for one error" do
      allow_any_instance_of(FlowchartServerValidator).to receive(:call).and_return([problem("error")])

      post launch_path

      expect(flash[:alert]).to eq("Fix the 1 problem in the editor before launching.")
    end

    it "launches when the validator reports only warnings" do
      allow_any_instance_of(FlowchartServerValidator).to receive(:call).and_return([problem("warning")])

      post launch_path

      expect(flowchart.reload.status).to eq("launched")
    end

    it "blocks a real structural error (subflow pointing at a missing flowchart)" do
      config = JSON.parse(flowchart.configuration)
      config["elements"] << { "id" => "sub_1", "type" => "subflow", "x" => 400, "y" => 200, "width" => 100,
                              "height" => 45, "label" => "Missing", "properties" => { "flowchartId" => 0 } }
      flowchart.update!(configuration: config.to_json)

      post launch_path

      expect(flash[:alert]).to match(/before launching/)
      expect(flowchart.reload.status).to eq("draft")
    end

    it "launches a clean flowchart without rewriting its configuration or snapshotting a version" do
      expect { post launch_path }.not_to(change { [flowchart.reload.configuration, flowchart.flowchart_versions.count] })
      expect(flowchart.reload.status).to eq("launched")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — return to draft
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — take a launched flowchart offline" do
    let!(:launched_flowchart) do
      create(:flowchart, :launched_status, customer: customer)
    end

    before { sign_in platform_owner }

    it "sets status back to draft and redirects" do
      delete "/#{customer.id}/admin/maintenance/flowcharts/#{launched_flowchart.id}/launch"

      expect(response).to have_http_status(:redirect)
      expect(launched_flowchart.reload.status).to eq("draft")
      expect(flash[:notice]).to match(/taken offline/i)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — already a draft branch
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — flowchart already a draft" do
    before { sign_in platform_owner }

    it "responds with 422 (redirect with unprocessable status) and leaves status as draft" do
      delete "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch"

      # The controller calls redirect_to ... status: :unprocessable_entity
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to match(/already a draft/i)
      expect(flowchart.reload.status).to eq("draft")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer)   { create(:customer) }
    let!(:other_flowchart) { create(:flowchart, customer: other_customer) }

    before { sign_in platform_owner }

    it "returns 404 for another tenant's flowchart on POST" do
      post "/#{customer.id}/admin/maintenance/flowcharts/#{other_flowchart.id}/launch"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for another tenant's flowchart on DELETE" do
      delete "/#{customer.id}/admin/maintenance/flowcharts/#{other_flowchart.id}/launch"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE destroy — launched forms on the flowchart's entity" do
    before { sign_in platform_owner }

    it "takes the flowchart offline without mentioning forms" do
      flowchart.update!(status: :launched)
      create(:page, customer: customer, launched: true)

      delete "/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}/launch"

      expect(flash[:notice]).to eq(I18n.t("maint_core.flash.flowchart_launches.taken_offline"))
      expect(flowchart.reload.status).to eq("draft")
    end

    it "redirects with an alert and does not 500 when a launched page uses the flowchart" do
      launched = create(:flowchart, :simple, :launched_status, customer: customer)
      create(:page, customer: customer, entity: create(:entity, customer: customer),
                    flowchart: launched, launched: true)

      delete "/#{customer.id}/admin/maintenance/flowcharts/#{launched.id}/launch"

      expect(response).to have_http_status(:redirect)
      expect(response).not_to have_http_status(:internal_server_error)
      expect(flash[:alert]).to eq(
        I18n.t("maint_core.errors.validations.flowchart_offline_used_by_pages", count: 1)
      )
      expect(launched.reload.status).to eq("launched")
    end
  end
end
