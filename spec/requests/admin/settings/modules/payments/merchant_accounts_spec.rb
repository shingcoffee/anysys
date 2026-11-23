# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/payments/merchant_accounts", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:admin_user)     { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin)          { admin_user }
  let(:other_admin)    { create(:user, :admin, customer: other_customer, password: "password123") }

  let(:index_url) { "/#{customer.id}/admin/settings/modules/payments/merchant_accounts" }

  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }

  let!(:account) do
    create(:payment_merchant_account, :alipay, customer: customer, merchant_id: "TEST_MERCHANT")
  end

  let(:edit_url)            { "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}/edit" }
  let(:test_connection_url) { "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}/test_connection" }

  # ===========================================================================
  # GET index — renders GatewayGalleryComponent
  # ===========================================================================
  describe "GET index" do
    let(:guard_path) { index_url }

    it_behaves_like "an admin-guarded GET"

    context "admin of the same customer" do
      before { sign_in admin_user }

      it "renders the empty-state card when no tenders are platform-available" do
        # All PlatformGateway rows default to available: false, so the gallery
        # receives an empty gateways array and renders the empty-state message.
        get index_url
        expect(response.body).to include(I18n.t("settings_modules.payments.empty_title"))
        Payments::Gateways.all.each do |gw|
          expect(response.body).not_to include(gw.display_name)
        end
      end

      it "renders only platform-available gateways (hides unavailable ones)" do
        # Make exactly one gateway available.
        available_gw   = Payments::Gateways.all.first
        unavailable_gw = Payments::Gateways.all.last
        Payments::PlatformGateway.for_provider(available_gw.key).update!(available: true)

        get index_url
        expect(response.body).to include(available_gw.display_name)

        # Only assert the unavailable gateway is absent when there is actually a
        # second distinct gateway registered (guard for single-gateway test envs).
        if available_gw.key != unavailable_gw.key
          expect(response.body).not_to include(unavailable_gw.display_name)
        end
      end

      it "shows enabled status for an available gateway's active account" do
        # Seed alipay as platform-available so the gallery renders it.
        Payments::PlatformGateway.for_provider("alipay").update!(available: true)
        get index_url
        expect(response.body).to include(I18n.t("common.status.enabled"))
      end

      it "does not expose another tenant's accounts in the gallery" do
        create(:payment_merchant_account, :wechat_pay, customer: other_customer,
               merchant_id: "OTHER_MERCHANT")
        get index_url
        expect(response.body).not_to include("OTHER_MERCHANT")
      end
    end

    context "admin of a different customer" do
      before { sign_in other_admin }

      it "is blocked from another tenant's index" do
        get index_url
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end

  # ===========================================================================
  # GET edit — renders GatewayConfigComponent
  # ===========================================================================
  describe "GET edit" do
    let(:guard_path) { edit_url }

    it_behaves_like "an admin-guarded GET"

    context "admin of the same customer" do
      before { sign_in admin_user }

      it "renders the GatewayConfigComponent (environment switcher present)" do
        get edit_url
        page = Capybara.string(response.body)
        expect(page).to have_css('[data-mode="sandbox"][data-active]', text: I18n.t("settings_modules.payments.environments.sandbox"))
        expect(page).to have_css('[data-mode="production"]', text: I18n.t("settings_modules.payments.environments.production"))
      end

      it "renders the currency select for GatewayConfigComponent" do
        get edit_url
        expect(response.body).to include("payment_merchant_account[default_currency]")
      end

      it "renders the Test saved connection button" do
        get edit_url
        expect(Capybara.string(response.body)).to have_button(I18n.t("settings_modules.payments.test_saved"))
      end

      # Regression: the form must be built with `model: account` so f.* fields
      # pre-fill. Without it merchant_id renders blank and a Save submits an empty
      # required field → 422 → the page never returns to the gallery.
      it "pre-fills the merchant_id field from the record" do
        get edit_url
        expect(Capybara.string(response.body)).to have_field("payment_merchant_account[merchant_id]", with: "TEST_MERCHANT")
      end

      it "does not reveal another tenant's account (cross-tenant 404)" do
        other_account = create(:payment_merchant_account, :alipay, customer: other_customer,
                                merchant_id: "LEAK")
        get "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{other_account.id}/edit"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "admin of a different customer" do
      before { sign_in other_admin }

      it "is blocked from another tenant's edit page" do
        get edit_url
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end

  # ===========================================================================
  # POST test_connection
  # ===========================================================================
  describe "POST test_connection" do
    let(:guard_path) { test_connection_url }

    it_behaves_like "an admin-guarded request", :post

    it "is redirected to sign-in (HTML) or gets 401 (JSON)" do
      post test_connection_url, as: :json
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
    end

    context "admin of the same customer" do
      before { sign_in admin_user }

      it "returns JSON with ok, message, and verified_at keys" do
        post test_connection_url, as: :json
        json = response.parsed_body
        expect(json).to include("ok", "message", "verified_at", "verified_at_label")
      end

      it "localizes verified_at_label instead of leaving clients to ISO-format UTC" do
        post test_connection_url, as: :json
        json = response.parsed_body
        parsed = Time.iso8601(json["verified_at"])
        expect(json["verified_at_label"]).to eq(I18n.l(parsed, format: :long))
        expect(json["verified_at_label"]).not_to include(" UTC")
      end

      it "localizes verified_at_label in zh-CN" do
        post test_connection_url, as: :json, params: { locale: "zh-CN" }
        json = response.parsed_body
        parsed = Time.iso8601(json["verified_at"])
        expect(json["verified_at_label"]).to eq(I18n.l(parsed, format: :long, locale: :"zh-CN"))
      end

      it "returns ok: true for the alipay account (Base#ping default)" do
        post test_connection_url, as: :json
        json = response.parsed_body
        expect(json["ok"]).to be(true)
      end
    end

    context "admin of a different customer" do
      before { sign_in other_admin }

      it "cannot access another tenant's account" do
        post test_connection_url, as: :json
        expect(response).to have_http_status(:forbidden)
          .or have_http_status(:redirect)
          .or have_http_status(:not_found)
      end
    end

    context "cross-tenant record fetch by same-tenant admin" do
      before { sign_in admin_user }

      let!(:other_account) do
        create(:payment_merchant_account, :alipay, customer: other_customer,
               merchant_id: "OTHER_MERCHANT")
      end

      it "returns 404 when account id belongs to another tenant" do
        post "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{other_account.id}/test_connection",
             as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context "Stripe gateway ping (WebMock)" do
      let!(:stripe_account) do
        create(:payment_merchant_account, customer: customer, merchant_id: "acct_test",
               credentials: {
                 secret_key: "sk_test_stub", publishable_key: "pk_test_stub",
                 webhook_signing_secret: "whsec_stub"
               })
      end

      let(:stripe_test_url) do
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{stripe_account.id}/test_connection"
      end

      before { sign_in admin_user }

      context "when Stripe responds successfully" do
        before do
          stub_request(:get, "https://api.stripe.com/v1/account")
            .to_return(status: 200, body: { id: "acct_test" }.to_json,
                       headers: { "Content-Type" => "application/json" })
        end

        it "returns ok: true with 200" do
          post stripe_test_url, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["ok"]).to be(true)
        end
      end

      context "when Stripe returns 401 (bad key)" do
        before do
          stub_request(:get, "https://api.stripe.com/v1/account")
            .to_return(status: 401,
                       body: { error: { message: "No such API key." } }.to_json,
                       headers: { "Content-Type" => "application/json" })
        end

        it "returns ok: false with 422" do
          post stripe_test_url, as: :json
          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json["ok"]).to be(false)
          expect(json["message"]).to be_present
        end
      end
    end
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "GET new — auth guards" do
    let(:guard_path) { "#{index_url}/new" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { index_url }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "GET new" do
    before { sign_in admin_user }

    it "redirects to index (accounts are auto-provisioned)" do
      get "#{index_url}/new"
      expect(response).to redirect_to(index_url)
    end
  end

  describe "POST create" do
    before { sign_in admin_user }

    it "creates a row for the current customer and redirects" do
      Payments::PlatformGateway.for_provider("wechat_pay").update!(available: true)

      post index_url, params: {
        payment_merchant_account: {
          provider: "wechat_pay", mode: "sandbox", merchant_id: "CREATE", status: "disabled"
        }
      }
      expect(response).to redirect_to(index_url)
      created = Payments::MerchantAccount.find_by(merchant_id: "CREATE")
      expect(created).to be_present
      expect(created.customer_id).to eq(customer.id)
    end

    it "slices selected-provider credentials on create and discards foreign-vendor keys" do
      Payments::PlatformGateway.for_provider("stripe").update!(available: true)

      post index_url, params: { payment_merchant_account: {
        provider: "stripe", mode: "sandbox", merchant_id: "CREATE-SLICE", status: "disabled",
        secret_key: "stripe-key", api_key_v3: "wechat-key"
      } }

      expect(response).to redirect_to(index_url)
      created = Payments::MerchantAccount.find_by!(merchant_id: "CREATE-SLICE")
      expect(created.customer_id).to eq(customer.id)
      expect(created.credential(:secret_key)).to eq("stripe-key")
      expect(created.credential(:api_key_v3)).to be_nil
    end

    it "rejects a non-scalar provider before registry lookup or account creation" do
      expect {
        post index_url, params: { payment_merchant_account: { provider: { key: "stripe" }, merchant_id: "BAD-SHAPE" } }
      }.not_to change(Payments::MerchantAccount, :count)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "does not create a row for a platform-unavailable provider" do
      Payments::PlatformGateway.for_provider("wechat_pay").update!(available: false)

      expect {
        post index_url, params: {
          payment_merchant_account: {
            provider: "wechat_pay", mode: "sandbox", merchant_id: "UNAVAILABLE", status: "active"
          }
        }
      }.not_to change(Payments::MerchantAccount, :count)
      expect(response).to redirect_to(index_url)
      expect(flash[:alert]).to eq(I18n.t("admin_settings.flash.merchant_accounts.not_platform_available"))
      expect(Payments::MerchantAccount.find_by(merchant_id: "UNAVAILABLE")).to be_nil
    end

    it "redirects to index with an alert when attrs are invalid" do
      post index_url, params: {
        payment_merchant_account: { provider: "", mode: "", merchant_id: "" }
      }
      expect(response).to redirect_to(index_url)
    end
  end

  # The inline enable/disable toggle (gateway_toggle_controller.js) PATCHes
  # update via fetch with Accept: application/json. It must get a 2xx — NOT a
  # 302 redirect (fetch re-issues the PATCH to the redirect target, which 404s).
  describe "PATCH update (JSON toggle)" do
    before { sign_in admin_user }

    it "returns a non-redirect 2xx for a JSON status toggle" do
      Payments::PlatformGateway.for_provider(account.provider).update!(available: true)
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { status: "disabled" } }, as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:no_content)
      expect(response).not_to have_http_status(:redirect)
      expect(account.reload.status).to eq("disabled")
    end

    it "rejects activating a platform-unavailable provider" do
      Payments::PlatformGateway.for_provider(account.provider).update!(available: false)
      account.update!(status: "disabled")

      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { status: "active" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("admin_settings.flash.merchant_accounts.not_platform_available")
      )
      expect(account.reload.status).to eq("disabled")
    end

    it "returns 404 when the Payments module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: payment_module
      ).update!(status: :suspended)
      account.update!(status: "disabled")

      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { status: "active" } }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(account.reload.status).to eq("disabled")
    end

    it "still redirects for an HTML form submission" do
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { status: "disabled" } }
      expect(response).to have_http_status(:redirect)
    end
  end

  # The config form ("Save changes") is a Turbo form. A successful save must
  # 303-redirect back to the gallery so Turbo performs a GET visit there.
  describe "PATCH update (HTML config-form save)" do
    before { sign_in admin_user }

    it "saves and redirects to the gallery with 303 See Other" do
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: {
              merchant_id: "NEW_MERCHANT", notify_url_override: "", default_currency: "cny"
            } }
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/merchant_accounts")
      expect(account.reload.merchant_id).to eq("NEW_MERCHANT")
    end

    it "ignores another gateway's credential keys even when the submitted provider is forged" do
      stripe = create(:payment_merchant_account, :stripe, customer: customer, merchant_id: "credential-slice")
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{stripe.id}",
            params: { payment_merchant_account: { provider: "wechat_pay", api_key_v3: "foreign-key",
                                                 secret_key: "selected-vendor-key", status: "disabled" } }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(stripe.reload.provider).to eq("stripe")
      expect(stripe.credential(:secret_key)).to eq("selected-vendor-key")
      expect(stripe.credential(:api_key_v3)).to be_nil
    end

    it "returns 422 instead of 500 when merchant_id collides with another tenant" do
      create(:payment_merchant_account, :alipay, customer: other_customer,
             merchant_id: "TAKEN_MERCHANT")

      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { merchant_id: "TAKEN_MERCHANT" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.merchant_id).to eq("TEST_MERCHANT")
    end

    it "ignores attempts to change provider or mode on an existing row" do
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: {
              provider: "stripe", mode: "production", merchant_id: "X"
            } }
      account.reload
      expect(account.provider).to eq("alipay")
      expect(account.mode).to eq("sandbox")
    end

    it "re-renders the config form when status is invalid" do
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: { status: "not_a_real_status" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Capybara.string(response.body)).to have_css('[data-mode="sandbox"][data-active]', text: I18n.t("settings_modules.payments.environments.sandbox"))
    end

    it "preserves existing encrypted secrets when the form submits blanks" do
      account.write_credentials(
        private_key_pem: "original-private-key",
        platform_public_key_pem: "original-public-key"
      )
      account.save!

      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{account.id}",
            params: { payment_merchant_account: {
              status: "disabled",
              private_key_pem: "", platform_public_key_pem: ""
            } }
      expect(response).to redirect_to(index_url)
      account.reload
      expect(account.status).to eq("disabled")
      expect(account.credential(:private_key_pem)).to eq("original-private-key")
      expect(account.credential(:platform_public_key_pem)).to eq("original-public-key")
    end

    it "rotates a secret when a new value is submitted" do
      wechat = create(:payment_merchant_account, customer: customer, provider: "wechat_pay",
                      merchant_id: "ROT", credentials: { api_key_v3: "old-key" })
      patch "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{wechat.id}",
            params: { payment_merchant_account: { api_key_v3: "new-key" } }
      expect(wechat.reload.credential(:api_key_v3)).to eq("new-key")
    end
  end
end
