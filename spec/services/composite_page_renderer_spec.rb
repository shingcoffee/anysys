# frozen_string_literal: true

require "rails_helper"

RSpec.describe CompositePageRenderer do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  def render(modules_config)
    described_class.new(modules_config, customer_id: customer.id).render_modules
  end

  describe "#render_modules" do
    it "renders one entry per configured module, tagged with its module_type" do
      result = render([
        { "id" => "mod_1", "module_type" => "list", "title" => "Items", "entity_id" => entity.id, "width" => "half",
          "config" => { "columns" => ["name", "status"], "pageSize" => 10 } },
        { "id" => "mod_2", "module_type" => "form", "title" => "Details", "entity_id" => entity.id, "width" => "half",
          "config" => { "fields" => [] } }
      ])
      expect(result.size).to eq(2)
      expect(result[0][:module_type]).to eq("list")
      expect(result[1][:module_type]).to eq("form")
    end

    it "loads the referenced entity for a list module" do
      result = render([
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["name"] } }
      ])
      expect(result[0][:entity]).to eq(entity)
    end

    it "fetches the entity's records and total count for a list module" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json)
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)

      result = render([
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["name", "status"], "pageSize" => 10 } }
      ])
      expect(result[0][:records].size).to eq(2)
      expect(result[0][:pagination][:total_count]).to eq(2)
    end

    it "filters list records by the module's conditions" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "status" => "active" }.to_json)
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob", "status" => "inactive" }.to_json)

      result = render([
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["name"],
            "conditions" => { "operator" => "AND", "rules" => [{ "field" => "data.status", "op" => "==", "value" => "active" }] } } }
      ])
      expect(result[0][:records].size).to eq(1)
    end

    it "returns an empty array when there are no modules" do
      expect(render([])).to eq([])
    end

    it "renders a nil entity and no records when the entity_id does not resolve" do
      result = render([{ "id" => "mod_1", "module_type" => "list", "entity_id" => 99999, "width" => "full", "config" => {} }])
      expect(result[0][:entity]).to be_nil
      expect(result[0][:records]).to eq([])
    end

    it "resolves list columns from the entity schema into slug/name/html_type" do
      result = render([
        { "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["name", "status"] } }
      ])
      expect(result[0][:columns]).to eq([
        { slug: "name", name: "Name", html_type: "text" },
        { slug: "status", name: "Status", html_type: "text" }
      ])
    end

    it "falls back to created_at when the requested sort path is unsafe" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)

      result = described_class.new(
        [{ "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
           "config" => { "columns" => ["name"] } }],
        customer_id: customer.id,
        params: { sort: "name')); DROP TABLE--" }
      ).render_modules

      expect(result[0][:records].size).to eq(1)
    end

    it "falls back when sort is blank" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)

      result = described_class.new(
        [{ "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
           "config" => { "columns" => ["name"] } }],
        customer_id: customer.id,
        params: { sort: "" }
      ).render_modules

      expect(result[0][:records].size).to eq(1)
    end

    it "lists only the member's owned rows and none to the public" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      member = create(:user, :member, customer: customer)
      peer = create(:user, :member, customer: customer)
      other_customer = create(:customer)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      assignment = create(:entity, customer: customer, name: "Assignment", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "name" } }
      ].to_json)
      own_student = create(:entity_entry, customer: customer, entity: student, user: member)
      peer_student = create(:entity_entry, customer: customer, entity: student, user: peer)
      mine = create(:entity_entry, :with_data, customer: customer, entity: assignment,
                    entry_data: { "title" => "Mine", "student" => own_student.id.to_s })
      theirs = create(:entity_entry, :with_data, customer: customer, entity: assignment,
                      entry_data: { "title" => "Peer", "student" => peer_student.id.to_s })
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      foreign_student = create(:entity, customer: other_customer, name: "Student", extended_model: person_model,
                              property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      foreign_assignment = create(:entity, customer: other_customer, name: "Assignment", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => foreign_student.id.to_s, "label_field" => "name" } }
      ].to_json)
      create(:entity_entry, :with_data, customer: other_customer, entity: foreign_assignment,
             entry_data: { "title" => "Foreign" })

      config = [{ "id" => "list", "module_type" => "list", "entity_id" => assignment.id,
                  "config" => { "columns" => ["title"], "pageSize" => 10 } }]

      member_ids = described_class.new(config, customer_id: customer.id, audience: EntityAttributeAudience::MEMBER,
                                       viewer: member).render_modules.first[:records].map(&:id)
      expect(member_ids).to eq([mine.id])
      expect(member_ids).not_to include(theirs.id)

      peer_ids = described_class.new(config, customer_id: customer.id, audience: EntityAttributeAudience::MEMBER,
                                     viewer: peer).render_modules.first[:records].map(&:id)
      expect(peer_ids).to eq([theirs.id])

      public_ids = described_class.new(config, customer_id: customer.id, audience: EntityAttributeAudience::PUBLIC,
                                       viewer: nil).render_modules.first[:records].map(&:id)
      expect(public_ids).to eq([])

      admin_ids = described_class.new(config, customer_id: customer.id, audience: EntityAttributeAudience::ADMIN,
                                      viewer: nil).render_modules.first[:records].map(&:id)
      expect(admin_ids).to match_array([mine.id, theirs.id])
    end

    it "builds a row-action path per record only when row_action is configured" do
      alice = create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)
      bob = create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Bob" }.to_json)

      with_action = render([{
        "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
        "config" => {
          "columns" => ["name"],
          "row_action" => { "action_key" => "enroll", "field" => "course", "label" => "Enroll" }
        }
      }])
      paths = with_action[0][:row_action_paths]
      expect(paths[alice.id]).to eq(
        Pages::ActionLink.path(customer_id: customer.id, action_key: "enroll", prefill: { "course" => alice.id })
      )
      expect(paths[bob.id]).to eq(
        Pages::ActionLink.path(customer_id: customer.id, action_key: "enroll", prefill: { "course" => bob.id })
      )

      without_action = render([{
        "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
        "config" => { "columns" => ["name"] }
      }])
      expect(without_action[0][:row_action_paths]).to eq({})
    end

    it "builds no row-action paths for a malformed action key or field" do
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice" }.to_json)

      [{ "action_key" => "../admin", "field" => "course" }, { "action_key" => "enroll", "field" => "bad field" }].each do |action|
        modules = render([{
          "id" => "mod_1", "module_type" => "list", "entity_id" => entity.id, "width" => "full",
          "config" => { "columns" => ["name"], "row_action" => action }
        }])
        expect(modules[0][:row_action_paths]).to eq({})
      end
    end

    it "omits audience-hidden columns and their data from list output" do
      entity.property_schema_json = [
        { "name_slug" => "name", "name" => "Name" },
        { "name_slug" => "internal", "name" => "Internal", "visibility" => { "public" => false, "member" => false } }
      ]
      entity.save!
      create(:entity_entry, entity: entity, customer: customer, data: { "name" => "Alice", "internal" => "hidden-data-value" }.to_json)
      config = [{ "id" => "list", "module_type" => "list", "entity_id" => entity.id, "config" => { "columns" => %w[name internal] } }]
      %w[public member].each do |audience|
        data = described_class.new(config, customer_id: customer.id, audience: audience).render_modules.first
        html = PageContentGenerator::CompositeRenderer.new.render_module(data)
        expect(data[:columns].map { |column| column[:slug] }).to eq(["name"])
        expect(html).to include("Alice")
        expect(html).not_to include("Internal", "hidden-data-value")
      end
    end
  end
end
