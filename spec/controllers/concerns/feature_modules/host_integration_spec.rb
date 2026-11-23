# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::HostIntegration, type: :controller do
  controller(ApplicationController) do
    def index
      render plain: "ok"
    end
  end

  let_it_be(:customer) { create(:customer) }

  before do
    routes.draw { get "index" => "anonymous#index" }
  end

  def stub_customer_id(id)
    allow(controller).to receive(:current_customer_id).and_return(id)
  end

  def disable_authentication_for(customer)
    auth_module = FeatureModules::Module.find_by!(key: "authentication")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).destroy_all
  end

  describe "#run_feature_module_before_request" do
    it "invokes before_request on every enabled module's registration" do
      stub_customer_id(customer.id)

      expect(FeatureModules::Authentication::Registration).to receive(:before_request).with(controller)

      get :index
    end

    it "does not invoke before_request for modules not enabled for the customer" do
      disable_authentication_for(customer)
      stub_customer_id(customer.id)

      expect(FeatureModules::Authentication::Registration).not_to receive(:before_request)

      get :index
    end

    it "is a no-op when current_customer_id is blank" do
      stub_customer_id(nil)
      expect(FeatureModules::Authentication::Registration).not_to receive(:before_request)

      get :index
    end

    it "stops the chain if before_request performed a redirect" do
      stub_customer_id(customer.id)
      allow(FeatureModules::Authentication::Registration).to receive(:before_request) do |c|
        c.redirect_to("/somewhere")
      end

      get :index
      expect(response).to redirect_to("/somewhere")
    end
  end

  describe "#feature_module_enabled? helper" do
    it "returns true for modules active for the current customer" do
      stub_customer_id(customer.id)
      expect(controller.feature_module_enabled?("authentication")).to be true
    end

    it "returns false when customer has no row for the module" do
      disable_authentication_for(customer)
      stub_customer_id(customer.id)
      expect(controller.feature_module_enabled?("authentication")).to be false
    end

    it "returns false when current_customer_id is blank" do
      stub_customer_id(nil)
      expect(controller.feature_module_enabled?("authentication")).to be false
    end
  end
end
