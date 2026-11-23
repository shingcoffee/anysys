# frozen_string_literal: true

require "rails_helper"

# S3 — deactivating a user must terminate their LIVE session, not merely block
# future logins. Enforced via Authentication::User#active_for_authentication?
# routing the custom `status` enum through Devise's per-request activatable hook.
RSpec.describe "Authentication: deactivation revokes a live session", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let(:admin_user)  { create(:user, :admin, customer: customer, password: "password123") }
  let(:protected_path) { admin_modules_authentication_users_path(customer.id) }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    sign_in admin_user
  end

  it "keeps the session valid while the user is active" do
    get protected_path
    expect(response).to have_http_status(:success)
  end

  it "logs the user out on the next request after deactivation" do
    get protected_path
    expect(response).to have_http_status(:success)

    admin_user.update!(status: :inactive)

    get protected_path
    # The activatable hook throws :warden → Devise failure app → sign-in redirect.
    expect(response).to redirect_to(new_user_session_path)
  end
end
