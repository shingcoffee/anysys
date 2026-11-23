# frozen_string_literal: true

require "rails_helper"

# How the test host below reports a definition it cannot apply. The real hosts
# raise their own: Persist::Writer::Failed, ChangePlan::Unplannable.
DefinitionAssignmentRefused = Class.new(StandardError)

# The in-memory half of writing a definition, extracted so that exactly one
# implementation exists. Persist::Writer drives it to write; the assistant's
# ChangePlan drives it on an unsaved copy to predict that write. If these two
# ever stopped sharing it, the plan would describe something other than what
# gets saved and the admin would approve a change they were not shown.
#
# Driven here through a minimal host rather than through either real caller, so
# what is being asserted is the module's own contract and not Persist's.
RSpec.describe EntityDefinitions::DefinitionAssignment do
  let_it_be(:customer) { create(:customer) }

  # The three things the module leaves to its host.
  let(:host_class) do
    Class.new do
      include EntityDefinitions::DefinitionAssignment

      attr_reader :tenant_id, :entities

      def initialize(tenant_id:, entities: {})
        @tenant_id = tenant_id
        @entities = entities
      end

      def fail!(messages) = raise(DefinitionAssignmentRefused, Array(messages).join(" "))

      def resolve_entity(name) = @entities[name.to_s]
    end
  end

  let(:host) { host_class.new(tenant_id: customer.id) }
  let(:refused) { DefinitionAssignmentRefused }
  let(:record) { build(:entity, customer: customer, name: "Student") }

  describe "#assign_identity" do
    it "takes the name it is given rather than the one in the definition" do
      host.assign_identity(record, { "name" => "Ignored" }, "Student")

      expect(record.name).to eq("Student")
    end

    it "falls back to the entity name when the definition carries no display_label" do
      host.assign_identity(record, {}, "Student")

      expect(record.display_label).to eq("Student")
    end

    it "falls back to the entity name when the display_label is blank" do
      record.display_label = "Student Record"
      host.assign_identity(record, { "display_label" => "  " }, "Student")

      expect(record.display_label).to eq("Student")
    end

    it "leaves extended_model alone when the definition omits the key" do
      record.extended_model = "Authentication::User"
      host.assign_identity(record, {}, "Student")

      expect(record.extended_model).to eq("Authentication::User")
    end

    # An explicit null is how a definition asks to stop extending a base model,
    # which is why the key's presence matters rather than its value.
    it "clears extended_model when the definition sends it as null" do
      record.extended_model = "Authentication::User"
      host.assign_identity(record, { "extended_model" => nil }, "Student")

      expect(record.extended_model).to be_nil
    end

    it "refuses a base model the tenant may not extend" do
      expect { host.assign_identity(record, { "extended_model" => "Made::Up" }, "Student") }
        .to raise_error(refused, /Made::Up/)
    end

    it "accepts a base model the tenant's enabled modules offer" do
      allow(ExtendableModelRegistry).to receive(:for_customer)
        .with(customer.id).and_return([{ class_name: "Authentication::User", label: "User", module_key: "auth" }])

      host.assign_identity(record, { "extended_model" => "Authentication::User" }, "Student")

      expect(record.extended_model).to eq("Authentication::User")
    end
  end

  describe "#assign_body" do
    # Merge-never-delete: a key the definition omits keeps whatever is stored,
    # which is what lets the model send a delta instead of a whole entity.
    %w[icon color description referenced_template].each do |field|
      it "leaves #{field} alone when the definition omits it" do
        record.public_send(:"#{field}=", "stored")
        host.assign_body(record, {})

        expect(record.public_send(field)).to eq("stored")
      end

      it "overwrites #{field} when the definition carries it" do
        record.public_send(:"#{field}=", "stored")
        host.assign_body(record, { field => "sent" })

        expect(record.public_send(field)).to eq("sent")
      end
    end

    it "leaves default_properties alone when the definition omits them" do
      record.default_properties_json = { "status" => "applied" }
      host.assign_body(record, {})

      expect(record.default_properties_json).to eq({ "status" => "applied" })
    end

    it "replaces default_properties wholesale when the definition carries them" do
      record.default_properties_json = { "status" => "applied", "year" => 2026 }
      host.assign_body(record, { "default_properties" => { "status" => "enrolled" } })

      expect(record.default_properties_json).to eq({ "status" => "enrolled" })
    end

    it "merges incoming attributes onto their stored twins and appends the new ones" do
      record.property_schema_json = [
        { "name" => "Email", "name_slug" => "email", "html_type" => "email", "description" => "Kept" }
      ]

      host.assign_body(record, {
        "property_schema" => [
          { "name_slug" => "email", "html_type" => "text" },
          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
        ]
      })

      expect(record.property_schema_json.map { |attr| attr["name_slug"] }).to eq(%w[email notes])
      expect(record.property_schema_json.first).to include("html_type" => "text", "description" => "Kept")
    end

    it "leaves the stored attributes alone when the definition omits property_schema" do
      stored = [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }]
      record.property_schema_json = stored

      host.assign_body(record, { "description" => "Changed" })

      expect(record.property_schema_json).to eq(stored)
    end

    # Computed attributes cannot be placed until every association in the batch
    # exists, so they are held back rather than merged in this pass.
    it "holds computed attributes back instead of merging them" do
      record.property_schema_json = []

      body = host.assign_body(record, {
        "property_schema" => [
          { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
          { "name" => "Total", "name_slug" => "total", "html_type" => "number", "type" => Entity::COMPUTED_TYPE }
        ]
      })

      expect(body.computed_attributes.map { |attr| attr["name"] }).to eq(["Total"])
      expect(body.computed_slots.map { |slot| slot[:index] }).to eq([1])
      expect(record.property_schema_json.map { |attr| attr["name"] }).to eq(["Email"])
    end

    it "writes the incoming attribute list exactly when replace is true" do
      record.property_schema_json = [
        { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
        { "name" => "Fax", "name_slug" => "fax", "html_type" => "tel" }
      ]

      host.assign_body(record, {
        "property_schema" => [
          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
        ]
      }, replace: true)

      expect(record.property_schema_json.map { |attr| attr["name_slug"] }).to eq(["notes"])
    end

    it "replaces groups wholesale when replace is true" do
      record.attribute_groups_json = [{ "id" => "g_old", "name" => "Old", "icon" => "folder", "color" => "slate" }]
      record.property_schema_json = []

      host.assign_body(record, {
        "attribute_groups" => [{ "id" => "g_new", "name" => "New", "icon" => "user", "color" => "indigo" }],
        "property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email", "group_id" => "g_new" }]
      }, replace: true)

      expect(record.attribute_groups_json.map { |group| group["id"] }).to eq(["g_new"])
    end

    it "reports the incoming groups it was given, and nil when there were none" do
      expect(host.assign_body(record, { "attribute_groups" => [{ "id" => "g", "name" => "G" }] }).incoming_groups)
        .to eq([{ "id" => "g", "name" => "G" }])
      expect(host.assign_body(record, {}).incoming_groups).to be_nil
    end

    it "regroups when the definition touches attributes or groups, and not otherwise" do
      record.property_schema_json = [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }]
      record.attribute_groups_json = []

      expect(EntityDefinitions::AttributeGrouper).to receive(:call).once.and_call_original
      host.assign_body(record, { "property_schema" => [] })
      host.assign_body(record, { "description" => "Changed" })
    end
  end

  describe "#partition_attributes" do
    it "splits computed attributes from input ones and keeps each side in order" do
      input, computed = host.partition_attributes(
        [
          { "name" => "A" },
          { "name" => "B", "type" => Entity::COMPUTED_TYPE },
          { "name" => "C" }
        ]
      )

      expect(input.map { |attr| attr["name"] }).to eq(%w[A C])
      expect(computed.map { |attr| attr["name"] }).to eq(["B"])
    end

    it "treats anything that is not an object as an input attribute, for the merge to drop" do
      input, computed = host.partition_attributes(["nonsense", nil])

      expect(input).to eq(["nonsense", nil])
      expect(computed).to eq([])
    end

    it "reads a missing list as two empty ones" do
      expect(host.partition_attributes(nil)).to eq([[], []])
    end
  end

  describe "#stored_associations" do
    let(:course) { create(:entity, customer: customer, name: "Course") }
    let(:host) { host_class.new(tenant_id: customer.id, entities: { "Course" => course }) }

    it "resolves each target name to its id and keeps the resolved name" do
      result = host.stored_associations(
        record,
        [{ "associated_entity_name" => "Course", "display_field" => "name", "display_field_label" => "Name" }]
      )

      expect(result).to eq(
        [{
          "target_entity_id" => course.id,
          "target_entity_name" => "Course",
          "display_field" => "name",
          "display_field_label" => "Name",
          "additional_attributes" => []
        }]
      )
    end

    it "refuses an association with no display field" do
      expect {
        host.stored_associations(record, [{ "associated_entity_name" => "Course", "display_field_label" => "Name" }])
      }.to raise_error(refused, /Course/)
    end

    it "refuses an association with no display field label" do
      expect {
        host.stored_associations(record, [{ "associated_entity_name" => "Course", "display_field" => "name" }])
      }.to raise_error(refused)
    end

    it "refuses an association whose target the host cannot resolve" do
      expect {
        host.stored_associations(
          record,
          [{ "associated_entity_name" => "Nowhere", "display_field" => "name", "display_field_label" => "Name" }]
        )
      }.to raise_error(refused, /Nowhere/)
    end

    it "refuses an entity linked to itself" do
      saved = create(:entity, customer: customer, name: "Student")
      linked = host_class.new(tenant_id: customer.id, entities: { "Student" => saved })

      expect {
        linked.stored_associations(
          saved,
          [{ "associated_entity_name" => "Student", "display_field" => "name", "display_field_label" => "Name" }]
        )
      }.to raise_error(refused)
    end

    it "reads a missing list as no associations at all" do
      expect(host.stored_associations(record, nil)).to eq([])
    end
  end

  describe "#resolve_computed" do
    let(:bridged) do
      record.associations_json = [{
        "target_entity_id" => 7,
        "target_entity_name" => "Course",
        "bridge_entity_id" => 42,
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }]
      record
    end

    let(:field) do
      {
        "name" => "Total",
        "name_slug" => "total",
        "html_type" => "number",
        "type" => Entity::COMPUTED_TYPE,
        "config" => { "target_entity_name" => "Course", "function" => "count" }
      }
    end

    # The authored target name is exchanged for the bridge it actually reads
    # through, and the result is forced read-only: a computed value is derived,
    # never typed in.
    it "swaps the authored target name for the bridge id and marks the field derived" do
      expect(host.resolve_computed(bridged, field)).to eq(
        field.merge(
          "config" => { "function" => "count", "bridge_entity_id" => 42, "bridge_role" => "source" },
          "readonly" => true,
          "storage" => "computed"
        )
      )
    end

    it "resolves a target-direction computed through the related entity's association" do
      course = create(:entity, customer: customer, name: "Course")
      student = create(:entity, customer: customer, name: "Student")
      student.associations_json = [{
        "target_entity_id" => course.id,
        "target_entity_name" => "Course",
        "bridge_entity_id" => 99,
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }]
      linked = host_class.new(tenant_id: customer.id, entities: { "Student" => student })
      target_field = field.merge("config" => { "target_entity_name" => "Student", "function" => "count", "bridge_role" => "target" })

      expect(linked.resolve_computed(course, target_field).dig("config", "bridge_entity_id")).to eq(99)
    end

    it "refuses a computed field whose config is not an object" do
      expect { host.resolve_computed(bridged, field.merge("config" => "nonsense")) }
        .to raise_error(refused, /Total/)
    end

    it "refuses a computed field whose target is not an association of this entity" do
      expect { host.resolve_computed(bridged, field.merge("config" => { "target_entity_name" => "Program" })) }
        .to raise_error(refused, /Program/)
    end

    it "refuses a computed field whose association has no bridge yet" do
      record.associations_json = [{ "target_entity_name" => "Course", "bridge_entity_id" => nil }]

      expect { host.resolve_computed(record, field) }.to raise_error(refused, /Course/)
    end
  end

  # Both real hosts drive the same assignment, but they answer two of its
  # questions differently on purpose. Each difference is safe in one direction
  # only, so each is asserted rather than assumed.
  describe "the change plan's deliberate differences from the writer" do
    let(:plan_host) do
      EntityDefinitions::Assistant::ChangePlan.new(entities: [], customer: customer)
    end

    # Planning a document that creates Course and points Student at it must not
    # collapse into "cannot plan" just because Course is not saved yet. The
    # stand-in is never written; only its name reaches the diff.
    it "stands in for an entity the same document creates later in the batch" do
      target = plan_host.send(:resolve_entity, "NotYetCreated")

      expect(target).to be_a(EntityDefinitions::Assistant::ChangePlan::PendingTarget)
      expect(target.id).to be_nil
      expect(target.name).to eq("NotYetCreated")
    end

    it "resolves a real entity to the record rather than to a stand-in" do
      course = create(:entity, customer: customer, name: "Course")

      expect(plan_host.send(:resolve_entity, "Course")).to eq(course)
    end

    it "never stands in for a blank name" do
      expect(plan_host.send(:resolve_entity, "  ")).to be_nil
    end

    # The writer refuses a base model the tenant may not extend; the plan does
    # not. Reporting the row the document asks for tells the admin more than
    # "this cannot be planned", and the write still refuses it on apply. The
    # override only ever yields MORE rows, so failing closed still holds.
    it "reports an impossible extended_model as a row instead of refusing to plan it" do
      create(:entity, customer: customer, name: "Student")

      plan = EntityDefinitions::Assistant::ChangePlan.call(
        entities: [{ "name" => "Student", "extended_model" => "Made::Up" }], customer: customer
      )

      expect(plan.entries.first["rows"]).to eq(
        [{
          "kind" => "identity",
          "action" => "modified",
          "field" => "extended_model",
          "before" => nil,
          "after" => "Made::Up",
          "breaking" => true
        }]
      )
      expect(plan.entries.first).not_to have_key("unplannable")
    end

    it "still refuses that same document on the way through Persist" do
      create(:entity, customer: customer, name: "Student")

      _signal, (ctx, *) = EntityDefinitions::Persist.call(
        { entities: [{ "name" => "Student", "extended_model" => "Made::Up" }], customer: customer }
      )

      expect(ctx[:errors]).to be_present
      expect(Entity.find_by!(customer_id: customer.id, name: "Student").extended_model).to be_nil
    end
  end
end
