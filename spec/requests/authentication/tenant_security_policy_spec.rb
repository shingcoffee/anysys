# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tenant authentication policy enforcement", type: :request do
  let(:short_customer) { create(:customer) }
  let(:long_customer) { create(:customer) }
  let(:short_user) { create(:user, :member, customer: short_customer, password: "Password123!") }
  let(:long_user) { create(:user, :member, customer: long_customer, password: "Password123!") }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  before do
    ensure_customer_feature_module(short_customer, auth_module, status: :active,
                                   configuration: { "session_timeout" => 2, "max_login_attempts" => 2 }.to_json)
    ensure_customer_feature_module(long_customer, auth_module, status: :active,
                                   configuration: { "session_timeout" => 8, "max_login_attempts" => 5 }.to_json)
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  it "expires only the short tenant's real Devise session after three idle minutes" do
    short_client = ActionDispatch::Integration::Session.new(Rails.application)
    long_client = ActionDispatch::Integration::Session.new(Rails.application)
    travel_to(Time.current.change(usec: 0)) do
      short_client.post user_session_path, params: { user: { email: short_user.email, password: "Password123!" } }
      expect(short_client.request.env["warden"].session(:user)["last_request_at"]).to eq(Time.current.to_i)
      long_client.post user_session_path, params: { user: { email: long_user.email, password: "Password123!" } }
      expect(long_client.request.env["warden"].session(:user)["last_request_at"]).to eq(Time.current.to_i)
      expect(short_client.response).to be_redirect
      expect(long_client.response).to be_redirect

      travel 3.minutes
      short_client.get member_dashboard_path(short_customer.id)
      long_client.get member_dashboard_path(long_customer.id)

      expect(short_client.response).to be_redirect
      # Devise retries the timed-out GET after clearing the signed-in scope.
      # The next, unauthenticated request is then redirected to sign-in.
      expect(short_client.request.env["warden.options"][:message]).to eq(:timeout)
      expect(short_client.request.env["warden"].authenticated?(:user)).to be(false)
      short_client.follow_redirect!
      expect(URI.parse(short_client.response.location).path).to eq(new_user_session_path)
      expect(long_client.response).to have_http_status(:ok)
    end
  end

  it "locks at the tenant limit on the real password sign-in endpoint" do
    2.times do
      post user_session_path, params: { user: { email: short_user.email, password: "wrong" } }
      expect(response).to have_http_status(:unprocessable_entity)
      post user_session_path, params: { user: { email: long_user.email, password: "wrong" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    expect(short_user.reload.failed_attempts).to eq(2)
    expect(short_user.access_locked?).to be(true)
    expect(long_user.reload.failed_attempts).to eq(2)
    expect(long_user.access_locked?).to be(false)
  end

  it "uses that same Lockable limit for account-edit current-password checks" do
    sign_in short_user

    2.times do
      patch user_registration_path, params: { user: { first_name: "Rejected", current_password: "wrong" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    expect(short_user.reload.access_locked?).to be(true)
    expect(short_user.failed_attempts).to eq(2)
    expect(short_user.first_name).not_to eq("Rejected")
    expect(long_user.reload.access_locked?).to be(false)
  end
end
