# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Emails::CredentialFormComponent, type: :component do
  def build_component(credential:, form_url: "/81721200/admin/maintenance/platform/module_settings/email/credentials",
                       form_method: :post,
                       cancel_path: "/81721200/admin/maintenance/platform/module_settings/email/credentials",
                       lock_identity: false)
    described_class.new(credential: credential, form_url: form_url, form_method: form_method,
                        cancel_path: cancel_path, lock_identity: lock_identity)
  end

  it "hides provider and mode selects when identity is locked to the vendor tab" do
    credential = Emails::Credential.new(provider: "smtp", mode: "sandbox", status: "disabled")
    render_inline(build_component(credential: credential, lock_identity: true))

    expect(page).to have_css("input[type='hidden'][name='emails_credential[provider]']", visible: :all)
    expect(page).to have_css("input[type='hidden'][name='emails_credential[mode]']", visible: :all)
    expect(page).not_to have_css("select#emails_credential_provider")
    expect(page).not_to have_css("select#emails_credential_mode")
    expect(page).to have_css("select#emails_credential_status")
    expect(page).to have_text(I18n.t("maint_platform.emails.credentials.form.identity_hint_locked"))
    expect(page).to have_css("form.w-full")
    expect(page).not_to have_css("form.max-w-3xl")
  end

  describe "rendering with default (new, unpersisted, SMTP) state" do
    let(:credential) { Emails::Credential.new(provider: "smtp", mode: "sandbox", status: "active") }

    before { render_inline(build_component(credential: credential)) }

    it "renders provider options for every registered provider" do
      Email::Providers.all.each do |provider|
        expect(page).to have_css("select#emails_credential_provider option", text: provider.display_name)
      end
    end

    it "renders the mode and status selects with the model's option lists" do
      Emails::Credential::MODES.each do |mode|
        expect(page).to have_css("select#emails_credential_mode option[value='#{mode}']")
      end
      Emails::Credential::STATUSES.each do |status|
        expect(page).to have_css("select#emails_credential_status option[value='#{status}']")
      end
    end

    it "renders the SMTP fieldset with typed-column inputs" do
      smtp_group = page.find("[data-provider='smtp']", visible: :all)
      %w[host port username domain authentication].each do |name|
        expect(smtp_group).to have_css("[name='emails_credential[#{name}]']", visible: :all)
      end
      expect(smtp_group).to have_css("[name='emails_credential[dkim_domain]']", visible: :all)
      expect(smtp_group).to have_css("[name='emails_credential[dkim_private_key]']", visible: :all)
    end

    it "labels SMTP authentication methods without upcasing the enum key" do
      Emails::Credential::AUTHENTICATIONS.each do |auth|
        expect(page).to have_css(
          "select#emails_credential_authentication option[value='#{auth}']",
          text: I18n.t("maint_platform.emails.credentials.form.authentications.#{auth}")
        )
      end
    end

    it "localizes SMTP authentication methods in zh-CN" do
      I18n.with_locale(:"zh-CN") { render_inline(build_component(credential: credential)) }
      expect(page).to have_css(
        "select#emails_credential_authentication option[value='cram_md5']",
        text: "CRAM-MD5"
      )
    end

    it "renders a config-field group per API provider with correct input names" do
      Email::Providers.all.reject { |p| p.key == "smtp" }.each do |provider|
        group = page.find("[data-provider='#{provider.key}']", visible: :all)
        provider.config_fields.each do |field|
          expect(group).to have_css("input[name='emails_credential[#{field[:name]}]']", visible: :all)
        end
      end
    end

    it "shows only the SMTP field group and hides API provider groups" do
      smtp_group = page.find("[data-provider='smtp']", visible: :all)
      expect(smtp_group[:class]).not_to include("hidden")

      ses_group = page.find("[data-provider='ses']", visible: :all)
      expect(ses_group[:class]).to include("hidden")
    end

    it "renders the SMTP secret label" do
      expect(page).to have_text(Email::Providers.for("smtp").credential_label(:password))
    end

    it "does not show the secret-keep hint for a new (unpersisted) credential" do
      expect(page).not_to have_text(I18n.t("maint_platform.emails.credentials.form.password_keep_hint"))
    end

    it "does not render a placeholder on the secret field for a new credential" do
      field = page.find("input#emails_credential_password")
      expect(field[:placeholder]).to be_blank
    end
  end

  describe "rendering with the Aliyun provider selected (variant prop)" do
    let(:credential) { Emails::Credential.new(provider: "aliyun", mode: "sandbox", status: "active") }

    before { render_inline(build_component(credential: credential)) }

    it "shows the aliyun field group and hides the SMTP group" do
      aliyun_group = page.find("[data-provider='aliyun']", visible: :all)
      expect(aliyun_group[:class]).not_to include("hidden")

      smtp_group = page.find("[data-provider='smtp']", visible: :all)
      expect(smtp_group[:class]).to include("hidden")
    end

    it "renders the aliyun provider's secret label" do
      expect(page).to have_text(Email::Providers.for("aliyun").credential_label(:password))
    end

    it "renders the aliyun config fields with password type for webhook_secret" do
      field = page.find("input#emails_credential_aliyun_webhook_secret")
      expect(field[:type]).to eq("password")
    end

    it "marks from_email as required for the Aliyun provider" do
      expect(page).to have_css("label.form-label-required", text: I18n.t("email.providers.aliyun.fields.from_email"))
      expect(page.find("input#emails_credential_aliyun_from_email")[:required]).to eq("required")
    end
  end

  describe "rendering a persisted credential" do
    let(:credential) do
      create(:email_credential, provider: "smtp")
    end

    before { render_inline(build_component(credential: credential, form_method: :patch)) }

    it "shows the secret-keep hint" do
      expect(page).to have_text(I18n.t("maint_platform.emails.credentials.form.password_keep_hint"))
    end

    it "renders a placeholder (not the real secret) on the password field" do
      field = page.find("input#emails_credential_password")
      expect(field[:placeholder]).to eq("••••••••")
      expect(field[:value]).to be_blank
    end

    it "does not HTML-require the password on edit (blank-keep)" do
      form = page.find("form")
      expect(form["data-email-credential-form-secret-required-value"]).to eq("false")
      expect(page.find("input#emails_credential_password")[:required]).to be_nil
      expect(page).not_to have_css("label.form-label-required[data-email-credential-form-target='secretLabel']")
    end

    it "shows the update submit label" do
      expect(page).to have_button(I18n.t("common.actions.update"))
    end
  end

  describe "rendering a persisted Aliyun credential with existing config" do
    let(:credential) do
      create(:email_credential, provider: "aliyun", host: nil, username: nil, password: "AKS",
             webhook_secret: "whsec",
             config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com", "from_alias" => "Ops" })
    end

    before { render_inline(build_component(credential: credential, form_method: :patch)) }

    it "pre-fills existing config values for the selected provider" do
      expect(page).to have_field("emails_credential_aliyun_from_email", with: "noreply@example.com")
      expect(page).to have_field("emails_credential_aliyun_from_alias", with: "Ops")
    end
  end

  describe "accessibility-relevant / Stimulus wiring attributes" do
    let(:credential) { Emails::Credential.new(provider: "smtp", mode: "sandbox", status: "active") }

    before { render_inline(build_component(credential: credential)) }

    it "wires the form to the email-credential-form Stimulus controller with provider/labels values" do
      form = page.find("form")
      expect(form["data-controller"]).to eq("email-credential-form")
      expect(form["data-email-credential-form-provider-value"]).to eq("smtp")
      expect(form["data-email-credential-form-secret-required-value"]).to eq("true")
      expect(JSON.parse(form["data-email-credential-form-labels-value"])).to include("smtp", "ses", "aliyun")
    end

    it "wires the provider select's change action to the controller" do
      select = page.find("select#emails_credential_provider")
      expect(select["data-action"]).to eq("change->email-credential-form#toggle")
    end

    it "targets the secret label for client-side swapping" do
      expect(page).to have_css("label[data-email-credential-form-target='secretLabel']")
    end

    it "marks required credential fields with form-label-required" do
      expect(page).to have_css("label.form-label-required", text: I18n.t("maint_platform.emails.credentials.form.provider_label"))
      expect(page).to have_css("label.form-label-required", text: I18n.t("maint_platform.emails.credentials.form.mode_label"))
      expect(page).to have_css("label.form-label-required", text: I18n.t("maint_platform.emails.credentials.form.status_label"))
      expect(page).to have_css("label.form-label-required", text: I18n.t("maint_platform.emails.credentials.form.host_label"))
      expect(page).to have_css("label.form-label-required[data-email-credential-form-target='secretLabel']")
    end

    it "marks SMTP host/port/username as required for the selected SMTP provider" do
      expect(page.find("input#emails_credential_host")[:required]).to eq("required")
      expect(page.find("input#emails_credential_port")[:required]).to eq("required")
      expect(page.find("input#emails_credential_username")[:required]).to eq("required")
      expect(page.find("input#emails_credential_password")[:required]).to eq("required")
    end

    it "each field group declares itself as a fields target with its provider key" do
      Email::Providers.all.each do |provider|
        expect(page).to have_css("[data-email-credential-form-target='fields'][data-provider='#{provider.key}']",
                                  visible: :all)
      end
    end
  end

  describe "rendering with the SES provider selected" do
    let(:credential) { Emails::Credential.new(provider: "ses", mode: "sandbox", status: "active") }

    before { render_inline(build_component(credential: credential)) }

    it "renders SES config fields and does not show a webhook_secret input for SES" do
      expect(page).to have_css("input#emails_credential_ses_access_key_id", visible: :all)
      expect(page).to have_css("input#emails_credential_ses_from_email", visible: :all)
      expect(page).not_to have_css("input#emails_credential_ses_webhook_secret", visible: :all)
    end
  end

  describe "form errors" do
    let(:credential) do
      c = Emails::Credential.new(provider: "smtp", mode: "sandbox", status: "active")
      c.errors.add(:base, "Complete the credential before activating it.")
      c
    end

    before { render_inline(build_component(credential: credential)) }

    it "renders the error message" do
      expect(page).to have_text("Complete the credential before activating it.")
    end
  end
end
