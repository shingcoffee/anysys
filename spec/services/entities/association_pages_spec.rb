# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::AssociationPages do
  include JourneyPageHelpers
  include_context "student course association"

  let(:customer) { create(:customer) }

  def association_on(entity) = Entities::EntryAssociations.new(entity: entity, customer: customer).find(bridge_entity.id)

  def link_page(launched: true, modes: %w[create], inputs: [{ field: "student", entity_id: student_entity.id }], **attributes)
    journey_page(bridge_entity, action_key: "student_courses", launched: launched, **attributes,
                                fields: [journey_reference_field("student", student_entity, "full_name"),
                                         journey_reference_field("course", course_entity, "code")],
                                form_settings: { modes: modes, inputs: inputs })
  end

  def find(entity, mode: :create)
    described_class.find(association: association_on(entity), entity: entity, customer_id: customer.id, mode: mode)
  end

  it "finds the launched admin page that locks exactly the record's side and serves the action" do
    page = link_page

    expect(find(student_entity)).to eq(page)
    expect(find(student_entity, mode: :update)).to be_nil
  end

  it "leaves the other side's section alone" do
    link_page

    expect(find(course_entity)).to be_nil
  end

  it "skips unlaunched pages and pages that lock more than the record" do
    link_page(launched: false)
    link_page(inputs: [{ field: "student", entity_id: student_entity.id }, { field: "course", entity_id: course_entity.id }])

    expect(find(student_entity)).to be_nil
  end
end
