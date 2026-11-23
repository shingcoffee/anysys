# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::ListMentions do
  let(:customer) { create(:customer) }

  def enable!
    enable_ai_assistant_module!(customer)
  end

  it "returns what the tenant can mention" do
    enable!
    create(:entity, customer: customer, name: "Invoice", display_label: "Invoices")
    create(:entity, customer: create(:customer), name: "Foreign")

    result = described_class.call(customer: customer)

    expect(result.success?).to be(true)
    expect(result.http_status).to eq(200)
    expect(result.mentions.map(&:as_json)).to eq([{ "kind" => "entity", "name" => "Invoice", "label" => "Invoices" }])
  end

  it "includes flowcharts for the platform owner" do
    enable!
    entity = create(:entity, customer: customer, name: "Invoice")
    create(:flowchart, customer: customer, name: "Issue invoice")

    result = described_class.call(customer: customer, viewer: find_or_create_platform_owner)

    expect(result.success?).to be(true)
    expect(result.mentions.map(&:kind)).to include("flowchart")
    expect(result.mentions.map(&:name)).to include("Issue invoice")
  end

  it "returns an empty list for a tenant that owns nothing yet" do
    enable!

    result = described_class.call(customer: customer)

    expect(result.success?).to be(true)
    expect(result.mentions).to eq([])
  end

  it "refuses when the module is disabled" do
    result = described_class.call(customer: customer)

    expect(result.success?).to be(false)
    expect(result.http_status).to eq(403)
    expect(result.errors).to eq([ I18n.t("ai_assistant.errors.module_disabled") ])
    expect(result.mentions).to eq([])
  end
end
