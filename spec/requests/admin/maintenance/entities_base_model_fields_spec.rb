# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity base_model_fields", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/base_model_fields" }

  it_behaves_like "an admin-guarded GET"

  # Enable the Payments module for `for_customer` and mark `model_name` extendable.
  def enable_extendable_model(model_name, for_customer: customer)
    mod = enable_module!("payment", for_customer, name: "Payments")
    mod.set_extendable_model!(model_name, true)
  end

  def get_base_model_fields(model)
    get "/#{customer.id}/admin/maintenance/entities/base_model_fields",
        params: { model: model },
        headers: { "Accept" => "application/json" }
  end

  describe "GET base_model_fields" do
    it "returns only attributes the owner has allowed for an extendable model" do
      enable_extendable_model("Payments::Order")

      get_base_model_fields("Payments::Order")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["fields"]).to eq([])

      column = Payments::Order.column_names.first
      FeatureModules::Module.find_by!(key: "payment").set_extendable_attribute!(
        "Payments::Order", column, true, candidates: Payments::Order.column_names
      )

      get_base_model_fields("Payments::Order")
      expect(JSON.parse(response.body)["fields"]).to eq([column])
    end

    it "refuses a non-extendable model" do
      get_base_model_fields("Payments::Order")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["fields"]).to eq([])
    end

    it "refuses an arbitrary class name" do
      get_base_model_fields("Evil::Klass")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["fields"]).to eq([])
    end

    it "refuses a non-ApplicationRecord model" do
      enable_extendable_model("String")

      get_base_model_fields("String")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["fields"]).to eq([])
    end
  end

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }

    it "does not leak models from another customer's enabled modules" do
      enable_extendable_model("Payments::Order", for_customer: other_customer)

      # admin from 'customer' tries to access a model only extendable for other_customer
      get_base_model_fields("Payments::Order")

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["fields"]).to eq([])
    end
  end
end
