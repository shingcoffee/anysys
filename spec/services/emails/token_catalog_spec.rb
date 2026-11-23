# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TokenCatalog do
  let(:customer) { create(:customer) }
  subject(:catalog) { described_class.for_customer(customer.id) }

  let!(:fn_token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.first_name"
    ) { |t| t.label = "First name" }
  end

  let!(:email_token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.email"
    ) { |t| t.label = "Email" }
  end

  let!(:cust_token) do
    Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "customer.name"
    ) { |t| t.label = "Customer name" }
  end

  it "builds picker groups with human labels as values (never storage UUIDs)" do
    groups = catalog.picker_groups
    expect(groups.first.first).to be_present
    values = groups.first.last.map(&:last)
    expect(values).to include(fn_token.display_label)
    expect(values).not_to include(fn_token.uuid)
  end

  it "resolves platform fields from VariableContext" do
    user = create(:user, customer: customer, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com")
    resolved = catalog.resolve_vars(Emails::VariableContext.for(user: user))
    expect(resolved[fn_token.uuid]).to eq("Ada")
    expect(resolved[email_token.uuid]).to eq("ada@example.com")
    expect(resolved[cust_token.uuid]).to eq(customer.name)
  end

  it "does not interpolate credential columns even if a leftover token exists" do
    secret_token = Emails::TemplateToken.find_or_create_by!(
      customer_id: nil,
      source_type: Emails::TemplateToken::SOURCE_PLATFORM,
      source_key: "authentication_user.otp_secret"
    ) { |t| t.label = "OTP secret" }
    user = create(:user, :with_mfa, customer: customer)
    resolved = catalog.resolve_vars(Emails::VariableContext.for(user: user))

    expect(user.otp_secret).to be_present
    expect(resolved[secret_token.uuid]).to eq("")
  end

  it "resolves custom entity attributes as blank" do
    custom = create(:email_template_token, customer: customer)
    resolved = catalog.resolve_vars({})
    expect(resolved[custom.uuid]).to eq("")
  end

  it "gives colliding platform/custom picker labels distinct, resolvable values" do
    custom = create(:email_template_token, customer: customer, label: fn_token.display_label)
    groups = catalog.picker_groups
    platform_value = groups.first.last.find { |entry| entry.first.include?(fn_token.source_key) }.last
    custom_value = groups.last.last.find { |entry| entry.first.include?("#{custom.entity_id}.#{custom.attribute_slug}") }.last

    expect(platform_value).not_to eq(custom_value)
    expect(catalog.label_index[platform_value.downcase]).to eq(fn_token.uuid)
    expect(catalog.label_index[custom_value.downcase]).to eq(custom.uuid)
    expect(catalog.label_index).not_to have_key(fn_token.display_label.downcase)
  end

  it "does not assign a winner when a crafted label collides with a qualified picker value" do
    create(:email_template_token, customer: customer, label: fn_token.display_label)
    create(:email_template_token, customer: customer, label: "#{fn_token.display_label} (#{fn_token.source_key})")

    expect(catalog.label_index).not_to have_key("#{fn_token.display_label} (#{fn_token.source_key})".downcase)
  end
end
