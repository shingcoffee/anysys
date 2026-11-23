# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Activities::UpdateAssociationEntry do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }

  include_context "student course association"

  let!(:enrollment) { enroll(student, math, status: "enrolled", grade: "60", secret: "kept") }

  def run(params, row: enrollment, **overrides)
    described_class.call(customer: customer, actor: actor, entity: student_entity, entry: student,
                         association_id: bridge_entity.id, row: row, params: params, **overrides)
  end

  it "rewrites the target and bridge attributes, keeping the back reference and hidden values" do
    signal, ctx = run(ActionController::Parameters.new(course: physics.id.to_s, grade: "99", student: "0", secret: "forged"))

    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:contract].class.validation_audience).to eq("admin")
    expect(enrollment.reload.data_json).to eq("student" => student.id.to_s, "course" => physics.id.to_s,
                                              "status" => "enrolled", "grade" => "99", "secret" => "kept")
  end

  it "keeps the stored row on validation failure" do
    signal, ctx = run({ "grade" => "101" })

    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors].keys).to eq(["grade"])
    expect(enrollment.reload.data_json["grade"]).to eq("60")
  end

  it "requires a submitted data object" do
    signal, ctx = run(nil)

    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.entry_form.errors.invalid_shape")])
  end

  it "forbids a row linked to another entry and a foreign admin" do
    theirs = enroll(create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: {}), math, grade: "1")

    expect(run({ "grade" => "2" }, row: theirs).first.to_h[:semantic]).to eq(:forbidden)
    expect(run({ "grade" => "2" }, actor: create(:user, :admin, customer: create(:customer))).first.to_h[:semantic]).to eq(:forbidden)
    expect(theirs.reload.data_json["grade"]).to eq("1")
    expect(enrollment.reload.data_json["grade"]).to eq("60")
  end
end
