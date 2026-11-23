# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::CredentialFieldsComponent, type: :component do
  let(:fields) { Payments::Gateways.for("alipay").credential_fields }

  let(:new_account) { Payments::MerchantAccount.new(provider: "alipay", mode: "sandbox", merchant_id: "M1") }
  let(:persisted_account) do
    acc = Payments::MerchantAccount.new(
      provider: "alipay", mode: "sandbox", merchant_id: "M1", status: "active"
    )
    acc.id = 1
    acc.instance_variable_set(:@new_record, false)
    acc.write_credentials(private_key_pem: "secret_key_here", platform_public_key_pem: "pub_key_here")
    acc
  end

  def build_component(account:, fields:)
    described_class.new(account: account, fields: fields)
  end

  def render_component(account:, fields:)
    render_inline(build_component(account: account, fields: fields))
  end

  describe "#initialize" do
    it "accepts account and fields" do
      component = build_component(account: new_account, fields: fields)
      expect(component.account).to eq(new_account)
      expect(component.fields).to eq(fields)
    end
  end

  describe "#encrypted_placeholder" do
    it "returns '••••••••' for encrypted field on persisted account with value set" do
      component = build_component(account: persisted_account, fields: fields)
      field = { name: :private_key_pem, label: "Key", type: :password, encrypted: true }
      expect(component.encrypted_placeholder(field)).to eq("••••••••")
    end

    it "returns empty string for non-encrypted field" do
      component = build_component(account: persisted_account, fields: fields)
      field = { name: :some_field, label: "Field", type: :string, encrypted: false }
      expect(component.encrypted_placeholder(field)).to eq("")
    end

    it "returns empty string for new (non-persisted) account" do
      component = build_component(account: new_account, fields: fields)
      field = { name: :private_key_pem, label: "Key", type: :password, encrypted: true }
      expect(component.encrypted_placeholder(field)).to eq("")
    end
  end

  describe "#field_value" do
    it "returns empty string for encrypted fields (never expose secrets)" do
      component = build_component(account: persisted_account, fields: fields)
      field = { name: :private_key_pem, label: "Key", type: :password, encrypted: true }
      expect(component.field_value(field)).to eq("")
    end

    it "returns current value for non-encrypted fields" do
      acc = Payments::MerchantAccount.new(provider: "alipay", mode: "sandbox", merchant_id: "M1")
      acc.id = 2
      acc.instance_variable_set(:@new_record, false)
      acc.write_credentials(some_string: "visible_value")
      component = build_component(account: acc, fields: [{ name: :some_string, label: "Label", type: :string, encrypted: false }])
      field = { name: :some_string, label: "Label", type: :string, encrypted: false }
      expect(component.field_value(field)).to eq("visible_value")
    end
  end

  describe "rendering" do
    it "renders every registered provider's fields in Chinese without exposing encrypted values" do
      I18n.with_locale(:"zh-CN") do
        Payments::Gateways.all.each do |gateway|
          account = Payments::MerchantAccount.new(provider: gateway.key, mode: "sandbox", merchant_id: "M1")
          gateway.credential_fields.each { |field| account.write_credentials(field[:name] => "saved-secret-value") }
          render_component(account: account, fields: gateway.credential_fields)
          gateway.credential_fields.each do |field|
            expect(page).to have_css("[name='payment_merchant_account[#{field[:name]}]']")
            expect(page).to have_text(I18n.t("settings_modules.payments.credentials.#{gateway.key}.#{field[:name]}"))
            next unless field[:encrypted]

            expect(page.find("[name='payment_merchant_account[#{field[:name]}]']").value).to be_blank
          end
          expect(page).not_to have_text("translation missing")
        end
      end
    end

    it "only claims a saved secret exists when a value is actually stored" do
      persisted_account.write_credentials(private_key_pem: nil)
      empty_field = { name: :missing_secret, label: "Secret", type: :password, encrypted: true }
      render_component(account: persisted_account, fields: [empty_field])
      expect(page).not_to have_text(/leave blank/i)
      expect(page).not_to have_css("[placeholder='••••••••']")
    end

    it "renders a password field for :password type" do
      password_fields = [{ name: :api_key, label: "API key", type: :password, encrypted: true }]
      render_component(account: new_account, fields: password_fields)
      expect(page).to have_css("input[type='password']")
    end

    it "renders encrypted placeholder for persisted account" do
      # Alipay's encrypted PEM fields are multi-line textareas.
      render_component(account: persisted_account, fields: fields)
      expect(page).to have_css("textarea[placeholder='••••••••']")
    end

    it "renders 'leave blank' hint for persisted encrypted fields" do
      render_component(account: persisted_account, fields: fields)
      expect(page).to have_text(/leave blank/i)
    end

    it "does NOT render 'leave blank' hint for new account" do
      render_component(account: new_account, fields: fields)
      expect(page).not_to have_text(/leave blank/i)
    end

    it "renders a textarea for :text type fields" do
      text_fields = [{ name: :cert_pem, label: "Certificate (PEM)", type: :text, encrypted: true }]
      render_component(account: new_account, fields: text_fields)
      expect(page).to have_css("textarea")
    end

    it "renders a text input for :string type fields" do
      string_fields = [{ name: :app_id, label: "App ID", type: :string, encrypted: false }]
      render_component(account: new_account, fields: string_fields)
      expect(page).to have_css("input[type='text']")
    end

    it "renders lock icon for encrypted fields" do
      render_component(account: new_account, fields: fields)
      expect(page).to have_css("svg")
    end

    it "renders each field label" do
      render_component(account: new_account, fields: fields)
      fields.each do |f|
        expect(page).to have_text(f[:label])
      end
    end
  end
end
