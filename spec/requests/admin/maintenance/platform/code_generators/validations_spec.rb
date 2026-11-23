# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::CodeGenerators::Validations", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@val.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@val.test", password: "password123") }

  let(:real_slug) { "element_types/start/start_generator" }

  let(:valid_body) do
    ::CodeGenerators::SourceDocument.new(Rails.root.join("app/services/code_generators/#{real_slug}.rb").read).body
  end

  def validation_path(slug = real_slug)
    admin_maintenance_platform_code_generator_validation_path(platform_customer.id, code_generator_slug: slug)
  end

  let(:guard_path) { validation_path }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      post admin_maintenance_platform_code_generator_validation_path(other_customer.id, code_generator_slug: real_slug),
           params: { methods_body: valid_body }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      post admin_maintenance_platform_code_generator_validation_path(other_customer.id, code_generator_slug: real_slug),
           params: { methods_body: valid_body }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path and branches
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "returns valid: true with empty errors for the generator's own body" do
      post validation_path, params: { methods_body: valid_body }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be true
      expect(body["errors"]).to eq([])
    end

    it "returns valid: false when the body drops the generator_metadata block" do
      post validation_path, params: { methods_body: "def generate_body = \"true\"" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be false
      expect(body["errors"]).to include(a_string_including("generator_metadata"))
    end

    it "returns valid: false with errors for invalid Ruby" do
      post validation_path, params: { methods_body: "def broken(" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to be false
      expect(body["errors"]).not_to be_empty
    end

    it "returns 404 for a slug that is not a registered generator" do
      post validation_path("element_types/process/utility/nope_generator"), params: { methods_body: valid_body }
      expect(response).to have_http_status(:not_found)
    end

    it "does not write the generator file" do
      path = Rails.root.join("app/services/code_generators/#{real_slug}.rb")
      expect { post validation_path, params: { methods_body: "def broken(" } }.not_to(change { path.read })
    end
  end
end
