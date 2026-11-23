# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Assistant::ChangePlan do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  # The plan is computed by simulating the write, so these examples are really
  # asserting what Persist would do. Whole rows are asserted rather than single
  # keys: the rows are the contract AiAssistant::ProposedChangesComponent
  # renders, and a silent shape change there is a change approved unseen.
  #
  # Values are machine values — a Hash, a boolean, an array of registry keys,
  # nil for absent — never pre-formatted strings, because the panel is rendered
  # later and possibly in another locale.
  def plan_for(entities, tenant: customer)
    described_class.call(entities: entities, customer: tenant)
  end

  def rows_for(entities, tenant: customer)
    plan_for(entities, tenant: tenant).entries.flat_map { |entry| entry["rows"] }
  end

  def student!(**attributes)
    create(:entity, customer: customer, name: "Student", **attributes)
  end

  def student_with_schema!(attributes, **rest)
    student!(property_schema: attributes.to_json, **rest)
  end

  # Every definition in these examples targets the one entity under test.
  def update(definition)
    [{ "name" => "Student" }.merge(definition)]
  end

  def attribute_row(field, before, after, name: "Email", breaking: false)
    {
      "kind" => "attribute",
      "action" => "modified",
      "name" => name,
      "field" => field,
      "before" => before,
      "after" => after,
      "breaking" => breaking
    }
  end

  describe "what counts as an entry" do
    it "omits an entity the document would leave exactly as it is" do
      entity = student!(
        display_label: "Student",
        description: "Enrolled people",
        icon: "user",
        color: "#111827",
        attribute_groups: [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
        property_schema: [{
          "name" => "Email",
          "name_slug" => "email",
          "html_type" => "email",
          "group_id" => "g_contact",
          "validators" => [{ "type" => "presence" }, { "type" => "format" }]
        }].to_json
      )

      plan = plan_for(
        [{
          "name" => "Student",
          "display_label" => "Student",
          "description" => "Enrolled people",
          "icon" => "user",
          "color" => "#111827",
          "default_properties" => {},
          "attribute_groups" => [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }],
          # Reordered on purpose: a validator list is a set, not an ordering.
          "property_schema" => [{
            "name" => "Email",
            "name_slug" => "email",
            "html_type" => "email",
            "group_id" => "g_contact",
            "validators" => [{ "type" => "format" }, { "type" => "presence" }]
          }]
        }]
      )

      expect(plan.entries).to eq([])
      expect(plan.changed_names).to eq([])
      expect(plan.breaking_names).to eq([])
      expect(plan.any?).to eq(false)
    end

    it "omits a name that does not exist in this tenant, because a create has nothing to review" do
      expect(plan_for([{ "name" => "Cohort", "property_schema" => [{ "name" => "Size" }] }]).entries).to eq([])
    end

    it "carries the record id and reports the changed name" do
      entity = student!(display_label: "Student")

      plan = plan_for(update("display_label" => "Learner"))

      expect(plan.entries.size).to eq(1)
      expect(plan.entries.first).to include("name" => "Student", "id" => entity.id)
      expect(plan.changed_names).to eq(["Student"])
      expect(plan.any?).to eq(true)
    end

    it "marks an entry breaking when any one of its rows is" do
      student_with_schema!([{ "name" => "Enrolled", "name_slug" => "enrolled", "html_type" => "date" }])

      plan = plan_for(
        update(
          "description" => "Now with a timestamp",
          "property_schema" => [{ "name" => "Enrolled", "name_slug" => "enrolled", "html_type" => "datetime-local" }]
        )
      )

      expect(plan.entries.first["breaking"]).to eq(true)
      expect(plan.entries.first["rows"].map { |row| row["breaking"] }).to eq([false, true])
      expect(plan.breaking_names).to eq(["Student"])
    end

    it "leaves an entry unbreaking when none of its rows are" do
      student!(description: "Before")

      plan = plan_for(update("description" => "After"))

      expect(plan.entries.first["breaking"]).to eq(false)
      expect(plan.breaking_names).to eq([])
    end

    it "keeps one entry per changed entity and skips the ones that did not change" do
      student!(description: "Before")
      create(:entity, customer: customer, name: "Course", description: "Unchanged",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)

      plan = plan_for(
        [
          { "name" => "Student", "description" => "After" },
          { "name" => "Course", "description" => "Unchanged" }
        ]
      )

      expect(plan.changed_names).to eq(["Student"])
    end

    it "serializes as its entries" do
      student!(description: "Before")

      plan = plan_for(update("description" => "After"))

      expect(plan.as_json).to eq(plan.entries)
    end

    it "ignores entries that are not objects and definitions without a usable name" do
      student!(description: "Before")

      expect(plan_for(["nonsense", nil, { "name" => "   " }, { "description" => "After" }]).entries).to eq([])
    end

    it "produces nothing without a tenant to compare against" do
      student!(description: "Before")

      expect(plan_for(update("description" => "After"), tenant: nil).entries).to eq([])
    end
  end

  describe "identity rows" do
    {
      "display_label" => %w[Student Learner],
      "extended_model" => [nil, "Authentication::User"],
      "icon" => %w[custom user],
      "color" => %w[#6366f1 #111827],
      "description" => %w[Before After]
    }.each do |field, (before, after)|
      it "emits a modified row when #{field} changes" do
        student!(field.to_sym => before)

        expect(rows_for(update(field => after))).to eq(
          [{
            "kind" => "identity",
            "action" => "modified",
            "field" => field,
            "before" => before,
            "after" => after,
            "breaking" => described_class::BREAKING_IDENTITY_KEYS.include?(field)
          }]
        )
      end
    end

    it "flags exactly the identity fields that re-home or re-base stored entries" do
      expect(described_class::BREAKING_IDENTITY_KEYS).to eq(%w[extended_model])
    end

    # Derived from the snapshot rather than from a list somebody maintains, so
    # a key added to the definition is reviewable the day it is added. `name`
    # is absent because a different name is a different entity, never an edit.
    it "declares the identity fields it can emit without enumerating them twice" do
      expect(described_class.identity_fields).to include("icon", "color", "description", "referenced_template")
      expect(described_class.identity_fields).to include("display_label", "extended_model")
      expect(described_class.identity_fields).not_to include("name", "name_slug")
      expect(described_class.identity_fields).not_to include("property_schema", "associations")
    end

    it "declares the attribute fields it can emit from the schema plus the synthetic ones" do
      expect(described_class.attribute_fields).to include("name", "html_type", "type", "readonly", "storage")
      expect(described_class.attribute_fields).to include("validators", "options", "options_source", "config", "group_id")
    end

    it "derives attribute_fields from Normalizer::ATTRIBUTE_KEYS rather than StructureSchema" do
      derived = (
        EntityDefinitions::Normalizer::ATTRIBUTE_KEYS -
          described_class::ATTRIBUTE_SPECIAL_KEYS
      ) | described_class::SYNTHETIC_ATTRIBUTE_KEYS | %w[group_id]

      expect(described_class.attribute_fields).to match_array(derived)
      expect(File.read(described_class.method(:attribute_fields).source_location.first))
        .not_to include("StructureSchema")
    end

    it "emits no row for an identity field the definition omits" do
      student!(description: "Kept", icon: "user")

      expect(rows_for(update({}))).to eq([])
    end
  end

  describe "attribute rows" do
    let(:groups) do
      [
        { "id" => "g_a", "name" => "Group A", "icon" => "folder", "color" => "slate" },
        { "id" => "g_b", "name" => "Group B", "icon" => "tag", "color" => "teal" }
      ]
    end

    # visibility and validator_apply are audience maps, not words; the plan
    # carries them as they are stored so the panel can word each audience.
    let(:all_audiences) { { "admin" => true, "member" => true, "public" => true } }

    let(:stored_attribute) do
      {
        "name" => "Email",
        "name_slug" => "email",
        "display_label" => "Email",
        "html_type" => "email",
        "type" => "String",
        "description" => "Old",
        "formula" => "1 + 1",
        "readonly" => false,
        "visibility" => all_audiences,
        "validator_apply" => all_audiences,
        "group_id" => "g_a",
        "storage" => "stored"
      }
    end

    describe "added" do
      it "emits an added row carrying the new field's html_type" do
        student_with_schema!([{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }])

        expect(rows_for(update("property_schema" => [{ "name" => "Notes", "html_type" => "textarea" }]))).to eq(
          [{ "kind" => "attribute", "action" => "added", "name" => "Notes", "html_type" => "textarea", "breaking" => false }]
        )
      end

      it "never marks an added attribute breaking, since nothing is stored under it yet" do
        student_with_schema!([])

        rows = rows_for(update("property_schema" => [{ "name" => "Notes", "html_type" => "textarea" }]))

        expect(rows.map { |row| row["breaking"] }).to eq([false])
      end

      it "names an added attribute by its slug when only a slug is given" do
        student_with_schema!([])

        rows = rows_for(update("property_schema" => [{ "name_slug" => "notes", "html_type" => "textarea" }]))

        expect(rows.first["name"]).to eq("notes")
      end

      it "names an added attribute by its display_label when it has a slug but no name" do
        student_with_schema!([])

        rows = rows_for(
          update("property_schema" => [{ "name_slug" => "notes", "display_label" => "Notes", "html_type" => "textarea" }])
        )

        expect(rows.first["name"]).to eq("Notes")
      end

      # An attribute with neither a name nor a slug has no key, so Persist has
      # nothing to merge it onto and there is nothing to review. The schema
      # rejects it long before the gate; this only keeps a row the component
      # could not render out of a panel the admin is asked to approve.
      it "skips an attribute the definition never names, rather than emitting a nameless row" do
        student_with_schema!([])

        expect(rows_for(update("property_schema" => [{ "html_type" => "textarea" }]))).to eq([])
      end

      it "skips a nameless attribute without dropping the named ones beside it" do
        student_with_schema!([])

        rows = rows_for(
          update("property_schema" => [{ "html_type" => "textarea" }, { "name" => "Notes", "html_type" => "textarea" }])
        )

        expect(rows.map { |row| row["name"] }).to eq(["Notes"])
      end

      # Normalizer defaults a missing control to text before Persist ever sees
      # it, so that is what an added field is planned as.
      it "reports the text control the normalizer defaults a typeless field to" do
        student_with_schema!([])

        rows = rows_for(update("property_schema" => [{ "name" => "Notes" }]))

        expect(rows.first).to include("html_type" => "text")
      end
    end

    describe "modified" do
      # sent => what the document carries, before/after => what the row reports.
      # They differ for group_id, which is sent as an id and reported as the
      # name the admin gave that section.
      {
        "display_label" => { sent: "E-mail", before: "Email", after: "E-mail" },
        "html_type" => { sent: "text", before: "email", after: "text" },
        "type" => { sent: "Calculated", before: "String", after: "Calculated" },
        "description" => { sent: "New", before: "Old", after: "New" },
        "formula" => { sent: "2 + 2", before: "1 + 1", after: "2 + 2" },
        "readonly" => { sent: true, before: false, after: true },
        "visibility" => {
          sent: { "admin" => true, "member" => true, "public" => false },
          before: { "admin" => true, "member" => true, "public" => true },
          after: { "admin" => true, "member" => true, "public" => false }
        },
        "validator_apply" => {
          sent: { "admin" => true, "member" => true, "public" => false },
          before: { "admin" => true, "member" => true, "public" => true },
          after: { "admin" => true, "member" => true, "public" => false }
        },
        "group_id" => { sent: "g_b", before: "Group A", after: "Group B" },
        "storage" => { sent: "computed", before: "stored", after: "computed" }
      }.each do |field, values|
        it "emits one row when the attribute's #{field} changes" do
          student_with_schema!([stored_attribute], attribute_groups: groups)

          rows = rows_for(
            update("property_schema" => [{ "name_slug" => "email", "html_type" => "email", field => values[:sent] }])
          )

          expect(rows).to eq(
            [attribute_row(
              field,
              values[:before],
              values[:after],
              breaking: described_class::BREAKING_ATTRIBUTE_KEYS.include?(field)
            )]
          )
        end
      end

      # The id is an internal handle the admin never chose; it is only shown
      # when it names no section at all.
      it "reports a group_id that matches no section as the raw id" do
        student_with_schema!([stored_attribute], attribute_groups: groups)

        rows = rows_for(
          update("property_schema" => [{ "name_slug" => "email", "html_type" => "email", "group_id" => nil }])
        )

        expect(rows).to eq([attribute_row("group_id", "Group A", nil)])
      end

      it "flags exactly the attribute fields that reinterpret a stored value" do
        expect(described_class::BREAKING_ATTRIBUTE_KEYS).to eq(%w[html_type type])
      end

      it "emits one row per changed field and none for the fields the definition omits" do
        student_with_schema!([stored_attribute], attribute_groups: groups)

        rows = rows_for(
          update(
            "property_schema" => [{
              "name_slug" => "email",
              "html_type" => "email",
              "description" => "New",
              "visibility" => { "admin" => true, "member" => false, "public" => true }
            }]
          )
        )

        expect(rows.map { |row| row["field"] }).to eq(%w[description visibility])
      end

      it "keeps the stored name when the definition renames nothing" do
        student_with_schema!([{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }])

        rows = rows_for(update("property_schema" => [{ "name_slug" => "email", "html_type" => "text" }]))

        expect(rows.first["name"]).to eq("Email")
      end

      # Renaming a field in place is a change in its own right — the admin
      # reads the old name on every form and report that mentions it.
      it "matches the stored twin by slug, and reports the rename it carries" do
        student_with_schema!([{ "name" => "E-mail address", "name_slug" => "email", "html_type" => "email" }])

        expect(rows_for(update("property_schema" => [{ "name" => "Email", "html_type" => "text" }]))).to eq(
          [
            attribute_row("html_type", "email", "text", name: "Email", breaking: true),
            attribute_row("name", "E-mail address", "Email", name: "Email")
          ]
        )
      end

      it "emits no attribute rows at all when the definition omits property_schema" do
        student_with_schema!([stored_attribute], attribute_groups: groups)

        rows = rows_for(update("description" => "Changed"))

        expect(rows.map { |row| row["kind"] }).to eq(["identity"])
      end

      it "ignores an attribute entry that is not an object" do
        student_with_schema!([stored_attribute], attribute_groups: groups)

        expect(rows_for(update("property_schema" => ["nonsense", nil]))).to eq([])
      end
    end

    describe "blank, nil and whitespace" do
      it "treats a blank incoming value and an absent stored one as the same" do
        student!(description: nil)

        expect(rows_for(update("description" => "   "))).to eq([])
      end

      it "treats a whitespace-only stored value and a nil incoming one as the same" do
        student_with_schema!([{ "name" => "Email", "name_slug" => "email", "html_type" => "email", "description" => "   " }])

        rows = rows_for(
          update("property_schema" => [{ "name_slug" => "email", "html_type" => "email", "description" => nil }])
        )

        expect(rows).to eq([])
      end

      it "ignores surrounding whitespace on both sides" do
        student_with_schema!([{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }])

        expect(rows_for(update("property_schema" => [{ "name_slug" => "email", "html_type" => "  email  " }]))).to eq([])
      end
    end

    describe "validators" do
      def email_with_validators!(validators)
        attribute = { "name" => "Email", "name_slug" => "email", "html_type" => "email" }
        attribute["validators"] = validators if validators
        student_with_schema!([attribute])
      end

      def validators_update(validators)
        attribute = { "name_slug" => "email", "html_type" => "email" }
        attribute["validators"] = validators if validators
        update("property_schema" => [attribute])
      end

      # Sorted registry keys, not a sentence: the panel translates each type at
      # render time, and a string joined here could only ever be in one
      # language.
      it "reports validators as a sorted array of their registry types" do
        email_with_validators!([{ "type" => "presence" }])

        rows = rows_for(validators_update([{ "type" => "length" }, { "type" => "presence" }]))

        expect(rows).to eq([attribute_row("validators", ["presence"], %w[length presence])])
      end

      it "emits no row when the same validators arrive in another order" do
        email_with_validators!([{ "type" => "presence" }, { "type" => "length" }])

        expect(rows_for(validators_update([{ "type" => "length" }, { "type" => "presence" }]))).to eq([])
      end

      it "reads a bare string validator as the same validator as its object form" do
        email_with_validators!([{ "type" => "presence" }])

        expect(rows_for(validators_update(["presence"]))).to eq([])
      end

      # The list is compared whole, so a moved bound is a change even though
      # the types on either side read the same.
      it "reports a validator whose configuration moved, even with the types unchanged" do
        email_with_validators!([{ "type" => "length", "config" => { "maximum" => 32 } }])

        rows = rows_for(validators_update([{ "type" => "length", "config" => { "maximum" => 64 } }]))

        expect(rows).to eq([attribute_row("validators", ["length"], ["length"])])
      end

      it "drops blank validator types rather than reporting them as a change" do
        email_with_validators!(nil)

        expect(rows_for(validators_update([{ "type" => "  " }, ""]))).to eq([])
      end

      it "reports adding the first validator against an empty before side" do
        email_with_validators!(nil)

        expect(rows_for(validators_update([{ "type" => "presence" }]))).to eq([attribute_row("validators", [], ["presence"])])
      end

      it "emits no validators row when the definition omits the key" do
        email_with_validators!([{ "type" => "presence" }])

        expect(rows_for(validators_update(nil))).to eq([])
      end
    end

    describe "static options" do
      def status_with(options)
        student_with_schema!([{
          "name" => "Status",
          "name_slug" => "status",
          "html_type" => "select",
          "config" => { "options" => options }
        }])
      end

      def status_update(config)
        update("property_schema" => [{ "name_slug" => "status", "html_type" => "select", "config" => config }])
      end

      it "lists the labels of added options" do
        status_with([{ "value" => "applied", "label" => "Applied" }])

        rows = rows_for(
          status_update(
            "options" => [
              { "value" => "applied", "label" => "Applied" },
              { "value" => "enrolled", "label" => "Enrolled" }
            ]
          )
        )

        expect(rows).to eq(
          [{
            "kind" => "attribute",
            "action" => "modified",
            "name" => "Status",
            "field" => "options",
            "added" => ["Enrolled"],
            "removed" => [],
            "relabelled" => [],
            "omitted" => 0,
            "breaking" => false
          }]
        )
      end

      it "carries all three buckets in one row when options are added, removed and renamed together" do
        status_with([
          { "value" => "applied", "label" => "Applied" },
          { "value" => "enrolled", "label" => "Enrolled" }
        ])

        rows = rows_for(
          status_update(
            "options" => [
              { "value" => "applied", "label" => "Applied for" },
              { "value" => "waitlisted", "label" => "Waitlisted" }
            ]
          )
        )

        expect(rows).to eq(
          [{
            "kind" => "attribute",
            "action" => "modified",
            "name" => "Status",
            "field" => "options",
            "added" => ["Waitlisted"],
            "removed" => ["Enrolled"],
            "relabelled" => [{ "before" => "Applied", "after" => "Applied for" }],
            "omitted" => 0,
            "breaking" => false
          }]
        )
      end

      it "lists the labels of options the definition leaves out, because Persist replaces the list" do
        status_with([
          { "value" => "applied", "label" => "Applied" },
          { "value" => "enrolled", "label" => "Enrolled" }
        ])

        rows = rows_for(status_update("options" => [{ "value" => "applied", "label" => "Applied" }]))

        expect(rows.first).to include("added" => [], "removed" => ["Enrolled"], "relabelled" => [])
      end

      it "emits no row when the list is only reordered" do
        status_with([
          { "value" => "applied", "label" => "Applied" },
          { "value" => "enrolled", "label" => "Enrolled" }
        ])

        rows = rows_for(
          status_update(
            "options" => [
              { "value" => "enrolled", "label" => "Enrolled" },
              { "value" => "applied", "label" => "Applied" }
            ]
          )
        )

        expect(rows).to eq([])
      end

      it "reads a bare string option as the same option as its value/label form" do
        status_with(%w[Low High])

        rows = rows_for(
          status_update(
            "options" => [{ "value" => "Low", "label" => "Low" }, { "value" => "High", "label" => "High" }]
          )
        )

        expect(rows).to eq([])
      end

      it "treats an option carrying only a label as its own value" do
        status_with([])

        rows = rows_for(status_update("options" => [{ "label" => "High" }]))

        expect(rows.first).to include("added" => ["High"], "removed" => [])
      end

      it "drops options that carry neither a value nor a label" do
        status_with([])

        rows = rows_for(status_update("options" => [{ "value" => "  ", "label" => "" }, "   ", 42, nil]))

        expect(rows).to eq([])
      end

      # A relabelled option keeps its stored value, so no entry changes — but
      # it does change what the admin reads on the form, and that is reviewed.
      it "reviews an option that keeps its value and only changes its label" do
        status_with([{ "value" => "applied", "label" => "Applied" }])

        rows = rows_for(status_update("options" => [{ "value" => "applied", "label" => "Applied for" }]))

        expect(rows).to eq(
          [{
            "kind" => "attribute",
            "action" => "modified",
            "name" => "Status",
            "field" => "options",
            "added" => [],
            "removed" => [],
            "relabelled" => [{ "before" => "Applied", "after" => "Applied for" }],
            "omitted" => 0,
            "breaking" => false
          }]
        )
      end

      it "reports one pair per relabelled option and leaves the untouched ones out" do
        status_with([
          { "value" => "applied", "label" => "Applied" },
          { "value" => "enrolled", "label" => "Enrolled" }
        ])

        rows = rows_for(
          status_update(
            "options" => [
              { "value" => "applied", "label" => "Applied for" },
              { "value" => "enrolled", "label" => "Enrolled" }
            ]
          )
        )

        expect(rows.first["relabelled"]).to eq([{ "before" => "Applied", "after" => "Applied for" }])
      end

      it "does not read a bare string option gaining an explicit label as a relabel" do
        status_with(%w[Low])

        rows = rows_for(status_update("options" => [{ "value" => "Low", "label" => "Low" }]))

        expect(rows).to eq([])
      end

      it "emits no options row when the definition omits config" do
        status_with([{ "value" => "applied", "label" => "Applied" }])

        expect(rows_for(update("property_schema" => [{ "name_slug" => "status", "html_type" => "select" }]))).to eq([])
      end

      it "reads a config that is not an object as no list at all" do
        status_with([{ "value" => "applied", "label" => "Applied" }])

        rows = rows_for(status_update("nonsense"))

        expect(rows.first).to include("field" => "options", "added" => [], "removed" => ["Applied"])
      end
    end

    describe "options_source" do
      def course!
        create(:entity, customer: customer, name: "Course",
               property_schema: [
                 { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
                 { "name" => "Code", "name_slug" => "code", "html_type" => "text" },
                 { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
               ].to_json)
      end

      def bound_status!(config)
        student_with_schema!([{
          "name" => "Status",
          "name_slug" => "status",
          "html_type" => "select",
          "config" => config
        }])
      end

      def status_update(config)
        update("property_schema" => [{ "name_slug" => "status", "html_type" => "select", "config" => config }])
      end

      # Structured, not a sentence: the component decides how to word "reads
      # its own list" against "reads Course entries".
      def static_source = { "kind" => "static" }

      def entity_source(name) = { "kind" => "entity", "entity_name" => name }

      it "reports binding a static list to another entity's entries, and marks it breaking" do
        course!
        bound_status!("options" => [{ "value" => "cs101", "label" => "CS 101" }])

        rows = rows_for(status_update("options_source" => "entity_entries", "options_entity_name" => "Course"))

        expect(rows).to eq(
          [attribute_row("options_source", static_source, entity_source("Course"), name: "Status", breaking: true)]
        )
      end

      it "does not also emit an options row for a rebound list" do
        course!
        bound_status!("options" => [{ "value" => "cs101", "label" => "CS 101" }])

        rows = rows_for(status_update("options_source" => "entity_entries", "options_entity_name" => "Course"))

        expect(rows.map { |row| row["field"] }).to eq(["options_source"])
      end

      it "reports unbinding a list back to a self-contained one" do
        course = course!
        bound_status!("options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title")

        rows = rows_for(status_update("options" => [{ "value" => "cs101", "label" => "CS 101" }]))

        expect(rows).to eq(
          [attribute_row("options_source", entity_source("Course"), static_source, name: "Status", breaking: true)]
        )
      end

      it "reports pointing the list at a different entity" do
        course = course!
        create(:entity, customer: customer, name: "Program",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
        bound_status!("options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title")

        rows = rows_for(status_update("options_source" => "entity_entries", "options_entity_name" => "Program"))

        expect(rows.first).to include(
          "before" => entity_source("Course"), "after" => entity_source("Program"), "breaking" => true
        )
      end

      it "emits no row for a faithful echo of a bound list in the shape the model is shown" do
        course = course!
        bound_status!(
          "options_source" => "entity_entries",
          "entity_id" => course.id.to_s,
          "label_field" => "title"
        )

        rows = rows_for(
          status_update(
            "options_source" => "entity_entries",
            "options_entity_name" => "Course",
            "label_field" => "title"
          )
        )

        expect(rows).to eq([])
      end

      # REGRESSION: label_field is a config key nobody thought to enumerate, so
      # the old allowlist diff said "no change" and the relabel of every entry
      # in a bound list applied without review. It reads as a config row now,
      # named by its key rather than by the field it lives on.
      it "reviews relabelling a bound list, which the allowlist diff applied unseen" do
        course = course!
        bound_status!(
          "options_source" => "entity_entries",
          "entity_id" => course.id.to_s,
          "label_field" => "code"
        )

        rows = rows_for(
          status_update("options_source" => "entity_entries", "options_entity_name" => "Course", "label_field" => "title")
        )

        expect(rows).to eq(
          [{
            "kind" => "attribute",
            "action" => "modified",
            "name" => "Status",
            "field" => "config",
            "config_key" => "label_field",
            "before" => "code",
            "after" => "title",
            "breaking" => false
          }]
        )
      end

      # The merge replaces the config wholesale, so a key the document leaves
      # out is a key that disappears — which is a change, not a silence.
      it "reviews a config key the document drops by omitting it" do
        course = course!
        bound_status!(
          "options_source" => "entity_entries",
          "entity_id" => course.id.to_s,
          "label_field" => "code"
        )

        rows = rows_for(status_update("options_source" => "entity_entries", "options_entity_name" => "Course"))

        expect(rows).to eq(
          [{
            "kind" => "attribute",
            "action" => "modified",
            "name" => "Status",
            "field" => "config",
            "config_key" => "label_field",
            "before" => "code",
            "after" => nil,
            "breaking" => false
          }]
        )
      end

      it "reports a binding with no entity name as a binding to nothing, still breaking" do
        bound_status!("options" => [{ "value" => "cs101", "label" => "CS 101" }])

        rows = rows_for(status_update("options_source" => "entity_entries"))

        expect(rows.first).to include(
          "before" => static_source, "after" => entity_source(nil), "breaking" => true
        )
      end
    end
  end

  describe "group rows" do
    let(:stored_groups) do
      [{ "id" => "g_contact", "name" => "Contact", "icon" => "mail", "color" => "sky" }]
    end

    it "emits an added row for a group the entity does not have" do
      student!(attribute_groups: stored_groups)

      rows = rows_for(
        update("attribute_groups" => stored_groups + [{ "id" => "g_billing", "name" => "Billing" }])
      )

      expect(rows).to eq([{ "kind" => "group", "action" => "added", "name" => "Billing", "breaking" => false }])
    end

    it "emits a modified row when a matched group's label changes" do
      student!(attribute_groups: stored_groups)

      rows = rows_for(update("attribute_groups" => [{ "id" => "g_contact", "name" => "Contact details" }]))

      expect(rows).to eq([{ "kind" => "group", "action" => "modified", "name" => "Contact details", "breaking" => false }])
    end

    it "matches a group by name when the definition carries no id" do
      student!(attribute_groups: stored_groups)

      rows = rows_for(update("attribute_groups" => [{ "name" => "contact", "icon" => "phone" }]))

      expect(rows).to eq([{ "kind" => "group", "action" => "modified", "name" => "contact", "breaking" => false }])
    end

    it "emits no row for a faithful echo of a group" do
      student!(attribute_groups: stored_groups)

      expect(rows_for(update("attribute_groups" => stored_groups))).to eq([])
    end

    it "skips a group with no name, which has nothing to show" do
      student!(attribute_groups: stored_groups)

      expect(rows_for(update("attribute_groups" => [{ "id" => "g_x", "name" => "  " }, "nonsense"]))).to eq([])
    end

    it "emits no group rows when the definition omits attribute_groups" do
      student!(attribute_groups: stored_groups)

      rows = rows_for(update("description" => "Changed"))

      expect(rows.map { |row| row["kind"] }).to eq(["identity"])
    end
  end

  describe "association rows" do
    def student_associated_to!(target, **overrides)
      entity = student!
      entity.associations_json = [{
        "target_entity_id" => target.id,
        "target_entity_name" => target.name,
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }.merge(overrides)]
      entity.save!
      entity
    end

    # The assignment replaces the list wholesale, so naming only Program also
    # drops Course. Both halves are reported, and the drop is the breaking one.
    it "emits an added row, and the removed row for the association it replaces" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)
      create(:entity, customer: customer, name: "Program",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)

      rows = rows_for(
        update(
          "associations" => [{
            "associated_entity_name" => "Program",
            "display_field" => "name",
            "display_field_label" => "Name"
          }]
        )
      )

      expect(rows).to eq(
        [
          { "kind" => "association", "action" => "removed", "name" => "Course", "breaking" => true },
          { "kind" => "association", "action" => "added", "name" => "Program", "breaking" => false }
        ]
      )
    end

    it "emits only an added row when the document keeps the associations it already has" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)
      create(:entity, customer: customer, name: "Program",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)

      rows = rows_for(
        update(
          "associations" => [
            { "associated_entity_name" => "Course", "display_field" => "name", "display_field_label" => "Name" },
            { "associated_entity_name" => "Program", "display_field" => "name", "display_field_label" => "Name" }
          ]
        )
      )

      expect(rows).to eq([{ "kind" => "association", "action" => "added", "name" => "Program", "breaking" => false }])
    end

    it "emits a modified row when the display field of an existing association changes" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)

      rows = rows_for(
        update(
          "associations" => [{
            "associated_entity_name" => "Course",
            "display_field" => "code",
            "display_field_label" => "Code"
          }]
        )
      )

      expect(rows).to eq([{ "kind" => "association", "action" => "modified", "name" => "Course", "breaking" => false }])
    end

    it "emits a modified row when the association's extra attributes change" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)

      rows = rows_for(
        update(
          "associations" => [{
            "associated_entity_name" => "Course",
            "display_field" => "name",
            "display_field_label" => "Name",
            "additional_attributes" => [{ "name" => "Grade", "html_type" => "number" }]
          }]
        )
      )

      expect(rows).to eq([{ "kind" => "association", "action" => "modified", "name" => "Course", "breaking" => false }])
    end

    it "emits no row for a faithful echo of an association" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)

      rows = rows_for(
        update(
          "associations" => [{
            "associated_entity_name" => "Course",
            "display_field" => "name",
            "display_field_label" => "Name",
            "additional_attributes" => []
          }]
        )
      )

      expect(rows).to eq([])
    end

    # The model is shown associations keyed by target_entity_name and echoes
    # that key back. Normalizer renames it before the plan runs, so the row
    # still names Course rather than reporting the link as dropped.
    it "names the target of an association echoed under its stored key" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)

      rows = rows_for(
        update(
          "associations" => [{
            "target_entity_name" => "Course",
            "display_field" => "code",
            "display_field_label" => "Code"
          }]
        )
      )

      expect(rows).to eq([{ "kind" => "association", "action" => "modified", "name" => "Course", "breaking" => false }])
    end

    it "emits no association rows when the definition omits associations" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      student_associated_to!(course)

      rows = rows_for(update("description" => "Changed"))

      expect(rows.map { |row| row["kind"] }).to eq(["identity"])
    end
  end

  describe "default_properties rows" do
    it "emits a modified row when the defaults change" do
      student!(default_properties: { "status" => "applied" }.to_json)

      rows = rows_for(update("default_properties" => { "status" => "enrolled" }))

      expect(rows).to eq([{ "kind" => "default_properties", "action" => "modified", "breaking" => false }])
    end

    it "emits no row for a faithful echo of the defaults" do
      student!(default_properties: { "status" => "applied" }.to_json)

      expect(rows_for(update("default_properties" => { "status" => "applied" }))).to eq([])
    end

    # Key order carries no meaning in a defaults hash, and the model does not
    # preserve it. A reordered echo that asked for a confirmation would leave
    # the document exactly where it was, so the loop would never converge.
    it "emits no row when the same defaults arrive with their keys shuffled" do
      student!(default_properties: { "status" => "applied", "year" => 2026, "active" => true }.to_json)

      rows = rows_for(update("default_properties" => { "active" => true, "status" => "applied", "year" => 2026 }))

      expect(rows).to eq([])
    end

    it "emits no row when a nested default is reordered at depth" do
      student!(default_properties: { "meta" => { "a" => 1, "b" => { "c" => 2, "d" => 3 } } }.to_json)

      rows = rows_for(update("default_properties" => { "meta" => { "b" => { "d" => 3, "c" => 2 }, "a" => 1 } }))

      expect(rows).to eq([])
    end

    it "still reports a real change hidden among reordered keys" do
      student!(default_properties: { "status" => "applied", "year" => 2026 }.to_json)

      rows = rows_for(update("default_properties" => { "year" => 2027, "status" => "applied" }))

      expect(rows).to eq([{ "kind" => "default_properties", "action" => "modified", "breaking" => false }])
    end

    it "reads a reordered list of defaults as a change, because list order is display order" do
      student!(default_properties: { "tags" => %w[a b] }.to_json)

      rows = rows_for(update("default_properties" => { "tags" => %w[b a] }))

      expect(rows).to eq([{ "kind" => "default_properties", "action" => "modified", "breaking" => false }])
    end

    it "emits no row when the definition omits default_properties" do
      student!(default_properties: { "status" => "applied" }.to_json)

      rows = rows_for(update("description" => "Changed"))

      expect(rows.map { |row| row["kind"] }).to eq(["identity"])
    end
  end

  # The plan used to compare an allowlist of keys while Persist wrote whole
  # documents, so every key nobody had enumerated was a change that applied
  # with no plan row, no panel and no confirmation. Each example here is one
  # of the writes that got through, named for the write it now stops.
  describe "changes that used to reach Persist with an empty plan" do
    it "reviews dropping an association, and calls it breaking — it deletes the link data" do
      course = create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      entity = student!
      entity.associations_json = [{
        "target_entity_id" => course.id,
        "target_entity_name" => "Course",
        "display_field" => "name",
        "display_field_label" => "Name",
        "additional_attributes" => []
      }]
      entity.save!

      plan = plan_for(update("associations" => []))

      expect(plan.entries.first["rows"]).to eq(
        [{ "kind" => "association", "action" => "removed", "name" => "Course", "breaking" => true }]
      )
      expect(plan.breaking_names).to eq(["Student"])
    end

    # display_label falls back to the entity name when the document omits it,
    # so a document that names the entity and nothing else silently renames
    # every heading that reads it.
    it "reviews an omitted display_label, which resets the label to the entity name" do
      student!(display_label: "Student Record")

      expect(rows_for([{ "name" => "Student" }])).to eq(
        [{
          "kind" => "identity",
          "action" => "modified",
          "field" => "display_label",
          "before" => "Student Record",
          "after" => "Student",
          "breaking" => false
        }]
      )
    end

    it "reviews referenced_template, which no allowlist mentioned" do
      student!(referenced_template: "intake_v1")

      expect(rows_for(update("referenced_template" => "intake_v2"))).to eq(
        [{
          "kind" => "identity",
          "action" => "modified",
          "field" => "referenced_template",
          "before" => "intake_v1",
          "after" => "intake_v2",
          "breaking" => false
        }]
      )
    end

    # Normalizer defaults a missing control to text before Persist writes, so
    # a delta that mentions a field without repeating its html_type really does
    # turn a stored email control back into a plain text box.
    it "reviews an omitted html_type resetting a stored control back to text" do
      student_with_schema!([{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }])

      expect(rows_for(update("property_schema" => [{ "name" => "Email", "name_slug" => "email" }]))).to eq(
        [attribute_row("html_type", "email", "text", breaking: true)]
      )
    end

    # The other side of the same coin: the diff is now wide enough to catch
    # everything, so it must not catch a reordered echo of something already
    # stored, or the model and the admin would confirm forever.
    it "still emits no row for an audience map echoed with its keys shuffled" do
      student_with_schema!([{
        "name" => "Email",
        "name_slug" => "email",
        "html_type" => "email",
        "visibility" => { "admin" => true, "member" => false, "public" => true }
      }])

      rows = rows_for(
        update(
          "property_schema" => [{
            "name" => "Email",
            "name_slug" => "email",
            "html_type" => "email",
            "visibility" => { "public" => true, "member" => false, "admin" => true }
          }]
        )
      )

      expect(rows).to eq([])
    end
  end

  describe "a document that cannot be applied even in memory" do
    # An association the assignment refuses outright. The operation's schema
    # and semantic validation normally catch this first, so reaching the plan
    # at all takes a caller that skips them — which is exactly when failing
    # closed matters.
    def unapplicable_association
      { "associated_entity_name" => "Course", "display_field" => "", "display_field_label" => "" }
    end

    # Fail closed: the gate must not open because the plan failed. The entry
    # carries no rows — there is nothing truthful to show the admin — but it
    # counts as changed and breaking, so it is asked about rather than applied,
    # and Persist refuses it for the same reason on the way through.
    it "reports an unplannable entry as changed and breaking, with no rows" do
      entity = student!
      create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)

      plan = plan_for(update("associations" => [unapplicable_association]))

      expect(plan.entries).to eq(
        [{ "name" => "Student", "id" => entity.id, "breaking" => true, "rows" => [], "omitted_rows" => 0, "unplannable" => true }]
      )
      expect(plan.any?).to eq(true)
      expect(plan.breaking_names).to eq(["Student"])
    end

    it "does not let one unplannable entity hide the changes to another" do
      student!
      create(:entity, customer: customer, name: "Course", description: "Before",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)

      plan = plan_for(
        [
          { "name" => "Student", "associations" => [unapplicable_association] },
          { "name" => "Course", "description" => "After" }
        ]
      )

      expect(plan.changed_names).to match_array(%w[Student Course])
      expect(plan.entries.find { |entry| entry["name"] == "Course" }["rows"].size).to eq(1)
    end
  end

  # If a faithful echo of what is already stored read as a change, the model
  # would be asked to confirm a document that changes nothing, and the turn
  # would never terminate. These are the two documents the assistant produces
  # most often.
  describe "convergence" do
    it "emits nothing for the catalog document the model is shown, associations and bound list included" do
      create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      document = {
        "name" => "Student",
        "property_schema" => [{
          "name" => "Course",
          "name_slug" => "course",
          "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "options_entity_name" => "Course", "label_field" => "name" }
        }],
        "associations" => [{
          "associated_entity_name" => "Course",
          "display_field" => "name",
          "display_field_label" => "Name",
          "additional_attributes" => [{ "name" => "Grade", "html_type" => "number" }]
        }]
      }
      EntityDefinitions::Persist.call({ entities: [document], customer: customer })

      echo = EntityDefinitions::Catalog.for_customer(customer.id)

      expect(plan_for(echo).entries).to eq([])
    end

    it "emits nothing for a document that only creates entities" do
      plan = plan_for(
        [{ "name" => "Cohort", "property_schema" => [{ "name" => "Size", "html_type" => "number" }] }]
      )

      expect(plan.entries).to eq([])
      expect(plan.any?).to eq(false)
    end
  end

  # The invariant the whole design rests on: the plan is computed by running
  # the same assignment the writer runs, so what it predicts is what gets
  # written. Asserted directly rather than inferred, because a drift here is
  # an admin approving one change and getting another.
  describe "the plan predicts what Persist writes" do
    let(:document) do
      {
        "name" => "Student",
        "display_label" => "Learner",
        "property_schema" => [
          { "name" => "Email", "name_slug" => "email", "html_type" => "text" },
          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
        ]
      }
    end

    before do
      student_with_schema!(
        [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }],
        display_label: "Student Record"
      )
    end

    it "predicts each row's after value, and the write produces exactly that" do
      rows = plan_for([document]).entries.first["rows"]

      expect(rows).to eq(
        [
          { "kind" => "identity", "action" => "modified", "field" => "display_label",
            "before" => "Student Record", "after" => "Learner", "breaking" => false },
          attribute_row("html_type", "email", "text", breaking: true),
          { "kind" => "attribute", "action" => "added", "name" => "Notes",
            "html_type" => "textarea", "breaking" => false }
        ]
      )

      EntityDefinitions::Persist.call({ entities: [document], customer: customer })

      written = Entity.find_by!(customer_id: customer.id, name: "Student")
      expect(written.display_label).to eq("Learner")
      expect(written.property_schema_json.map { |attr| [attr["name_slug"], attr["html_type"]] })
        .to eq([%w[email text], %w[notes textarea]])
    end

    # The sharpest form of the same statement: once the document has been
    # applied, planning it again must find nothing left to do. Any key the
    # plan mispredicted would surface here as a row that will not go away.
    it "leaves nothing to plan once the document it planned has been applied" do
      expect(plan_for([document]).any?).to eq(true)

      EntityDefinitions::Persist.call({ entities: [document], customer: customer })

      expect(plan_for([document]).entries).to eq([])
    end

    it "predicts an association change the same way, down to the bridge it keeps" do
      create(:entity, customer: customer, name: "Course",
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      linked = {
        "name" => "Student",
        "display_label" => "Student Record",
        "associations" => [{
          "associated_entity_name" => "Course",
          "display_field" => "name",
          "display_field_label" => "Name",
          "additional_attributes" => []
        }]
      }

      expect(plan_for([linked]).entries.first["rows"]).to eq(
        [{ "kind" => "association", "action" => "added", "name" => "Course", "breaking" => false }]
      )

      EntityDefinitions::Persist.call({ entities: [linked], customer: customer })

      expect(plan_for([linked]).entries).to eq([])
    end
  end

  # The load-bearing safety claim of simulating the write on `record.dup`:
  # computing a plan must not persist anything. Today that rests on
  # DefinitionAssignment containing no `save`; pin it so a later `save` in
  # the shared assignment path fails here rather than silently writing.
  describe "replace mode" do
    it "emits a breaking attribute_removed row for a field the incoming schema drops" do
      student_with_schema!([
        { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
        { "name" => "Fax", "name_slug" => "fax", "html_type" => "tel" }
      ])

      plan = described_class.call(
        entities: update("property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }]),
        customer: customer,
        replace: true
      )

      expect(plan.entries.first["breaking"]).to eq(true)
      expect(plan.entries.first["rows"]).to include(
        { "kind" => "attribute_removed", "action" => "removed", "name" => "Fax", "breaking" => true }
      )
    end

    it "still keeps omitted attributes in merge mode" do
      student_with_schema!([
        { "name" => "Email", "name_slug" => "email", "html_type" => "email" },
        { "name" => "Fax", "name_slug" => "fax", "html_type" => "tel" }
      ])

      expect(rows_for(update("property_schema" => [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }])))
        .to eq([])
    end
  end

  describe "planning performs no writes" do
    it "leaves the stored entity, its version, and the tenant's row counts untouched" do
      entity = student_with_schema!(
        [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }],
        display_label: "Student Record"
      )
      before_snapshot = entity.definition_snapshot
      before_version = entity.current_version_id
      entity_count = Entity.count
      version_count = EntityVersion.count

      expect(plan_for(update(
        "display_label" => "Learner",
        "property_schema" => [
          { "name" => "Email", "name_slug" => "email", "html_type" => "text" },
          { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
        ]
      )).any?).to eq(true)

      entity.reload
      expect(entity.definition_snapshot).to eq(before_snapshot)
      expect(entity.current_version_id).to eq(before_version)
      expect(Entity.count).to eq(entity_count)
      expect(EntityVersion.count).to eq(version_count)
    end
  end

  describe "linking an existing entity to one the same document creates" do
    def course_link
      {
        "associated_entity_name" => "Course",
        "display_field" => "title",
        "display_field_label" => "Title"
      }
    end

    it "describes the new association instead of reporting the change as unplannable" do
      student!

      plan = plan_for(
        [
          { "name" => "Course", "property_schema" => [{ "name" => "Title", "html_type" => "text" }] },
          { "name" => "Student", "associations" => [course_link] }
        ]
      )

      expect(plan.entries.size).to eq(1)
      expect(plan.entries.first).not_to have_key("unplannable")
      expect(plan.entries.first["rows"]).to eq(
        [{ "kind" => "association", "action" => "added", "name" => "Course", "breaking" => false }]
      )
    end

    it "still reports a genuine self-association as unplannable" do
      student!

      plan = plan_for(update("associations" => [{
        "associated_entity_name" => "Student",
        "display_field" => "name",
        "display_field_label" => "Name"
      }]))

      expect(plan.entries.first).to include("unplannable" => true, "breaking" => true, "rows" => [])
    end
  end

  describe "payload caps" do
    it "caps each option bucket and reports how many labels were omitted" do
      options = (1..30).map { |index| { "value" => "v#{index}", "label" => "Label #{index}" } }
      student_with_schema!([{
        "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "options" => options }
      }])

      incoming = options.map { |option| option.merge("label" => "#{option["label"]} renamed") }
      row = rows_for(update(
        "property_schema" => [{ "name_slug" => "status", "html_type" => "select", "config" => { "options" => incoming } }]
      )).find { |entry| entry["field"] == "options" }

      expect(row["relabelled"].size).to eq(described_class::OPTION_LIMIT)
      expect(row["omitted"]).to eq(options.size - described_class::OPTION_LIMIT)
    end

    it "caps rows per entry, keeping breaking rows first" do
      stored = (1..described_class::ROW_LIMIT).map do |index|
        { "name" => "Field #{index}", "name_slug" => "field_#{index}", "html_type" => "text" }
      end
      student_with_schema!(stored)

      incoming = stored.map { |attr| attr.merge("description" => "changed") }
      incoming[0] = incoming[0].merge("html_type" => "email")
      extra = { "name" => "Extra", "name_slug" => "extra", "html_type" => "text" }
      entry = plan_for(update("property_schema" => incoming + [extra])).entries.first

      expect(entry["rows"].size).to eq(described_class::ROW_LIMIT)
      expect(entry["omitted_rows"]).to be >= 2
      expect(entry["rows"]).to include(
        include("field" => "html_type", "before" => "text", "after" => "email", "breaking" => true)
      )
    end
  end

  describe "tenant and bridge isolation" do
    it "does not target an entity of the same name owned by another customer" do
      create(
        :entity,
        customer: other_customer,
        name: "Student",
        property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json
      )

      plan = plan_for(update("property_schema" => [{ "name_slug" => "email", "html_type" => "text" }]))

      expect(plan.entries).to eq([])
      expect(plan.any?).to eq(false)
    end

    it "does target that same record when the plan is computed for its own tenant" do
      create(
        :entity,
        customer: other_customer,
        name: "Student",
        property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json
      )

      plan = plan_for(
        update("property_schema" => [{ "name_slug" => "email", "html_type" => "text" }]),
        tenant: other_customer
      )

      expect(plan.changed_names).to eq(["Student"])
    end

    it "does not target a bridge entity" do
      create(
        :entity,
        customer: customer,
        name: "assoc_student_course",
        category: :bridge,
        property_schema: [{ "name" => "Grade", "name_slug" => "grade", "html_type" => "number" }].to_json
      )

      plan = plan_for(
        [{
          "name" => "assoc_student_course",
          "property_schema" => [{ "name_slug" => "grade", "html_type" => "text" }]
        }]
      )

      expect(plan.entries).to eq([])
    end
  end
end
