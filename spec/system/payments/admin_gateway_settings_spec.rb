# frozen_string_literal: true

require "rails_helper"

# QA gap-fill: System spec — admin gateway gallery → configure → test-connection.
#
# Coverage rationale:
# - spec/requests/admin/settings/modules/payments/merchant_accounts_spec.rb and
#   spec/requests/payments/admin/merchant_accounts_spec.rb cover controller
#   actions at the HTTP layer. Neither exercises the full browser flow with
#   page navigation (gallery → configure → submit form → test connection feedback).
# - This spec drives Capybara through the multi-step admin UI to verify that the
#   ViewComponents compose correctly in the real page and that the Stimulus
#   test-connection button wires up the correct form action. The JS interaction
#   itself is not exercised (rack_test driver; no JS). The form submission is.
# - "BUG: Stripe webhook route missing" is not exercised here; that is in
#   spec/requests/payments/webhooks_stripe_spec.rb.

RSpec.describe "Admin gateway settings flow", type: :system do
  # ViewComponent::SystemTestHelpers (mixed into :system groups) shadows
  # Capybara's `page` helper — restore the session-backed version here.
  def page
    Capybara.current_session
  end

  let(:customer)   { create(:customer) }
  let(:admin_user) { create(:user, :admin, customer: customer, password: "password123") }

  before do
    Current.customer = customer
    enable_module!("payment", customer, name: "Payments")
    # The gallery only renders gateways the platform owner has made available,
    # so flip all registered gateways on for this tenant's gallery.
    Payments::Gateways.all.each do |gw|
      Payments::PlatformGateway.for_provider(gw.key).update!(available: true)
    end
    # Provision an Alipay sandbox account so the gallery has at least one tile.
    @alipay_account = create(:payment_merchant_account, :alipay, customer: customer,
                              merchant_id: "GALLERY_TEST")
    sign_in admin_user
  end

  after { Current.customer = nil }

  # ---------------------------------------------------------------------------
  # 1. Gallery renders all registered gateways
  # ---------------------------------------------------------------------------
  describe "gateway gallery (index)" do
    it "shows a tile for every registered gateway" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"

      Payments::Gateways.all.each do |gw|
        expect(page).to have_text(gw.display_name)
      end
    end

    it "shows Enabled for the provisioned Alipay account" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      within("article", text: "Alipay") do
        expect(page).to have_text("Enabled")
        expect(page).to have_css("input[type='checkbox'][checked]")
      end
    end

    it "shows a Configure link for each gateway" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      expect(page).to have_link("Configure", minimum: 1)
    end

    it "does not show another tenant's merchant_id in the gallery" do
      other = create(:customer)
      Current.customer = other
      create(:payment_merchant_account, :wechat_pay, customer: other,
             merchant_id: "SHOULD_NOT_APPEAR")
      Current.customer = customer

      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      expect(page).not_to have_text("SHOULD_NOT_APPEAR")
    end

    it "anonymous visitor is redirected to sign-in" do
      page.driver.browser.clear_cookies rescue nil
      sign_out admin_user
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      expect(page).to have_current_path(%r{sign_in})
    end

    it "cross-tenant admin is blocked from another tenant's gallery" do
      other_customer = create(:customer)
      other_admin    = create(:user, :admin, customer: other_customer)
      sign_out admin_user
      sign_in other_admin

      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      # RouteAuthorization redirects cross-tenant admins; must not see the gallery.
      expect(page).not_to have_current_path(
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Configure page (edit) renders the GatewayConfigComponent
  # ---------------------------------------------------------------------------
  describe "gateway configure page (edit)" do
    it "navigates from gallery Configure link to the merchant account detail path" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      # GatewayCardComponent#configure_url builds the `edit` route (/:id/edit) for
      # gateways that already have a persisted MerchantAccount, and falls back to
      # the `index` path otherwise. Only Alipay is provisioned in this spec, so we
      # click *its* Configure link specifically — clicking whichever card happens
      # to sort first is non-deterministic, since gateway registry order is not
      # guaranteed (it depends on the load order of the vendor files).
      page.find(
        "a[href$='/merchant_accounts/#{@alipay_account.id}/edit']",
        text: "Configure"
      ).click
      expect(page).to have_current_path(
        %r{/#{customer.id}/admin/settings/modules/payments/merchant_accounts/\d+}
      )
    end

    it "config form shows environment switcher (Test / Live)" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"
      expect(page).to have_css("[data-mode='sandbox'][aria-current='page']", text: "Test")
      expect(page).to have_css("[data-mode='production']", text: "Live")
    end

    it "config form renders the Test saved connection button" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"
      expect(page).to have_button("Test saved connection")
    end

    it "config form renders the default_currency select" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"
      expect(page).to have_field("payment_merchant_account[default_currency]")
    end

    it "does not render another tenant's config page (404)" do
      other = create(:customer)
      other_acct = create(:payment_merchant_account, :wechat_pay, customer: other,
                           merchant_id: "X_TENANT")

      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{other_acct.id}/edit"
      expect(page.status_code).to eq(404)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Update merchant account via form submission
  # ---------------------------------------------------------------------------
  describe "updating a merchant account (PATCH)" do
    it "saves edited account details through the form and returns to the gallery" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"

      fill_in "payment_merchant_account[merchant_id]", with: "UPDATED_GALLERY_TEST"
      page.click_button "Save changes"

      expect(@alipay_account.reload.merchant_id).to eq("UPDATED_GALLERY_TEST")
      expect(@alipay_account.status).to eq("active")
      expect(page).to have_current_path("/#{customer.id}/admin/settings/modules/payments/merchant_accounts")
      expect(page).to have_css("h1", text: "Payment providers", exact_text: true)
    end

    it "preserves encrypted credentials when blank fields are submitted" do
      @alipay_account.write_credentials(private_key_pem: "KEEP_THIS_VALUE")
      @alipay_account.save!

      page.driver.submit :patch,
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}",
        { "payment_merchant_account" => { "private_key_pem" => "", "status" => "active" } }

      expect(@alipay_account.reload.credential(:private_key_pem)).to eq("KEEP_THIS_VALUE")
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Test connection — Alipay (Base#ping, always succeeds)
  # ---------------------------------------------------------------------------
  describe "test connection (POST test_connection)" do
    it "returns ok: true for the Alipay sandbox account" do
      # Rack-test can't handle Stimulus JS so we exercise the endpoint directly;
      # the system spec verifies the button is rendered and the endpoint exists.
      page.driver.submit :post,
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/test_connection",
        {}
      expect(page.status_code).to eq(200)
      result = JSON.parse(page.body) rescue {}
      expect(result["ok"]).to be(true)
    end

    it "returns 404 when test_connection targets another tenant's account" do
      other = create(:customer)
      other_acct = create(:payment_merchant_account, :alipay, customer: other,
                           merchant_id: "CROSS_TENANT")
      page.driver.submit :post,
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{other_acct.id}/test_connection",
        {}
      expect(page.status_code).to eq(404)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Stripe gateway: test connection with WebMock
  # ---------------------------------------------------------------------------
  describe "test connection for Stripe account (HTTP stubbed)" do
    let!(:stripe_account) do
      create(:payment_merchant_account, customer: customer, merchant_id: "acct_sys_test",
             credentials: {
               secret_key:             "sk_test_sysgallery",
               publishable_key:        "pk_test_sysgallery",
               webhook_signing_secret: "whsec_sysgallery"
             })
    end

    context "when Stripe responds successfully" do
      before do
        stub_request(:get, "https://api.stripe.com/v1/account")
          .to_return(
            status:  200,
            body:    { id: "acct_sys_test" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns ok: true for the Stripe sandbox account" do
        page.driver.submit :post,
          "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{stripe_account.id}/test_connection",
          {}
        expect(page.status_code).to eq(200)
        result = JSON.parse(page.body)
        expect(result["ok"]).to be(true)
      end
    end

    context "when Stripe returns 401 (bad credentials)" do
      before do
        stub_request(:get, "https://api.stripe.com/v1/account")
          .to_return(
            status:  401,
            body:    { error: { message: "Invalid API Key provided." } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns HTTP 422 with ok: false" do
        page.driver.submit :post,
          "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{stripe_account.id}/test_connection",
          {}
        expect(page.status_code).to eq(422)
        result = JSON.parse(page.body)
        expect(result["ok"]).to be(false)
        expect(result["message"]).to be_present
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Authorization matrix — member cannot access any admin settings URL
  # ---------------------------------------------------------------------------
  describe "member user is blocked from all admin payment settings URLs" do
    let(:member_user) { create(:user, :member, customer: customer) }

    before do
      sign_out admin_user
      sign_in member_user
    end

    it "GET index is forbidden for a member" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      expect(page).not_to have_current_path(
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts"
      )
    end

    it "GET edit is forbidden for a member" do
      page.visit "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"
      expect(page).not_to have_current_path(
        "/#{customer.id}/admin/settings/modules/payments/merchant_accounts/#{@alipay_account.id}/edit"
      )
    end
  end
end
