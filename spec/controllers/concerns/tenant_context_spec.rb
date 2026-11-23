# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantContext, type: :controller do
  let(:customer) { create(:customer, name: 'Test Tenant') }

  after { Current.reset }

  # =============================================================
  # Auto-extraction: any URL whose first segment is an 8-digit
  # customer id sets the tenant without per-controller opt-in.
  # =============================================================
  describe 'auto-extraction from /:cid/...' do
    controller(ApplicationController) do
      include TenantContext

      def index
        render json: {
          customer_id: current_customer_id,
          customer_name: current_customer&.name,
          tenant_set: tenant_set?
        }
      end
    end

    before do
      routes.draw do
        get '*path', to: 'anonymous#index'
      end
    end

    context 'with a valid customer_id in the URL' do
      it 'makes current_customer available in the response' do
        get :index, params: { path: "#{customer.id}/flowcharts" }

        json = JSON.parse(response.body)
        expect(json['customer_id']).to eq(customer.id)
        expect(json['customer_name']).to eq('Test Tenant')
        expect(json['tenant_set']).to be true
      end
    end

    context 'with an unknown customer_id in the URL' do
      it 'renders not_found' do
        get :index, params: { path: '99999999/flowcharts' }

        expect(response).to have_http_status(:not_found)
      end

      it 'returns the error message in json' do
        get :index, params: { path: '99999999/flowcharts' }, format: :json

        json = JSON.parse(response.body)
        expect(json['error']).to eq('Customer not found')
      end
    end

    context 'when the URL has no leading 8-digit segment' do
      it 'leaves the tenant unset and serves the request' do
        get :index, params: { path: 'somewhere/else' }

        json = JSON.parse(response.body)
        expect(json['tenant_set']).to be false
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # =============================================================
  # Explicit set_tenant_from_path opt-in (used by the dynamic
  # catch-all whose customer id is buried inside params[:path]).
  # =============================================================
  describe '.set_tenant_from_path' do
    controller(ApplicationController) do
      include TenantContext

      set_tenant_from_path segment: 0, required: true

      def index
        render json: { tenant_set: tenant_set?, customer_id: current_customer_id }
      end
    end

    before do
      routes.draw do
        get '*path', to: 'anonymous#index'
      end
    end

    it 'extracts tenant from the configured path segment' do
      get :index, params: { path: "#{customer.id}/anything" }

      json = JSON.parse(response.body)
      expect(json['tenant_set']).to be true
      expect(json['customer_id']).to eq(customer.id)
    end
  end

  describe 'helper methods available in controllers' do
    controller(ApplicationController) do
      include TenantContext

      def index
        render json: {
          has_current_customer_method:    respond_to?(:current_customer),
          has_current_customer_id_method: respond_to?(:current_customer_id),
          has_tenant_set_method:          respond_to?(:tenant_set?)
        }
      end
    end

    before do
      routes.draw do
        get 'test', to: 'anonymous#index'
      end
    end

    it 'exposes current_customer, current_customer_id, tenant_set?' do
      get :index

      json = JSON.parse(response.body)
      expect(json['has_current_customer_method']).to be true
      expect(json['has_current_customer_id_method']).to be true
      expect(json['has_tenant_set_method']).to be true
    end
  end

  describe 'request metadata storage' do
    controller(ApplicationController) do
      include TenantContext

      def index
        render json: {
          request_id: Current.request_id,
          ip_address: Current.ip_address,
          user_agent: Current.user_agent
        }
      end
    end

    before do
      routes.draw do
        get 'test', to: 'anonymous#index'
      end
    end

    it 'stores request metadata in Current' do
      get :index

      json = JSON.parse(response.body)
      expect(json['ip_address']).to eq('0.0.0.0')
    end
  end
end
