# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDomains::EntityOrder do
  def entity(id, label, links: 0)
    instance_double(Entity, id: id, display_label: label, associations_list: Array.new(links) { { "target_entity_id" => 99 } })
  end

  let(:course) { entity(1, "Course") }
  let(:student) { entity(2, "student", links: 1) }
  let(:enrolment) { entity(3, "Enrolment", links: 2) }
  let(:alias_course) { entity(4, "course") }

  it "puts entities declaring the most associations first, then the rest, breaking ties by label then id" do
    expect(described_class.sort([alias_course, course, student, enrolment])).to eq([enrolment, student, course, alias_course])
  end

  it "treats an entity declaring any association as primary" do
    expect([course, student, enrolment].map { |each| described_class.primary?(each) }).to eq([false, true, true])
  end

  it "sorts nothing into an empty list" do
    expect(described_class.sort(nil)).to eq([])
  end
end
