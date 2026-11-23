# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Registrations", type: :request do
  # Devise mail is enqueued; deliver it so examples can read the mailbox.
  around { |example| perform_enqueued_jobs { example.run } }

  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { find_or_create_feature_module!("authentication") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  def set_signup(enabled)
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: auth_module.id
    )
    cfm.update!(configuration: { "allow_registration" => enabled }.to_json)
  end

  describe "GET /:cid/auth/sign_up" do
    it "renders the disabled page when allow_registration is false" do
      set_signup(false)
      get "/#{customer.id}/auth/sign_up"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign-up is currently disabled")
    end

    it "renders the form when allow_registration is true" do
      set_signup(true)
      get "/#{customer.id}/auth/sign_up"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create your account")
    end
  end

  describe "POST /:cid/auth" do
    before { set_signup(true) }

    let(:valid_params) do
      { user: { first_name: "Pat", last_name: "Lee", email: "pat@example.com",
                password: "Password123!", password_confirmation: "Password123!" } }
    end

    it "creates an unconfirmed user and sends one confirmation email" do
      expect {
        post "/#{customer.id}/auth", params: valid_params
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      user = Authentication::User.find_by(email: "pat@example.com")
      expect(user).to be_present
      expect(user.confirmed_at).to be_nil
      expect(user.confirmation_token).to be_present
      expect(user.member?).to eq(true)
    end

    it "does not go through CustomerSignupToken or create a tenant" do
      expect(Authentication::CustomerSignupToken).not_to receive(:generate)
      expect(Authentication::IssueCustomerSignup).not_to receive(:call)

      expect {
        post "/#{customer.id}/auth", params: valid_params
      }.not_to change(Customer, :count)

      user = Authentication::User.find_by(email: "pat@example.com")
      expect(user).to be_present
      expect(user.confirmed_at).to be_nil
      expect(user.confirmation_token).to be_present
    end

    it "redirects to sign-in with a 'please confirm' flash" do
      post "/#{customer.id}/auth", params: valid_params
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(flash[:notice]).to include("confirmation link")
    end

    it "does NOT sign the new user in until confirmed" do
      post "/#{customer.id}/auth", params: valid_params
      get "/#{customer.id}/member"
      expect(response).not_to have_http_status(:ok)
    end

    it "ignores any role parameter and only assigns :member" do
      malicious = valid_params.deep_dup
      malicious[:user][:role] = "admin"
      malicious[:role] = "admin"
      post "/#{customer.id}/auth", params: malicious
      user = Authentication::User.find_by(email: "pat@example.com")
      expect(user.member?).to eq(true)
      expect(user.admin?).to eq(false)
      expect(user.owner?).to eq(false)
      expect(user.users_roles.joins(:role).where(roles: { system: true, key: Authentication::User::RESERVED_ROLE_KEYS }).count).to eq(1)
    end

    it "rolls signup back when its reserved assignment fails instead of leaving a roleless user" do
      allow_any_instance_of(UsersRole).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
        record = method.receiver
        if record.user&.email == valid_params[:user][:email]
          record.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
          raise ActiveRecord::RecordInvalid.new(record)
        end
        method.call(*args, **kwargs)
      end

      expect {
        post "/#{customer.id}/auth", params: valid_params
      }.not_to change { Authentication::User.exists?(email: valid_params[:user][:email]) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("auth.errors.reserved_role_required"))
      expect(controller.user_signed_in?).to be(false)
    end

    it "renders the disabled page when allow_registration is false" do
      set_signup(false)
      post "/#{customer.id}/auth", params: valid_params
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign-up is currently disabled")
    end

    describe "an address that already has an account" do
      def sign_up_as(email, **overrides)
        params = valid_params.deep_dup
        params[:user].merge!(email: email, **overrides)
        post "/#{customer.id}/auth", params: params
        { status: response.status, location: response.location, notice: flash[:notice], alert: flash[:alert] }
      end

      before { Authentication::Throttle.reset_store! }
      after { Authentication::Throttle.reset_store! }

      it "answers like a new sign-up and mails a sign-in link only to this tenant's confirmed member" do
        other_customer = create(:customer)
        ensure_customer_feature_module(other_customer, auth_module, status: :active)
        member = create(:user, :member, customer: customer, email: "member@example.com")
        foreign = create(:user, :member, customer: other_customer, email: "foreign@example.com")
        unconfirmed = create(:user, :member, :unconfirmed, customer: customer, email: "pending@example.com")

        fresh = sign_up_as("fresh@example.com")
        expect(fresh).to include(status: 303, notice: I18n.t("auth.flash.confirmation_sent", email: "fresh@example.com"))

        ActionMailer::Base.deliveries.clear
        users = Authentication::User.count
        answers = [member, foreign, unconfirmed].to_h { |user| [user, sign_up_as(user.email)] }

        expect(Authentication::User.count).to eq(users)
        expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[member.email]])
        answers.each do |user, answer|
          expect(answer).to eq(fresh.merge(notice: I18n.t("auth.flash.confirmation_sent", email: user.email)))
        end
        expect(unconfirmed.reload.confirmed_at).to be_nil
      end

      it "keeps other validation errors but never says the address is taken" do
        create(:user, :member, customer: customer, email: "member@example.com")

        sign_up_as("member@example.com", password: "short", password_confirmation: "short")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).not_to include(I18n.t("errors.messages.taken"))
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "pads a new and an existing address to the same minimum duration" do
        create(:user, :member, customer: customer, email: "member@example.com")
        expect(Authentication::UniformTiming).to receive(:pad).with(kind_of(Numeric)).twice

        sign_up_as("fresh@example.com")
        sign_up_as("member@example.com")
      end
    end

    it "renders new with 422 when registration params are invalid (validation failure)" do
      invalid_params = { user: { first_name: "", last_name: "", email: "not-an-email",
                                 password: "short", password_confirmation: "mismatch" } }
      post "/#{customer.id}/auth", params: invalid_params
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not 500 when user is posted as an array" do
      expect {
        post "/#{customer.id}/auth", params: { user: ["not-a-hash"] }
      }.not_to change(Authentication::User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # check_auth_enabled redirect branch — auth module disabled
  describe "auth module disabled" do
    before do
      FeatureModules::CustomerAssignment
        .where(customer: customer, feature_module: auth_module)
        .delete_all
    end

    it "redirects GET /sign_up to admin dashboard when auth is disabled" do
      get "/#{customer.id}/auth/sign_up"
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end

    it "redirects GET /auth/edit to the signed-in landing when auth is disabled" do
      user = create(:user, :admin, customer: customer, password: "Password123!")
      sign_in user
      get "/auth/edit"
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "redirects PATCH /auth to the signed-in landing when auth is disabled" do
      user = create(:user, :admin, customer: customer, password: "Password123!")
      sign_in user
      patch "/auth",
            params: { user: { first_name: "New", current_password: "Password123!" } }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end
  end

  # edit and update actions (profile self-management)
  describe "GET /:cid/auth/edit" do
    let!(:user) { create(:user, customer: customer, password: "Password123!") }

    before do
      set_signup(true)
      sign_in user
    end

    it "renders the edit form" do
      get "/auth/edit"
      expect(response).to have_http_status(:ok)
    end

    it "sends an admin to MFA setup when tenant MFA is on and they have not enrolled" do
      admin = create(:user, :admin, customer: customer, password: "Password123!")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: auth_module.id
      )
      cfm.update!(configuration: { "allow_registration" => true, "mfa_enabled" => true }.to_json)
      sign_in admin

      get "/auth/edit"
      expect(response).to redirect_to(mfa_setup_path(customer.id))
    end

    it "does not let an unenrolled admin change email/password while tenant MFA is on" do
      admin = create(:user, :admin, customer: customer, password: "Password123!")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: auth_module.id
      )
      cfm.update!(configuration: { "allow_registration" => true, "mfa_enabled" => true }.to_json)
      sign_in admin
      original = admin.email

      patch "/auth",
            params: { user: { email: "skip-mfa@example.com",
                              current_password: "Password123!" } }
      expect(response).to redirect_to(mfa_setup_path(customer.id))
      expect(admin.reload.email).to eq(original)
    end
  end

  describe "PATCH /:cid/auth (update)" do
    # Explicitly an admin: the post-update redirect goes through
    # Authentication::LandingPath, which routes on the user's role.
    let!(:user) { create(:user, :admin, customer: customer, password: "Password123!") }

    before do
      set_signup(true)
      sign_in user
    end

    it "updates the user's name with valid current_password and redirects" do
      patch "/auth",
            params: { user: { first_name: "Updated",
                              current_password: "Password123!" } }
      expect(user.reload.first_name).to eq("Updated")
      expect(response).to redirect_to(admin_assistant_path(customer.id))
    end

    it "renders edit with 422 when current_password is wrong" do
      expect {
        patch "/auth",
              params: { user: { first_name: "Bad",
                                current_password: "wrongpassword" } }
      }.to change { user.reload.failed_attempts }.by(1)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(controller.send(:resource).errors.of_kind?(:current_password, :invalid)).to be(true)
      expect(user.reload.first_name).not_to eq("Bad")
    end

    [nil, "", "   "].each do |current_password|
      it "preserves the blank current-password error and counts the failed attempt for #{current_password.inspect}" do
        attributes = { first_name: "Rejected" }
        attributes[:current_password] = current_password unless current_password.nil?

        expect {
          patch "/auth", params: { user: attributes }
        }.to change { user.reload.failed_attempts }.by(1)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(controller.send(:resource).errors.of_kind?(:current_password, :blank)).to be(true)
        expect(user.reload.first_name).not_to eq("Rejected")
      end
    end

    it "does not persist submitted credentials while recording a failed current-password verification" do
      original = user.attributes.slice("first_name", "email", "encrypted_password")

      patch "/auth", params: {
        user: { first_name: "Rejected", email: "rejected-update@example.com",
                password: "NewPassword1!", password_confirmation: "NewPassword1!",
                current_password: "wrongpassword" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.attributes.slice(*original.keys)).to eq(original)
      expect(user.failed_attempts).to eq(1)
      expect(controller.send(:resource).errors.of_kind?(:current_password, :invalid)).to be(true)
    end

    it "retains submitted field validation errors alongside an invalid current password" do
      patch "/auth", params: {
        user: { email: "invalid-email", current_password: "wrongpassword" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(controller.send(:resource).errors.of_kind?(:email, :invalid)).to be(true)
      expect(controller.send(:resource).errors.of_kind?(:current_password, :invalid)).to be(true)
      expect(user.reload.email).not_to eq("invalid-email")
    end

    it "locks the account at the configured current-password attempt limit without updating the profile" do
      original_name = user.first_name

      Devise.maximum_attempts.times do
        patch "/auth", params: {
          user: { first_name: "Rejected", current_password: "wrongpassword" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      expect(user.reload.failed_attempts).to eq(Devise.maximum_attempts)
      expect(user.access_locked?).to be(true)
      expect(user.first_name).to eq(original_name)

      patch "/auth", params: {
        user: { first_name: "StillRejected", current_password: "Password123!" }
      }
      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.first_name).to eq(original_name)
    end

    it "resets failed attempts on valid re-authentication and ignores empty password fields" do
      patch "/auth", params: { user: { current_password: "wrongpassword" } }
      expect(user.reload.failed_attempts).to eq(1)
      original_digest = user.encrypted_password

      patch "/auth", params: {
        user: { first_name: "Updated", password: "", password_confirmation: "",
                current_password: "Password123!" }
      }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.reload.failed_attempts).to eq(0)
      expect(user.first_name).to eq("Updated")
      expect(user.encrypted_password).to eq(original_digest)
    end

    it "verifies the old password before saving a new one" do
      patch "/auth", params: {
        user: { password: "NewPassword1!", password_confirmation: "NewPassword1!",
                current_password: "Password123!" }
      }

      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.reload.valid_password?("NewPassword1!")).to be(true)
      expect(user.valid_password?("Password123!")).to be(false)
      expect(controller.user_signed_in?).to be(true)
    end

    it "lets a user without a password set one without current_password" do
      user.update_columns(encrypted_password: "")
      patch "/auth",
            params: { user: { password: "NewPassword1!",
                              password_confirmation: "NewPassword1!" } }
      expect(response).to redirect_to(admin_assistant_path(customer.id))
      expect(user.reload.password_set?).to be(true)
      expect(user.valid_password?("NewPassword1!")).to be(true)
    end

    it "does not let a passwordless user change email without current_password" do
      user.update_columns(encrypted_password: "")
      original = user.email
      patch "/auth",
            params: { user: { email: "hijacked@example.com",
                              password: "NewPassword1!",
                              password_confirmation: "NewPassword1!" } }
      expect(user.reload.email).to eq(original)
      expect(user.valid_password?("NewPassword1!")).to be(true)
    end

    it "sends a member back to the member surface after updating" do
      member = create(:user, :member, customer: customer, password: "Password123!")
      sign_in member
      patch "/auth",
            params: { user: { first_name: "MemberName",
                              current_password: "Password123!" } }
      expect(response).to redirect_to("/#{customer.id}/member")
    end

    # This branch used to read `member? && !admin_or_owner?`, which is false
    # for a user carrying no role row and so dropped them on the admin surface
    # — where the role gate immediately denied them. LandingPath defers to
    # primary_role_key, which falls back to "member".
    it "sends a user carrying no role row to the member surface" do
      roleless = create(:user, customer: customer, password: "Password123!")
      sign_in roleless
      patch "/auth",
            params: { user: { first_name: "NoRole",
                              current_password: "Password123!" } }
      expect(response).to redirect_to("/#{customer.id}/member")
    end
  end
end

# ---------------------------------------------------------------------------
# Plan-limit enforcement on member self-registration
# ---------------------------------------------------------------------------
RSpec.describe "Authentication::Registrations — plan limit enforcement", type: :request do
  def accept_member_quota(cust, limit_value)
    plan = create(:billing_plan)
    snapshot = Billing::PlanChangePolicy.snapshot(plan: plan, currency: "USD")
    snapshot["limits"]["member"] = limit_value
    create(:billing_subscription, customer: cust, plan: plan, status: "active", plan_snapshot: snapshot)
  end

  def enable_countable_item!
    Billing::CountableItem.find_or_create_by!(key: "member") do |i|
      i.label    = "Members"
      i.enabled  = true
      i.position = 3
    end.tap { |i| i.update!(enabled: true) }
  end

  def ensure_auth_module_enabled(cust)
    auth_module = find_or_create_feature_module!("authentication")
    ensure_customer_feature_module(cust, auth_module, status: :active)
    cfm = FeatureModules::CustomerAssignment.find_by!(customer_id: cust.id, feature_module_id: auth_module.id)
    cfm.update!(configuration: { "allow_registration" => true }.to_json)
  end

  let(:customer) { create(:customer) }
  let(:valid_signup_params) do
    { user: { first_name: "New", last_name: "User", email: "newuser#{SecureRandom.hex(4)}@example.com",
              password: "Password123!", password_confirmation: "Password123!" } }
  end

  before do
    enable_countable_item!
    ensure_auth_module_enabled(customer)
  end


  # Provisioned admins do not consume the reserved-member quota.
  describe "with an accepted limit of 1 member" do
    before { accept_member_quota(customer, 1) }

    it "allows signing up when user count is below the limit" do
      # No member has consumed this accepted allowance yet.
      expect(Billing::Quota.for(customer).usage("member")).to eq(0)
      expect {
        post "/#{customer.id}/auth", params: valid_signup_params
      }.to change(Authentication::User, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "blocks sign-up when at the limit — returns 422 and does not persist the user" do
      create(:user, :member, customer: customer)
      expect(Billing::Quota.for(customer).usage("member")).to eq(1)

      expect {
        post "/#{customer.id}/auth", params: valid_signup_params
      }.not_to change(Authentication::User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Upgrade your plan")
    end

    it "enforces the accepted snapshot even when the current plan catalog permits more members" do
      subscription = Billing::Subscription.where(customer_id: customer.id).live.first!
      Billing::PlanLimit.create!(plan: subscription.plan, item_key: "member", limit_value: 10)
      create(:user, :member, customer: customer)

      expect(Billing::Quota.for(customer).limit("member")).to eq(1)
      expect {
        post "/#{customer.id}/auth", params: valid_signup_params
      }.not_to change(Authentication::User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(subscription.reload.plan_snapshot.fetch("limits").fetch("member")).to eq(1)
    end

    it "re-checks the member quota under a customer lock so a concurrent signup cannot slip past" do
      inserted = false
      expect(Billing::Quota.for(customer).usage("member")).to eq(0)
      allow_any_instance_of(Customer).to receive(:with_lock).and_wrap_original do |method, *args, **kwargs, &block|
        if method.receiver.id == customer.id && !inserted
          inserted = true
          create(:user, :member, customer: customer)
        end
        method.call(*args, **kwargs, &block)
      end

      email = valid_signup_params[:user][:email]
      expect {
        post "/#{customer.id}/auth", params: valid_signup_params
      }.not_to change { Authentication::User.exists?(email: email) }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "with an unlimited plan (-1)" do
    before { accept_member_quota(customer, Billing::PlanLimit::UNLIMITED) }

    it "allows signing up past the seeded-admin count" do
      # Even with multiple existing users, unlimited plan always allows
      create(:user, :member, customer: customer)

      expect {
        post "/#{customer.id}/auth", params: valid_signup_params
      }.to change(Authentication::User, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "platform owner bypass (customer 81721200)" do
    before { ensure_platform_customer }

    it "bypasses limits even with a zero-limit plan" do
      platform_customer = Customer.find(Authentication::User::PLATFORM_CUSTOMER_ID)
      accept_member_quota(platform_customer, 0)
      ensure_auth_module_enabled(platform_customer)

      expect {
        post "/#{platform_customer.id}/auth", params: valid_signup_params
      }.to change(Authentication::User, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "multi-tenant isolation" do
    let(:customer_b) { create(:customer) }

    before do
      accept_member_quota(customer, 1)
      create(:user, :member, customer: customer)
      accept_member_quota(customer_b, 5)
      ensure_auth_module_enabled(customer_b)
    end

    it "customer A at limit does not block customer B" do
      expect {
        post "/#{customer_b.id}/auth", params: valid_signup_params
      }.to change(Authentication::User, :count).by(1)

      expect(response).to have_http_status(:redirect)
    end
  end
end
