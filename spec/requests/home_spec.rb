# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  let!(:customer) { create(:customer) }
  # Explicitly an admin: post-sign-in destinations go through
  # Authentication::LandingPath, which routes on the user's role.
  let!(:user) { create(:user, :admin, customer: customer, password: "password123") }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  def sign_in_post(email: user.email, password: "password123", extra: {})
    post user_session_path, params: {
      user: { email: email, password: password }
    }.merge(extra)
  end

  describe "GET /" do
    before { get root_path }

    it "renders the sign-in page" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in to your account")
    end

    it "does not include a customer number field" do
      expect(response.body).not_to include('name="customer_number"')
    end

    it "includes email field" do
      expect(response.body).to include('name="user[email]"')
    end

    it "includes password field" do
      expect(response.body).to include('name="user[password]"')
    end

    it "includes an email sign-in link control" do
      expect(response.body).to include("Email me a sign-in link")
      expect(response.body).to include('name="intent"')
      expect(response.body).to include('value="sign_in_link"')
    end

    it "includes a public customer sign-up link" do
      expect(response.body).to include("/auth/sign_up")
    end
  end

  describe "GET / when already signed in" do
    it "sends an admin to the AI Assistant" do
      sign_in user
      get root_path
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "sends a member to the member surface" do
      member = create(:user, :member, customer: customer, email: "member-root@example.com", password: "password123")
      sign_in member
      get root_path
      expect(response).to redirect_to("/#{customer.id}/member")
    end
  end

  describe "POST /auth/sign_in from the marketing root form" do
    context "with valid credentials" do
      it "signs in the user and redirects to the AI Assistant" do
        sign_in_post

        expect(response).to redirect_to(admin_assistant_path(customer.id))
      end

      context "when user has an OTP secret but MFA is not yet enforced" do
        before { user.generate_otp_secret! }

        it "signs in the user and redirects to MFA setup" do
          sign_in_post

          expect(response).to redirect_to(mfa_setup_path(customer.id))
        end
      end

      context "when user has MFA configured" do
        before do
          user.generate_otp_secret!
          user.enable_mfa!
        end

        it "signs in the user and redirects to MFA verify" do
          sign_in_post

          expect(response).to redirect_to(mfa_session_path(customer.id))
        end
      end
    end

    context "with a leftover customer_number param" do
      it "ignores it and signs the user into their own tenant" do
        sign_in_post(extra: { customer_number: "00000000" })

        expect(response).to redirect_to(admin_assistant_path(customer.id))
      end
    end

    context "with invalid password" do
      it "renders error message" do
        sign_in_post(password: "wrongpassword")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid email or password")
        expect(response.body).not_to include("Invalid customer number")
      end
    end

    context "with deactivated user" do
      let!(:inactive_user) { create(:user, customer: customer, password: "password123", status: :inactive) }

      it "returns invalid credentials error (security: indistinguishable from non-existent user)" do
        sign_in_post(email: inactive_user.email)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Invalid email or password")
      end
    end
  end
end
