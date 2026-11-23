# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Flowcharts::ImplicitKeys", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }

  let(:config_path) do
    Rails.root.join("config", "flowchart_validation.yml")
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/flowcharts/validation/implicit_keys" }

    it_behaves_like "a platform-owner-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "GET show — admin fetches implicit keys" do
    before { sign_in platform_owner }

    it "returns 200 with an implicit_keys array" do
      get "/#{customer.id}/admin/maintenance/flowcharts/validation/implicit_keys", as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key("implicit_keys")
      expect(body["implicit_keys"]).to be_an(Array)
    end

    it "returns the keys declared in flowchart_validation.yml" do
      config = YAML.safe_load_file(config_path)
      expected = config["implicit_context_keys"] || []

      get "/#{customer.id}/admin/maintenance/flowcharts/validation/implicit_keys", as: :json

      expect(response.parsed_body["implicit_keys"]).to eq(expected)
    end
  end
end
