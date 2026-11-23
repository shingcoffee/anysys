# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Maintenance::FlowchartVersions", type: :request do
  include_context "as platform owner on tenant"

  let(:entity)    { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, customer: customer) }

  # Force a genuinely new version row (content-addressed store dedups equal
  # payloads, so `commit_version!` alone would no-op). Mirrors the old
  # `create_version_snapshot!`, which unconditionally created a new version.
  def snap!(fc, description: nil, based_on_version_id: nil)
    content = fc.content_class.store!(customer_id: fc.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
    fc.commit_version!(description: description, based_on_version_id: based_on_version_id, content: content)
  end

  def versions_path(fc = flowchart, cid = customer.id)
    "/#{cid}/admin/maintenance/flowcharts/#{fc.id}/versions"
  end

  let(:guard_path) { versions_path }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :post

  def version_path(ver, fc = flowchart, cid = customer.id)
    "#{versions_path(fc, cid)}/#{ver.id}"
  end

  def default_path(ver, fc = flowchart, cid = customer.id)
    "#{version_path(ver, fc, cid)}/default"
  end

  def edit_version_path(ver, fc = flowchart, cid = customer.id)
    "#{version_path(ver, fc, cid)}/edit"
  end

  describe "GET show — auth guards" do
    let(:guard_path) { "#{version_path(flowchart.flowchart_versions.ordered.first)}.json" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_version_path(flowchart.flowchart_versions.ordered.first) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PUT default — auth guards" do
    let(:guard_path) { default_path(flowchart.flowchart_versions.ordered.first) }

    it_behaves_like "a platform-owner-guarded request", :put
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { version_path(flowchart.flowchart_versions.ordered.first) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  # A flowchart owned by a different, freshly-created customer.
  def foreign_flowchart
    other = create(:customer)
    create(:flowchart, :simple, :draft, customer: other)
  end

  before do
    snap!(flowchart, description: "Manual save")
  end

  describe "GET show" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }
    let!(:version) { snap!(flowchart, description: "v-test"); flowchart.flowchart_versions.ordered.first }

    it "returns the version configuration for the tenant" do
      get "#{version_path(version)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["version_number"]).to eq(version.version_number)
      expect(body["configuration"]).to be_present
    end

    it "404s for a version that belongs to another flowchart" do
      other = create(:flowchart, :simple, :draft, customer: customer)
      snap!(other)
      foreign = other.flowchart_versions.ordered.first
      get "#{version_path(foreign)}.json"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a version owned by another customer's flowchart" do
      other_flowchart = foreign_flowchart
      snap!(other_flowchart)
      foreign = other_flowchart.flowchart_versions.ordered.first
      get "#{version_path(foreign, other_flowchart)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create (restore as new version)" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "preserves current state and adds an explicit restored version" do
      snap!(flowchart, description: "v1")
      target = flowchart.flowchart_versions.ordered.first
      target_payload = target.payload

      # restore_as_new! creates a single new head referencing the chosen
      # version's existing content — no separate "preserve current state"
      # commit, since every save already auto-commits its own version.
      expect {
        post "#{versions_path}.json", params: { version_id: target.id }, as: :json
      }.to change { flowchart.flowchart_versions.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["version_number"]).to be_present
      expect(flowchart.reload.configuration).to eq(target_payload)
      expect(flowchart.flowchart_versions.ordered.first.description).to eq("Restored from v#{target.version_number}")
    end

    it "returns the new line head as version_id so the editor's next save is not a conflict" do
      snap!(flowchart, description: "v1")
      target = flowchart.flowchart_versions.ordered.first

      post "#{versions_path}.json", params: { version_id: target.id }, as: :json

      expect(JSON.parse(response.body)["version_id"]).to eq(flowchart.reload.current_line_head_version_id)
      expect(JSON.parse(response.body)["version_id"]).not_to eq(target.id)
    end

    it "restores into a draft version while launched, leaving the launched version live" do
      live = create(:flowchart, :simple, :launched_status, customer: customer)
      launched_id = live.launched_version_id
      target = snap!(live, description: "older draft")
      snap!(live, description: "newer draft")

      expect {
        post "#{versions_path(live)}.json", params: { version_id: target.id }, as: :json
      }.to change { live.flowchart_versions.count }.by(1)

      expect(response).to have_http_status(:ok)
      live.reload
      expect(live.launched_version_id).to eq(launched_id)
      expect(live.current_version.content_id).to eq(target.content_id)
      expect(live).to be_pending_draft
      expect(JSON.parse(response.body)["head_revision"]).to eq(live.current_line_head_revision)
    end

    it "404s when creating a version on another customer's flowchart" do
      other_flowchart = foreign_flowchart
      snap!(other_flowchart)
      target = other_flowchart.flowchart_versions.ordered.first
      post "#{versions_path(other_flowchart)}.json", params: { version_id: target.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT default (set as default = publish/restore)" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "syncs live config to the version and repoints current_version_id" do
      snap!(flowchart, description: "v1")
      target = flowchart.flowchart_versions.ordered.first
      target_payload = target.payload
      snap!(flowchart, description: "later")

      put "#{default_path(target)}.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "default_version_id" => target.id)
      expect(flowchart.reload.configuration).to eq(target_payload)
      expect(flowchart.current_version_id).to eq(target.id)
    end

    it "moves the head while launched without touching the launched version" do
      live = create(:flowchart, :simple, :launched_status, customer: customer)
      launched_id = live.launched_version_id
      target = snap!(live, description: "older draft")
      snap!(live, description: "newer draft")

      put "#{default_path(target, live)}.json"

      expect(response).to have_http_status(:ok)
      live.reload
      expect(live.current_version_id).to eq(target.id)
      expect(live.launched_version_id).to eq(launched_id)
    end

    it "404s for a global version of a shared flowchart on the tenant path" do
      shared = create(:flowchart, :simple, :shared_type, :draft, customer: nil)
      v = snap!(shared, description: "v1")
      put "#{default_path(v, shared)}.json"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a version on another customer's flowchart" do
      other_flowchart = foreign_flowchart
      snap!(other_flowchart)
      target = other_flowchart.flowchart_versions.ordered.first
      put "#{default_path(target, other_flowchart)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE destroy" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "refuses to delete the launched version while a draft sits above it" do
      live = create(:flowchart, :simple, :launched_status, customer: customer)
      launched = live.launched_version
      snap!(live, description: "draft")

      expect {
        delete "#{version_path(launched, live)}.json"
      }.not_to change { live.flowchart_versions.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include(
        "error" => "launched_version_undeletable",
        "message" => I18n.t("maint_core.errors.versions.launched_undeletable")
      )
    end

    it "deletes a non-default version for the tenant" do
      # Create two versions so v1 is not the default (v2 becomes default after second snapshot)
      target = snap!(flowchart, description: "v1")
      snap!(flowchart, description: "v2") # becomes default
      expect {
        delete "#{version_path(target)}.json"
      }.to change { flowchart.flowchart_versions.count }.by(-1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "id" => target.id)
    end

    it "nullifies based_on pointers from other versions before deleting" do
      # Create three versions: base, child (based on base), and a third to hold the default
      base  = snap!(flowchart, description: "base")
      child = snap!(flowchart, description: "child", based_on_version_id: base.id)
      # child is already the current version (commit_version! advances the head
      # on every real commit), so base is non-default and can be deleted
      delete "#{version_path(base)}.json"
      expect(response).to have_http_status(:ok)
      expect(child.reload.based_on_version_id).to be_nil
    end

    it "refuses (422) to delete the default version" do
      v = snap!(flowchart, description: "v1")
      expect {
        delete "#{version_path(v)}.json"
      }.not_to change { flowchart.flowchart_versions.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("default_version_undeletable")
    end

    it "404s for a global version of a shared flowchart on the tenant path" do
      shared = create(:flowchart, :simple, :shared_type, :draft, customer: nil)
      v = snap!(shared, description: "v1")
      delete "#{version_path(v, shared)}.json"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a version on another customer's flowchart" do
      other_flowchart = foreign_flowchart
      v = snap!(other_flowchart)
      delete "#{version_path(v, other_flowchart)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET edit (open version in editor)" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "renders the editor with the version's configuration and based-on attribute" do
      version = snap!(flowchart, description: "v1")
      get edit_version_path(version)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-flowchart-canvas-based-on-version-id-value=\"#{version.id}\"")
      expect(response.body).to include("Editing based on v#{version.version_number}")
    end

    it "404s for a version on another customer's flowchart" do
      other_flowchart = foreign_flowchart
      v = snap!(other_flowchart)
      get edit_version_path(v, other_flowchart)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for another tenant's override version of a shared flowchart" do
      shared = create(:flowchart, :simple, :shared_type, :draft, customer: nil)
      other = create(:customer)
      foreign_version = nil
      Current.with_customer(other) do
        fc = Flowchart.find(shared.id)
        foreign_version = snap!(fc, description: "other-tenant")
      end
      get edit_version_path(foreign_version, shared)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET index" do
    it "lists the flowchart's versions as JSON for the tenant" do
      flowchart = create(:flowchart, :simple, :draft, customer: customer)
      snap!(flowchart, description: "v-index")
      # Pass the local flowchart explicitly — the helper's default binds to the
      # `let(:flowchart)`, not this shadowing local.
      get "#{versions_path(flowchart)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first).to include("version_number", "description", "created_at")
    end
  end

  describe "GET index based-on lineage" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "exposes the base version number for versions derived from another version" do
      # The outer before-block creates a version on this flowchart (with
      # current_version_id set). Create base fresh with no lineage by
      # resetting current_version_id first.
      flowchart.update_column(:current_version_id, nil)
      base    = snap!(flowchart, description: "base")
      derived = snap!(flowchart, description: "derived", based_on_version_id: base.id)
      get "#{versions_path}.json"
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == derived.id }["based_on_version_number"]).to eq(base.version_number)
      # base was created with no current_version_id set, so it has no lineage
      expect(body.find { |r| r["id"] == base.id }["based_on_version_number"]).to be_nil
    end
  end

  describe "GET index is_default flag" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "marks only the default version row" do
      v1 = snap!(flowchart, description: "v1")
      v2 = snap!(flowchart, description: "v2")
      flowchart.set_current_version!(v2)
      get "#{versions_path}.json"
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == v2.id }["is_default"]).to be(true)
      expect(body.find { |r| r["id"] == v1.id }["is_default"]).to be(false)
    end
  end

  describe "POST create promotes restored snapshot to default with based-on" do
    let(:flowchart) { create(:flowchart, :simple, :draft, customer: customer) }

    it "sets default_version_id to the restored snapshot and tags based_on" do
      snap!(flowchart, description: "v1")
      target = flowchart.flowchart_versions.ordered.first
      post "#{versions_path}.json", params: { version_id: target.id }, as: :json
      flowchart.reload
      restored = flowchart.flowchart_versions.ordered.first
      expect(flowchart.current_version_id).to eq(restored.id)
      expect(restored.based_on_version_id).to eq(target.id)
    end
  end
end
