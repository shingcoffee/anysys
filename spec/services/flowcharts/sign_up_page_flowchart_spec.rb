# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::SignUpPageFlowchart do
  def stored = Flowchart.unscoped.find_by(uuid: described_class::UUID)

  it "creates the shared, launched member sign-up flowchart on first use and reuses it" do
    stored&.update_column(:uuid, SecureRandom.uuid)

    flowchart = Current.set(customer: create(:customer)) { described_class.fetch }

    expect(flowchart).to be_shared
    expect(flowchart).to be_launched
    expect(flowchart.name).to eq(I18n.t("maint_core.flowcharts.sign_up_page_flowchart.name", locale: I18n.default_locale))
    expect(flowchart.current_version).to have_attributes(customer_id: nil)
    steps = flowchart.elements.flat_map { |element| Array(element.dig("properties", "steps")) }
    expect(steps.pluck("action")).to eq(%w[build_contract validate_contract register_member save_model])
    expect(steps.find { |step| step["action"] == "register_member" }["config"])
      .to eq("personVar" => "model", "identityVar" => "identity", "resultVar" => "registration")
    expect(described_class.fetch).to eq(flowchart)
    expect(Flowchart.unscoped.where(uuid: described_class::UUID).count).to eq(1)
  end

  it "stays deleted once the platform owner deletes it" do
    described_class.fetch.update_columns(status: Flowchart.statuses[:deleted])

    expect(described_class.fetch).to be_nil
    expect(stored).to be_deleted
  end
end
