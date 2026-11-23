# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Attachments", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let(:other_customer) { create(:customer) }

  let(:blob_params) do
    {
      blob: {
        filename:     "test.png",
        byte_size:    4,
        checksum:     Digest::MD5.base64digest("data"),
        content_type: "image/png"
      }
    }
  end

  # ---------------------------------------------------------------------------
  # POST create — tenant-scoped direct-upload handshake
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/attachments" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/attachments" }

    it_behaves_like "an admin-guarded request", :post
    it "returns 200 JSON with signed_id and direct_upload url/headers" do
      post "/#{customer.id}/admin/modules/emails/attachments", params: blob_params, as: :json
      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["signed_id"]).to be_present
      expect(json.dig("direct_upload", "url")).to be_present
      expect(json.dig("direct_upload", "headers")).to be_a(Hash)
    end

    it "stamps the created blob with the current customer_id" do
      expect {
        post "/#{customer.id}/admin/modules/emails/attachments", params: blob_params, as: :json
      }.to change(ActiveStorage::Blob, :count).by(1)

      blob = ActiveStorage::Blob.order(:created_at).last
      expect(blob.customer_id).to eq(customer.id)
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post "/#{customer.id}/admin/modules/emails/attachments", params: blob_params, as: :json
      }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show — tenant-scoped blob redirect
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/attachments/:id" do
    def build_blob_for(cid)
      Current.set(customer: Customer.find(cid)) do
        blob = ActiveStorage::Blob.new(
          key:          ActiveStorage::Blob.generate_unique_secure_token,
          filename:     "img.png",
          content_type: "image/png",
          byte_size:    4,
          checksum:     Digest::MD5.base64digest("data"),
          service_name: ActiveStorage::Blob.service.name.to_s
        )
        blob.customer_id = cid
        blob.save!
        blob
      end
    end

    it "redirects to blob URL for a blob owned by the current customer" do
      blob = build_blob_for(customer.id)
      get "/#{customer.id}/admin/modules/emails/attachments/#{blob.id}"
      # Rails redirect to blob service URL or a 302 is acceptable; not a 404/500
      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    end

    it "returns 404 for a blob owned by a different customer" do
      blob = build_blob_for(other_customer.id)
      get "/#{customer.id}/admin/modules/emails/attachments/#{blob.id}"
      expect(response).to have_http_status(:not_found)
    end

    describe "auth guards" do
      let(:blob) { build_blob_for(customer.id) }
      let(:guard_path) { "/#{customer.id}/admin/modules/emails/attachments/#{blob.id}" }

      it_behaves_like "an admin-guarded GET"
    end
  end
end
