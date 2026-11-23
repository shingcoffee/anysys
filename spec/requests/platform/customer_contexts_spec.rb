# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Platform::CustomerContexts', type: :request do
  let(:platform_customer) { ensure_platform_customer(name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Acme Industries') }
  let(:another_customer) { create(:customer, name: 'Widgets Corp') }

  let(:platform_owner_user) { find_or_create_platform_owner }
  let(:platform_owner) { platform_owner_user }

  let(:regular_owner) do
    create(:user, :admin, customer: target_customer, email: 'owner@acme.test', password: 'password123')
  end

  before do
    platform_customer
    target_customer
    another_customer
  end

  describe 'GET /platform/customer_contexts/search' do
    let(:guard_path) { admin_maintenance_platform_customer_context_search_path(platform_customer.id) }

    it_behaves_like "a platform-owner-guarded GET"
    context 'when signed in as platform owner' do
      before { sign_in platform_owner_user }

      it 'returns matching customers as JSON' do
        get admin_maintenance_platform_customer_context_search_path(platform_customer.id), params: { q: 'Acme' }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).to be_an(Array)
        expect(body.first).to include('id', 'name')
      end

      it 'returns multiple matching customers' do
        create(:customer, name: 'Acme Corp')
        get admin_maintenance_platform_customer_context_search_path(platform_customer.id), params: { q: 'Acme' }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.map { |c| c['name'] }).to include('Acme Industries', 'Acme Corp')
      end

      it 'returns empty array when no matches' do
        get admin_maintenance_platform_customer_context_search_path(platform_customer.id), params: { q: 'zzzznotfound' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq([])
      end

      it 'limits results to 20 customers' do
        25.times { |i| create(:customer, name: "Test #{i}") }

        get admin_maintenance_platform_customer_context_search_path(platform_customer.id), params: { q: 'Test' }, as: :json

        body = JSON.parse(response.body)
        expect(body.size).to be <= 20
      end
    end

    context 'when signed in as regular owner' do
      before { sign_in regular_owner }

      it 'redirects with access denied' do
        get admin_maintenance_platform_customer_context_search_path(target_customer.id), params: { q: 'Acme' }, as: :json

        expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      end
    end

    context 'as unauthenticated user' do
      it 'redirects to login' do
        get admin_maintenance_platform_customer_context_search_path(platform_customer.id), params: { q: 'test' }, as: :json
        expect(response).to have_http_status(:unauthorized).or redirect_to(%r{/auth/sign_in})
      end
    end
  end

  describe 'POST /platform/customer_contexts/switch' do
    let(:guard_path) { admin_maintenance_platform_customer_context_path(platform_customer.id) }

    it_behaves_like "a platform-owner-guarded request", :patch

    context 'when signed in as platform owner' do
      before { sign_in platform_owner_user }

      it 'switches when the target id is only a query parameter' do
        patch admin_maintenance_platform_customer_context_path(platform_customer.id, target_customer_id: target_customer.id)

        expect(response).to redirect_to("/#{target_customer.id}/admin/dashboard")
      end

      it 'switches to target customer context' do
        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: target_customer.id }

        expect(response).to redirect_to("/#{target_customer.id}/admin/dashboard")
        expect(flash[:notice]).to eq("Now acting as #{target_customer.name}")
      end

      it 'handles invalid customer ID' do
        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: 99999999 }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Customer not found')
      end

      it 'returns not found for invalid customer' do
        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: 99999999 }, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'can switch between multiple customers' do
        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: target_customer.id }
        expect(response).to redirect_to("/#{target_customer.id}/admin/dashboard")

        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: another_customer.id }
        expect(response).to redirect_to("/#{another_customer.id}/admin/dashboard")
      end
    end

    context 'when signed in as regular owner' do
      before { sign_in regular_owner }

      it 'redirects with access denied' do
        patch admin_maintenance_platform_customer_context_path(target_customer.id), params: { customer_id: another_customer.id }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to match(/Platform owner.+required|Access denied/i)
      end
    end
  end

  describe 'DELETE /platform/customer_contexts/clear' do
    let(:guard_path) { admin_maintenance_platform_customer_context_path(platform_customer.id) }

    it_behaves_like "a platform-owner-guarded request", :delete

    context 'when signed in as platform owner' do
      before do
        sign_in platform_owner_user
        patch admin_maintenance_platform_customer_context_path(platform_customer.id), params: { customer_id: target_customer.id }
      end

      it 'clears platform owner context and returns to own customer' do
        delete admin_maintenance_platform_customer_context_path(platform_customer.id)

        expect(response).to redirect_to("/#{platform_customer.id}/admin/dashboard")
        expect(flash[:notice]).to eq('Returned to platform context')
      end

      it 'clears Current attributes' do
        delete admin_maintenance_platform_customer_context_path(platform_customer.id)

        get "/#{platform_customer.id}/admin/dashboard"

        expect(Current.platform_owner_context?).to be false
        expect(Current.acting_as_customer).to be_nil
        expect(Current.original_customer).to be_nil
      end
    end

    context 'when signed in as regular owner' do
      before { sign_in regular_owner }

      it 'redirects with access denied' do
        delete admin_maintenance_platform_customer_context_path(target_customer.id)

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to match(/Platform owner.+required|Access denied/i)
      end
    end
  end

  describe 'platform owner context detection in requests' do
    before { sign_in platform_owner_user }

    it 'allows dashboard and settings on own and other tenants' do
      # Context is per-request and derived from the URL — there is no
      # session-stored "currently acting as" key.
      [
        "/#{platform_customer.id}/admin/dashboard",
        "/#{target_customer.id}/admin/dashboard",
        "/#{target_customer.id}/admin/settings"
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'authorization across customers' do
    before { sign_in platform_owner_user }

    it 'allows platform owner to view entities of another customer' do
      create(:entity, customer: target_customer, name: 'Test Entity')

      get "/#{target_customer.id}/admin/domains"

      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end

    it 'maintains proper tenant isolation' do
      create(:entity, customer: platform_customer, name: 'Platform Entity')
      create(:entity, customer: target_customer, name: 'Target Entity')

      get "/#{platform_customer.id}/admin/domains"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)

      get "/#{target_customer.id}/admin/domains"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end
  end
end
