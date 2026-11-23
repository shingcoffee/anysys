# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::LockedInputsComponent, type: :component do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let(:inputs) { [{ field: "student", entity_id: student_entity.id }, { field: "course", entity_id: course_entity.id }] }
  let(:bridge_page) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: bridge_entity,
                    configuration: { form_settings: { inputs: inputs }, pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
  end

  before { Current.customer = customer }
  after { Current.customer = nil }

  def render_card(bindings)
    render_inline(described_class.new(page: bridge_page, bindings: bindings))
  end

  it "lists each bound input with its attribute name and the record's label" do
    render_card("student" => student.id.to_s, "course" => math.id.to_s)

    card = page.find("[data-role='locked-inputs']")
    expect(card).to have_css("dt", text: "Student")
    expect(card).to have_css("dd", text: "Ada")
    expect(card).to have_css("dt", text: "Course")
    expect(card).to have_css("dd", text: "MATH-101")
  end

  it "labels an unnamed record by its id" do
    student.update!(data: {}.to_json)
    render_card("student" => student.id.to_s)

    expect(page).to have_css("dd", text: Entities::ReferenceLabels.text(nil, student.id))
  end

  it "renders nothing without bindings for declared inputs" do
    render_card({})
    expect(page).not_to have_css("[data-role='locked-inputs']")

    render_card("grade" => "1")
    expect(page).not_to have_css("[data-role='locked-inputs']")
  end

  it "uses the records Pages::InputBindings already loaded instead of reading them again" do
    bound = Pages::InputBindings::Bound.new.merge!("student" => student.id.to_s)
    bound.records["student"] = student
    allow(EntityEntry).to receive(:find_by).and_call_original

    render_card(bound)

    expect(page).to have_css("dd", text: "Ada")
    expect(EntityEntry).not_to have_received(:find_by)
  end

  it "never shows another tenant's record" do
    foreign = create(:entity_entry, :with_data, customer: create(:customer), entity: student_entity, entry_data: { "full_name" => "Eve" })
    render_card("student" => foreign.id.to_s)

    expect(page).not_to have_text("Eve")
  end
end
