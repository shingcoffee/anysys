# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageVersions", type: :request do
  include_context "as admin"

  let(:other_customer) { create(:customer) }
  let(:other_admin)    { create(:user, :admin, customer: other_customer) }
  let(:page)           { create(:page, customer: customer) }
  let!(:version)       { snap!(page, description: "Initial snapshot") }

  # Force a genuinely new version row (content-addressed store dedups equal
  # payloads, so `commit_version!` alone would no-op). Mirrors the old
  # `create_version_snapshot!`, which unconditionally created a new version.
  def snap!(pg, description: nil, based_on_version_id: nil)
    content = pg.content_class.store!(customer_id: pg.customer_id, payload: { "_marker" => SecureRandom.hex(8) })
    pg.commit_version!(description: description, based_on_version_id: based_on_version_id, content: content)
  end

  def versions_path(cid = customer.id, pg = page)
    "/#{cid}/admin/maintenance/pages/#{pg.id}/versions"
  end

  let(:guard_path) { versions_path }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  def version_path(ver, cid = customer.id, pg = page)
    "/#{cid}/admin/maintenance/pages/#{pg.id}/versions/#{ver.id}"
  end

  def default_path(ver, cid = customer.id, pg = page)
    "/#{cid}/admin/maintenance/pages/#{pg.id}/versions/#{ver.id}/default"
  end

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------
  describe "GET index" do
    it "returns 200 and a JSON array" do
      get versions_path, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first).to include("version_number", "description", "created_at", "is_default")
    end

    it "lists versions newest-first" do
      v2 = snap!(page, description: "second")
      get versions_path, as: :json
      numbers = JSON.parse(response.body).map { |v| v["version_number"] }
      expect(numbers.first).to eq(v2.version_number)
    end

    it "marks only the default version as is_default" do
      v2 = snap!(page, description: "v2")
      page.set_current_version!(v2)
      get versions_path, as: :json
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == v2.id }["is_default"]).to be(true)
      expect(body.find { |r| r["id"] == version.id }["is_default"]).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show
  # ---------------------------------------------------------------------------
  describe "GET show" do
    it "returns 200 and the version snapshot as JSON" do
      get "#{version_path(version)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["version_number"]).to eq(version.version_number)
      expect(body["configuration"]).to be_present
    end

    it "404s for a version owned by a different page" do
      other = create(:page, customer: customer)
      other_v = snap!(other, description: "other")
      get "#{version_path(other_v)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create (restore-as-new)
  # ---------------------------------------------------------------------------
  describe "POST create (restore-as-new)" do
    it "creates one new (restored) snapshot and returns success" do
      # restore_as_new! creates a single new head referencing the chosen
      # version's existing content — no separate "preserve current state"
      # commit, since every save already auto-commits its own version.
      expect {
        post versions_path, params: { version_id: version.id }, as: :json
      }.to change { page.page_versions.count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["version_number"]).to be_present
    end

    it "sets default_version_id to the restored snapshot with based_on lineage" do
      post versions_path, params: { version_id: version.id }, as: :json
      page.reload
      restored = page.page_versions.ordered.first
      expect(page.current_version_id).to eq(restored.id)
      expect(restored.based_on_version_id).to eq(version.id)
    end
  end

  # ---------------------------------------------------------------------------
  # PUT default
  # ---------------------------------------------------------------------------
  describe "PUT default" do
    let!(:v2) { snap!(page, description: "v2") }

    it "repoints default_version_id and applies the snapshot" do
      target_payload = version.payload
      page.configuration = page.configuration.sub("page_1", "page_2")
      page.save!

      put "#{default_path(version)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("success" => true, "default_version_id" => version.id)
      expect(page.reload.configuration).to eq(target_payload)
      expect(page.current_version_id).to eq(version.id)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE destroy" do
    let!(:v2) { snap!(page, description: "v2") }

    it "deletes a non-default version" do
      expect {
        delete "#{version_path(version)}.json"
      }.to change { page.page_versions.count }.by(-1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "id" => version.id)
    end

    it "refuses (422) to delete the default version" do
      page.set_current_version!(v2)
      expect {
        delete "#{version_path(v2)}.json"
      }.not_to change { page.page_versions.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("default_version_undeletable")
    end

    it "nullifies based_on pointers before deleting" do
      child = snap!(page, description: "child", based_on_version_id: version.id)
      delete "#{version_path(version)}.json"
      expect(response).to have_http_status(:ok)
      expect(child.reload.based_on_version_id).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-tenant isolation
  # ---------------------------------------------------------------------------
  describe "multi-tenant isolation" do
    let(:other_page)    { create(:page, customer: other_customer) }
    let!(:other_version) { snap!(other_page, description: "Other tenant snapshot") }

    context "when admin of customer A tries to access customer B's page" do
      it "returns 404 on index" do
        get versions_path(customer.id, other_page), as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on show" do
        get "#{version_path(other_version, customer.id, other_page)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on create" do
        post versions_path(customer.id, other_page), params: { version_id: other_version.id }, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on default" do
        put "#{default_path(other_version, customer.id, other_page)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on destroy" do
        delete "#{version_path(other_version, customer.id, other_page)}.json"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when using customer A's page but supplying a version from customer B" do
      it "returns 404 on show" do
        get "#{version_path(other_version, customer.id, page)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on destroy" do
        delete "#{version_path(other_version, customer.id, page)}.json"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization — show (not covered by the index shared example)
  # ---------------------------------------------------------------------------
  describe "authorization — show" do
    let(:guard_path) { "#{version_path(version)}.json" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { "#{version_path(version)}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PUT default — auth guards" do
    let(:guard_path) { default_path(version) }

    it_behaves_like "an admin-guarded request", :put
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { version_path(version) }

    it_behaves_like "an admin-guarded request", :delete
  end
end
