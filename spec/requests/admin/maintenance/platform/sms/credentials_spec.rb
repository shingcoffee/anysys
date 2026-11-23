# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Sms::Credentials", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@sc.test", password: "password123") }

  def index_path(cid = platform_customer.id, provider: nil)
    admin_maintenance_platform_module_settings_sms_credentials_path(
      cid, **{ provider: provider }.compact
    )
  end

  def new_path(cid = platform_customer.id)
    new_admin_maintenance_platform_module_settings_sms_credential_path(cid)
  end

  def edit_path(record, cid = platform_customer.id)
    edit_admin_maintenance_platform_module_settings_sms_credential_path(cid, record)
  end

  def update_path(record, cid = platform_customer.id)
    admin_maintenance_platform_module_settings_sms_credential_path(cid, record)
  end

  let(:sms_valid_attrs) do
    { provider: "aliyun", mode: "sandbox", access_key_id: "AKID_TEST",
      access_key_secret: "AKSECRET_TEST", status: "disabled" }
  end

  let!(:existing) { create(:sms_credential, mode: "production", status: "disabled") }

  let(:guard_path) { index_path }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :post

  describe "GET new — auth guards" do
    let(:guard_path) { new_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_path(existing) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { update_path(existing) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "PATCH delivery — auth guards" do
    let(:guard_path) { delivery_admin_maintenance_platform_module_settings_sms_credentials_path(platform_customer.id) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "regular admin (non-owner)" do
    before { sign_in admin_user }

    it "is denied on index (own tenant path)" do
      get index_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Platform owner — happy paths
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "renders the index" do
      get index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-module-settings-nav")
      expect(response.body).to include(I18n.t("maint_platform.sms.platform_settings.delivery_section"))
      expect(response.body).to include(I18n.t("maint_platform.sms.platform_settings.vendor_section"))
      expect(response.body).not_to include(I18n.t("maint_platform.sms.credentials.index.search_placeholder"))
    end

    it "renders the new and edit forms" do
      get new_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-module-settings-shell="true"')
      expect(response.body).to match(/data-section-nav-tab="providers"[^>]*aria-current="page"/)
      expect(response.body).to include('data-provider-workspace="true"')
      expect(response.body).to include("sms_credential[access_key_id]")

      get edit_path(existing)
      expect(response).to have_http_status(:ok)
    end

    it "redirects new to edit when that vendor environment already exists" do
      get new_path, params: { provider: "aliyun", mode: "production" }
      expect(response).to redirect_to(edit_path(existing))
    end

    describe "create" do
      it "creates a credential and redirects with the created flash" do
        expect do
          post index_path, params: { sms_credential: sms_valid_attrs }
        end.to change(::Sms::Credential, :count).by(1)

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(index_path(provider: "aliyun"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.sms_credentials.created"))
      end

      it "re-renders new with 422 on validation failure" do
        expect do
          post index_path, params: { sms_credential: sms_valid_attrs.merge(access_key_id: "") }
        end.not_to change(::Sms::Credential, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "creates a twilio credential with its own config fields" do
        post index_path, params: {
          sms_credential: {
            provider: "twilio", mode: "sandbox", access_key_id: "AC_TEST", access_key_secret: "AUTH_TOKEN",
            messaging_service_sid: "MG1", status: "active"
          }
        }
        expect(response).to redirect_to(index_path(provider: "twilio"))
        cred = Sms::Credential.find_by(mode: "sandbox", provider: "twilio")
        expect(cred).to be_present
        expect(cred.config).to eq("messaging_service_sid" => "MG1")
      end
    end

    describe "update" do
      it "updates the credential and redirects with the updated flash" do
        patch update_path(existing), params: { sms_credential: sms_valid_attrs.merge(mode: "production", access_key_id: "AKID_NEW") }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(index_path(provider: "aliyun"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.sms_credentials.updated"))
        expect(existing.reload.access_key_id).to eq("AKID_NEW")
      end

      it "re-renders edit with 422 on validation failure" do
        patch update_path(existing), params: { sms_credential: sms_valid_attrs.merge(mode: "production", access_key_id: "") }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(existing.reload.access_key_id).to eq("AKID_TEST")
      end

      it "keeps access_key_secret when submitted blank" do
        existing.update!(access_key_secret: "original-secret")
        patch update_path(existing), params: { sms_credential: { status: "disabled", access_key_secret: "" } }
        expect(existing.reload.access_key_secret).to eq("original-secret")
      end

      it "rotates access_key_secret when a new value is submitted" do
        existing.update!(access_key_secret: "old")
        patch update_path(existing), params: { sms_credential: { access_key_secret: "new" } }
        expect(existing.reload.access_key_secret).to eq("new")
      end

      it "removes a config key submitted blank" do
        existing.update!(config: { "sign_name" => "TestCo", "region" => "cn-hangzhou" })
        patch update_path(existing), params: { sms_credential: { region: "" } }
        expect(existing.reload.config).to eq("sign_name" => "TestCo")
      end
    end

    describe "PATCH delivery" do
      it "assigns the live vendor and redirects" do
        patch delivery_admin_maintenance_platform_module_settings_sms_credentials_path(platform_customer.id),
              params: { sandbox_provider: "", production_provider: "aliyun", provider: "aliyun" }

        expect(response).to redirect_to(index_path(provider: "aliyun"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.sms_credentials.delivery_updated"))
        expect(existing.reload.status).to eq("active")
      end
    end
  end
end
