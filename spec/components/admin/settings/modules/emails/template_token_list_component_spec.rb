# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Emails::TemplateTokenListComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81721200) }
  let(:entity) { build_stubbed(:entity, :with_name_status_schema, customer: customer, display_label: "Supporters") }
  let(:token) { build_stubbed(:email_template_token, entity: entity, customer: entity.customer, label: "Supporter name") }
  let(:platform_token) { build_stubbed(:email_template_token, :platform, label: "unsubscribe_url", source_key: "unsubscribe_url", uuid: SecureRandom.uuid) }

  def render_list(custom_tokens: [token], platform_tokens: [platform_token])
    render_inline(described_class.new(customer_id: entity.customer_id, platform_tokens: platform_tokens, custom_tokens: custom_tokens))
  end

  def built_in_disclosure
    page.find("details.group\\/item.card", visible: :all)
  end

  def custom_disclosures
    page.all("section[aria-label='#{I18n.t('settings_modules.email.custom_fields')}'] details.group\\/item", visible: :all)
  end

  it "renders readable mappings and a read-only platform section" do
    render_list
    expect(page).to have_css("h1", text: "Email personalization", count: 1)
    expect(built_in_disclosure[:open]).to be_nil
    expect(built_in_disclosure).to have_css("summary", text: "Built-in fields", visible: :all)
    expect(built_in_disclosure).to have_css("summary", text: "These fields are managed by the platform", visible: :all)
    expect(custom_disclosures.size).to eq(1)
    expect(custom_disclosures.first[:open]).to be_nil
    expect(custom_disclosures.first).to have_css("summary", text: "Supporters", visible: :all)
    expect(custom_disclosures.first).to have_css("summary", text: "1 field", visible: :all)
    expect(custom_disclosures.first).to have_css("li", text: "Supporter name", visible: :all)
    expect(custom_disclosures.first).to have_css("li", text: "Name", visible: :all)
    expect(custom_disclosures.first).not_to have_css("li", text: "Supporters", visible: :all)
    expect(page).to have_text("Unsubscribe URL")
    expect(page).to have_text("Read-only")
    expect(page).not_to have_text("unsubscribe_url")
    expect(page).not_to have_text(platform_token.uuid)
    expect(page).not_to have_text("name_slug")
    expect(page).to have_css("a[aria-label='Edit Supporter name'][href='/#{entity.customer_id}/admin/settings/modules/emails/template_tokens/#{token.id}/edit']", visible: :all)
    expect(page).to have_css("form input[name='_method'][value='delete']", count: 1, visible: :all)
    expect(page).to have_css("button[data-turbo-confirm]", count: 1, visible: :all)
  end

  it "groups tokens by entity id, even when different entities share a display name" do
    same_name_entity = build_stubbed(:entity, :with_name_status_schema, customer: customer, display_label: "Supporters")
    other_entity = build_stubbed(:entity, :with_name_status_schema, customer: customer, display_label: "Events")
    status_token = build_stubbed(:email_template_token, entity: entity, customer: customer, label: "Supporter status", attribute_slug: "status")
    same_name_token = build_stubbed(:email_template_token, entity: same_name_entity, customer: customer, label: "Other supporter name")
    event_token = build_stubbed(:email_template_token, entity: other_entity, customer: customer, label: "Event name")

    render_list(custom_tokens: [token, same_name_token, event_token, status_token])

    first_group, same_name_group, event_group = custom_disclosures
    expect(custom_disclosures.size).to eq(3)
    expect(custom_disclosures.map { |group| group[:open] }).to eq([nil, nil, nil])
    expect(first_group).to have_css("summary", text: "Supporters", visible: :all)
    expect(first_group).to have_css("summary", text: "2 fields", visible: :all)
    expect(first_group).to have_css("li", text: "Supporter name", visible: :all)
    expect(first_group).to have_css("li", text: "Supporter status", visible: :all)
    expect(first_group).to have_css("li", text: "Status", visible: :all)
    expect(first_group).not_to have_css("li", text: "Other supporter name", visible: :all)
    expect(same_name_group).to have_css("summary", text: "Supporters", visible: :all)
    expect(same_name_group).to have_css("summary", text: "1 field", visible: :all)
    expect(same_name_group).to have_css("li", text: "Other supporter name", visible: :all)
    expect(same_name_group).not_to have_css("li", text: "Supporter status", visible: :all)
    expect(event_group).to have_css("summary", text: "Events", visible: :all)
    expect(event_group).to have_css("li", text: "Event name", visible: :all)

    [[first_group, token], [first_group, status_token], [same_name_group, same_name_token], [event_group, event_token]].each do |group, field|
      expect(group).to have_css("a[aria-label='Edit #{field.display_label}'][href='/#{customer.id}/admin/settings/modules/emails/template_tokens/#{field.id}/edit']", visible: :all)
      expect(group).to have_css("button[aria-label='Delete #{field.display_label}'][data-turbo-confirm]", visible: :all)
    end
  end

  it "shows a truthful empty state and add action" do
    render_list(custom_tokens: [])
    expect(page).to have_text("No custom personalization fields yet.")
    expect(page).to have_link("Add personalization field")
    expect(page).not_to have_button("Delete")
    expect(custom_disclosures).to be_empty
  end

  it "does not silently display the raw slug when a mapped field is missing" do
    token.attribute_slug = "deleted_field_internal"
    render_list
    expect(page).to have_text("Field unavailable")
    expect(page).not_to have_text("deleted_field_internal")
  end

  it "uses the localized fallback for missing entities and attributes" do
    other_entity = build_stubbed(:entity, :with_name_status_schema, customer: customer)
    other_token = build_stubbed(:email_template_token, entity: other_entity, customer: customer, label: "Other missing record")
    allow(token).to receive(:entity).and_return(nil)
    allow(other_token).to receive(:entity).and_return(nil)

    [:en, :"zh-CN"].each do |locale|
      I18n.with_locale(locale) do
        render_list(custom_tokens: [token, other_token])
        groups = custom_disclosures
        expect(groups.size).to eq(2)
        groups.each do |group|
          expect(group).to have_css("summary", text: I18n.t("settings_modules.email.unavailable_record"), visible: :all)
          expect(group).to have_css("li", text: I18n.t("settings_modules.email.unavailable_field"), visible: :all)
        end
      end
    end
  end

  it "localizes platform field labels and keeps customer names intact" do
    I18n.with_locale(:"zh-CN") do
      render_list
      expect(page).to have_css("h1", text: "邮件个性化")
      expect(page).to have_text("Supporter name")
      expect(page).to have_text(I18n.t("email.template_tokens.platform.unsubscribe_url"))
      expect(built_in_disclosure).to have_css("summary", text: I18n.t("settings_modules.email.built_in_hint"), visible: :all)
      expect(custom_disclosures.first).to have_css("summary", text: I18n.t("settings_modules.email.fields_count", count: 1), visible: :all)
      expect(page).not_to have_text("translation missing")
    end
  end

  it "pluralizes group counts in English and Chinese" do
    status_token = build_stubbed(:email_template_token, entity: entity, customer: customer, label: "Supporter status", attribute_slug: "status")
    other_entity = build_stubbed(:entity, :with_name_status_schema, customer: customer, display_label: "Events")
    event_token = build_stubbed(:email_template_token, entity: other_entity, customer: customer, label: "Event name")

    [:en, :"zh-CN"].each do |locale|
      I18n.with_locale(locale) do
        render_list(custom_tokens: [token, status_token, event_token])
        groups = custom_disclosures
        expect(groups.first).to have_css("summary", text: I18n.t("settings_modules.email.fields_count", count: 2), visible: :all)
        expect(groups.last).to have_css("summary", text: I18n.t("settings_modules.email.fields_count", count: 1), visible: :all)
        expect(page).not_to have_text("translation missing")
      end
    end
    expect(I18n.t("settings_modules.email.fields_count", locale: :en, count: 1)).to eq("1 field")
    expect(I18n.t("settings_modules.email.fields_count", locale: :en, count: 2)).to eq("2 fields")
    expect(I18n.t("settings_modules.email.fields_count", locale: :"zh-CN", count: 2)).to eq("2 个字段")
  end

  it "describes the source of every legacy field accurately in both locales" do
    fields = {
      "Dispute.provider" => "payments_dispute.provider",
      "Dispute.psp_dispute_id" => "payments_dispute.psp_dispute_id",
      "Dispute.raw" => "payments_dispute.raw",
      "Event.id" => "authentication_event.id",
      "TrustedDevice.id" => "authentication_trusted_device.id",
      "User.first_name" => "authentication_user.first_name",
      "User.last_name" => "authentication_user.last_name",
      "unsubscribe_url" => "unsubscribe_url"
    }
    platform_tokens = fields.map do |label, source_key|
      build_stubbed(:email_template_token, :platform, label: label, source_key: source_key)
    end
    source_types = {
      "payments_dispute.provider" => "workflow_source",
      "payments_dispute.psp_dispute_id" => "workflow_source",
      "payments_dispute.raw" => "workflow_source",
      "authentication_event.id" => "workflow_source",
      "authentication_trusted_device.id" => "workflow_source",
      "authentication_user.first_name" => "recipient_source",
      "authentication_user.last_name" => "recipient_source",
      "unsubscribe_url" => "unsubscribe_source"
    }

    [:en, :"zh-CN"].each do |locale|
      I18n.with_locale(locale) do
        render_list(platform_tokens: platform_tokens, custom_tokens: [])
        platform_tokens.each do |field|
          row = page.all("li", visible: :all).find { |item| item.has_text?(field.display_label) }
          expect(row).to have_text(I18n.t("settings_modules.email.#{source_types.fetch(field.source_key)}"))
        end
        expect(page).not_to have_text("Provided automatically when the email is sent.")
        expect(page).not_to have_text("translation missing")
      end
    end
  end

  it "explains customer context and keeps unknown platform labels readable" do
    fields = [
      build_stubbed(:email_template_token, :platform, label: "Customer.display_name", source_key: "customer.display_name"),
      build_stubbed(:email_template_token, :platform, label: "Fraud.case_number", source_key: "fraud.case_number")
    ]

    render_list(platform_tokens: fields, custom_tokens: [])

    customer_row = page.all("li", visible: :all).find { |item| item.has_text?("Other field: Customer Display Name") }
    fraud_row = page.all("li", visible: :all).find { |item| item.has_text?("Other field: Fraud Case Number") }
    expect(customer_row).to have_text(I18n.t("settings_modules.email.customer_source"))
    expect(fraud_row).to have_text(I18n.t("settings_modules.email.workflow_source"))
    expect(page).not_to have_text("case_number")
  end

  it "keeps every source description translated in both locales" do
    %w[recipient_source customer_source unsubscribe_source workflow_source].each do |key|
      [:en, :"zh-CN"].each do |locale|
        expect(I18n.exists?("settings_modules.email.#{key}", locale)).to be(true)
      end
    end
  end
end
