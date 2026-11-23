# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::InvocationContext, type: :controller do
  controller(ApplicationController) do
    include FeatureModules::InvocationContext
    def index
      parts = [current_invocation&.dig(:module_key), invocation_input&.dig(:x)].compact
      render plain: parts.join(",")
    end

    def show
      invocation = require_module_invocation("demo") or return
      render plain: invocation[:module_key]
    end
  end

  let_it_be(:customer) { create(:customer) }

  before do
    routes.draw do
      get 'test', to: 'anonymous#index'
      get 'guarded', to: 'anonymous#show'
      get ':customer_id/handoff', to: 'feature_modules/handoffs#show', as: :feature_module_handoff
    end
  end

  after do
    Current.reset
  end

  it "returns blank when no invocation is present" do
    allow(FeatureModules::Invocation).to receive(:current).and_return(nil)
    get :index
    expect(response.body).to eq("")
  end

  it "returns invocation data when present" do
    invocation_data = { module_key: "demo", customer_id: customer.id, input: { x: 7 } }
    allow(FeatureModules::Invocation).to receive(:current).and_return(invocation_data)
    get :index
    expect(response.body).to eq("demo,7")
  end

  describe "#require_module_invocation" do
    def stub_invocation(data)
      allow(FeatureModules::Invocation).to receive(:current).and_return(data&.with_indifferent_access)
    end

    it "yields the live invocation of the module" do
      stub_invocation(module_key: "demo", customer_id: customer.id, awaiting_input: false)
      get :show
      expect(response.body).to eq("demo")
    end

    it "redirects home with the generic alert when there is no invocation for the module" do
      stub_invocation(module_key: "other", customer_id: customer.id)
      get :show
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("feature_modules.handoff.no_active_request"))
    end

    it "sends the end user back to the entry step while their input is still owed" do
      stub_invocation(module_key: "demo", customer_id: customer.id, awaiting_input: true)
      get :show
      expect(response).to redirect_to("/#{customer.id}/handoff")
    end
  end
end
