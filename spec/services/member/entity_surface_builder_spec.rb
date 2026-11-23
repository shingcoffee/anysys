# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::EntitySurfaceBuilder do
  subject(:surface) { described_class.call(entity: entity, customer: customer) }

  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:entity) do
    e = Entity.new(
      customer_id: customer.id,
      name:        "Course",
      description: "Courses you've enrolled in."
    )
    e.property_schema_json = [
      { "name" => "Term",  "name_slug" => "term",  "type" => "string" },
      { "name" => "Score", "name_slug" => "score", "type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
    ]
    e.save!
    e
  end

  it "returns a Member::Surface" do
    expect(surface).to be_a(Member::Surface)
  end

  it "namespaces the surface key with entity_<id>" do
    expect(surface.key).to eq(:"entity_#{entity.id}")
  end

  it "uses the entity name as the label" do
    expect(surface.label).to eq("Course")
  end

  it "skips Calculated fields when building columns" do
    keys = surface.index.columns.map { |c| c[:key] }
    expect(keys).to include(:term, :score)
    expect(keys).not_to include(:total)
  end

  it "does not English-titleize an unlabeled attribute slug" do
    entity.property_schema_json = [
      { "name_slug" => "raw_slug", "type" => "string" }
    ]
    entity.save!
    col = described_class.call(entity: entity, customer: customer).index.columns.find { |c| c[:key] == :raw_slug }
    expect(col[:label]).to eq("raw_slug")
  end

  it "uses :money/:number/:string format for known types" do
    score_col = surface.index.columns.find { |c| c[:key] == :score }
    expect(score_col[:format]).to eq(:number)

    term_col = surface.index.columns.find { |c| c[:key] == :term }
    expect(term_col[:format]).to eq(:string)
  end

  it "lists every tenant row of an open entity and never another tenant's rows" do
    member = create(:user, :member, customer: customer)
    other_member = create(:user, :member, customer: customer)
    mine = create(:entity_entry, entity: entity, customer: customer)
    peer = create(:entity_entry, entity: entity, customer: customer)
    foreign_entity = create(:entity, customer: other_customer, name: "ForeignCourse")
    foreign_row = create(:entity_entry, entity: foreign_entity, customer: other_customer)

    scoped = surface.index.scope.call(member)
    expect(scoped).to include(mine, peer)
    expect(scoped).not_to include(foreign_row)
    expect(surface.index.scope.call(other_member)).to include(mine, peer)
  end

  it "defaults an open entity's surface off" do
    expect(surface.default_enabled?).to be(false)
  end

  it "subtitles with the entity description when present" do
    expect(surface.index.subtitle).to eq("Courses you've enrolled in.")
  end

  context "when the entity has no data fields" do
    let(:entity) do
      e = Entity.new(customer_id: customer.id, name: "Bare")
      e.property_schema_json = []
      e.save!
      e
    end

    it "falls back to a single :id column so validate! passes" do
      expect(surface.index.columns.map { |c| c[:key] }).to eq([:id])
      expect(surface.index.columns.first[:label]).to eq("ID")
    end

    it "uses default subtitle and empty copy when the entity has no description" do
      expect(surface.index.subtitle).to eq("Records linked to your account.")
      expect(surface.index.empty_state[:headline]).to eq("No bare yet")
      expect(surface.index.empty_state[:body]).to eq("Records will appear here once they're linked to your account.")
    end
  end

  context "with a default-position offset" do
    it "places entities after the DEFAULT_POSITION_BASE" do
      expect(surface.default_position).to be >= described_class::DEFAULT_POSITION_BASE
    end
  end

  describe "grouped output" do
    let(:customer) { create(:customer) }
    let(:entity) do
      e = create(:entity, customer: customer)
      # Definition body is virtual (head-content backed); set via *_json= + save!.
      e.attribute_groups_json = [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }]
      e.property_schema_json  = [{ "name" => "email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_1" }]
      e.save!
      Entity.find(e.id)
    end

    it "exposes grouped attribute sections via #groups" do
      surface = described_class.call(entity: entity, customer: customer)
      expect(surface).to respond_to(:groups)
      expect(surface.groups).to be_an(Array)
      expect(surface.groups.first[:group]["name"]).to eq("Contact")
      expect(surface.groups.first[:attributes].first["name_slug"]).to eq("email")
    end
  end

  describe "Detail delegation" do
    let(:customer) { create(:customer) }
    let(:entity) do
      e = create(:entity, customer: customer)
      e.attribute_groups_json = [{ "id" => "g_one", "name" => "Account" }]
      e.property_schema_json = [
        { "name" => "Email", "name_slug" => "email", "type" => "string",
          "html_type" => "email", "group_id" => "g_one" }
      ]
      e.save(validate: false) # mirror the old update_columns bypass (group styling irrelevant here)
      Entity.find(e.id)
    end

    it "delegates Detail construction to SurfaceTemplateApplier" do
      detail = double("Detail", title: nil, subtitle: nil, meta: nil, sections: [])
      expect(Member::SurfaceTemplateApplier)
        .to receive(:call).with(entity: entity).and_return(Member::Surface::Detail.new(
          title: ->(e) { "##{e.id}" }, subtitle: ->(_) { "" },
          sections: [{ key: :primary, title: "Account",
                       rows: [{ key: :email, label: "Email", span: 2,
                                value: ->(e) { e.data_json["email"] } }] }]
        ))

      surface = described_class.call(entity: entity, customer: customer)
      titles = surface.detail.sections.map { |s| s[:title] }
      expect(titles).to eq(["Account"])
    end

    it "falls back to a single :primary section when the applier returns nil" do
      allow(Member::SurfaceTemplateApplier).to receive(:call).and_return(nil)
      surface = described_class.call(entity: entity, customer: customer)
      expect(surface.detail.sections.map { |s| s[:key] }).to eq([:primary])
    end
  end

  describe "computed fields" do
    let(:entity) do
      e = create(:entity, customer: customer, name: "Student")
      e.property_schema_json = [
        { "name" => "Term", "name_slug" => "term", "type" => "string" },
        { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
          "visibility" => { "admin" => true, "member" => true, "public" => false } },
        { "name" => "Hidden Avg", "name_slug" => "hidden_avg", "type" => "Computed",
          "visibility" => { "member" => false } },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
      ]
      e.save(validate: false)
      e
    end

    it "includes a visible computed and reads it through display_text" do
      col = surface.index.columns.find { |c| c[:key] == :average_score }
      expect(col).to include(format: :number, align: :right)

      entry = create(:entity_entry, entity: entity, customer: customer, data: { "term" => "Fall" }.to_json)
      allow(entry).to receive(:display_text).with("average_score").and_return("87.5")

      expect(col[:value].call(entry)).to eq("87.5")
      expect(entry).to have_received(:display_text)
    end

    it "reads a text attribute's column through display_text" do
      col = surface.index.columns.find { |c| c[:key] == :term }
      entry = create(:entity_entry, entity: entity, customer: customer, data: { "term" => "Fall" }.to_json)
      allow(entry).to receive(:display_text).with("term").and_return("In person")

      expect(col[:value].call(entry)).to eq("In person")
      expect(entry).to have_received(:display_text)
    end

    it "reads a Date-typed attribute's column through data_json" do
      entity.property_schema_json = [
        { "name" => "Starts", "name_slug" => "starts_on", "type" => "Date" }
      ]
      entity.save!
      col = described_class.call(entity: entity, customer: customer).index.columns.find { |c| c[:key] == :starts_on }
      entry = create(:entity_entry, entity: entity, customer: customer, data: { "starts_on" => "2026-11-02" }.to_json)
      allow(entry).to receive(:data_json).and_return({ "starts_on" => Date.new(2026, 11, 2) })

      expect(col[:value].call(entry)).to eq(Date.new(2026, 11, 2))
    end

    it "excludes a computed when visibility.member is false" do
      keys = surface.index.columns.map { |c| c[:key] }
      expect(keys).to include(:average_score)
      expect(keys).not_to include(:hidden_avg)
    end

    it "still excludes Calculated fields" do
      expect(surface.index.columns.map { |c| c[:key] }).not_to include(:total)
    end
  end

  describe "member-hidden fields" do
    let(:entity) do
      e = create(:entity, customer: customer, name: "CourseHidden")
      e.property_schema_json = [
        { "name" => "Title", "name_slug" => "title", "type" => "string" },
        { "name" => "Internal", "name_slug" => "internal_note", "type" => "string",
          "visibility" => { "admin" => true, "member" => false, "public" => false } },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
      ]
      e.save(validate: false)
      e
    end

    it "omits attributes hidden from members from index columns, detail fields, and groups" do
      expect(surface.index.columns.map { |c| c[:key] }).to include(:title)
      expect(surface.index.columns.map { |c| c[:key] }).not_to include(:internal_note, :total)

      detail_keys = surface.detail.sections.flat_map { |s| Array(s[:rows]).map { |r| r[:key] } }
      expect(detail_keys).to include(:title)
      expect(detail_keys).not_to include(:internal_note, :total)

      group_slugs = surface.groups.flat_map { |g| Array(g[:attributes]).map { |a| a["name_slug"] } }
      expect(group_slugs).to include("title")
      expect(group_slugs).not_to include("internal_note", "total")
    end
  end

  describe "person and owned scopes" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:student) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Student", extended_model: person_model,
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:course) do
      create(:entity, customer: customer, name: "OwnedCourse",
             property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    end
    let(:enrollment) do
      student.associations_json = [association_to(course)]
      student.save!
      student.sync_bridge_entities!
      student.reload
      Entity.find(student.associations_list.first.fetch("bridge_entity_id"))
    end
    let(:member) { create(:user, :member, customer: customer) }
    let(:peer) { create(:user, :member, customer: customer) }
    let(:foreign_member) { create(:user, :member, customer: other_customer) }

    it "defaults a person or owned surface on" do
      expect(described_class.call(entity: student, customer: customer).default_enabled?).to be(true)
      expect(described_class.call(entity: enrollment, customer: customer).default_enabled?).to be(true)
    end

    it "scopes a person entity to the viewer's linked entry and hides another member and another tenant" do
      linked = create(:entity_entry, entity: student, customer: customer, user: member)
      create(:entity_entry, entity: student, customer: customer, user: peer)
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      foreign_student = create(:entity, customer: other_customer, name: "Student", extended_model: person_model)
      create(:entity_entry, entity: foreign_student, customer: other_customer, user: foreign_member)

      scoped = described_class.call(entity: student, customer: customer).index.scope
      expect(scoped.call(member)).to contain_exactly(linked)
      expect(scoped.call(peer)).not_to include(linked)
      expect(scoped.call(foreign_member)).to be_empty
    end

    it "lists only the member's owned enrollments and omits the owner column" do
      own_student = create(:entity_entry, entity: student, customer: customer, user: member)
      peer_student = create(:entity_entry, entity: student, customer: customer, user: peer)
      own_course = create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" })
      peer_course = create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "B" })
      mine = create(:entity_entry, :with_data, entity: enrollment, customer: customer,
                    entry_data: { "student" => own_student.id.to_s })
      create(:entity_entry, :with_data, entity: enrollment, customer: customer,
             entry_data: { "student" => peer_student.id.to_s })

      surface = described_class.call(entity: enrollment, customer: customer)
      expect(surface.index.scope.call(member)).to contain_exactly(mine)
      expect(surface.index.scope.call(peer)).not_to include(mine)
      expect(surface.index.columns.map { |c| c[:key] }).not_to include(:student)
      expect(surface.groups.flat_map { |g| Array(g[:attributes]).map { |a| a["name_slug"] } }).not_to include("student")
      expect(surface.detail.sections.flat_map { |s| Array(s[:rows]).map { |r| r[:key] } }).not_to include(:student)
    end

    it "scopes an owned surface to the viewer's own rows when the viewer is an admin" do
      admin = create(:user, :admin, customer: customer)
      admin_student = create(:entity_entry, entity: student, customer: customer, user: admin)
      member_student = create(:entity_entry, entity: student, customer: customer, user: member)
      own_course = create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "A" })
      admin_row = create(:entity_entry, :with_data, entity: enrollment, customer: customer,
                         entry_data: { "student" => admin_student.id.to_s })
      create(:entity_entry, :with_data, entity: enrollment, customer: customer,
             entry_data: { "student" => member_student.id.to_s })

      scoped = described_class.call(entity: enrollment, customer: customer).index.scope.call(admin)
      expect(scoped).to contain_exactly(admin_row)
    end

    it "enables a shared entity for members of the visiting tenant only" do
      shared = create(:entity, :shared, name: "SharedCourse")
      surface = described_class.call(entity: shared, customer: customer)

      expect(surface.enabled_for?(member)).to be(true)
      expect(surface.enabled_for?(foreign_member)).to be(false)
    end
  end

  def association_to(target)
    {
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "title",
      "display_field_label" => "Title",
      "additional_attributes" => []
    }
  end
end
