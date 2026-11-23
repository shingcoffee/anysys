# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform SMS campaign fields", type: :component do
  %i[en zh-CN].each do |locale|
    it "renders purpose and approved mirror through the template FormBuilder in #{locale}" do
      template = build_stubbed(:sms_template, purpose: "marketing", body_template: "Offer {{name}}")
      I18n.with_locale(locale) do
        render_inline(Admin::Maintenance::Platform::Sms::TemplateFormComponent.new(template: template,
          form_url: "/81721200/admin/maintenance/platform/module_settings/sms/templates/#{template.id}", form_method: :patch, cancel_path: "/"))
        expect(page).to have_select("sms_template[purpose]", selected: I18n.t("admin_modules.emails.streams.form.kinds.marketing"))
        expect(page).to have_field("sms_template[body_template]", with: "Offer {{name}}")
        expect(page).to have_css("label[for='sms_template_body_template']")
        expect(page).to have_text(I18n.t("sms_campaign_ui.platform.body_help"))
        expect(rendered_content).not_to include("translation_missing", "Translation missing")
      end
    end

    it "renders common config rate independently of provider fields without exposing secrets in #{locale}" do
      credential = build_stubbed(:sms_credential, config: { "sender_rate_per_second" => 0.5 }, access_key_secret: "private-secret")
      I18n.with_locale(locale) do
        render_inline(Admin::Maintenance::Platform::Sms::CredentialFormComponent.new(credential: credential,
          form_url: "/81721200/admin/maintenance/platform/module_settings/sms/credentials/#{credential.id}", form_method: :patch, cancel_path: "/", lock_identity: true))
        expect(page).to have_field("sms_credential[sender_rate_per_second]", with: "0.5")
        expect(page).to have_css("input[name='sms_credential[sender_rate_per_second]'][max='1'][step='any']")
        expect(page).to have_css("label[for='sms_credential_config_sender_rate_per_second']")
        expect(page).to have_text(I18n.t("sms_campaign_ui.platform.sender_rate_help"))
        expect(page).not_to have_css("[data-sms-credential-form-target='fields'] input[name*='sender_rate_per_second']")
        expect(rendered_content).not_to include("private-secret", "dispatch_next_at", "translation_missing", "Translation missing")
      end
    end
  end
end
