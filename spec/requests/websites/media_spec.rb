# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Websites media", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let(:admin) { create(:user, :admin, customer: customer, password: "password123") }
  let(:png) do
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def png_upload
    file = Tempfile.new(["photo", ".png"])
    file.binmode
    file.write(png)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  describe "POST /:cid/admin/modules/website/media" do
    let(:guard_path) { "/#{customer.id}/admin/modules/website/media" }

    before do
      Current.customer = customer
      sign_in admin
    end

    it_behaves_like "an admin-guarded request", :post

    it "returns a public media URL for an admin upload" do
      post guard_path, params: { file: png_upload }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["url"]).to match(%r{\A/#{customer.id}/site/media/})

      get response.parsed_body.fetch("url")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "returns 422 when the file is missing" do
      post guard_path
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("website.errors.image_missing"))
    end

    it "returns 404 when the Website module is off" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: FeatureModules::Module.find_by!(key: "website")
      ).update!(status: :suspended)

      post guard_path, params: { file: png_upload }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /:cid/site/media/:signed_id" do
    def blob_for(cid, bytes: png, content_type: "image/png", metadata: { website_media: true })
      Current.set(customer: Customer.find(cid)) do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(bytes),
          filename: "photo.png",
          content_type: content_type,
          identify: false,
          metadata: metadata
        )
        blob.update!(customer_id: cid) if blob.customer_id.blank?
        blob
      end
    end

    it "serves classified raster bytes inline with a verified content type and nosniff" do
      blob = blob_for(customer.id)
      get "/#{customer.id}/site/media/#{blob.signed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.body).to eq(png)
      expect(response.headers["Content-Disposition"]).to start_with("inline;")
      expect(response.headers["Content-Disposition"]).to include("photo.png")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "supports HEAD without a response body" do
      blob = blob_for(customer.id)
      head "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/png")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.body).to be_empty
    end

    it "supports draft image previews without publishing the site's pages" do
      site = create(:website, customer: customer, published: false)
      create(:website_page, :home, :published, website: site)
      blob = blob_for(customer.id)

      get "/#{customer.id}/site"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty

      get "/#{customer.id}/site/media/#{blob.signed_id}"
      expect(response).to have_http_status(:ok)
    end

    [{}, { website_media: false }, { website_media: "true" }].each do |metadata|
      it "404s for a generic signed tenant blob with metadata #{metadata.inspect}" do
        blob = blob_for(customer.id, metadata: metadata)

        get "/#{customer.id}/site/media/#{blob.signed_id}"

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
      end
    end

    %w[text/html image/svg+xml application/pdf application/octet-stream].each do |content_type|
      it "404s for classified media declared as #{content_type}" do
        blob = blob_for(customer.id, content_type: content_type)

        get "/#{customer.id}/site/media/#{blob.signed_id}"

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
      end
    end

    ["<html><script>alert(1)</script></html>", '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "%PDF-1.7\n"].each do |bytes|
      it "404s for #{bytes.split(/[ >]/).first} bytes masquerading as image/png" do
        blob = blob_for(customer.id, bytes: bytes)

        get "/#{customer.id}/site/media/#{blob.signed_id}"

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
        expect(response.headers["Content-Disposition"]).to be_nil
      end
    end

    it "404s when an allowed declared MIME does not match the actual raster MIME" do
      blob = blob_for(customer.id, content_type: "image/jpeg")

      get "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s for an empty classified blob" do
      blob = blob_for(customer.id, bytes: "")

      get "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s for classified media exceeding the public size limit" do
      blob = blob_for(customer.id, bytes: png + "x" * Websites::MediaPolicy::MAX_BYTES)

      get "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s when stored bytes no longer match the recorded byte size" do
      blob = blob_for(customer.id)
      blob.update!(byte_size: blob.byte_size - 1)

      get "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s when the blob belongs to another customer" do
      blob = blob_for(other_customer.id)
      get "/#{customer.id}/site/media/#{blob.signed_id}"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for an invalid signature" do
      get "/#{customer.id}/site/media/not-a-signed-id"
      expect(response).to have_http_status(:not_found)
    end

    it "404s for an expired signed id" do
      blob = blob_for(customer.id)
      signed_id = blob.signed_id(expires_in: 1.minute)

      travel 2.minutes do
        get "/#{customer.id}/site/media/#{signed_id}"

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
      end
    end

    it "404s for a stale signed id after the blob is purged" do
      blob = blob_for(customer.id)
      signed_id = blob.signed_id
      blob.purge

      get "/#{customer.id}/site/media/#{signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s when the storage object is missing but the blob row still exists" do
      blob = blob_for(customer.id)
      blob.service.delete(blob.key)

      get "/#{customer.id}/site/media/#{blob.signed_id}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "404s when the Website module is off" do
      blob = blob_for(customer.id)
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: FeatureModules::Module.find_by!(key: "website")
      ).update!(status: :suspended)

      get "/#{customer.id}/site/media/#{blob.signed_id}"
      expect(response).to have_http_status(:not_found)
    end
  end
end
