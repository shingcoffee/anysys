# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index = render plain: "ok"
  end

  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  it "chooses dashboard layout for customer-scoped controllers" do
    expect(controller.send(:dashboard_layout)).to eq("dashboard")
  end

  it "falls back to application when no customer is set" do
    Current.customer = nil
    expect(controller.send(:dashboard_layout)).to eq("application")
  end

  describe "#current_dashboard_menu_item (path inference)" do
    def menu_for(path)
      controller.request = ActionController::TestRequest.create(controller.class)
      controller.request.path_info = path
      controller.send(:current_dashboard_menu_item)
    end

    it "infers :maintenance for tenant + /admin/ prefixed maintenance pages" do
      expect(menu_for("/81721200/admin/maintenance")).to eq(:maintenance)
      expect(menu_for("/81721200/admin/maintenance/platform/module_settings/sms/credentials")).to eq(:maintenance)
    end

    it "infers :modules, :entities, :settings, :assistant under /admin/" do
      expect(menu_for("/81721200/admin/modules")).to eq(:modules)
      expect(menu_for("/81721200/admin/entities/123")).to eq(:entities)
      expect(menu_for("/81721200/admin/domains/5/pages")).to eq(:entities)
      expect(menu_for("/81721200/admin/pages/7")).to eq(:entities)
      expect(menu_for("/81721200/admin/settings/modules/sms")).to eq(:settings)
      expect(menu_for("/81721200/admin/assistant")).to eq(:assistant)
      expect(menu_for("/81721200/admin/assistant/messages")).to eq(:assistant)
    end

    it "infers :assistant for the bare /admin landing" do
      expect(menu_for("/81721200/admin")).to eq(:assistant)
      expect(menu_for("/81721200/admin/")).to eq(:assistant)
    end

    it "returns :home for tenant root without /admin" do
      expect(menu_for("/81721200")).to eq(:home)
    end

    it "does not strip a path segment that merely starts with 'admin' (e.g. /administration)" do
      expect(menu_for("/81721200/administration/foo")).to eq(:home)
    end
  end
end

RSpec.describe ApplicationController, 'platform elevated access', type: :controller do
  controller do
    before_action :setup_tenant_context
    before_action :require_elevated_access!, only: [:elevated_action]

    def index
      render json: { elevated: platform_elevated_access? }
    end

    def elevated_action
      render json: { success: true }
    end

    private

    def setup_tenant_context
      # Manually set up tenant context since this anonymous controller
      # doesn't have automatic tenant extraction configured
      customer_id = params[:customer_id]
      if customer_id.present?
        customer = Customer.find_by(id: customer_id)
        if customer && current_user&.platform_owner? && customer.id != current_user.customer_id
          # Platform owner accessing another customer
          Current.customer = customer
          Current.platform_owner_context = true
          Current.original_customer = current_user.customer
          Current.acting_as_customer = customer
        elsif customer
          # Regular customer access
          Current.customer = customer
          Current.platform_owner_context = false
        end
      end
    end
  end

  let(:platform_customer) { ensure_platform_customer(name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }
  let(:regular_customer) { create(:customer, name: 'Regular Customer') }

  let(:platform_owner_user) { find_or_create_platform_owner }

  let(:regular_owner_user) do
    create(:user, customer: regular_customer, role: :admin, email: 'regular@test.io')
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'elevated_action' => 'anonymous#elevated_action'
    end
  end

  after { Current.reset }

  describe '#platform_elevated_access?' do
    context 'platform owner in platform owner context' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = true
      end

      it 'returns true' do
        get :index, params: { customer_id: target_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be true
      end
    end

    context 'platform owner in own context' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = false
      end

      it 'returns false' do
        get :index, params: { customer_id: platform_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be false
      end
    end

    context 'regular user' do
      before do
        sign_in regular_owner_user
        Current.platform_owner_context = false
      end

      it 'returns false' do
        get :index, params: { customer_id: regular_customer.id }
        json = JSON.parse(response.body)
        expect(json['elevated']).to be false
      end
    end
  end

  describe '#require_elevated_access!' do
    context 'with elevated access' do
      before do
        sign_in platform_owner_user
        Current.platform_owner_context = true
      end

      it 'allows the action' do
        get :elevated_action, params: { customer_id: target_customer.id }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'without elevated access' do
      before do
        sign_in regular_owner_user
        Current.platform_owner_context = false
      end

      it 'returns forbidden for JSON request' do
        get :elevated_action, params: { customer_id: regular_customer.id }, format: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
