# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::Sms::TemplateFormComponent, type: :component do
  def build_component(template:, form_url: "/81721200/admin/maintenance/platform/module_settings/sms/templates",
                       form_method: :post,
                       cancel_path: "/81721200/admin/maintenance/platform/module_settings/sms/templates")
    described_class.new(template: template, form_url: form_url, form_method: form_method, cancel_path: cancel_path)
  end

  describe "rendering with default (new, unpersisted) state" do
    let(:template) { Sms::Template.new(variables: []) }

    before { render_inline(build_component(template: template)) }

    it "renders the key, description and variables inputs" do
      expect(page).to have_css("input#sms_template_key")
      expect(page).to have_css("input#sms_template_description")
      expect(page).to have_css("input[name='sms_template[variables_raw]']")
    end

    it "renders one provider-code input per registered adapter with correct name" do
      Sms::Adapters.keys.each do |key|
        expect(page).to have_css("input[name='sms_template[provider_template_codes][#{key}]']")
      end
    end

    it "labels each provider-code input with the adapter's display name" do
      Sms::Adapters.all.each do |adapter|
        expect(page).to have_text(I18n.t("maint_platform.sms.templates.form.provider_code_label", provider: adapter.display_name))
      end
    end

    it "renders the status select with the model's status list" do
      Sms::Template::STATUSES.each do |status|
        expect(page).to have_css("select#sms_template_status option[value='#{status}']")
      end
    end

    it "localizes status options instead of humanizing the keys" do
      expect(page).to have_css(
        "select#sms_template_status option[value='active']",
        text: I18n.t("common.status.active")
      )
      expect(page).to have_css(
        "select#sms_template_status option[value='retired']",
        text: I18n.t("common.status.retired")
      )
    end

    it "localizes status options in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_inline(build_component(template: template))
        expect(page).to have_css(
          "select#sms_template_status option[value='retired']",
          text: I18n.t("common.status.retired")
        )
      end
    end

    it "renders the create submit label for an unpersisted template" do
      expect(page).to have_button(I18n.t("common.actions.create"))
    end

    it "uses shared module-settings sections and responsive form actions" do
      expect(page).to have_css("section[aria-labelledby]", count: 2)
      expect(page).to have_css("[data-module-settings-form-actions]")
    end

    it "renders an empty variables_raw value when there are no variables" do
      expect(page).to have_field("sms_template[variables_raw]", with: "")
    end
  end

  describe "rendering a persisted template (variant prop)" do
    let(:template) do
      create(:sms_template, key: "verify_code", variables: %w[code minutes],
                             provider_template_codes: { "aliyun" => "SMS_999" })
    end

    before { render_inline(build_component(template: template, form_method: :patch)) }

    it "joins existing variables into the comma-separated variables_raw field" do
      expect(page).to have_field("sms_template[variables_raw]", with: "code, minutes")
    end

    it "pre-fills the existing provider template code" do
      expect(page).to have_field("sms_template[provider_template_codes][aliyun]", with: "SMS_999")
    end

    it "renders the update submit label" do
      expect(page).to have_button(I18n.t("common.actions.update"))
    end
  end

  describe "form errors" do
    let(:template) do
      t = Sms::Template.new(variables: [])
      t.errors.add(:key, "can't be blank")
      t
    end

    before { render_inline(build_component(template: template)) }

    it "renders the error message" do
      expect(page).to have_text("can't be blank")
    end
  end

  describe "accessibility-relevant attributes" do
    let(:template) { Sms::Template.new(variables: []) }

    before { render_inline(build_component(template: template)) }

    it "associates each provider-code label with its input via for/id" do
      Sms::Adapters.keys.each do |key|
        field_id = "sms_template_provider_template_codes_#{key}"
        expect(page).to have_css("label[for='#{field_id}']")
        expect(page).to have_css("input##{field_id}")
      end
    end
  end
end
