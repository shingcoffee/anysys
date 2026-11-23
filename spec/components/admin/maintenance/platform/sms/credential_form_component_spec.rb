# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Sms::CredentialFormComponent, type: :component do
  def build_component(credential:, form_url: "/81721200/admin/maintenance/platform/module_settings/sms/credentials",
                       form_method: :post,
                       cancel_path: "/81721200/admin/maintenance/platform/module_settings/sms/credentials",
                       lock_identity: false)
    described_class.new(credential: credential, form_url: form_url, form_method: form_method,
                        cancel_path: cancel_path, lock_identity: lock_identity)
  end

  it "hides provider and mode selects when identity is locked to the vendor tab" do
    credential = Sms::Credential.new(provider: "aliyun", mode: "sandbox", status: "disabled")
    render_inline(build_component(credential: credential, lock_identity: true))

    expect(page).to have_css("input[type='hidden'][name='sms_credential[provider]']", visible: :all)
    expect(page).to have_css("input[type='hidden'][name='sms_credential[mode]']", visible: :all)
    expect(page).not_to have_css("select#sms_credential_provider")
    expect(page).not_to have_css("select#sms_credential_mode")
    expect(page).to have_css("select#sms_credential_status")
    expect(page).to have_text(I18n.t("maint_platform.sms.credentials.form.identity_hint_locked"))
    expect(page).to have_css("form.w-full")
    expect(page).not_to have_css("form.max-w-3xl")
  end

  describe "rendering with default (new, unpersisted) state" do
    let(:credential) { Sms::Credential.new(provider: "aliyun", mode: "sandbox") }

    before { render_inline(build_component(credential: credential)) }

    it "renders provider options for every registered adapter" do
      Sms::Adapters.all.each do |adapter|
        expect(page).to have_css("select#sms_credential_provider option", text: adapter.display_name)
      end
    end

    it "renders the mode and status selects with the model's option lists" do
      Sms::Credential::MODES.each do |mode|
        expect(page).to have_css("select#sms_credential_mode option[value='#{mode}']")
      end
      Sms::Credential::STATUSES.each do |status|
        expect(page).to have_css("select#sms_credential_status option[value='#{status}']")
      end
    end

    it "localizes mode and status options instead of humanizing the keys" do
      expect(page).to have_css(
        "select#sms_credential_mode option[value='sandbox']",
        text: I18n.t("common.modes.sandbox")
      )
      expect(page).to have_css(
        "select#sms_credential_status option[value='active']",
        text: I18n.t("common.status.active")
      )
    end

    it "localizes mode options in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_inline(build_component(credential: credential))
        expect(page).to have_css(
          "select#sms_credential_mode option[value='sandbox']",
          text: I18n.t("common.modes.sandbox")
        )
      end
    end

    it "renders a config-field group per adapter with correct input names" do
      Sms::Adapters.all.each do |adapter|
        group = page.find("[data-provider='#{adapter.key}']", visible: :all)
        adapter.config_fields.each do |field|
          expect(group).to have_css("input[name='sms_credential[#{field[:name]}]']", visible: :all)
        end
      end
    end

    it "shows only the currently selected provider's field group" do
      aliyun_group = page.find("[data-provider='aliyun']", visible: :all)
      expect(aliyun_group[:class]).not_to include("hidden")

      Sms::Adapters.all.reject { |a| a.key.to_s == "aliyun" }.each do |adapter|
        group = page.find("[data-provider='#{adapter.key}']", visible: :all)
        expect(group[:class]).to include("hidden")
      end
    end

    it "does not show the secret-keep hint for a new (unpersisted) credential" do
      expect(page).not_to have_text(I18n.t("maint_platform.sms.credentials.form.secret_keep_hint"))
    end

    it "does not render a placeholder on the secret field for a new credential" do
      field = page.find("input#sms_credential_access_key_secret")
      expect(field[:placeholder]).to be_blank
    end
  end

  describe "rendering with a different provider selected (variant prop)" do
    let(:credential) { Sms::Credential.new(provider: "twilio", mode: "sandbox") }

    before { render_inline(build_component(credential: credential)) }

    it "shows the twilio field group and hides the others" do
      twilio_group = page.find("[data-provider='twilio']", visible: :all)
      expect(twilio_group[:class]).not_to include("hidden")

      aliyun_group = page.find("[data-provider='aliyun']", visible: :all)
      expect(aliyun_group[:class]).to include("hidden")
    end

    it "renders the twilio adapter's credential labels" do
      adapter = Sms::Adapters.for("twilio")
      expect(page).to have_text(adapter.credential_label(:access_key_id))
      expect(page).to have_text(adapter.credential_label(:access_key_secret))
    end
  end

  describe "rendering a persisted credential" do
    let(:credential) do
      create(:sms_credential, provider: "aliyun", access_key_id: "AKID_EXISTING",
                               config: { "sign_name" => "MyApp", "region" => "cn-hangzhou" })
    end

    before { render_inline(build_component(credential: credential, form_method: :patch)) }

    it "shows the secret-keep hint" do
      expect(page).to have_text(I18n.t("maint_platform.sms.credentials.form.secret_keep_hint"))
    end

    it "renders a placeholder (not the real secret) on the access_key_secret field" do
      field = page.find("input#sms_credential_access_key_secret")
      expect(field[:placeholder]).to eq("••••••••")
      expect(field[:value]).to be_blank
    end

    it "pre-fills existing config values for the selected adapter" do
      expect(page).to have_field("sms_credential[sign_name]", with: "MyApp")
      expect(page).to have_field("sms_credential[region]", with: "cn-hangzhou")
    end

    it "shows the update submit label" do
      expect(page).to have_button(I18n.t("common.actions.update"))
    end
  end

  describe "accessibility-relevant / Stimulus wiring attributes" do
    let(:credential) { Sms::Credential.new(provider: "aliyun", mode: "sandbox") }

    before { render_inline(build_component(credential: credential)) }

    it "wires the form to the sms-credential-form Stimulus controller with provider/labels values" do
      form = page.find("form")
      expect(form["data-controller"]).to eq("sms-credential-form")
      expect(form["data-sms-credential-form-provider-value"]).to eq("aliyun")
      expect(JSON.parse(form["data-sms-credential-form-labels-value"])).to include("aliyun", "twilio")
    end

    it "wires the provider select's change action to the controller" do
      select = page.find("select#sms_credential_provider")
      expect(select["data-action"]).to eq("change->sms-credential-form#toggle")
    end

    it "targets the access-key labels for client-side swapping" do
      expect(page).to have_css("label[data-sms-credential-form-target='accessKeyIdLabel']")
      expect(page).to have_css("label[data-sms-credential-form-target='accessKeySecretLabel']")
    end

    it "each field group declares itself as a fields target with its provider key" do
      Sms::Adapters.all.each do |adapter|
        expect(page).to have_css("[data-sms-credential-form-target='fields'][data-provider='#{adapter.key}']",
                                  visible: :all)
      end
    end
  end

  describe "password-type config field (security — never echo the stored secret)" do
    before do
      allow(Sms::Adapters::Aliyun).to receive(:config_fields).and_return([
        { name: :sign_name,    label: "Sign name",    type: :string },
        { name: :secret_token, label: "Secret token", type: :password }
      ])
render_inline(build_component(credential: credential, form_method: :patch))
    end

    let(:credential) do
      create(:sms_credential, provider: "aliyun",
                              config: { "sign_name" => "MyApp", "secret_token" => "SUPERSECRET" })
    end


    it "never emits the stored secret value into the HTML" do
      expect(page.native.to_html).not_to include("SUPERSECRET")
    end

    it "renders the password config field blank with a dot-mask placeholder" do
      field = page.find("input#sms_credential_secret_token", visible: :all)
      expect(field[:value]).to be_blank
      expect(field[:placeholder]).to eq("••••••••")
    end

    it "still echoes non-password config values (e.g. sign_name)" do
      expect(page).to have_field("sms_credential[sign_name]", with: "MyApp")
    end
  end

  describe "form errors" do
    let(:credential) do
      c = Sms::Credential.new(provider: "aliyun", mode: "sandbox")
      c.errors.add(:base, "Complete the credential before activating it.")
      c
    end

    before { render_inline(build_component(credential: credential)) }

    it "renders the error message" do
      expect(page).to have_text("Complete the credential before activating it.")
    end
  end
end
