# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::GatewayConfigComponent, type: :component do
  let(:account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "sandbox", merchant_id: "M1", status: "active"
    )
    acc.id = 1
    acc.instance_variable_set(:@new_record, false)
    acc
  end

  let(:production_account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "production", merchant_id: "M1", status: "disabled"
    )
    acc.id = 2
    acc.instance_variable_set(:@new_record, false)
    acc
  end

  let(:accounts_by_mode) { { "sandbox" => account, "production" => production_account } }

  let(:component) { described_class.new(account: account) }

  let(:stub_helpers) do
    double("helpers",
      params: { customer_id: "12345678" },
      admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1",
      edit_admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/2/edit",
      admin_settings_modules_payments_merchant_accounts_path: "/12345678/admin/settings/modules/payments/merchant_accounts",
      test_connection_admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1/test_connection",
      protect_against_forgery?: false
    )
  end

  before do
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
    allow_any_instance_of(Payments::Admin::CredentialFieldsComponent).to receive(:helpers).and_return(stub_helpers)
  end

  # Renders the config form for the sandbox account, plus any extra props (e.g. accounts_by_mode).
  def render_config(**opts)
    render_inline(described_class.new(account: account, **opts))
  end

  describe "#initialize" do
    it "exposes the account it was built with" do
      expect(component.account).to eq(account)
    end
  end

  describe "#gateway" do
    it "returns the gateway class for the account's provider" do
      expect(component.gateway).to eq(Payments::Gateways.for("alipay"))
    end
  end

  describe "#form_url" do
    it "returns the PATCH URL for persisted account" do
      expect(component.form_url).to include("merchant_accounts/1")
    end
  end

  describe "#currency_options" do
    it "returns a non-empty array of supported currencies for the gateway" do
      options = component.currency_options
      expect(options).to be_an(Array)
      expect(options).not_to be_empty
    end
  end

  describe "#test_connection_url" do
    it "returns the test_connection path" do
      expect(component.test_connection_url).to include("test_connection")
    end
  end

  describe "#cancel_url" do
    it "returns the index path" do
      expect(component.cancel_url).to include("merchant_accounts")
    end
  end

  describe "rendering" do
    it "renders a form element" do
      render_config
      expect(page).to have_css("form")
    end

    it "renders both Test and Live environment links" do
      render_config(accounts_by_mode: accounts_by_mode)
      expect(page).to have_text("Test")
      expect(page).to have_text("Live")
    end

    it "marks the current mode tab as active (non-link)" do
      render_config(accounts_by_mode: accounts_by_mode)
      # sandbox account — sandbox tab is the active, non-link span
      expect(page).to have_css("[data-mode='sandbox'][data-active]")
      expect(page).not_to have_css("a[data-mode='sandbox']")
    end

    it "links the other mode tab to that row's edit page (not ?mode=)" do
      render_config(accounts_by_mode: accounts_by_mode)
      link = page.find("a[data-mode='production']")
      expect(link[:href]).to eq("/12345678/admin/settings/modules/payments/merchant_accounts/2/edit")
      expect(link[:href]).not_to include("mode=")
    end

    it "does not render the in-form gateway status toggle (lives on the gallery card)" do
      render_config(accounts_by_mode: accounts_by_mode)
      expect(page).not_to have_css("[data-controller='payments--gateway-toggle']")
      expect(page).not_to have_text("Gateway status")
    end

    it "renders the credential fields section" do
      render_config
      # Alipay PEM keys are multi-line, so they render as textareas (not single-line inputs).
      expect(page).to have_css("textarea")
    end

    it "renders the merchant_id field" do
      render_config
      expect(page).to have_field("payment_merchant_account[merchant_id]")
    end

    it "renders the notify_url_override field" do
      render_config
      expect(page).to have_field("payment_merchant_account[notify_url_override]", visible: :all)
    end

    it "renders the default_currency select" do
      render_config
      expect(page).to have_select("payment_merchant_account[default_currency]")
    end

    it "renders the Test connection button with data-action" do
      render_config
      expect(page).to have_button("Test saved connection")
      expect(page).to have_text("This test uses saved credentials. Save your changes first to test newly entered values.")
      expect(page).to have_css("[data-payments--gateway-config-verified-label-value='Saved connection verified']")
    end

    it "renders the gateway-config controller with test URL data value" do
      render_config
      expect(page).to have_css("[data-controller='payments--gateway-config']")
      expect(page).to have_css("[data-payments--gateway-config-test-url-value]")
    end

    it "renders the result target area (hidden by default)" do
      render_config
      expect(page).to have_css("[data-payments--gateway-config-target='result']")
    end

    it "renders Cancel and Save changes buttons" do
      render_config
      expect(page).to have_link("Cancel")
      expect(page).to have_button("Save changes")
    end

    it "renders a readable settings form with a single page title and parent breadcrumb" do
      render_config
      expect(page).to have_css(".w-full.max-w-3xl")
      expect(page).to have_css("h1", text: account.gateway_class.display_name, count: 1)
      expect(page).to have_link("Payment providers", href: "/12345678/admin/settings/modules/payments/merchant_accounts")
      expect(page).to have_css("form[action='/12345678/admin/settings/modules/payments/merchant_accounts/1'] input[name='_method'][value='patch']", visible: :all)
    end

    it "keeps provisioning placeholders out of the merchant field" do
      account.customer_id = 12345678
      account.merchant_id = "unset-alipay-sandbox-12345678"
      render_config
      expect(page.find_field("payment_merchant_account[merchant_id]").value).to be_blank
      expect(page).to have_text("Not configured")
      expect(page).not_to have_text(account.merchant_id)
    end

    it "preserves real identifiers that happen to start with unset" do
      account.merchant_id = "unset-real-account"
      render_config
      expect(page).to have_field("payment_merchant_account[merchant_id]", with: "unset-real-account")
    end

    it "shows validation feedback and preserves entered values" do
      account.errors.add(:merchant_id, "is already in use")
      render_config
      expect(page).to have_text("is already in use")
      expect(page).to have_field("payment_merchant_account[merchant_id]", with: "M1")
    end
  end
end
