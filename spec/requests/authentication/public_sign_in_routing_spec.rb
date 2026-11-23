# frozen_string_literal: true

require "rails_helper"

# Public sign-in (POST /auth/sign_in) role routing and audit ledger. Baseline
# credential-handling coverage lives in spec/requests/home_spec.rb and
# spec/requests/authentication/sessions_spec.rb.
RSpec.describe "Authentication public sign-in routing", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  def sign_in_post(email:, password: "password123")
    post user_session_path, params: {
      user: { email: email, password: password }
    }
  end

  describe "post_auth_path member vs admin routing" do
    it "routes a member to the member surface (not /admin) after signing in" do
      member = create(:user, :member, customer: customer, email: "member@example.com", password: "password123")

      sign_in_post(email: member.email)

      expect(response).to redirect_to("/#{customer.id}/member")
    end

    it "routes an admin to the AI Assistant after signing in" do
      admin = create(:user, :admin, customer: customer, email: "admin@example.com", password: "password123")

      sign_in_post(email: admin.email)

      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    # AGENTS.md requires every user to hold exactly one reserved role, so this
    # is an invalid state that should not exist. When it does, treat it as the
    # least-privileged one: Authentication::User#primary_role_key already
    # falls back to "member", and sending such a user to /admin only gets them
    # denied by the role gate.
    it "routes a user carrying no reserved role to the least-privileged surface" do
      plain_user = create(:user, customer: customer, email: "plain@example.com", password: "password123")

      sign_in_post(email: plain_user.email)

      expect(response).to redirect_to("/#{customer.id}/member")
    end
  end

  describe "audit events" do
    let!(:user) { create(:user, customer: customer, email: "cr_audit@example.com", password: "password123") }

    it "records login_succeeded on success" do
      expect { sign_in_post(email: user.email) }
        .to change { Authentication::Event.where(event: "login_succeeded", user_id: user.id).count }.by(1)
    end

    it "records login_failed on a bad password" do
      expect { sign_in_post(email: user.email, password: "wrong") }
        .to change { Authentication::Event.where(event: "login_failed", user_id: user.id).count }.by(1)
    end

    it "records login_failed for an unknown email (no user_id)" do
      expect { sign_in_post(email: "nobody@example.com") }
        .to change { Authentication::Event.where(event: "login_failed", user_id: nil).count }.by(1)
    end

    it "records locked_out (not login_failed) once the account is already locked" do
      Devise.maximum_attempts.times { sign_in_post(email: user.email, password: "wrong") }
      expect(user.reload.access_locked?).to be(true)

      expect { sign_in_post(email: user.email, password: "wrong") }
        .to change { Authentication::Event.where(event: "locked_out", user_id: user.id).count }.by(1)
    end
  end
end
