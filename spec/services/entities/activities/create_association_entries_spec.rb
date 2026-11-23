# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Activities::CreateAssociationEntries do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }

  include_context "student course association"

  def run(rows, **overrides)
    described_class.call(customer: customer, actor: actor, entity: student_entity, entry: student,
                         association_id: bridge_entity.id, rows: rows, **overrides)
  end

  def row(**data) = ActionController::Parameters.new(data)
  def bridge_rows = EntityEntry.where(entity_id: bridge_entity.id).order(:id)

  it "creates every row linked to the entry with the admin audience" do
    signal, ctx = nil
    expect { signal, ctx = run([row(course: math.id.to_s, status: "enrolled", grade: "80"), row(course: physics.id.to_s, status: "enrolled")]) }
      .to change(EntityEntry, :count).by(2)

    expect(signal.to_h[:semantic]).to eq(:success)
    expect(ctx[:models].map(&:id)).to eq(bridge_rows.map(&:id))
    expect(bridge_rows.map { |entry| entry.data_json.slice("student", "course") }).to eq([
      { "student" => student.id.to_s, "course" => math.id.to_s },
      { "student" => student.id.to_s, "course" => physics.id.to_s }
    ])
    expect(bridge_rows.map(&:customer_id).uniq).to eq([customer.id])
  end

  it "applies the bridge defaults to omitted fields and never writes hidden or forged keys" do
    run([row(course: math.id.to_s, secret: "forged", student: "0", customer_id: 0)])

    expect(bridge_rows.sole.data_json).to eq("course" => math.id.to_s, "status" => "enrolled", "grade" => nil, "student" => student.id.to_s)
  end

  it "writes nothing when one row is invalid and keeps each row's errors" do
    signal, ctx = nil
    expect { signal, ctx = run([row(course: math.id.to_s, status: "enrolled"), row(course: "", grade: "abc"), "scalar"]) }
      .not_to change(EntityEntry, :count)

    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:forms].map { |form| form.errors.keys }).to eq([[], %w[grade], ["base"]])
    expect(ctx[:errors]).to eq({})
  end

  it "reports contract errors for every row that passed the form boundary" do
    _, ctx = run([row(course: "", status: "enrolled"), row(course: physics.id.to_s, status: "enrolled", grade: "150")])

    expect(ctx[:forms].map { |form| form.errors.keys }).to eq([%w[course], %w[grade]])
  end

  it "requires at least one row and at most MAX_ROWS" do
    signal, ctx = run([])
    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:forms].size).to eq(1)
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.association_entries.errors.no_rows")])

    _, ctx = run("not rows")
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.association_entries.errors.no_rows")])

    _, ctx = run(Array.new(described_class::MAX_ROWS + 1) { row(course: math.id.to_s, status: "enrolled") })
    expect(ctx[:forms].size).to eq(described_class::MAX_ROWS)
    expect(ctx[:errors]["base"]).to eq([I18n.t("admin_misc.entities.association_entries.errors.too_many_rows", count: described_class::MAX_ROWS)])
    expect(bridge_rows).to be_empty
  end

  it "falls back to the translated save failure when a save reports no details" do
    allow(Entries::Save).to receive(:call).and_return(
      Entries::Save::Result.new(
        entry: nil,
        errors: [I18n.t("admin_misc.entities.entry_form.errors.save_failed")],
        field_errors: []
      )
    )

    signal, ctx = run([row(course: math.id.to_s, status: "enrolled")])

    expect(signal.to_h[:semantic]).to eq(:failure)
    expect(ctx[:forms].sole.errors["base"]).to eq([I18n.t("admin_misc.entities.entry_form.errors.save_failed")])
    expect(Entries::Save).to have_received(:call).with(hash_including(audience: "admin"))
  end

  context "when the associated entity is shared" do
    let(:course_entity) do
      create(:entity, customer: nil, name: "Course", display_label: "Course",
                      property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json)
    end
    let(:other_customer) { create(:customer) }
    let!(:foreign_course) { create(:entity_entry, :with_data, customer: other_customer, entity: course_entity, entry_data: { "code" => "THEIRS" }) }

    it "links this tenant's records of the shared entity and rejects another tenant's" do
      signal, = run([row(course: math.id.to_s, status: "enrolled")])
      expect(signal.to_h[:semantic]).to eq(:success)
      expect(bridge_rows.sole).to have_attributes(customer_id: customer.id)

      signal, ctx = run([row(course: foreign_course.id.to_s, status: "enrolled")])
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:forms].sole.errors["base"].join).to include("Course")
      expect(bridge_rows.count).to eq(1)
    end

    it "lists only this tenant's rows" do
      enroll(student, math)
      create(:entity_entry, :with_data, customer: other_customer, entity: bridge_entity,
                                        entry_data: { "student" => student.id.to_s, "course" => foreign_course.id.to_s })
      association = Entities::EntryAssociations.new(entity: student_entity, customer: customer).find(bridge_entity.id)

      expect(association.target).to eq(course_entity)
      expect(Entities::EntryAssociations.new(entity: student_entity, customer: customer).rows(association, student).map(&:customer_id))
        .to eq([customer.id])
    end
  end

  describe "authorization" do
    it "forbids members, other tenants' admins, other entities' entries and undeclared associations" do
      cases = [
        { actor: create(:user, :member, customer: customer) },
        { actor: create(:user, :admin, customer: create(:customer)) },
        { entity: unrelated = create(:entity, customer: customer), entry: create(:entity_entry, :with_data, customer: customer, entity: unrelated, entry_data: {}) },
        { entry: create(:entity_entry, :with_data, entity: create(:entity), entry_data: {}) },
        { association_id: 0 }
      ]

      cases.each do |overrides|
        signal, = run([row(course: math.id.to_s, status: "enrolled")], **overrides)
        expect(signal.to_h[:semantic]).to eq(:forbidden), overrides.keys.inspect
      end
      expect(bridge_rows).to be_empty
    end

    it "lets the platform owner write into this tenant" do
      signal, = run([row(course: math.id.to_s, status: "enrolled")], actor: find_or_create_platform_owner)

      expect(signal.to_h[:semantic]).to eq(:success)
      expect(bridge_rows.sole.customer_id).to eq(customer.id)
    end
  end
end
