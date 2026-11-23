# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::GatewayCardComponent, type: :component do
  let(:gateway) { Payments::Gateways.for("alipay") }
  let(:active_account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "sandbox", merchant_id: "M1", status: "active"
    )
    acc.id = 1
    acc.instance_variable_set(:@new_record, false)
    acc
  end
  let(:disabled_account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "sandbox", merchant_id: "M2", status: "disabled"
    )
    acc.id = 2
    acc.instance_variable_set(:@new_record, false)
    acc
  end

  let(:stub_helpers) do
    double("helpers",
      params: { customer_id: "12345678" },
      admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1",
      edit_admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1/edit",
      admin_settings_modules_payments_merchant_accounts_path: "/12345678/admin/settings/modules/payments/merchant_accounts",
      admin_settings_modules_payments_default_gateway_path: "/12345678/admin/settings/modules/payments/default_gateway",
      protect_against_forgery?: false
    )
  end

  before do
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_card(account:, **opts)
    described_class.new(gateway: gateway, account: account, **opts)
  end

  def render_card(account:, **opts)
    render_inline(build_card(account: account, **opts))
  end

  describe "#initialize" do
    it "accepts gateway and account" do
      component = build_card(account: active_account)
      expect(component.gateway).to eq(gateway)
      expect(component.account).to eq(active_account)
    end

    it "accepts nil account (gateway seeded but not yet provisioned)" do
      component = build_card(account: nil)
      expect(component.account).to be_nil
    end
  end

  describe "#gateway_state" do
    it "returns :active when account is enabled" do
      component = build_card(account: active_account)
      expect(component.gateway_state).to eq(:active)
    end

    it "returns :disabled when account exists but is disabled" do
      component = build_card(account: disabled_account)
      expect(component.gateway_state).to eq(:disabled)
    end

    it "returns :needs_setup when account is nil" do
      component = build_card(account: nil)
      expect(component.gateway_state).to eq(:needs_setup)
    end
  end

  describe "#flow_labels" do
    it "returns display labels for supported flows" do
      component = build_card(account: active_account)
      labels = component.flow_labels
      expect(labels).to be_an(Array)
      expect(labels).not_to be_empty
    end
  end

  describe "#configure_url" do
    it "returns the edit path for a persisted account" do
      component = build_card(account: active_account)
      allow(component).to receive(:helpers).and_return(stub_helpers)
      expect(component.configure_url).to include("/edit")
    end

    it "returns the index/gallery path when account is nil" do
      component = build_card(account: nil)
      allow(component).to receive(:helpers).and_return(stub_helpers)
      expect(component.configure_url).to eq(
        "/12345678/admin/settings/modules/payments/merchant_accounts"
      )
    end
  end

  describe "#toggle_url" do
    it "returns the base member path (for PATCH update) for a persisted account" do
      component = build_card(account: active_account)
      allow(component).to receive(:helpers).and_return(stub_helpers)
      expect(component.toggle_url).not_to include("/edit")
      expect(component.toggle_url).to eq(
        "/12345678/admin/settings/modules/payments/merchant_accounts/1"
      )
    end

    it "returns nil when account is nil" do
      component = build_card(account: nil)
      expect(component.toggle_url).to be_nil
    end
  end

  describe "#toggle_enabled?" do
    it "is true when account is active" do
      component = build_card(account: active_account)
      expect(component.toggle_enabled?).to be(true)
    end

    it "is false when account is disabled" do
      component = build_card(account: disabled_account)
      expect(component.toggle_enabled?).to be(false)
    end

    it "is false when account is nil" do
      component = build_card(account: nil)
      expect(component.toggle_enabled?).to be(false)
    end
  end

  describe "rendering" do
    it "renders the gateway display name" do
      render_card(account: active_account)
      expect(page).to have_text(gateway.display_name)
    end

    it "distinguishes enablement from incomplete credentials" do
      render_card(account: active_account)
      expect(page).to have_text("Enabled")
      expect(page).to have_text("Not configured")
      expect(page).not_to have_text("Credentials saved")
    end

    it "renders Disabled state when account is disabled" do
      render_card(account: disabled_account)
      expect(page).to have_text("Disabled")
    end

    it "explains a missing account without implying a working configure action" do
      render_card(account: nil)
      expect(page).to have_text("This provider has no account configured for your organization.")
      expect(page).not_to have_css("input[type=checkbox]")
    end

    it "renders the mode badge when account is present" do
      render_card(account: active_account)
      expect(page).to have_text("Test")
    end

    it "renders a Configure link" do
      render_card(account: active_account)
      expect(page).to have_link("Configure")
    end

    it "Configure link points at the edit path (not show)" do
      render_card(account: active_account)
      expect(page).to have_link("Configure →",
        href: "/12345678/admin/settings/modules/payments/merchant_accounts/1/edit")
    end

    it "does not link Configure back to the same page for a missing account" do
      render_card(account: nil)
      expect(page).not_to have_link("Configure →")
    end

    it "toggle data-url targets the update (PATCH) path, not the edit path" do
      render_card(account: active_account)
      toggle_wrapper = page.find("[data-controller='payments--gateway-toggle']")
      expect(toggle_wrapper["data-payments--gateway-toggle-url-value"]).to eq(
        "/12345678/admin/settings/modules/payments/merchant_accounts/1"
      )
    end

    it "renders the gateway toggle with data-controller" do
      render_card(account: active_account)
      expect(page).to have_css("[data-controller='payments--gateway-toggle']")
    end

    it "toggle is checked when account is active" do
      render_card(account: active_account)
      expect(page).to have_css("input[type='checkbox'][checked]")
    end

    it "toggle is unchecked when account is disabled" do
      render_card(account: disabled_account)
      expect(page).not_to have_css("input[type='checkbox'][checked]")
    end

    # Regression: the visual switch is driven by Tailwind's peer-checked: utilities,
    # which only react to a *preceding sibling* marked `peer`. That marker must live
    # on the checkbox, not on the styled slider div — otherwise the switch never
    # changes appearance even though the underlying state (and PATCH) works.
    it "marks the checkbox itself as the Tailwind peer for the visual switch" do
      render_card(account: active_account)
      checkbox = page.find("input[type='checkbox']", visible: :all)
      expect(checkbox[:class]).to match(/\bpeer\b/)
    end

    it "drives the slider colour/knob off peer-checked: utilities" do
      render_card(account: active_account)
      slider = page.find("label.cursor-pointer > div", visible: :all)
      # The slider styles its checked appearance via peer-checked:, and must NOT
      # carry the bare `peer` marker itself (that broke the original toggle).
      expect(slider[:class]).to include("peer-checked:bg-accent")
      expect(slider[:class]).to include("peer-checked:after:translate-x-4")
      expect(slider[:class]).not_to match(/(?<![-:])\bpeer\b(?!-)/)
    end

    it "uses a neutral missing-account state" do
      render_card(account: nil)
      expect(page).to have_css("article.border-border-subtle")
      expect(page).not_to have_css("[class*='warning']")
    end

    it "sets data-url for the toggle PATCH endpoint when account present" do
      render_card(account: active_account)
      expect(page).to have_css("[data-payments--gateway-toggle-url-value]")
    end
  end

  describe "default gateway" do
    let_it_be(:customer) { create(:customer) }

    def configured_account
      a = Payments::MerchantAccount.unscoped_by_tenant.create!(
        customer_id: customer.id, provider: "alipay", mode: "sandbox",
        merchant_id: "M1", status: "active"
      )
      gateway.credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
      a.save!
      a
    end

    it "shows a Default badge when this provider is the default" do
      html = render_card(account: configured_account, default_provider: "alipay").to_html
      expect(html).to include("Default")
    end

    it "distinguishes stored credentials from disabled state" do
      account = configured_account
      account.status = "disabled"
      render_card(account: account)
      expect(page).to have_text("Credentials saved")
      expect(page).to have_text("Disabled")
      expect(page).not_to have_button("Set as default")
    end

    it "recognizes only the exact provisioning placeholder for display" do
      account = configured_account
      account.merchant_id = "unset-alipay-sandbox-#{customer.id}"
      render_card(account: account)
      expect(page).to have_text("Not configured")
      expect(page).not_to have_text(account.merchant_id)
    end

    it "shows a Set as default control when eligible and not default" do
      html = render_card(account: configured_account, default_provider: nil).to_html
      expect(html).to include("Set as default")
    end

    it "hides Set as default when not configured" do
      acc = Payments::MerchantAccount.unscoped_by_tenant.create!(
        customer_id: customer.id, provider: "alipay", mode: "sandbox",
        merchant_id: "unset-alipay-sandbox-#{customer.id}", status: "disabled"
      )
      html = render_card(account: acc, default_provider: nil).to_html
      expect(html).not_to include("Set as default")
    end
  end
end
