# frozen_string_literal: true

require "rails_helper"

# ---------------------------------------------------------------------------
# Flowchart reference-options endpoint
#   GET /:cid/admin/maintenance/flowcharts/reference_options/:source
#   GET /:cid/admin/maintenance/platform/flowcharts/reference_options/:source
#
# Scope:
#  1. Owner on a tenant prefix receives that URL customer's options only
#  2. Owner on the platform prefix receives the platform owner customer's options
#  3. Authorization matrix matches flowchart traces: tenant admin / member /
#     anonymous rejected the same way; cross-tenant admin forbidden
#  4. Unknown source → 404 JSON with a translated message
#  5. q trimmed and capped at 100; limit fixed at 50; entity_id Integer-only
#  6. JSON only (HTML → 406)
# ---------------------------------------------------------------------------

RSpec.describe "Maintenance::Flowcharts reference_options endpoint", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:calls) { [] }
  let(:source_key) { "email_templates" }
  let(:fake_source) do
    recorded = calls
    Class.new do
      define_method(:options) do |customer:, query: nil, limit: 50, entity_id: nil, exclude_id: nil|
        recorded << { customer: customer, query: query, limit: limit, entity_id: entity_id, exclude_id: exclude_id }
        [{ value: "cust-#{customer.id}", label: "Option #{customer.id}" }]
      end
    end.new
  end
  let(:registry) do
    source = fake_source
    key = source_key
    Module.new do
      define_singleton_method(:fetch) do |name|
        name.to_s == key ? source : nil
      end
    end
  end

  def options_path(cid: customer.id, source: source_key, platform: false)
    prefix = platform ? "/#{cid}/admin/maintenance/platform" : "/#{cid}/admin/maintenance"
    "#{prefix}/flowcharts/reference_options/#{source}"
  end

  def get_options(**path_args)
    extra = path_args.extract!(:params)
    get options_path(**path_args), params: extra[:params] || {}, as: :json
  end

  shared_context "stubbed reference sources" do
    before do
      stub_const("CodeGenerators::ReferenceSources", registry)
    end
  end

  # -------------------------------------------------------------------------
  # Routing (collection on both prefixes; same controller as traces naming)
  # -------------------------------------------------------------------------
  describe "routing" do
    it "recognises the tenant collection path" do
      recognized = Rails.application.routes.recognize_path(
        options_path, method: :get
      )
      expect(recognized).to include(
        controller: "admin/maintenance/flowchart_reference_options",
        action: "show",
        source: source_key,
        customer_id: customer.id.to_s
      )
    end

    it "recognises the platform collection path" do
      cid = Authentication::User::PLATFORM_CUSTOMER_ID
      recognized = Rails.application.routes.recognize_path(
        options_path(cid: cid, platform: true), method: :get
      )
      expect(recognized).to include(
        controller: "admin/maintenance/flowchart_reference_options",
        action: "show",
        source: source_key,
        customer_id: cid.to_s
      )
    end

    it "exposes path helpers the editor can call" do
      expect(
        reference_options_admin_maintenance_flowcharts_path(customer.id, source_key)
      ).to eq(options_path)
      expect(
        reference_options_admin_maintenance_platform_flowcharts_path(
          Authentication::User::PLATFORM_CUSTOMER_ID, source_key
        )
      ).to eq(options_path(cid: Authentication::User::PLATFORM_CUSTOMER_ID, platform: true))
    end
  end

  # -------------------------------------------------------------------------
  # Owner on tenant prefix
  # -------------------------------------------------------------------------
  context "when signed in as the platform owner (tenant prefix)" do
    include_context "stubbed reference sources"

    before { sign_in platform_owner }

    it "returns 200 with only that URL customer's options" do
      get_options

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "options" => [{ "value" => "cust-#{customer.id}", "label" => "Option #{customer.id}" }]
      )
      expect(calls.length).to eq(1)
      expect(calls.first[:customer]).to eq(customer)
    end

    it "does not call the source with another tenant's customer" do
      other = create(:customer)
      get_options

      expect(calls.first[:customer]).to eq(customer)
      expect(calls.first[:customer]).not_to eq(other)
      expect(calls.first[:customer]).not_to eq(platform_owner.customer)
    end

    it "trims q and caps it at 100 characters" do
      get_options(params: { q: "  #{'x' * 150}  " })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:query]).to eq("x" * 100)
    end

    it "passes a blank q as nil" do
      get_options(params: { q: "   " })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:query]).to be_nil
    end

    it "fixes limit at 50 even when the client sends another value" do
      get_options(params: { limit: 3 })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:limit]).to eq(50)
    end

    it "casts entity_id to Integer" do
      get_options(params: { entity_id: "42" })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:entity_id]).to eq(42)
    end

    it "casts exclude_id to Integer" do
      get_options(params: { exclude_id: "99" })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:exclude_id]).to eq(99)
    end

    it "drops a non-integer entity_id rather than passing it through" do
      get_options(params: { entity_id: "abc" })

      expect(response).to have_http_status(:ok)
      expect(calls.first[:entity_id]).to be_nil
    end

    it "responds 404 JSON with a translated message for an unknown source" do
      get_options(source: "not_a_source")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(
        "error" => I18n.t("maint_core.flowcharts.reference_options.unknown_source")
      )
      expect(calls).to be_empty
    end

    it "translates the unknown-source message in zh-CN" do
      get options_path(source: "not_a_source"), params: { locale: "zh-CN" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(
        I18n.t("maint_core.flowcharts.reference_options.unknown_source", locale: :"zh-CN")
      )
      expect(response.parsed_body["error"]).not_to eq("Unknown reference source")
    end

    it "rejects an HTML request" do
      get options_path

      expect(response).to have_http_status(:not_acceptable)
      expect(calls).to be_empty
    end
  end

  context "when signed in as the platform owner (cross-tenant URL customer)" do
    include_context "stubbed reference sources"

    let(:other_customer) { create(:customer) }

    before { sign_in platform_owner }

    it "returns tenant B's options on tenant B's URL, never tenant A's" do
      get_options(cid: other_customer.id)

      expect(response).to have_http_status(:ok)
      expect(calls.first[:customer]).to eq(other_customer)
      expect(calls.first[:customer]).not_to eq(customer)
      expect(response.parsed_body["options"]).to eq(
        [{ "value" => "cust-#{other_customer.id}", "label" => "Option #{other_customer.id}" }]
      )
    end
  end

  # -------------------------------------------------------------------------
  # Owner on platform prefix
  # -------------------------------------------------------------------------
  context "when signed in as the platform owner (platform prefix)" do
    include_context "stubbed reference sources"

    before do
      ensure_platform_customer
      sign_in platform_owner
    end

    it "returns the platform owner customer's options" do
      cid = Authentication::User::PLATFORM_CUSTOMER_ID
      get_options(cid: cid, platform: true)

      expect(response).to have_http_status(:ok)
      expect(calls.first[:customer].id).to eq(cid)
      expect(response.parsed_body["options"]).to eq(
        [{ "value" => "cust-#{cid}", "label" => "Option #{cid}" }]
      )
    end
  end

  # -------------------------------------------------------------------------
  # Authorization matrix — same shared examples as flowchart traces
  # -------------------------------------------------------------------------
  context "authorization matrix (HTML, matching flowchart traces)" do
    include_context "stubbed reference sources"

    let(:guard_path) { options_path }

    it_behaves_like "a platform-owner-guarded request", :get
    it_behaves_like "redirects anonymous away from flowchart editor", :get
  end

  context "when signed in as a tenant admin" do
    include_context "stubbed reference sources"

    before { sign_in admin }

    it "is forbidden on JSON, matching flowchart traces" do
      get_options

      expect(response).not_to have_http_status(:ok)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when signed in as a member" do
    include_context "stubbed reference sources"

    let(:member) { create(:user, :member, customer: customer) }

    before { sign_in member }

    it "is forbidden on JSON, matching flowchart traces" do
      get_options

      expect(response).not_to have_http_status(:ok)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when anonymous" do
    it "is unauthorized on JSON" do
      get_options

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when signed in as admin of a DIFFERENT tenant (cross-tenant isolation)" do
    include_context "stubbed reference sources"

    let(:other_customer) { create(:customer) }
    let(:other_admin) { create(:user, :admin, customer: other_customer) }

    before { sign_in other_admin }

    it "cannot read another tenant's reference options" do
      get_options

      expect(response).not_to have_http_status(:ok)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------------
  # Live T4 registry (skip if that file has not landed yet)
  # -------------------------------------------------------------------------
  context "against the live CodeGenerators::ReferenceSources registry" do
    let(:registry_path) { Rails.root.join("app/services/code_generators/reference_sources.rb") }

    before do
      skip "T4 registry not in tree yet" unless registry_path.exist?
      sign_in platform_owner
    end

    it "returns a JSON options array for a registered source" do
      live = CodeGenerators::ReferenceSources
      skip "T4 registry does not implement fetch" unless live.respond_to?(:fetch)

      key = %w[
        email_templates sms_templates constants entities
        entity_associations pages flowcharts job_classes service_classes
      ].find { |candidate| live.fetch(candidate) }
      skip "no registered source yet" unless key

      get options_path(source: key), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("options")
      expect(response.parsed_body["options"]).to be_an(Array)
    end
  end

  context "live flowcharts source" do
    let!(:owned) { create(:flowchart, :launched_status, customer: customer, name: "Alpha Flow") }
    let!(:draft) { create(:flowchart, :draft, customer: customer, name: "Draft Flow") }
    let!(:other) { create(:flowchart, :launched_status, customer: create(:customer), name: "Other Tenant") }
    let!(:shared) { create(:flowchart, :shared_type, :launched_status, name: "Shared Flow") }

    before { sign_in platform_owner }

    it "lists launched own and shared flowcharts, never another tenant, and excludes self" do
      get options_path(source: "flowcharts"), params: { exclude_id: owned.id }, as: :json

      expect(response).to have_http_status(:ok)
      labels = response.parsed_body.fetch("options").map { |row| row["label"] }
      values = response.parsed_body.fetch("options").map { |row| row["value"] }
      expect(labels).to include("Shared Flow")
      expect(labels).not_to include("Alpha Flow", "Draft Flow", "Other Tenant")
      expect(values).not_to include(owned.id, other.id, draft.id)
    end

    it "filters launched flowcharts by name" do
      get options_path(source: "flowcharts"), params: { q: "shared" }, as: :json

      expect(response).to have_http_status(:ok)
      labels = response.parsed_body.fetch("options").map { |row| row["label"] }
      expect(labels).to include("Shared Flow")
      expect(labels).not_to include("Alpha Flow")
    end
  end
end
