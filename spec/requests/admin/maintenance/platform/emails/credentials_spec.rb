# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Emails::Credentials", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@ec.test", password: "password123") }

  def index_path(cid = platform_customer.id, provider: nil)
    admin_maintenance_platform_module_settings_email_credentials_path(
      cid, **{ provider: provider }.compact
    )
  end

  def new_path(cid = platform_customer.id)
    new_admin_maintenance_platform_module_settings_email_credential_path(cid)
  end

  def edit_path(record, cid = platform_customer.id)
    edit_admin_maintenance_platform_module_settings_email_credential_path(cid, record)
  end

  def update_path(record, cid = platform_customer.id)
    admin_maintenance_platform_module_settings_email_credential_path(cid, record)
  end

  # A persisted, valid (disabled → skips the "configured when active" guard) SMTP
  # credential to drive edit/update.
  let(:smtp_valid_attrs) do
    { provider: "smtp", host: "smtp.example.com", port: "587", username: "user@example.com",
      password: "secret123", authentication: "plain", enable_starttls: "1", mode: "sandbox", status: "disabled" }
  end

  let!(:existing) { ::Emails::Credential.create!(smtp_valid_attrs.merge(mode: "production")) }

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
    let(:guard_path) { delivery_admin_maintenance_platform_module_settings_email_credentials_path(platform_customer.id) }

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
      expect(response.body).to include(I18n.t("maint_platform.emails.platform_settings.delivery_section"))
      expect(response.body).to include(I18n.t("maint_platform.emails.platform_settings.vendor_section"))
      expect(response.body).not_to include(I18n.t("maint_platform.emails.credentials.index.search_placeholder"))
    end

    it "renders the new and edit forms" do
      get new_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-module-settings-shell="true"')
      expect(response.body).to match(/data-section-nav-tab="providers"[^>]*aria-current="page"/)
      expect(response.body).to include('data-provider-workspace="true"')
      expect(response.body).to include("emails_credential[host]")

      get edit_path(existing)
      expect(response).to have_http_status(:ok)
    end

    it "localizes SMTP authentication options on the new form in zh-CN" do
      get new_path, params: { locale: "zh-CN" }
      expect(response.body).to include("CRAM-MD5")
      expect(response.body).not_to include(">CRAM_MD5<")
    end

    it "redirects new to edit when that vendor environment already exists" do
      get new_path, params: { provider: "smtp", mode: "production" }
      expect(response).to redirect_to(edit_path(existing))
    end

    describe "create" do
      it "creates a credential and redirects with the created flash" do
        expect do
          post index_path, params: { emails_credential: smtp_valid_attrs }
        end.to change(::Emails::Credential, :count).by(1)

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(index_path(provider: "smtp"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.emails_credentials.created"))
      end

      it "re-renders new with 422 on validation failure" do
        expect do
          post index_path, params: { emails_credential: smtp_valid_attrs.merge(password: "") }
        end.not_to change(::Emails::Credential, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "update" do
      it "updates the credential and redirects with the updated flash" do
        patch update_path(existing), params: { emails_credential: smtp_valid_attrs.merge(mode: "production", host: "smtp2.example.com") }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(index_path(provider: "smtp"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.emails_credentials.updated"))
        expect(existing.reload.host).to eq("smtp2.example.com")
      end

      it "re-renders edit with 422 on validation failure" do
        patch update_path(existing), params: { emails_credential: smtp_valid_attrs.merge(mode: "production", host: "") }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(existing.reload.host).to eq("smtp.example.com")
      end

      it "keeps the password when submitted blank" do
        existing.update!(password: "original-secret")
        patch update_path(existing), params: { emails_credential: { status: "disabled", password: "" } }
        expect(existing.reload.password).to eq("original-secret")
      end

      it "keeps the dkim_private_key when submitted blank" do
        key = OpenSSL::PKey::RSA.new(2048).to_pem
        existing.update!(dkim_enabled: true, dkim_domain: "example.com", dkim_selector: "mail",
                         dkim_private_key: key)
        patch update_path(existing), params: { emails_credential: { status: "active", dkim_private_key: "" } }
        expect(existing.reload.dkim_private_key).to eq(key)
      end

      it "rotates the password when a new value is submitted" do
        existing.update!(password: "old-secret")
        patch update_path(existing), params: { emails_credential: { password: "new-secret" } }
        expect(existing.reload.password).to eq("new-secret")
      end
    end

    describe "PATCH delivery" do
      it "assigns the live vendor and redirects" do
        patch delivery_admin_maintenance_platform_module_settings_email_credentials_path(platform_customer.id),
              params: { sandbox_provider: "", production_provider: "smtp", provider: "smtp" }

        expect(response).to redirect_to(index_path(provider: "smtp"))
        expect(flash[:notice]).to eq(I18n.t("maint_platform.flash.emails_credentials.delivery_updated"))
        expect(existing.reload.status).to eq("active")
      end
    end
  end
end
