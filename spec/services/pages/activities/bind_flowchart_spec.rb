# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Activities::BindFlowchart do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, :with_name_status_schema, customer: customer, name: "Student", display_label: "Student") }
  let(:page) { create(:page, customer: customer, entity: entity) }

  def flowchart_setting(key)
    create(:flowchart, :launched_status, customer: customer, configuration: {
      "elements" => [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "Set", "properties" => {
          "steps" => [{ "action" => "set_record_fields",
                        "config" => { "modelVariable" => "model", "assignments" => [{ "key" => key, "value" => "1" }] } }]
        } },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [{ "id" => "c1", "from" => "s", "to" => "p" }, { "id" => "c2", "from" => "p", "to" => "e" }],
      "metadata" => {}
    }.to_json)
  end

  it "refuses a shared page, which is rebound on the platform prefix only" do
    expect { described_class.call(page: Page.new(customer_id: nil), flowchart_id: 1) }.to raise_error(ArgumentError)
  end

  it "binds a flowchart the page may use and has nothing to explain" do
    flowchart = flowchart_setting("name")

    result = described_class.call(page: page, flowchart_id: flowchart.id)

    expect(result.ok).to be(true)
    expect(result.reasons).to eq([])
    expect(page.reload.flowchart).to eq(flowchart)
  end

  it "explains a refusal in words any admin may read, without naming flowcharts or steps" do
    foreign = create(:flowchart, :launched_status, customer: create(:customer))
    page.update_columns(launched: true)
    offline = create(:flowchart, :draft, customer: customer)
    incompatible = flowchart_setting("missing_field")

    reasons = [foreign, offline, incompatible].map { |flowchart| described_class.call(page: page.reload, flowchart_id: flowchart.id).reasons }

    expect(reasons).to eq([
      [I18n.t("maint_core.errors.validations.page_processing_unavailable")],
      [I18n.t("maint_core.errors.page_launch.submission_process_offline")],
      [I18n.t("maint_core.errors.page_launch.submission_process_incompatible", entity: "Student")]
    ])
    expect(reasons.flatten.join).not_to match(/flowchart|missing_field/i)
  end

  it "keeps the detailed reasons for the platform owner's processing card" do
    page.update_columns(launched: true)

    result = described_class.call(page: page, flowchart_id: flowchart_setting("missing_field").id)

    expect(result.ok).to be(false)
    expect(result.errors.join).to include("missing_field")
  end
end
