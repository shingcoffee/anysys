# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Maintenance::EntityVersions", type: :request do
  include_context "as admin"

  let(:entity) { create(:entity, customer: customer) }

  def versions_path(cid = customer.id, ent = entity)
    "/#{cid}/admin/maintenance/entities/#{ent.id}/versions"
  end

  let(:guard_path) { versions_path }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  def version_path(ver, cid = customer.id, ent = entity)
    "/#{cid}/admin/maintenance/entities/#{ent.id}/versions/#{ver.id}"
  end

  def default_path(ver, cid = customer.id, ent = entity)
    "/#{cid}/admin/maintenance/entities/#{ent.id}/versions/#{ver.id}/default"
  end

  describe "GET show — auth guards" do
    let(:guard_path) { "#{version_path(entity.current_version)}.json" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { "#{version_path(entity.current_version)}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PUT default — auth guards" do
    let(:guard_path) { default_path(entity.current_version) }

    it_behaves_like "an admin-guarded request", :put
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { version_path(entity.current_version) }

    it_behaves_like "an admin-guarded request", :delete
  end

  # Force a genuinely new version row (content-addressed store dedups equal
  # payloads, so `commit_version!` alone would no-op). Mirrors the old
  # `create_version_snapshot!`, which unconditionally created a new version.
  def snap!(ent, description: nil, based_on_version_id: nil)
    payload = ent.definition_snapshot.merge("description" => SecureRandom.hex(8))
    content = ent.content_class.store!(customer_id: ent.customer_id, payload: payload)
    version = ent.commit_version!(description: description, based_on_version_id: based_on_version_id, content: content)
    ent.reload
    version
  end

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------
  describe "GET index" do
    it "returns 200 and a JSON array" do
      snap!(entity, description: "v1")
      get versions_path, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first).to include("version_number", "description", "created_at", "is_default")
    end

    it "lists versions newest-first" do
      snap!(entity, description: "first")
      snap!(entity, description: "second")
      get versions_path, as: :json
      numbers = JSON.parse(response.body).map { |v| v["version_number"] }
      expect(numbers).to eq(numbers.sort.reverse)
      expect(numbers.first).to eq(numbers.max)
    end

    it "marks only the default version as is_default" do
      v1 = snap!(entity, description: "v1")
      v2 = snap!(entity, description: "v2")
      entity.set_current_version!(v2)
      get versions_path, as: :json
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == v2.id }["is_default"]).to be(true)
      expect(body.find { |r| r["id"] == v1.id }["is_default"]).to be(false)
    end

    it "exposes based_on_version_number lineage" do
      # Entity creation itself auto-commits v1 (Versionable autocommits on
      # every save), so reset current_version_id first to give "base" no
      # lineage of its own.
      entity.update_column(:current_version_id, nil)
      base    = snap!(entity, description: "base")
      derived = snap!(entity, description: "derived", based_on_version_id: base.id)
      get versions_path, as: :json
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == derived.id }["based_on_version_number"]).to eq(base.version_number)
      expect(body.find { |r| r["id"] == base.id }["based_on_version_number"]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # GET show
  # ---------------------------------------------------------------------------
  describe "GET show" do
    let!(:version) { snap!(entity, description: "v-test") }

    it "returns version snapshot with configuration key" do
      get "#{version_path(version)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["version_number"]).to eq(version.version_number)
      expect(body["configuration"]).to be_present
    end

    it "404s for a version belonging to a different entity" do
      other = create(:entity, customer: customer)
      other_v = snap!(other, description: "other")
      get "#{version_path(other_v)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create (restore-as-new)
  # ---------------------------------------------------------------------------
  describe "POST create (restore-as-new)" do
    let!(:version) { snap!(entity, description: "v1") }

    it "creates one new (restored) snapshot and returns success" do
      # restore_as_new! creates a single new head referencing the chosen
      # version's existing content — there is no separate "preserve current
      # state" commit since every save already auto-commits its own version.
      expect {
        post versions_path, params: { version_id: version.id }, as: :json
      }.to change { entity.entity_versions.count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["version_number"]).to be_present
    end

    it "sets default_version_id to the restored snapshot" do
      post versions_path, params: { version_id: version.id }, as: :json
      entity.reload
      restored = entity.entity_versions.ordered.first
      expect(entity.current_version_id).to eq(restored.id)
      expect(restored.based_on_version_id).to eq(version.id)
    end

    it "returns 404 when the version_id belongs to another entity" do
      other = create(:entity, customer: customer)
      other_v = snap!(other, description: "other")
      post versions_path, params: { version_id: other_v.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # PUT default
  # ---------------------------------------------------------------------------
  describe "PUT default" do
    let!(:v1) { snap!(entity, description: "v1") }
    let!(:v2) { snap!(entity, description: "v2") }

    it "sets default_version_id to the chosen version" do
      put "#{default_path(v1)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("success" => true, "default_version_id" => v1.id)
      expect(entity.reload.current_version_id).to eq(v1.id)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE destroy" do
    let!(:v1) { snap!(entity, description: "v1") }
    let!(:v2) { snap!(entity, description: "v2") }

    it "deletes a non-default version" do
      expect {
        delete "#{version_path(v1)}.json"
      }.to change { entity.entity_versions.count }.by(-1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "id" => v1.id)
    end

    it "refuses (422) to delete the default version" do
      entity.set_current_version!(v2)
      expect {
        delete "#{version_path(v2)}.json"
      }.not_to change { entity.entity_versions.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("default_version_undeletable")
    end

    it "nullifies based_on pointers before deleting" do
      child = snap!(entity, description: "child", based_on_version_id: v1.id)
      delete "#{version_path(v1)}.json"
      expect(response).to have_http_status(:ok)
      expect(child.reload.based_on_version_id).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------
  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, :admin, customer: other_customer) }
    let(:other_entity)   { create(:entity, customer: other_customer) }
    let!(:other_version) { snap!(other_entity, description: "other") }

    context "when admin of customer A tries to access customer B's entity" do
      it "returns 404 on index" do
        get versions_path(customer.id, other_entity), as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on show" do
        get "#{version_path(other_version, customer.id, other_entity)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on create" do
        post versions_path(customer.id, other_entity), params: { version_id: other_version.id }, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on default" do
        put "#{default_path(other_version, customer.id, other_entity)}.json"
        expect(response).to have_http_status(:not_found)
      end

    it "returns 404 on destroy" do
      delete "#{version_path(other_version, customer.id, other_entity)}.json"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 on page create" do
      post "#{version_path(other_version, customer.id, other_entity)}/page.json"
      expect(response).to have_http_status(:not_found)
    end
    end

    context "when admin B tries to access customer A's entity" do
      before { sign_out admin; sign_in other_admin }

      it "returns 404 on index" do
        get "/#{other_customer.id}/admin/maintenance/entities/#{entity.id}/versions", as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization — nested POST page (not the versions index)
  # ---------------------------------------------------------------------------
  describe "authorization — POST page" do
    let(:guard_path) { "#{version_path(entity.current_version)}/page" }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "POST page" do
    def page_path(ver, cid = customer.id, ent = entity)
      "#{version_path(ver, cid, ent)}/page"
    end

    it "creates a page from the version and returns the detail URL" do
      entity.update!(display_label: "Student")
      version = entity.current_version
      post page_path(version), as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be(true)
      expect(body["url"]).to match(%r{/admin/maintenance/pages/\d+\z})
      expect(body["url"]).not_to include("/edit")
      expect(Page.find(body["page_id"]).entity_version_id).to eq(version.id)
    end

    it "includes generated_page_id only on the version that created the page" do
      original = entity.current_version
      other = snap!(entity, description: "other")
      post page_path(original), as: :json
      expect(response).to have_http_status(:ok)
      page_id = JSON.parse(response.body)["page_id"]
      get versions_path, as: :json
      rows = JSON.parse(response.body)
      created = rows.find { |row| row["id"] == original.id }
      leftover = rows.find { |row| row["id"] == other.id }
      expect(created["generated_page_id"]).to eq(page_id)
      expect(leftover["generated_page_id"]).to be_nil
    end

    it "clears generated_page_id after the generated page is deleted" do
      post page_path(entity.current_version), as: :json
      page = Page.find(JSON.parse(response.body)["page_id"])
      page.update_column(:status, Page.statuses[:inactive])
      get versions_path, as: :json
      expect(JSON.parse(response.body).map { |r| r["generated_page_id"] }).to all(be_nil)
    end

    it "creates again after the generated page is soft-deleted" do
      post page_path(entity.current_version), as: :json
      page = Page.find(JSON.parse(response.body)["page_id"])
      page.soft_delete
      post page_path(entity.current_version), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["page_id"]).to eq(page.id)
    end

    it "returns 404 for another tenant's entity" do
      other_customer = create(:customer)
      other_entity = create(:entity, customer: other_customer)
      post page_path(other_entity.current_version, customer.id, other_entity), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "shared entity with no tenant override line" do
    let!(:shared_entity) { create(:entity, :shared) }

    def shared_versions_path
      "/#{customer.id}/admin/maintenance/entities/#{shared_entity.id}/versions"
    end

    def shared_version_path(ver)
      "#{shared_versions_path}/#{ver.id}"
    end

    it "lists the global versions as read-only so Create page has an id" do
      version = shared_entity.current_version
      get shared_versions_path, as: :json
      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body)
      expect(rows.map { |row| row["id"] }).to include(version.id)
      expect(rows.find { |row| row["id"] == version.id }["writable"]).to be(false)
    end

    it "creates a customer-owned page from the global version" do
      version = shared_entity.current_version
      post "#{shared_version_path(version)}/page", as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be(true)
      page = Page.find(body["page_id"])
      expect(page.customer_id).to eq(customer.id)
      expect(page.entity_version_id).to eq(version.id)
    end

    it "does not let the tenant set-default a global version" do
      version = shared_entity.current_version
      put "#{shared_version_path(version)}/default.json"
      expect(response).to have_http_status(:not_found)
      expect(shared_entity.reload.current_version_id).to eq(version.id)
    end

    it "does not let the tenant delete a global version" do
      version = shared_entity.current_version
      delete "#{shared_version_path(version)}.json"
      expect(response).to have_http_status(:not_found)
      expect(shared_entity.entity_versions.where(customer_id: nil)).to exist
    end
  end
end
