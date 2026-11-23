# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Api::Mapper do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:domain) { create(:entity_domain, customer: customer) }
  let(:mapper) { described_class.new(customer: customer) }

  def access(visible: true, rules: true)
    flags = { "admin" => true, "member" => true, "public" => visible }
    apply = { "admin" => true, "member" => true, "public" => rules && visible }
    { "visible_to" => flags, "rules_apply_to" => apply }
  end

  def persist!(spec)
    definition = mapper.to_definition(spec)
    signal, (ctx, *) = EntityDefinitions::Persist.call({ entities: [definition], customer: customer, domain: domain })
    expect(signal.to_h[:semantic]).to eq(:success), Array(ctx[:errors]).inspect
    Entity.find_by!(customer_id: customer.id, name: spec["name"])
  end

  describe "#to_definition" do
    it "emits only keys present on the spec" do
      expect(mapper.to_definition("name" => "Student")).to eq("name" => "Student")
    end

    it "maps public identity, settings, groups, attributes and associations" do
      definition = mapper.to_definition(
        "name" => "Student",
        "display_label" => "Learner",
        "description" => "Enrolled people",
        "extends" => "Authentication::User",
        "settings" => { "icon" => "user", "color" => "#111827", "default_values" => { "status" => "applied" } },
        "attribute_groups" => [{ "key" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" }],
        "attributes" => [{ "name" => "Email", "html_type" => "email", "group" => "basics" }],
        "associations" => [{ "related_entity" => "Course", "display_field" => "title" }]
      )

      expect(definition).to include(
        "name" => "Student",
        "display_label" => "Learner",
        "description" => "Enrolled people",
        "extended_model" => "Authentication::User",
        "icon" => "user",
        "color" => "#111827",
        "default_properties" => { "status" => "applied" }
      )
      expect(definition["attribute_groups"]).to eq(
        [{ "id" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" }]
      )
      expect(definition["property_schema"].first).to include("name" => "Email", "group_id" => "basics")
      expect(definition["associations"]).to eq(
        [{
          "associated_entity_name" => "Course",
          "display_field" => "title",
          "display_field_label" => "Title"
        }]
      )
    end
  end

  describe "attribute round-trips" do
    def round_trip(public_attr)
      mapper.attribute_from_stored(mapper.attribute_to_stored(public_attr))
    end

    it "round-trips an input text field with rules, access and a group" do
      attr = {
        "name" => "Title",
        "slug" => "title",
        "display_label" => "Title",
        "description" => "Course title",
        "kind" => "input",
        "html_type" => "text",
        "group" => "basics",
        "rules" => [{ "type" => "presence" }, { "type" => "length_maximum", "value" => 120 }],
        "access" => access
      }

      expect(round_trip(attr)).to eq(attr)
    end

    it "stores who may edit a field only when someone who sees it may not" do
      readonly = access.merge("editable_by" => { "admin" => true, "member" => false, "public" => false })
      attr = { "name" => "Status", "slug" => "status", "display_label" => "Status", "kind" => "input",
               "html_type" => "text", "access" => readonly }

      stored = mapper.attribute_to_stored(attr)
      expect(stored["editable"]).to eq("admin" => true, "member" => false, "public" => false)
      expect(round_trip(attr)).to eq(attr)

      everyone = mapper.attribute_to_stored(attr.merge("access" => access.merge("editable_by" => { "member" => true })))
      expect(everyone).not_to have_key("editable")
      expect(mapper.attribute_from_stored(everyone)["access"]).not_to have_key("editable_by")
    end

    it "keeps who may edit a field when a later change only touches visibility" do
      stored = mapper.attribute_to_stored({ "name" => "Status", "slug" => "status", "kind" => "input", "html_type" => "text",
                                            "access" => { "editable_by" => { "member" => false } } })
      patched = mapper.attribute_from_stored(stored)
      patched["access"] = patched["access"].merge("visible_to" => { "admin" => true, "member" => true, "public" => false })

      expect(mapper.attribute_to_stored(patched, base: stored)["editable"]).to eq("admin" => true, "member" => false, "public" => false)
    end

    describe "status lifecycle" do
      let(:lifecycle) do
        { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => %w[member] },
                            { "from" => "submitted", "to" => "approved", "by" => %w[admin system] }] }
      end
      let(:status) do
        { "name" => "Status", "slug" => "status", "display_label" => "Status", "kind" => "input", "html_type" => "select",
          "access" => access,
          "options" => { "source" => "static", "values" => [
            { "label" => "Draft", "value" => "draft", "default" => true },
            { "label" => "Submitted", "value" => "submitted" }, { "label" => "Approved", "value" => "approved" }
          ] },
          "lifecycle" => lifecycle }
      end

      it "stores the lifecycle as given beside the static options and reads it back" do
        stored = mapper.attribute_to_stored(status)

        expect(stored["lifecycle"]).to eq(lifecycle)
        expect(stored["config"]).to include("source" => "manual")
        expect(Entities::Lifecycle.from_attribute(stored)).to have_attributes(initial: "draft")
        expect(round_trip(status)).to include("lifecycle" => lifecycle)
      end

      it "keeps the lifecycle when a patch touches another key and clears it when the patch nulls it" do
        stored = mapper.attribute_to_stored(status)
        relabelled = mapper.attribute_from_stored(stored).merge("display_label" => "State")
        cleared = EntityDefinitions::Api::MergePatch.apply(mapper.attribute_from_stored(stored), { "lifecycle" => nil })

        expect(mapper.attribute_to_stored(relabelled, base: stored)["lifecycle"]).to eq(lifecycle)
        expect(mapper.attribute_to_stored(cleared, base: stored)).not_to have_key("lifecycle")
        expect(mapper.attribute_to_stored(status.merge("lifecycle" => nil))).not_to have_key("lifecycle")
      end

      it "leaves attributes without a lifecycle alone" do
        expect(mapper.attribute_to_stored(status.except("lifecycle"))).not_to have_key("lifecycle")
        expect(mapper.attribute_from_stored(mapper.attribute_to_stored(status).merge("lifecycle" => "draft"))).not_to have_key("lifecycle")
      end
    end

    it "round-trips every rule config kind" do
      attr = {
        "name" => "Score",
        "slug" => "score",
        "display_label" => "Score",
        "kind" => "input",
        "html_type" => "number",
        "rules" => [
          { "type" => "presence" },
          { "type" => "greater_than_or_equal_to", "value" => 0 },
          { "type" => "length_in_range", "min" => 1, "max" => 5 },
          { "type" => "format_custom", "pattern" => "\\A\\d+\\z" },
          { "type" => "exclusion", "values" => %w[x y] }
        ],
        "access" => access
      }

      expect(round_trip(attr)).to eq(attr)
    end

    it "round-trips a static select, collapsing string options and syncing inclusion" do
      attr = {
        "name" => "Level",
        "slug" => "level",
        "display_label" => "Level",
        "kind" => "input",
        "html_type" => "select",
        "rules" => [{ "type" => "presence" }, { "type" => "inclusion", "values" => %w[Beginner Intermediate Advanced] }],
        "access" => access,
        "options" => { "source" => "static", "values" => %w[Beginner Intermediate Advanced] }
      }

      stored = mapper.attribute_to_stored(attr)
      expect(stored["config"]).to eq(
        "source" => "manual",
        "options" => [
          { "label" => "Beginner", "value" => "Beginner", "default" => false },
          { "label" => "Intermediate", "value" => "Intermediate", "default" => false },
          { "label" => "Advanced", "value" => "Advanced", "default" => false }
        ]
      )
      expect(stored["validators"]).to eq(
        [
          { "type" => "presence" },
          { "type" => "inclusion", "config" => { "values" => %w[Beginner Intermediate Advanced] } }
        ]
      )
      expect(mapper.attribute_from_stored(stored)).to eq(attr)
    end

    it "replaces an authored inclusion rule with the option values" do
      stored = mapper.attribute_to_stored({
        "name" => "Level",
        "html_type" => "select",
        "rules" => [{ "type" => "inclusion", "values" => %w[stale] }],
        "options" => { "source" => "static", "values" => %w[A B] }
      })

      expect(stored["validators"]).to eq([{ "type" => "inclusion", "config" => { "values" => %w[A B] } }])
    end

    it "round-trips a constant select" do
      constant = create(:constant, :with_status, :customer_specific, customer: customer)
      attr = {
        "name" => "Status",
        "slug" => "status",
        "display_label" => "Status",
        "kind" => "input",
        "html_type" => "select",
        "rules" => [{ "type" => "inclusion", "values" => constant.options }],
        "access" => access,
        "options" => { "source" => "constant", "constant" => constant.name }
      }

      stored = mapper.attribute_to_stored(attr)
      expect(stored["config"]).to include(
        "source" => "constant",
        "constant_id" => constant.id,
        "constant_name" => constant.name,
        "options" => constant.options
      )
      expect(mapper.attribute_from_stored(stored)).to eq(attr)
    end

    it "prefers a customer-owned constant when a shared row shares the name" do
      create(:constant, name: "Priority", options: %w[shared], customer: nil)
      owned = create(:constant, name: "Priority", options: %w[owned], customer: customer)

      stored = mapper.attribute_to_stored({
        "name" => "Priority",
        "html_type" => "select",
        "options" => { "source" => "constant", "constant" => "Priority" }
      })

      expect(stored.dig("config", "constant_id")).to eq(owned.id)
      expect(stored.dig("config", "options")).to eq(%w[owned])
    end

    it "round-trips an entity-entries select without syncing inclusion" do
      attr = {
        "name" => "Course",
        "slug" => "course",
        "display_label" => "Course",
        "kind" => "input",
        "html_type" => "select",
        "rules" => [{ "type" => "presence" }],
        "access" => access,
        "options" => {
          "source" => "entity_entries",
          "entity" => "Course",
          "label_field" => "title"
        }
      }

      stored = mapper.attribute_to_stored(attr)
      expect(stored["config"]).to eq(
        "options_entity_name" => "Course",
        "label_field" => "title"
      )
      expect(stored["validators"]).to eq([{ "type" => "presence" }])
      expect(mapper.attribute_from_stored(stored)).to eq(attr)
    end

    it "round-trips owner: true on an entity-entries select and omits it otherwise" do
      attr = {
        "name" => "Student",
        "slug" => "student",
        "display_label" => "Student",
        "kind" => "input",
        "html_type" => "select",
        "access" => access,
        "owner" => true,
        "options" => {
          "source" => "entity_entries",
          "entity" => "Student",
          "label_field" => "student_id"
        }
      }

      stored = mapper.attribute_to_stored(attr)
      expect(stored["owner"]).to eq(true)
      expect(mapper.attribute_from_stored(stored)).to eq(attr)

      without = mapper.attribute_to_stored(attr.merge("owner" => false))
      expect(without).not_to have_key("owner")
      expect(mapper.attribute_from_stored(without)).not_to have_key("owner")

      omitted = mapper.attribute_to_stored(attr.except("owner"))
      expect(omitted).not_to have_key("owner")
      expect(mapper.attribute_from_stored(omitted)).not_to have_key("owner")
    end

    it "clears a stored owner flag when the public attribute sets owner false" do
      base = {
        "name" => "Student",
        "name_slug" => "student",
        "html_type" => "select",
        "owner" => true,
        "config" => { "options_entity_name" => "Student", "label_field" => "student_id" }
      }
      stored = mapper.attribute_to_stored({ "owner" => false }, base: base)

      expect(stored).to include("html_type" => "select")
      expect(stored).not_to have_key("owner")
    end

    it "round-trips file settings" do
      attr = {
        "name" => "Resume",
        "slug" => "resume",
        "display_label" => "Resume",
        "kind" => "input",
        "html_type" => "file",
        "access" => access,
        "file" => { "accept" => ".pdf", "multiple" => false }
      }

      expect(round_trip(attr)).to eq(attr)
    end

    it "round-trips a calculated field" do
      attr = {
        "name" => "Total",
        "slug" => "total",
        "display_label" => "Total",
        "kind" => "calculated",
        "html_type" => "number",
        "access" => access,
        "formula" => "price * quantity"
      }

      stored = mapper.attribute_to_stored(attr)
      expect(stored).to include("type" => "Calculated", "formula" => "price * quantity", "readonly" => true, "storage" => "computed")
      expect(mapper.attribute_from_stored(stored)).to eq(attr)
    end

    it "round-trips a computed aggregate in both directions" do
      %w[source target].each do |direction|
        attr = {
          "name" => "Course count",
          "slug" => "course_count",
          "display_label" => "Course count",
          "kind" => "computed",
          "html_type" => "number",
          "access" => access,
          "aggregate" => {
            "related_entity" => "Course",
            "function" => "avg",
            "source_attribute" => "score",
            "precision" => 2,
            "filter" => { "attribute" => "status", "operator" => "=", "value" => "active" },
            "direction" => direction
          }
        }

        stored = mapper.attribute_to_stored(attr)
        expect(stored["html_type"]).to eq("number")
        expect(stored["type"]).to eq(Entity::COMPUTED_TYPE)
        expect(stored["config"]).to include(
          "target_entity_name" => "Course",
          "function" => "avg",
          "source_slug" => "score",
          "precision" => 2,
          "filter" => { "slug" => "status", "op" => "=", "value" => "active" },
          "bridge_role" => direction
        )
        expect(mapper.attribute_from_stored(stored)).to eq(attr)
      end
    end

    it "defaults computed direction to source" do
      stored = mapper.attribute_to_stored({
        "name" => "Count",
        "kind" => "computed",
        "aggregate" => { "related_entity" => "Course", "function" => "count" }
      })

      expect(stored.dig("config", "bridge_role")).to eq("source")
    end

    it "keeps unmodeled stored keys when a base attribute is given" do
      base = { "name" => "Email", "name_slug" => "email", "html_type" => "email", "type" => "String" }
      stored = mapper.attribute_to_stored({ "description" => "Work email" }, base: base)

      expect(stored).to include("type" => "String", "html_type" => "email", "description" => "Work email")
    end
  end

  describe "editor stored-shape parity" do
    it "matches the editor payload for a representative text attribute" do
      stored = mapper.attribute_to_stored({
        "name" => "Title",
        "slug" => "title",
        "display_label" => "Title",
        "description" => "Course title",
        "html_type" => "text",
        "group" => "basics",
        "rules" => [{ "type" => "presence" }, { "type" => "length_maximum", "value" => 120 }],
        "access" => access
      })

      expect(stored).to eq(
        "name" => "Title",
        "name_slug" => "title",
        "display_label" => "Title",
        "description" => "Course title",
        "html_type" => "text",
        "group_id" => "basics",
        "validators" => [
          { "type" => "presence" },
          { "type" => "length_maximum", "config" => { "value" => 120 } }
        ],
        "visibility" => { "admin" => true, "member" => true, "public" => true },
        "validator_apply" => { "admin" => true, "member" => true, "public" => true }
      )
    end

    it "matches the editor payload for a static select, including synced inclusion" do
      stored = mapper.attribute_to_stored({
        "name" => "Level",
        "html_type" => "select",
        "rules" => [{ "type" => "presence" }],
        "options" => { "source" => "static", "values" => %w[Beginner Intermediate] },
        "access" => access
      })

      expect(stored["config"]).to eq(
        "source" => "manual",
        "options" => [
          { "label" => "Beginner", "value" => "Beginner", "default" => false },
          { "label" => "Intermediate", "value" => "Intermediate", "default" => false }
        ]
      )
      expect(stored["validators"]).to include(
        { "type" => "inclusion", "config" => { "values" => %w[Beginner Intermediate] } }
      )
    end

    it "persists mapper output in the same stored shape the editor writes" do
      constant = create(:constant, :with_status, :customer_specific, customer: customer)
      entity = persist!(
        "name" => "Ticket",
        "attribute_groups" => [{ "key" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" }],
        "attributes" => [
          {
            "name" => "Title",
            "html_type" => "text",
            "group" => "basics",
            "rules" => [{ "type" => "presence" }],
            "access" => access
          },
          {
            "name" => "Level",
            "html_type" => "select",
            "group" => "basics",
            "options" => { "source" => "static", "values" => %w[Low High] },
            "access" => access
          },
          {
            "name" => "Status",
            "html_type" => "select",
            "group" => "basics",
            "options" => { "source" => "constant", "constant" => constant.name },
            "access" => access
          },
          {
            "name" => "Resume",
            "html_type" => "file",
            "file" => { "accept" => ".pdf", "multiple" => false },
            "access" => access
          },
          {
            "name" => "Total",
            "kind" => "calculated",
            "html_type" => "number",
            "formula" => "price * quantity",
            "access" => access
          }
        ]
      )

      by_slug = entity.property_schema_json.index_by { |attr| attr["name_slug"] }
      expect(by_slug["title"]).to include("name" => "Title", "html_type" => "text", "group_id" => "basics")
      expect(by_slug["title"]["validators"]).to eq([{ "type" => "presence" }])
      expect(by_slug["level"]["config"]).to include("source" => "manual")
      expect(by_slug["level"]["validators"]).to include(
        { "type" => "inclusion", "config" => { "values" => %w[Low High] } }
      )
      expect(by_slug["status"]["config"]).to include(
        "source" => "constant",
        "constant_id" => constant.id,
        "constant_name" => constant.name
      )
      expect(by_slug["status"]["config"]["options"]).to eq(
        constant.options.map { |value| { "value" => value, "label" => value } }
      )
      expect(by_slug["resume"]["config"]).to eq("accept" => ".pdf", "multiple" => false)
      expect(by_slug["total"]).to include("type" => "Calculated", "formula" => "price * quantity", "readonly" => true, "storage" => "computed")
    end
  end

  describe "#from_entity" do
    it "returns the public vocabulary with version, slug and bridge_entity" do
      create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
      persist!(
        "name" => "Student",
        "attributes" => [
          { "name" => "Email", "html_type" => "email" },
          {
            "name" => "Course count",
            "kind" => "computed",
            "aggregate" => { "related_entity" => "Course", "function" => "count", "direction" => "source" }
          }
        ],
        "associations" => [{
          "related_entity" => "Course",
          "display_field" => "title",
          "bridge_attributes" => [{ "name" => "Enrolled On", "html_type" => "date" }]
        }]
      )

      student = Entity.find_by!(customer_id: customer.id, name: "Student")
      public = mapper.from_entity(student)

      expect(public).not_to have_key("slug")
      expect(public["version"]).to eq(student.display_current_version.version_number)
      expect(public["associations"].first).to include(
        "related_entity" => "Course",
        "bridge_entity" => "assoc_student_course"
      )
      expect(public["associations"].first["bridge_attributes"].first).to include("name" => "Enrolled On")
      computed = public["attributes"].find { |attr| attr["kind"] == "computed" }
      expect(computed.dig("aggregate", "related_entity")).to eq("Course")
      expect(computed.dig("aggregate", "direction")).to eq("source")
    end
  end
end
