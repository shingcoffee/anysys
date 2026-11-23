# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormParamsRouter do
  let_it_be(:customer) { create(:customer) }

  let(:entity) do
    create(:entity, customer: customer,
           property_schema: [
             { "name" => "Grade", "name_slug" => "grade", "type" => "String" }
           ].to_json)
  end

  let(:page) do
    config = {
      "pages" => [
        {
          "id" => "page_1",
          "name" => "Form",
          "fields" => [
            { "property_slug" => "grade", "source" => "entity", "source_section" => "Form" }
          ]
        }
      ],
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name }
    }

    page = build(:page, customer: customer, entity: entity)
    page.configuration = config.to_json
    page.save!
    page
  end

  describe ".call" do
    context "with nested params" do
      let(:raw_params) do
        {
          "entity" => { "grade" => "A" }
        }
      end

      it "routes entity params to primary.entity" do
        result = described_class.call(page, raw_params)
        expect(result[:primary][:entity]).to eq("grade" => "A")
      end

      it "returns empty base_models" do
        result = described_class.call(page, raw_params)
        expect(result[:primary][:base_models]).to eq({})
      end

      it "returns empty associations when no assoc params" do
        result = described_class.call(page, raw_params)
        expect(result[:associations]).to eq([])
      end
    end

    context "with bridge entity association params" do
      let(:target_entity) do
        create(:entity, customer: customer, name: "Course", property_schema: [
          { "name" => "Credits", "name_slug" => "credits", "type" => "Integer" }
        ].to_json)
      end

      let(:bridge_entity) do
        create(:entity, customer: customer, name: "assoc_student_course", property_schema: [
          { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => target_entity.id },
          { "name" => "Score", "name_slug" => "score", "type" => "String" }
        ].to_json)
      end

      let(:page_with_assoc) do
        # Add association to entity
        entity.associations_json = [
          {
            "target_entity_id" => target_entity.id,
            "target_entity_name" => target_entity.name,
            "bridge_entity_id" => bridge_entity.id,
            "bridge_entity_name" => bridge_entity.name,
            "association_type" => "has_many"
          }
        ]
        entity.save(validate: false)

        config = {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Student",
              "fields" => [
                { "property_slug" => "grade", "source" => "entity", "source_section" => "Student" }
              ]
            },
            {
              "id" => "page_2",
              "name" => "Course",
              "fields" => [
                { "property_slug" => "course", "source" => "bridge", "source_section" => bridge_entity.name },
                { "property_slug" => "score", "source" => "bridge", "source_section" => bridge_entity.name }
              ]
            }
          ],
          "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name }
        }

        page = build(:page, customer: customer, entity: entity)
        page.configuration = config.to_json
        page.save!
        page
      end

      let(:raw_params) do
        {
          "entity" => { "grade" => "A" },
          "assoc" => {
            "assoc_student_course" => { "course" => "12", "score" => "95" }
          }
        }
      end

      it "routes bridge params into bridge.params" do
        result = described_class.call(page_with_assoc, raw_params)
        assoc = result[:associations].first
        expect(assoc[:bridge][:params]).to eq("course" => "12", "score" => "95")
      end

      it "sets bridge entity metadata" do
        result = described_class.call(page_with_assoc, raw_params)
        assoc = result[:associations].first
        expect(assoc[:bridge][:entity_id]).to eq(bridge_entity.id)
        expect(assoc[:bridge][:entity_name]).to eq(bridge_entity.name)
      end

      it "sets target entity metadata" do
        result = described_class.call(page_with_assoc, raw_params)
        assoc = result[:associations].first
        expect(assoc[:entity_id]).to eq(target_entity.id)
        expect(assoc[:entity_name]).to eq(target_entity.name)
      end
    end

    context "with empty params" do
      it "returns empty groups" do
        result = described_class.call(page, {})
        expect(result[:primary][:base_models]).to eq({})
        expect(result[:primary][:entity]).to eq({})
        expect(result[:associations]).to eq([])
      end
    end

    context "when assoc params key does not match any configured association" do
      it "ignores unrecognised assoc section keys and returns empty associations" do
        raw_params = {
          "entity" => { "grade" => "B" },
          "assoc" => { "unknown_section" => { "foo" => "bar" } }
        }
        result = described_class.call(page, raw_params)
        expect(result[:associations]).to eq([])
      end
    end

    context "find_bridge_entity_name using bridge_entity_name fallback (line 103)" do
      # Association record has no bridge_entity_id — find_bridge_entity_name
      # must fall back to assoc["bridge_entity_name"] (line 103).
      let(:target_entity) do
        create(:entity, customer: customer, name: "Product", property_schema: [
          { "name" => "Title", "name_slug" => "title", "type" => "String" }
        ].to_json)
      end

      let(:page_with_name_only_assoc) do
        entity.associations_json = [
          {
            "target_entity_id" => target_entity.id,
            "target_entity_name" => target_entity.name,
            # No bridge_entity_id — only a name-based reference
            "bridge_entity_name" => "assoc_student_product",
            "association_type" => "has_many"
          }
        ]
        entity.save(validate: false)

        config = {
          "pages" => [
            {
              "id" => "page_1",
              "name" => "Student",
              "fields" => [
                {
                  "property_slug" => "title",
                  "source" => "bridge",
                  "source_section" => "assoc_student_product"
                }
              ]
            }
          ],
          "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name }
        }

        p = build(:page, customer: customer, entity: entity)
        p.configuration = config.to_json
        p.save!
        p
      end

      it "routes bridge params using the name-only association (no bridge_entity_id)" do
        raw_params = {
          "entity" => { "grade" => "A" },
          "assoc" => { "assoc_student_product" => { "title" => "Widget" } }
        }
        result = described_class.call(page_with_name_only_assoc, raw_params)
        assoc = result[:associations].first
        expect(assoc).not_to be_nil
        expect(assoc[:bridge][:params]).to eq("title" => "Widget")
        # bridge_entity_id is nil since no bridge entity was DB-persisted
        expect(assoc[:bridge][:entity_id]).to be_nil
      end
    end

    context "when assoc params value is not a hash" do
      it "skips non-hash section values" do
        raw_params = {
          "entity" => { "grade" => "A" },
          "assoc" => { "some_section" => "not_a_hash" }
        }
        result = described_class.call(page, raw_params)
        expect(result[:associations]).to eq([])
      end
    end
  end

  # -----------------------------------------------------------------------
  # Branch-coverage additions — remaining arms not reached above
  # -----------------------------------------------------------------------

  describe "association_meta — branch coverage for nil guards and fallbacks" do
    let(:target_entity) do
      create(:entity, customer: customer, name: "Widget", property_schema: [
        { "name" => "Title", "name_slug" => "title", "type" => "String" }
      ].to_json)
    end

    # Helper that builds a page with no-bridge-entity-id association.
    # find_bridge_entity_name falls back to assoc["bridge_entity_name"] (line 103).
    # Entity.find_by for a nil bridge_entity_id returns nil (line 81, :else on &.name line 87).
    let(:page_name_only) do
      entity.associations_json = [{
        "target_entity_id"   => target_entity.id,
        "target_entity_name" => target_entity.name,
        "bridge_entity_name" => "assoc_student_widget",
        "association_type"   => "has_many"
      }]
      entity.save(validate: false)

      config = {
        "pages" => [{
          "id" => "p1",
          "fields" => [{ "property_slug" => "title", "source" => "bridge",
                         "source_section" => "assoc_student_widget" }]
        }],
        "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name }
      }
      p = build(:page, customer: customer, entity: entity)
      p.configuration = config.to_json
      p.save!
      p
    end

    it "uses assoc target_entity_name when target Entity is not DB-persisted (line 85 ||)" do
      # Delete target_entity so Entity.find_by returns nil:
      # entity_name comes from assoc["target_entity_name"] fallback.
      target_entity.destroy
      result = described_class.call(page_name_only, { "assoc" => { "assoc_student_widget" => { "title" => "Gadget" } } })
      assoc = result[:associations].first
      expect(assoc).not_to be_nil
      expect(assoc[:entity_name]).to eq("Widget")
    end

    it "uses section_name as bridge_entity_name when bridge Entity is nil (line 87 || section_name)" do
      result = described_class.call(page_name_only, { "assoc" => { "assoc_student_widget" => { "title" => "Gadget" } } })
      assoc = result[:associations].first
      expect(assoc).not_to be_nil
      # bridge_entity nil → bridge_entity_name falls back to section_name
      expect(assoc[:bridge][:entity_name]).to eq("assoc_student_widget")
    end

    it "returns empty associations when entity has no associations (entity&.associations_json || [] line 74)" do
      # Page entity has no associations → associations stays [] → sections loop has no matches
      result = described_class.call(page, { "assoc" => { "some_section" => { "x" => "1" } } })
      expect(result[:associations]).to eq([])
    end

    it "find_bound_entity returns nil when metadata has no entity_id (line 96 :else guard)" do
      # Build a page with config.metadata that omits entity_id entirely.
      config = { "pages" => [{ "id" => "p1", "fields" => [
        { "property_slug" => "x", "source" => "bridge", "source_section" => "s1" }
      ] }], "metadata" => {} }
      p = build(:page, customer: customer)
      p.configuration = config.to_json
      p.save!(validate: false)
      result = described_class.call(p, { "assoc" => { "s1" => { "x" => "1" } } })
      expect(result[:associations]).to eq([])
    end

    it "find_bridge_entity_name returns nil via &.name safe-nav when bridge_entity_id record not found (line 101)" do
      entity.associations_json = [{
        "target_entity_id"   => target_entity.id,
        "target_entity_name" => target_entity.name,
        "bridge_entity_id"   => 999_999,   # non-existent → find_by returns nil → &.name is nil
        "bridge_entity_name" => "assoc_x",
        "association_type"   => "has_many"
      }]
      entity.save(validate: false)

      config = {
        "pages" => [{
          "id" => "p1",
          "fields" => [{ "property_slug" => "t", "source" => "bridge", "source_section" => nil.to_s }]
        }],
        "metadata" => { "entity_id" => entity.id }
      }
      p = build(:page, customer: customer, entity: entity)
      p.configuration = config.to_json
      p.save!
      # section_name won't match nil-named bridge → no association returned (graceful)
      result = described_class.call(p, { "assoc" => { "" => { "t" => "v" } } })
      expect(result[:associations]).to eq([])
    end
  end
end
