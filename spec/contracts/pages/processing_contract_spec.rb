# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ProcessingContract do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:page) { create(:page, customer: customer) }

  def contract_for(record = page)
    described_class.new(record)
  end

  def unavailable
    I18n.t("maint_core.errors.validations.page_flowchart_unavailable")
  end

  it "requires a bindable flowchart" do
    contract = contract_for
    expect(contract.validate("flowchart_id" => "")).to be(false)
    expect(contract.errors[:flowchart_id]).to include(unavailable)
  end

  it "refuses another tenant's flowchart" do
    foreign = create(:flowchart, :launched_status, customer: other)
    contract = contract_for
    expect(contract.validate("flowchart_id" => foreign.id)).to be(false)
    expect(contract.errors[:flowchart_id]).to include(unavailable)
    expect(page.reload.flowchart).not_to eq(foreign)
  end

  it "lets a draft page bind a draft flowchart" do
    draft = create(:flowchart, :draft, customer: customer)
    contract = contract_for
    expect(contract.validate("flowchart_id" => draft.id)).to be(true)
    expect(contract.save).to be_truthy
    expect(page.reload.flowchart_id).to eq(draft.id)
  end

  context "when the page is launched" do
    let(:page) { create(:page, :launched, customer: customer) }

    it "refuses an offline flowchart" do
      draft = create(:flowchart, :draft, customer: customer)
      contract = contract_for
      expect(contract.validate("flowchart_id" => draft.id)).to be(false)
      expect(contract.errors[:base]).to include(I18n.t("maint_core.errors.page_launch.submission_process_offline"))
    end

    it "refuses a flowchart that does not fit the page's entity" do
      incompatible = create_page_flowchart(customer: customer, steps: [{
        "action" => "set_record_fields",
        "config" => { "assignments" => [{ "key" => "not_a_field", "value" => "1" }] }
      }])
      contract = contract_for
      expect(contract.validate("flowchart_id" => incompatible.id)).to be(false)
      expect(contract.errors[:base].join).to include(page.entity.display_label)
      expect(contract.errors[:base].join).to include("not_a_field")
    end
  end
end
