# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantContext, 'platform owner context', type: :controller do
  controller(ApplicationController) do
    def index
      render json: {
        customer_id:           Current.customer_id,
        platform_owner_context: Current.platform_owner_context?,
        original_customer_id:  Current.original_customer&.id,
        acting_as_customer_id: Current.acting_as_customer&.id
      }
    end
  end

  let(:platform_customer) { ensure_platform_customer(name: 'Platform Owner') }
  let(:target_customer)   { create(:customer, name: 'Target Customer') }
  let(:regular_customer)  { create(:customer, name: 'Regular Customer') }

  let(:platform_owner_user) { find_or_create_platform_owner }

  let(:regular_owner_user) do
    create(:user, customer: regular_customer, role: :admin, email: 'regular@test.io')
  end

  # Tenant is auto-extracted from the URL prefix `/:cid/...`. We route the
  # anonymous controller under that pattern so the auto-extract path runs
  # exactly as it would in production.
  before do
    routes.draw do
      get '/:customer_id/admin/context', to: 'anonymous#index', constraints: { customer_id: /\d{8}/ }
    end
  end

  after { Current.reset }

  def json_for(customer_id)
    get :index, params: { customer_id: customer_id }
    JSON.parse(response.body)
  end

  describe 'platform owner accessing another customer' do
    before { sign_in platform_owner_user }

    it 'sets platform_owner_context to true' do
      expect(json_for(target_customer.id)['platform_owner_context']).to be true
    end

    it 'sets Current.customer to target customer' do
      expect(json_for(target_customer.id)['customer_id']).to eq(target_customer.id)
    end

    it 'sets original_customer to platform customer' do
      expect(json_for(target_customer.id)['original_customer_id']).to eq(81_721_200)
    end

    it 'sets acting_as_customer to target customer' do
      expect(json_for(target_customer.id)['acting_as_customer_id']).to eq(target_customer.id)
    end
  end

  describe 'platform owner accessing own customer' do
    before { sign_in platform_owner_user }

    it 'does not set platform_owner_context' do
      expect(json_for(platform_customer.id)['platform_owner_context']).to be false
    end
  end

  describe 'regular user accessing own customer' do
    before { sign_in regular_owner_user }

    it 'does not set platform_owner_context' do
      expect(json_for(regular_customer.id)['platform_owner_context']).to be false
    end
  end

  describe 'regular user attempting to access another customer' do
    before { sign_in regular_owner_user }

    it 'is denied with forbidden' do
      get :index, params: { customer_id: target_customer.id }

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end

    it 'does not leak target customer in Current' do
      get :index, params: { customer_id: target_customer.id }

      expect(Current.customer&.id).not_to eq(target_customer.id)
    end

    it 'still denies cross-tenant access when SCRIPT_NAME prefixes the path' do
      @request.env['SCRIPT_NAME'] = '/anysys'
      get :index, params: { customer_id: target_customer.id }

      expect(@request.script_name).to eq('/anysys')
      expect(@request.path).to start_with('/anysys/')
      expect(@request.path_info).to start_with("/#{target_customer.id}")
      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(Current.customer&.id).not_to eq(target_customer.id)
    end
  end

  describe 'own-tenant SCRIPT_NAME extraction' do
    before { sign_in regular_owner_user }

    it 'sets Current.customer from path_info when SCRIPT_NAME prefixes request.path' do
      @request.env['SCRIPT_NAME'] = '/anysys'
      get :index, params: { customer_id: regular_customer.id }

      expect(@request.path).to eq("/anysys/#{regular_customer.id}/admin/context")
      expect(@request.path_info).to eq("/#{regular_customer.id}/admin/context")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['customer_id']).to eq(regular_customer.id)
    end
  end
end
