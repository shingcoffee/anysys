# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::TemplateVersions", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }

  let(:other_customer) { create(:customer) }
  let(:template)       { create(:email_template, customer: customer, subject: "Original subject") }
  let!(:version)       { template.template_versions.order(:version_number).first }

  # Force a genuinely new version row (content-addressed store dedups equal
  # payloads, so `commit_version!` alone would no-op).
  def snap!(tmpl, description: nil, based_on_version_id: nil)
    content = tmpl.content_class.store!(customer_id: tmpl.customer_id, payload: { "subject" => SecureRandom.hex(8) })
    tmpl.commit_version!(description: description, based_on_version_id: based_on_version_id, content: content)
  end

  def versions_path(cid = customer.id, tmpl = template)
    "/#{cid}/admin/modules/emails/templates/#{tmpl.id}/versions"
  end

  let(:guard_path) { versions_path }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  describe "GET show — auth guards" do
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

  def version_path(ver, cid = customer.id, tmpl = template)
    "/#{cid}/admin/modules/emails/templates/#{tmpl.id}/versions/#{ver.id}"
  end

  def default_path(ver, cid = customer.id, tmpl = template)
    "/#{cid}/admin/modules/emails/templates/#{tmpl.id}/versions/#{ver.id}/default"
  end

  context "when the Email module is disabled" do
    let!(:v2) { snap!(template, description: "second") }

    before do
      FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: email_module).update!(status: :suspended)
    end

    it "blocks restore-as-new without writing a version" do
      expect { post versions_path, params: { version_id: version.id }, as: :json }
        .not_to change { template.template_versions.count }
      expect(response).to have_http_status(:not_found)
    end

    it "blocks changing the current version" do
      head = template.reload.current_version_id
      put default_path(version), as: :json

      expect(response).to have_http_status(:not_found)
      expect(template.reload.current_version_id).to eq(head)
    end

    it "blocks deleting a non-current version" do
      expect { delete version_path(version), as: :json }.not_to change { template.template_versions.count }
      expect(response).to have_http_status(:not_found)
    end
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
      v2 = snap!(template, description: "second")
      get versions_path, as: :json
      numbers = JSON.parse(response.body).map { |v| v["version_number"] }
      expect(numbers.first).to eq(v2.version_number)
    end

    it "marks only the default version as is_default" do
      v2 = snap!(template, description: "v2")
      template.set_current_version!(v2)
      get versions_path, as: :json
      body = JSON.parse(response.body)
      expect(body.find { |r| r["id"] == v2.id }["is_default"]).to be(true)
      expect(body.find { |r| r["id"] == version.id }["is_default"]).to be(false)
    end

    it "does not expose another customer's template versions" do
      other_template = create(:email_template, customer: other_customer)
      get versions_path(customer.id, other_template), as: :json
      expect(response).to have_http_status(:not_found)
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

    it "404s for a version owned by a different template" do
      other = create(:email_template, customer: customer)
      other_v = snap!(other, description: "other")
      get "#{version_path(other_v)}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create (restore-as-new)
  # ---------------------------------------------------------------------------
  describe "POST create (restore-as-new)" do
    it "restores the template's subject and returns success" do
      template.update!(subject: "Changed subject")
      v1 = template.template_versions.order(:version_number).first

      expect {
        post versions_path, params: { version_id: v1.id }, as: :json
      }.to change { template.template_versions.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["version_number"]).to be_present
      expect(template.reload.subject).to eq("Original subject")
    end

    it "sets default_version_id to the restored snapshot with based_on lineage" do
      post versions_path, params: { version_id: version.id }, as: :json
      template.reload
      restored = template.template_versions.ordered.first
      expect(template.current_version_id).to eq(restored.id)
      expect(restored.based_on_version_id).to eq(version.id)
    end
  end

  # ---------------------------------------------------------------------------
  # PUT default
  # ---------------------------------------------------------------------------
  describe "PUT default" do
    let!(:v2) { snap!(template, description: "v2") }

    it "repoints default_version_id and applies the snapshot" do
      put "#{default_path(version)}.json"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("success" => true, "default_version_id" => version.id)
      expect(template.reload.current_version_id).to eq(version.id)
      expect(template.subject).to eq("Original subject")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE destroy" do
    let!(:v2) { snap!(template, description: "v2") }

    it "deletes a non-default version" do
      expect {
        delete "#{version_path(version)}.json"
      }.to change { template.template_versions.count }.by(-1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("success" => true, "id" => version.id)
    end

    it "refuses (422) to delete the default version" do
      template.set_current_version!(v2)
      expect {
        delete "#{version_path(v2)}.json"
      }.not_to change { template.template_versions.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("default_version_undeletable")
    end

    it "nullifies based_on pointers before deleting" do
      child = snap!(template, description: "child", based_on_version_id: version.id)
      delete "#{version_path(version)}.json"
      expect(response).to have_http_status(:ok)
      expect(child.reload.based_on_version_id).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # GET edit — redirect into the template editor with ?version=
  # ---------------------------------------------------------------------------
  describe "GET edit" do
    it "redirects to the template edit page with the version id" do
      get "#{version_path(version)}/edit"
      expect(response).to redirect_to(
        "/#{customer.id}/admin/modules/emails/templates/#{template.id}/edit?version=#{version.id}"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-tenant isolation
  # ---------------------------------------------------------------------------
  describe "multi-tenant isolation" do
    let(:other_template)  { create(:email_template, customer: other_customer) }
    let!(:other_version)  { other_template.template_versions.order(:version_number).first }

    context "when admin of customer A tries to access customer B's template" do
      it "returns 404 on index" do
        get versions_path(customer.id, other_template), as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on show" do
        get "#{version_path(other_version, customer.id, other_template)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on create" do
        post versions_path(customer.id, other_template), params: { version_id: other_version.id }, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on default" do
        put "#{default_path(other_version, customer.id, other_template)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on destroy" do
        delete "#{version_path(other_version, customer.id, other_template)}.json"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when using customer A's template but supplying a version from customer B" do
      it "returns 404 on show" do
        get "#{version_path(other_version, customer.id, template)}.json"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on destroy" do
        delete "#{version_path(other_version, customer.id, template)}.json"
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
