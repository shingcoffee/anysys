# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::GatewayGalleryComponent, type: :component do
  let(:gateways) { Payments::Gateways.all }
  let(:alipay_account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "sandbox", merchant_id: "M1", status: "active"
    )
    acc.id = 1
    acc.instance_variable_set(:@new_record, false)
    acc
  end
  let(:accounts_by_provider) { { "alipay" => alipay_account } }

  let(:stub_helpers) do
    double("helpers",
      params: { customer_id: "12345678" },
      admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1",
      edit_admin_settings_modules_payments_merchant_account_path: "/12345678/admin/settings/modules/payments/merchant_accounts/1/edit",
      admin_settings_modules_payments_merchant_accounts_path: "/12345678/admin/settings/modules/payments/merchant_accounts",
      protect_against_forgery?: false
    )
  end

  before do
    allow_any_instance_of(Payments::Admin::GatewayCardComponent).to receive(:helpers).and_return(stub_helpers)
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def render_gallery(gateways:, accounts_by_provider:)
    render_inline(described_class.new(gateways: gateways, accounts_by_provider: accounts_by_provider))
  end

  describe "#initialize" do
    it "accepts gateways and accounts_by_provider" do
      component = described_class.new(gateways: gateways, accounts_by_provider: accounts_by_provider)
      expect(component.gateways).to eq(gateways)
      expect(component.accounts_by_provider).to eq(accounts_by_provider)
    end
  end

  describe "rendering" do
    it "renders one settings page heading and a linked root breadcrumb" do
      render_gallery(gateways: [], accounts_by_provider: {})
      expect(page).to have_css("h1", text: "Payment providers", count: 1)
      expect(page).to have_link("Settings", href: "/12345678/admin/settings")
      expect(page).not_to have_css("form")
    end

    context "with gateways present" do
      it "renders a responsive grid" do
        render_gallery(gateways: gateways, accounts_by_provider: accounts_by_provider)
        expect(page).to have_css("[class*='grid']")
      end

      it "renders a card for each gateway" do
        render_gallery(gateways: gateways, accounts_by_provider: accounts_by_provider)
        gateways.each do |gw|
          expect(page).to have_text(gw.display_name)
        end
      end

      it "passes the account to the gateway card when account exists" do
        render_gallery(gateways: [Payments::Gateways.for("alipay")], accounts_by_provider: accounts_by_provider)
        expect(page).to have_text("Enabled")
        expect(page).to have_text("Not configured")
      end
    end

    context "with no gateways" do
      it "renders empty state" do
        render_gallery(gateways: [], accounts_by_provider: {})
        expect(page).to have_text("No payment providers available")
      end

      it "shows contact platform owner message" do
        render_gallery(gateways: [], accounts_by_provider: {})
        expect(page).to have_text("Contact the platform owner")
      end
    end
  end
end
