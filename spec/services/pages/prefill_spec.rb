# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Prefill do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }

  let(:student) { Entity.find_by!(customer_id: customer.id, name: "Student") }
  let(:course) { Entity.find_by!(customer_id: customer.id, name: "Course") }
  let(:enrollment) { Entity.find_by!(customer_id: customer.id, name: "Enrollment") }

  let(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
  let(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
  let(:own_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" }) }
  let(:foreign_course) do
    foreign_entity = create(:entity, customer: other_customer, name: "Course",
                            property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(:entity_entry, :with_data, entity: foreign_entity, customer: other_customer, entry_data: { "title" => "X" })
  end

  let(:page) { enroll_page }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)

    name_field = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(:entity, customer: customer, name: "Enrollment", category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id,
        "html_type" => "select" },
      { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id,
        "html_type" => "select" },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "text" },
      { "name" => "Internal", "name_slug" => "internal_note", "html_type" => "text",
        "visibility" => { "admin" => true, "member" => false, "public" => false } }
    ].to_json)
  end

  def enroll_page(*traits)
    traits = %i[for_member launched] if traits.empty?
    Current.set(customer: customer) do
      create(:page, *traits, customer: customer, entity: enrollment, configuration_json: {
        "metadata" => { "entity_id" => enrollment.id, "entity_name" => enrollment.name },
        "pages" => [{
          "id" => "p1",
          "fields" => [
            { "id" => "student", "property_slug" => "student", "html_type" => "select", "source" => "entity" },
            { "id" => "course", "property_slug" => "course", "html_type" => "select", "source" => "entity" },
            { "id" => "notes", "property_slug" => "notes", "html_type" => "text", "source" => "entity" },
            { "id" => "internal_note", "property_slug" => "internal_note", "html_type" => "text", "source" => "entity" }
          ]
        }]
      })
    end
  end

  def prefill_values(params, audience: EntityAttributeAudience::MEMBER, viewer: member, for_page: page)
    Current.set(customer: customer) do
      described_class.values(page: for_page, params: params, audience: audience, viewer: viewer)
    end
  end

  def prefill(hash)
    { "prefill" => hash }
  end

  it "keeps a visible text field" do
    expect(prefill_values(prefill("notes" => "Bring a laptop"))).to eq("notes" => "Bring a laptop")
  end

  it "keeps an in-scope reference" do
    expect(prefill_values(prefill("course" => own_course.id.to_s))).to eq("course" => own_course.id.to_s)
  end

  it "drops a field hidden from the audience" do
    expect(prefill_values(prefill("internal_note" => "secret", "notes" => "ok"))).to eq("notes" => "ok")
  end

  it "drops an unknown slug" do
    expect(prefill_values(prefill("not_a_field" => "x", "notes" => "ok"))).to eq("notes" => "ok")
  end

  it "never prefills a file field from a link" do
    receipts = create(:entity, customer: customer, name: "Receipt", property_schema: [
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "text" },
      { "name" => "Scan", "name_slug" => "scan", "html_type" => "file" }
    ].to_json)
    receipt_page = Current.set(customer: customer) do
      create(:page, :launched, customer: customer, entity: receipts, configuration_json: {
        "metadata" => { "entity_id" => receipts.id, "entity_name" => receipts.name },
        "pages" => [{ "id" => "p1", "fields" => [
          { "id" => "notes", "property_slug" => "notes", "html_type" => "text", "source" => "entity" },
          { "id" => "scan", "property_slug" => "scan", "html_type" => "file", "source" => "entity" }
        ] }]
      })
    end

    expect(prefill_values(prefill("scan" => "x.pdf", "notes" => "ok"), audience: EntityAttributeAudience::ADMIN,
                          viewer: create(:user, :admin, customer: customer), for_page: receipt_page)).to eq("notes" => "ok")
  end

  it "never prefills the owner reference" do
    expect(prefill_values(prefill("student" => own_student.id.to_s, "notes" => "ok"))).to eq("notes" => "ok")
    expect(prefill_values(
      prefill("student" => own_student.id.to_s),
      audience: EntityAttributeAudience::ADMIN,
      viewer: create(:user, :admin, customer: customer)
    )).to eq({})
  end

  it "drops a reference id outside the viewer's options" do
    expect(prefill_values(prefill("student" => peer_student.id.to_s))).to eq({})
    expect(prefill_values(prefill("course" => foreign_course.id.to_s, "notes" => "ok"))).to eq("notes" => "ok")
  end

  it "never raises on malformed params" do
    expect { prefill_values(nil) }.not_to raise_error
    expect { prefill_values([]) }.not_to raise_error
    expect { prefill_values({ "prefill" => %w[notes x] }) }.not_to raise_error
    expect { prefill_values(prefill("notes" => { "nested" => "1" })) }.not_to raise_error
    expect { prefill_values(prefill("notes" => %w[a b])) }.not_to raise_error
    expect { prefill_values(ActionController::Parameters.new(prefill: { notes: 12 })) }.not_to raise_error

    expect(prefill_values(nil)).to eq({})
    expect(prefill_values({ "prefill" => %w[notes x] })).to eq({})
    expect(prefill_values(prefill("notes" => { "nested" => "1" }))).to eq({})
    expect(prefill_values(prefill("notes" => %w[a b]))).to eq({})
    expect(prefill_values(ActionController::Parameters.new(prefill: { notes: 12 }))).to eq("notes" => "12")
  end

  it "applies the action-link prefill limits" do
    extras = (1..11).to_h { |n| ["notes_#{n}", "v#{n}"] }
    page_with_many = Current.set(customer: customer) do
      fields = (1..11).map { |n|
        { "id" => "notes_#{n}", "property_slug" => "notes_#{n}", "html_type" => "text", "source" => "entity" }
      }
      schema = (1..11).map { |n| { "name" => "Notes #{n}", "name_slug" => "notes_#{n}", "html_type" => "text" } }
      entity = create(:entity, customer: customer, property_schema: schema.to_json)
      create(:page, :for_member, :launched, customer: customer, entity: entity, configuration_json: {
        "metadata" => { "entity_id" => entity.id },
        "pages" => [{ "id" => "p1", "fields" => fields }]
      })
    end

    kept = prefill_values({ "prefill" => extras.merge("notes_11" => "too-many") }, for_page: page_with_many)
    expect(kept.keys).to eq((1..10).map { |n| "notes_#{n}" })
    expect(kept).not_to have_key("notes_11")

    expect(prefill_values(prefill("notes" => "x" * 201))).to eq({})
    expect(prefill_values(prefill("notes" => "x" * 200))).to eq("notes" => "x" * 200)
  end
end
