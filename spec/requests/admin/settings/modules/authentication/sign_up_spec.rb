# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Settings::Modules::Authentication::SignUp", type: :request do
  include_context "as admin"

  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  let(:assignment) do
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: auth_module)
  end

  let(:show_path) { admin_settings_modules_authentication_sign_up_path(customer.id) }
  let(:guard_path) { show_path }

  it_behaves_like "an admin-guarded GET"

  # A same-tenant admin belonging to a *different* customer (cross-tenant probe).
  let(:other_admin) { create(:user, :admin, customer: create(:customer)) }

  # Directly set the tenant's persisted allow_registration flag.
  def set_registration(enabled)
    assignment.update!(configuration: { "allow_registration" => enabled }.to_json)
  end

  # ---------------------------------------------------------------------------
  # PATCH /:customer_id/admin/settings/modules/authentication/sign_up
  # ---------------------------------------------------------------------------
  describe "PATCH update" do
    context "enabling self-sign-up" do
      before { set_registration(false) }

      it "persists allow_registration = true" do
        patch show_path,
              params: { setting: { enabled: "1" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_registration"]).to be(true)
      end

      it "keeps sibling authentication keys on the same configuration blob" do
        assignment.update!(configuration: {
          "allow_registration" => false,
          "allow_password_reset" => true
        }.to_json)

        patch show_path, params: { setting: { enabled: "1" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_registration"]).to be(true)
        expect(config["allow_password_reset"]).to be(true)
      end

      it "redirects back to the show page with a notice" do
        patch show_path,
              params: { setting: { enabled: "1" } }
        expect(response).to redirect_to(show_path)
        follow_redirect!
        expect(response.body).to include("enabled")
      end
    end

    context "disabling self-sign-up" do
      before { set_registration(true) }

      it "persists allow_registration = false" do
        patch show_path,
              params: { setting: { enabled: "0" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_registration"]).to be(false)
      end

      it "redirects back to the show page with a notice" do
        patch show_path,
              params: { setting: { enabled: "0" } }
        expect(response).to redirect_to(show_path)
        follow_redirect!
        expect(response.body).to include("disabled")
      end
    end

    it "treats a blank 'enabled' param as a falsy value (signup becomes disabled)" do
      set_registration(true)
      patch show_path,
            params: { setting: { enabled: "" } }

      # ActiveModel::Type::Boolean casts "" to nil, which is stored as null in JSON.
      # Authentication::Settings#signup_enabled? treats nil as the default (false),
      # so sign-up is effectively disabled.
      config = JSON.parse(assignment.reload.configuration)
      expect(config["allow_registration"]).to be_nil
      expect(::Authentication::Settings.for(customer.id).signup_enabled?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization
  # ---------------------------------------------------------------------------
  describe "authorization" do
    it_behaves_like "an admin-guarded request", :patch

    it "allows the platform owner to access another customer's settings" do
      sign_out admin
      sign_in find_or_create_platform_owner
      get show_path
      expect(response).to have_http_status(:ok)
    end

    # Cross-tenant isolation: admin A cannot touch customer B's registration toggle
    it "prevents a cross-tenant admin from reading another customer's sign-up setting" do
      sign_out admin
      sign_in other_admin
      get show_path
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "prevents a cross-tenant admin from updating another customer's sign-up setting" do
      sign_out admin
      sign_in other_admin
      patch show_path,
            params: { setting: { enabled: "1" } }
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end
end
