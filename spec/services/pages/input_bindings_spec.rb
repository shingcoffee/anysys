# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::InputBindings do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let(:inputs) { [{ "field" => "student", "entity_id" => student_entity.id }] }
  let!(:student_page) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: student_entity, launched: true, action_key: "student_new",
                    configuration: { form_settings: { modes: %w[create] }, pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
  end
  let(:bridge_page) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: bridge_entity, launched: true, action_key: "student_add_course",
                    configuration: { form_settings: { inputs: inputs }, pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
  end
  let!(:journey) { create(:journey, :launched, customer: customer) }

  def run_with(record_id, page: bridge_page, customer_id: customer.id, step: "relate_1")
    run = JourneyRun.issue!(customer_id: customer_id, user: nil, session: {},
                            journey: journey, current_step: step).first
    run.record!("start", record_id) if record_id
    run
  end

  def resolve(run, audience: EntityAttributeAudience::ADMIN, viewer: nil)
    described_class.resolve(page: bridge_page, run: run, viewer: viewer, audience: audience, customer_id: customer.id)
  end

  it "keeps a same-tenant record of the input's entity, with the record it checked" do
    bound = resolve(run_with(student.id))
    expect(bound).to eq("student" => student.id.to_s)
    expect(bound.records).to eq("student" => student)
  end

  it "is empty without a run" do
    expect(resolve(nil)).to eq({})
  end

  it "drops a record of another entity, another tenant or none at all" do
    foreign_customer = create(:customer)
    foreign = create(:entity_entry, :with_data, customer: foreign_customer, entity: student_entity, entry_data: { "full_name" => "Eve" })

    [math.id, foreign.id, EntityEntry.maximum(:id) + 100].each do |id|
      expect(resolve(run_with(id))).to eq({})
    end
  end

  it "drops malformed ids" do
    ["abc", "0", " #{student.id}", "#{student.id}x", "", nil].each do |id|
      expect(resolve(run_with(id))).to eq({})
    end
  end

  it "drops bindings for slugs the page does not declare as inputs" do
    other = Current.set(customer: customer) do
      create(:page, customer: customer, entity: bridge_entity, launched: true, action_key: "student_add_course",
                    configuration: { form_settings: { inputs: [{ "field" => "course", "entity_id" => course_entity.id }] },
                                     pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
    expect(described_class.resolve(page: other, run: run_with(student.id), viewer: nil,
                                   audience: EntityAttributeAudience::ADMIN, customer_id: customer.id)).to eq({})
  end

  it "drops a declared input that is not a reference to that entity on the page's entity" do
    bridge_page.configuration_json = bridge_page.configuration_json.merge(
      "form_settings" => { "inputs" => [{ "field" => "course", "entity_id" => student_entity.id }] }
    )
    expect(resolve(run_with(student.id))).to eq({})
  end

  it "drops a record the viewer cannot reach" do
    allow(People::Ownership).to receive(:reachable_ids).and_return([])
    expect(resolve(run_with(student.id), audience: EntityAttributeAudience::PUBLIC)).to eq({})
    expect(People::Ownership).to have_received(:reachable_ids)
      .with(student_entity, [student.id.to_s], viewer: nil, audience: EntityAttributeAudience::PUBLIC, customer_id: customer.id)
  end

  it "ignores a run whose current step is not this page" do
    expect(resolve(run_with(student.id, step: "start"))).to eq({})
  end
end
