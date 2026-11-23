# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::Contracts::Build do
  let(:customer) { create(:customer) }
  let(:template) { create(:email_template, customer: customer) }
  let(:contract) { described_class.new(described_class::Input.new) }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  def input(**overrides)
    { customer_id: customer.id, name: "Campaign", email_template_id: template.id,
      email_list_ids: [create(:email_list, customer: customer).id],
      scheduled_at: 1.day.from_now, timezone: "UTC" }.merge(overrides)
  end

  it "accepts exactly ten tenant lists and returns their records" do
    lists = create_list(:email_list, 10, customer: customer)
    expect(contract.validate(input(email_list_ids: lists.map(&:id)))).to be(true)
    expect(contract.lists).to match_array(lists)
  end

  it "rejects a foreign list even when every other field is valid" do
    foreign = create(:email_list, customer: create(:customer))
    expect(contract.validate(input(email_list_ids: [foreign.id]))).to be(false)
    expect(contract.errors[:email_lists]).to be_present
  end

  it "does not coerce a malformed list identifier into an accessible ID" do
    list = create(:email_list, customer: customer)
    expect(contract.validate(input(email_list_ids: ["#{list.id}garbage"]))).to be(false)
    expect(contract.errors[:email_lists]).to be_present
  end

  it "rejects the selected Aliyun transport with a localized campaign capability error" do
    credential.update!(status: "disabled")
    aliyun = create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
                    config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })

    expect(contract.validate(input)).to be(false)
    expect(contract.errors[:base]).to include(I18n.t("email.providers.errors.unsupported_campaign", provider: aliyun.provider_class.display_name))
  end

  it "rejects a dynamic list whose persisted rules are no longer valid" do
    list = create(:email_list, :dynamic, customer: customer)
    list.update_columns(segment_rules: { "conditions" => [{ "field" => "first_name", "operator" => "unknown", "value" => "Ada" }] })

    expect(contract.validate(input(email_list_ids: [list.id]))).to be(false)
    expect(contract.errors[:email_lists]).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
  end

  it "reports delivery unavailability before accepting a campaign with no active credential" do
    credential.update!(status: "disabled")
    expect(contract.validate(input)).to be(false)
    expect(contract.errors[:base]).to include(I18n.t("admin_modules.flash.templates.credentials_missing"))
  end
end
