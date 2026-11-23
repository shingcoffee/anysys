# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Entries do
  let(:customer) { create(:customer) }
  let(:schema) do
    [
      { "name" => "Email", "name_slug" => "email", "data_type" => "string" },
      { "name" => "Status", "name_slug" => "status", "data_type" => "string" }
    ]
  end
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:other_customer) { create(:customer) }
  let(:ctx) { { bound_entity: entity, customer_id: customer.id } }

  def entry_for(entity:, customer:, data:)
    create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
  end

  describe ".assign write modes" do
    let(:model) do
      entry = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      described_class.find_by(ctx, "id" => entry.id)
    end

    it "overwrites by default and fills only blank fields when write_mode is only_blank" do
      described_class.assign(model, { "email" => "n@x.io", "status" => "open" })
      expect([model.email, model.status]).to eq(%w[n@x.io open])

      described_class.assign(model, { "email" => "z@x.io", "status" => "closed" }, write_mode: "only_blank")
      expect([model.email, model.status]).to eq(%w[n@x.io open])
    end

    it "fills an empty File field in only_blank mode and keeps one that holds a file" do
      entity.update!(property_schema: (schema + [{ "name" => "Contract", "name_slug" => "contract", "html_type" => "file" }]).to_json)
      pdf = ->(name) { { io: StringIO.new("%PDF-1.4\n"), filename: name } }

      described_class.assign(model, { "contract" => pdf.call("first.pdf") }, write_mode: "only_blank")
      model.save!
      described_class.assign(model, { "contract" => pdf.call("second.pdf") }, write_mode: "only_blank")

      expect(model.contract.filename.to_s).to eq("first.pdf")
    end

    it "skips nil assignments when skip_nil is true" do
      described_class.assign(model, { "email" => nil, "status" => "open" }, skip_nil: true)
      expect([model.email, model.status]).to eq(%w[a@x.io open])
    end
  end

  describe ".scoped" do
    it "queries another reachable entity in this tenant only" do
      mine = entry_for(entity: other_entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: other_entity, customer: other_customer, data: { "email" => "a@x.io" })

      result = described_class.query(ctx, entity: other_entity, order_by: "email")
      expect(result.records.map(&:id)).to eq([mine.id])
    end

    it "looks up a named entity and rejects a foreign one" do
      other_entity.update!(name: "Booking")
      mine = entry_for(entity: other_entity, customer: customer, data: { "email" => "a@x.io" })

      expect(described_class.query(ctx, entity: "Booking").records.map(&:id)).to eq([mine.id])
      foreign = create(:entity, customer: other_customer, name: "Secret")
      expect { described_class.query(ctx, entity: foreign.name) }.to raise_error(described_class::Error)
    end

    it "limits own scope to the signed-in member's person rows" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      member = create(:user, :member, customer: customer)
      other_member = create(:user, :member, customer: customer)
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      person = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                      property_schema: schema.to_json)
      mine = create(:entity_entry, entity: person, customer: customer, user: member)
      create(:entity_entry, entity: person, customer: customer, user: other_member)
      own_ctx = ctx.merge(bound_entity: person, current_user_id: member.id)

      expect(described_class.tally(own_ctx, record_scope: "own")).to eq(1)
      expect(described_class.query(own_ctx, record_scope: "own").records.map(&:id)).to eq([mine.id])
      expect(described_class.tally(own_ctx.merge(current_user_id: nil), record_scope: "own")).to eq(0)
    end

    it "keeps own scope empty on an entity no member owns" do
      member = create(:user, :member, customer: customer)
      entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      own_ctx = ctx.merge(current_user_id: member.id)

      expect(People::Ownership.kind(entity)).to eq(:open)
      expect(described_class.tally(own_ctx, record_scope: "own")).to eq(0)
      expect(described_class.query(own_ctx, record_scope: "own").records).to be_empty
      expect(described_class.tally(own_ctx, record_scope: "all")).to eq(1)
    end
  end

  describe ".query / .tally" do
    it "offsets within the tenant scope and ignores another tenant's rows" do
      entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "active" })
      second = entry_for(entity: entity, customer: customer, data: { "email" => "b@x.io", "status" => "active" })
      entry_for(entity: entity, customer: other_customer, data: { "email" => "c@x.io", "status" => "active" })

      result = described_class.query(ctx, order_by: "email", offset: 1, limit: 10)
      expect(result.records.map(&:id)).to eq([second.id])
    end

    it "applies a secondary sort" do
      later = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "z" })
      earlier = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "a" })

      result = described_class.query(ctx, order_by: "email", then_order_by: "status", then_order_direction: "asc")
      expect(result.records.map(&:id)).to eq([earlier.id, later.id])
    end

    it "filters JSON attributes through Entries and never returns another tenant" do
      mine = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io", "status" => "active" })
      entry_for(entity: entity, customer: customer, data: { "email" => "z@x.io", "status" => "closed" })
      create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "email" => "a@x.io", "status" => "active" })

      conditions = {
        "type" => "group",
        "joins" => [],
        "conditions" => [{ "type" => "single", "leftOperand" => "status", "operator" => "==", "rightOperand" => "active" }]
      }
      result = described_class.query(ctx, conditions: conditions, returns: "records")
      expect(result.records.map(&:id)).to eq([mine.id])
      expect(described_class.query(ctx, conditions: conditions, select: %w[email], returns: "values").records).to eq(["a@x.io"])
      expect(described_class.tally(ctx, conditions: conditions, result_as: "count")).to eq(1)
      expect(described_class.tally(ctx, result_as: "exists")).to be(true)
    end
  end

  describe ".scope" do
    it "returns only entries of the bound entity and customer" do
      mine = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: other_entity, customer: customer, data: { "email" => "b@x.io" })
      foreign = create(:entity_entry, customer: other_customer, entity: entity)

      expect(described_class.scope(ctx).pluck(:id)).to eq([mine.id])
      expect(described_class.scope(ctx).where(id: foreign.id)).to be_empty
    end

    it "returns an empty relation when no entity is bound" do
      expect(described_class.scope(ctx.merge(bound_entity: nil))).to be_empty
    end
  end

  describe ".assign" do
    it "writes entity attributes and ignores internal columns and unknown keys" do
      entry = described_class.scope(ctx).new(customer_id: customer.id)
      described_class.assign(entry, { "email" => "c@x.io", "customer_id" => 999, "id" => 7,
                                      "entity_id" => 42, "data" => "{}", "user_id" => 5, "bogus" => 1 })

      expect(entry.email).to eq("c@x.io")
      expect(entry.customer_id).to eq(customer.id)
      expect(entry.id).to be_nil
      expect(entry.entity_id).to eq(entity.id)
      expect(entry.user_id).to be_nil
    end

    it "refuses user_id in strict mode" do
      entry = described_class.scope(ctx).new(customer_id: customer.id)

      expect { described_class.assign(entry, { "user_id" => 5 }, strict: true) }
        .to raise_error(described_class::UnknownAttribute, "user_id")
    end

    it "stores a reference as the record's id string, however the step gives it" do
      lines = create(:entity, customer: customer, property_schema: [
        { "name" => "Owner", "name_slug" => "owner", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => entity.id.to_s, "label_field" => "email" } },
        { "name" => "Parent", "name_slug" => "parent", "html_type" => "select", "type" => "EntityReference", "entity_id" => entity.id.to_s },
        { "name" => "Count", "name_slug" => "count", "html_type" => "number" }
      ].to_json)
      target = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      entry = described_class.scope_for(ctx, lines).new(customer_id: customer.id, entity_id: lines.id)

      described_class.assign(entry, { "owner" => target, "parent" => target.id, "count" => 3 })

      expect(entry.data_json.slice("owner", "parent", "count")).to eq("owner" => target.id.to_s, "parent" => target.id.to_s, "count" => 3)
    end
  end

  describe ".reference_target" do
    it "follows both ways a reference is stored, and nothing else" do
      lines = create(:entity, customer: customer, property_schema: [
        { "name" => "Owner", "name_slug" => "owner", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => entity.id.to_s, "label_field" => "email" } },
        { "name" => "Parent", "name_slug" => "parent", "html_type" => "select", "type" => "EntityReference", "entity_id" => other_entity.id.to_s },
        { "name" => "Status", "name_slug" => "status", "html_type" => "select", "config" => { "options_source" => "manual" } }
      ].to_json)

      expect(%w[owner parent status missing].map { |slug| described_class.reference_target(lines, slug) }).to eq([entity, other_entity, nil, nil])
    end
  end

  describe ".where_attributes" do
    it "matches entity attributes stored in the JSON data column" do
      hit = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: entity, customer: customer, data: { "email" => "z@x.io" })

      relation = described_class.where_attributes(described_class.scope(ctx), { "email" => "a@x.io" }, ctx)
      expect(relation.pluck(:id)).to eq([hit.id])
    end

    it "matches id as a column" do
      hit = entry_for(entity: entity, customer: customer, data: {})
      relation = described_class.where_attributes(described_class.scope(ctx), { "id" => hit.id }, ctx)
      expect(relation.pluck(:id)).to eq([hit.id])
    end

    it "treats a value starting with ctx. as a literal, not a context path" do
      hit = entry_for(entity: entity, customer: customer, data: { "email" => "ctx.customer_id" })
      entry_for(entity: entity, customer: customer, data: { "email" => customer.id.to_s })

      relation = described_class.where_attributes(
        described_class.scope(ctx),
        { "email" => "ctx.customer_id" },
        ctx.merge("customer_id" => customer.id)
      )
      expect(relation.pluck(:id)).to eq([hit.id])
    end
  end

  describe ".scope_for" do
    it "scopes another customer-owned entity by the run tenant" do
      mine = entry_for(entity: other_entity, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: other_entity, customer: other_customer, data: { "email" => "a@x.io" })

      expect(described_class.scope_for(ctx, other_entity).pluck(:id)).to eq([mine.id])
    end

    it "allows a shared entity but still isolates entry rows by customer_id" do
      shared = create(:entity, :shared, property_schema: schema.to_json)
      mine = entry_for(entity: shared, customer: customer, data: { "email" => "a@x.io" })
      entry_for(entity: shared, customer: other_customer, data: { "email" => "a@x.io" })

      expect(described_class.scope_for(ctx, shared).pluck(:id)).to eq([mine.id])
    end

    it "rejects an entity that is not reachable from the run tenant" do
      foreign_entity = create(:entity, customer: other_customer, property_schema: schema.to_json)

      expect { described_class.scope_for(ctx, foreign_entity) }
        .to raise_error(described_class::Error)
    end
  end

  describe ".find_current_person" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:person_entity) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Student", extended_model: person_model,
             property_schema: schema.to_json)
    end
    let(:own_entry) { create(:entity_entry, entity: person_entity, customer: customer, user: member) }

    it "loads the linked entry from current_person_ids and ignores a forged params id" do
      other_entry = create(:entity_entry, entity: person_entity, customer: customer)
      person_ctx = ctx.merge(
        bound_entity: person_entity,
        current_person_ids: { person_entity.id.to_s => own_entry.id },
        params: { "id" => other_entry.id }
      )

      found = described_class.find_current_person(person_ctx)
      expect(found.id).to eq(own_entry.id)
      expect(described_class.find_current_person(person_ctx, entity_id: person_entity.id).id).to eq(own_entry.id)
    end

    it "returns nil for anonymous viewers, missing links, and non-person entities" do
      expect(described_class.find_current_person(ctx.merge(bound_entity: person_entity))).to be_nil
      expect(
        described_class.find_current_person(
          ctx.merge(bound_entity: person_entity, current_person_ids: {})
        )
      ).to be_nil
      expect(
        described_class.find_current_person(
          ctx.merge(current_person_ids: { entity.id.to_s => entry_for(entity: entity, customer: customer, data: {}).id })
        )
      ).to be_nil
    end

    it "never returns another tenant's entry even when the map points at it" do
      foreign = create(:entity_entry, entity: person_entity, customer: other_customer)
      person_ctx = ctx.merge(
        bound_entity: person_entity,
        current_person_ids: { person_entity.id.to_s => foreign.id }
      )

      expect(described_class.find_current_person(person_ctx)).to be_nil
    end

    it "still loads the linked entry when lock is true" do
      person_ctx = ctx.merge(
        bound_entity: person_entity,
        current_person_ids: { person_entity.id.to_s => own_entry.id }
      )

      expect(described_class.find_current_person(person_ctx, lock: true).id).to eq(own_entry.id)
    end

    it "never returns an entry that does not belong to the bound entity" do
      other = create(:entity_entry, entity: other_entity, customer: customer)
      person_ctx = ctx.merge(
        bound_entity: person_entity,
        current_person_ids: { person_entity.id.to_s => other.id }
      )

      expect(described_class.find_current_person(person_ctx)).to be_nil
    end
  end

  describe ".find_by / .where" do
    it "matches a JSON attribute and never returns another tenant's row" do
      mine = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      foreign = entry_for(entity: entity, customer: other_customer, data: { "email" => "a@x.io" })

      expect(described_class.find_by(ctx, "email" => "a@x.io").id).to eq(mine.id)
      expect(described_class.where(ctx, "email" => "a@x.io").pluck(:id)).to eq([mine.id])
      expect(described_class.where(ctx, "email" => "a@x.io")).not_to include(foreign)
    end

    it "raises UnknownAttribute for a slug that is not on the entity" do
      expect { described_class.find_by(ctx, "missing" => "x") }
        .to raise_error(described_class::UnknownAttribute)
    end

    it "still returns the tenant row when lock is true" do
      mine = entry_for(entity: entity, customer: customer, data: { "email" => "a@x.io" })
      foreign = entry_for(entity: entity, customer: other_customer, data: { "email" => "a@x.io" })

      found = described_class.find_by(ctx, { "id" => mine.id }, true)
      expect(found.id).to eq(mine.id)
      expect(described_class.find_by(ctx, { "id" => foreign.id }, true)).to be_nil
    end
  end

  describe ".assign" do
    it "raises on unknown keys when strict" do
      entry = described_class.scope(ctx).new(customer_id: customer.id)

      expect { described_class.assign(entry, { "bogus" => 1 }, strict: true) }
        .to raise_error(described_class::UnknownAttribute)
    end
  end

  describe ".save / .destroy / .archive" do
    it "saves a valid entry and records record_invalid without writing a foreign row" do
      entry = described_class.scope(ctx).new(customer_id: customer.id)
      described_class.assign(entry, { "email" => "c@x.io" })

      expect(described_class.save(ctx, entry)).to be(true)
      expect(entry).to be_persisted

      foreign = entry_for(entity: entity, customer: other_customer, data: { "email" => "z@x.io" })
      expect { described_class.save(ctx, foreign) }.to raise_error(described_class::Error)
      expect(foreign.reload.data_json["email"]).to eq("z@x.io")
    end

    it "archives a datetime field and optionally the actor" do
      entity.update!(property_schema: (
        schema + [
          { "name" => "Archived at", "name_slug" => "archived_at", "data_type" => "datetime" },
          { "name" => "Archived by", "name_slug" => "archived_by", "data_type" => "string" }
        ]
      ).to_json)
      entry = described_class.scope(ctx).new(customer_id: customer.id)
      described_class.save(ctx, entry)
      archive_ctx = ctx.merge(current_user_id: 88)

      expect(described_class.archive(archive_ctx, entry, field: :archived_at, by_field: :archived_by)).to be(true)
      expect(entry.archived_at).to be_present
      expect(entry.archived_by).to eq(88)
    end

    it "destroys a tenant row and refuses a foreign row" do
      entry = entry_for(entity: entity, customer: customer, data: {})
      foreign = entry_for(entity: entity, customer: other_customer, data: {})

      expect(described_class.destroy(ctx, described_class.find_by(ctx, "id" => entry.id))).to be(true)
      expect(EntityEntry.where(id: entry.id)).to be_empty
      expect { described_class.destroy(ctx, foreign) }.to raise_error(described_class::Error)
      expect(EntityEntry.where(id: foreign.id)).to exist
    end
  end

  describe ".upsert" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(cache) }

    it "creates once and then updates the same tenant row" do
      first = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "new" })
      second = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "ok" }, on_match: "update")

      expect(first.first).to be_a(EntityEntry)
      expect(first.last).to be(true)
      expect(second.first).to be_a(EntityEntry)
      expect(second.last).to be(false)
      expect(described_class.scope(ctx).count).to eq(1)
      expect(second.first.status).to eq("ok")
    end

    it "does not upsert into another tenant" do
      entry_for(entity: entity, customer: other_customer, data: { "email" => "a@x.io", "status" => "theirs" })

      created = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "mine" })
      expect(created.last).to be(true)
      expect(described_class.scope(ctx).count).to eq(1)
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(1)
    end

    it "creates a single row under concurrent callers" do
      allow(FlowchartRuntime::Lock).to receive(:acquire).and_call_original
      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.upsert(ctx, match: { "email" => "race@x.io" }, attributes: { "status" => "ok" })
          end
        end
      end
      results = threads.map(&:value)

      expect(results.count { |result| result.is_a?(Array) && result.last }).to eq(1)
      expect(described_class.scope(ctx).where("json_extract(entity_entries.data, '$.email') = ?", "race@x.io").count).to eq(1)
      expect(FlowchartRuntime::Lock).to have_received(:acquire).at_least(:twice)
    end

    it "skips the write when on_match is skip and a tenant row matches" do
      first = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "new" })
      skipped = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "ok" }, on_match: "skip")

      expect(skipped.last).to be(false)
      expect(skipped.first.id).to eq(first.first.id)
      expect(skipped.first.reload.status).to eq("new")
    end

    it "fails when on_match is fail and a tenant row matches" do
      described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "new" })
      busy_ctx = ctx.merge(errors: [])

      expect(described_class.upsert(busy_ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "ok" }, on_match: "fail")).to be(false)
      expect(busy_ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_already_exists")])
      expect(described_class.scope(ctx).first.status).to eq("new")
    end

    it "creates this tenant's row when on_match is fail and only another tenant matches" do
      entry_for(entity: entity, customer: other_customer, data: { "email" => "a@x.io", "status" => "theirs" })

      created = described_class.upsert(ctx, match: { "email" => "a@x.io" }, attributes: { "status" => "mine" }, on_match: "fail")
      expect(created.last).to be(true)
      expect(created.first.customer_id).to eq(customer.id)
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(1)
    end

    it "fails with a translated busy message without waiting when another caller holds the lock" do
      allow(FlowchartRuntime::Lock).to receive(:acquire).and_return(false)

      expect(described_class.upsert(ctx, match: { "email" => "busy@x.io" }, attributes: {})).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_busy")])
      expect(ctx[:error_details].last["code"]).to eq("record_busy")
      expect(FlowchartRuntime::Lock).to have_received(:acquire).once
      expect(described_class.scope(ctx).count).to eq(0)
    end
  end

  describe ".save" do
    let(:ctx) do
      { bound_entity: entity, customer_id: customer.id, audience: "admin", source: { "surface" => "page" }, errors: [] }
    end

    def new_entry(data = {})
      described_class.scope(ctx).new(customer_id: customer.id).tap { |entry| described_class.assign(entry, data) }
    end

    it "saves the record through Entries::Save" do
      entry = new_entry("email" => "a@x.io")
      expect(described_class.save(ctx, entry)).to be(true)

      expect(entry).to be_persisted
      expect(entry.reload.data_json).to include("email" => "a@x.io")
    end

    it "syncs a Reform form onto its model before persist" do
      entry = new_entry
      contract = EntityEntryContract.build_for(entity).new(entry)
      expect(contract.validate("email" => "form@x.io")).to be(true)

      expect(described_class.save(ctx, contract)).to be(true)
      expect(entry).to be_persisted
      expect(entry.reload.email).to eq("form@x.io")
    end

    it "saves as the run's audience, or as system when no person is behind the run" do
      allow(::Entries::Save).to receive(:call).and_call_original

      described_class.save(ctx.merge(audience: "member"), new_entry("email" => "m@x.io"))
      described_class.save(ctx.except(:audience), new_entry("email" => "s@x.io"))

      expect(::Entries::Save).to have_received(:call).with(hash_including(audience: "member"))
      expect(::Entries::Save).to have_received(:call).with(hash_including(audience: "system"))
    end

    it "refuses to save another tenant's record" do
      foreign = entry_for(entity: entity, customer: other_customer, data: {})

      expect { described_class.save(ctx, foreign) }.to raise_error(described_class::Error, "customer mismatch")
    end

    it "writes a submission's bridge rows once, after its new page record is saved" do
      entry = new_entry("email" => "a@x.io")
      ctx.merge!(timing: "submit", page_record: entry, association_params: { "links" => { "note" => "x" } })
      allow(Pages::BridgeEntries).to receive(:call).and_return([])

      expect(described_class.save(ctx, new_entry("email" => "other@x.io"))).to be(true)
      expect(Pages::BridgeEntries).not_to have_received(:call)

      expect(described_class.save(ctx, entry)).to be(true)
      described_class.save(ctx, entry)

      expect(Pages::BridgeEntries).to have_received(:call).once
        .with(hash_including(entry: entry, entity: entity, sections: { "links" => { "note" => "x" } }, customer_id: customer.id))
    end

    it "fails when a bridge row is refused" do
      entry = new_entry
      ctx.merge!(timing: "submit", page_record: entry, association_params: { "links" => { "note" => "x" } })
      allow(Pages::BridgeEntries).to receive(:call).and_return(["Selected on can't be blank"])

      expect(described_class.save(ctx, entry)).to be(false)
      expect(ctx[:errors]).to include("Selected on can't be blank")
    end
  end

  describe ".adjust" do
    let(:product_entity) do
      create(:entity, customer: customer, name: "Product", property_schema: [
        { "name" => "Stock", "name_slug" => "stock", "html_type" => "number" }
      ].to_json)
    end
    let(:product) do
      EntityEntry.build_for(product_entity).create!(customer: customer, entity: product_entity, data: { stock: 5 }.to_json)
    end
    let(:adjust_ctx) { { customer_id: customer.id, errors: [] } }

    def stock
      product.class.find(product.id).data_json["stock"]
    end

    it "subtracts under a lock, reloading so a stale copy cannot oversell" do
      stale = product.class.find(product.id)
      expect(described_class.adjust(adjust_ctx, product, "stock", amount: 2, subtract: true, minimum: 0)).to eq(3)
      expect(described_class.adjust(adjust_ctx.merge(errors: []), stale, "stock", amount: 4, subtract: true, minimum: 0)).to be(false)
      expect(stock).to eq(3)
    end

    it "fails busy when the adjust lock cannot be acquired" do
      allow(FlowchartRuntime::Lock).to receive(:acquire).and_return(false)
      stub_const("FlowchartRuntime::Entries::ADJUST_LOCK_WAIT", 0)

      expect(described_class.adjust(adjust_ctx, product, "stock", amount: 1, subtract: true, minimum: 0)).to be(false)
      expect(adjust_ctx[:error_details].last["code"]).to eq("adjust_number.busy")
      expect(stock).to eq(5)
    end
  end
end
