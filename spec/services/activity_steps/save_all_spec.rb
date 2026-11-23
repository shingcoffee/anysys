# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivitySteps::SaveAll do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer, property_schema: [{ "name_slug" => "name" }].to_json) }

  def entry(name)
    EntityEntry.build_for(entity).new(customer_id: customer.id, data: { "name" => name }.to_json)
  end

  describe "unsupported base writes" do
    it "rejects forged identity metadata before persisting an existing user or its contract" do
      user = create(:user, :member, customer: customer)
      original_email = user.email
      user.email = "forged@example.com"
      contract = double("base contract")
      expect(contract).not_to receive(:save)
      ctx = { model: user, contract: contract, current_user_id: user.id, current_user_role: "owner",
        authentication: { user_id: user.id }, routed_params: { primary: { base_models: { "Authentication::User" => { "email" => user.email } } } } }
      expect(described_class.call(ctx)).to be(false)
      expect(user.reload.email).to eq(original_email)
      expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.base_model_submission_not_supported"))
    end

    it "rejects raw base params even when the routing step was skipped" do
      model = double("base model")
      expect(model).not_to receive(:save!)
      ctx = { model: model, params: { "base" => { "other" => { "value" => "forged" } } } }
      expect(described_class.call(ctx)).to be(false)
    end

    it "rejects a base contract's physical target even when model and base params are omitted" do
      user = create(:user, :member, customer: customer)
      original_email = user.email
      contract_class = Class.new(Reform::Form) { property :email }
      contract = contract_class.new(user)
      contract.validate("email" => "forged@example.com")
      expect(described_class.call({ contract: contract })).to be(false)
      expect(user.reload.email).to eq(original_email)
    end
  end

  # ---------------------------------------------------------------------------
  # save_primary via a Reform contract — mock-level (fast)
  # ---------------------------------------------------------------------------
  describe ".call — save_primary via contract (mock)" do
    it "calls contract.save and returns true on success" do
      contract = double("contract", save: true)
      ctx = { contract: contract, associated_entries: [] }
      expect(described_class.call(ctx)).to be(true)
    end

    it "returns false and sets ctx[:error] when contract.save raises RecordInvalid" do
      record = build(:customer)
      record.errors.add(:name, "can't be blank")
      contract = double("contract")
      allow(contract).to receive(:save).and_raise(ActiveRecord::RecordInvalid.new(record))
      ctx = { contract: contract, associated_entries: [] }
      expect(described_class.call(ctx)).to be(false)
      expect(ctx[:error]).to be_a(String)
    end

    it "does not report success or save bridges when contract.save returns false" do
      contract = double("contract", save: false)
      bridge = double("bridge entry")
      expect(bridge).not_to receive(:save!)
      ctx = { contract: contract, associated_entries: [{ bridge_entry: bridge }] }
      expect(described_class.call(ctx)).to be(false)
      expect(ctx[:error]).to eq(I18n.t("common.errors.dynamic.activity_execution_failed"))
    end
  end

  # ---------------------------------------------------------------------------
  # save_primary via a Reform contract — integration (real DB persist)
  # ---------------------------------------------------------------------------
  describe ".call — save_primary via contract (integration)" do
    let(:model) { entry("T") }
    let(:contract) { EntityEntryContract.build_for(entity).new(model) }

    before { contract.validate("name" => "T") }

    it "returns true on successful save" do
      ctx = { contract: contract, associated_entries: [] }
      expect(described_class.call(ctx)).to be true
    end

    it "persists the model via the contract" do
      ctx = { contract: contract, associated_entries: [] }
      expect { described_class.call(ctx) }.to change(EntityEntry, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # save_primary via model (no contract present) — mock-level
  # ---------------------------------------------------------------------------
  describe ".call — save_primary via model (mock)" do
    it "calls model.save! and returns true" do
      model = entry("Saved")
      ctx = { model: model, associated_entries: [] }
      expect(described_class.call(ctx)).to be(true)
    end

    it "returns false and sets ctx[:error] when model.save! raises RecordNotSaved" do
      model = double("model")
      allow(model).to receive(:save!).and_raise(ActiveRecord::RecordNotSaved.new("fail", model))
      ctx = { model: model, associated_entries: [] }
      expect(described_class.call(ctx)).to be(false)
      expect(ctx[:error]).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # save_primary via model (no contract present) — integration
  # ---------------------------------------------------------------------------
  describe ".call — save_primary via model (integration)" do
    let(:model) do
      entry("Direct")
    end

    it "saves the model directly and returns true" do
      ctx = { model: model }
      result = described_class.call(ctx)
      expect(result).to be true
      expect(model).to be_persisted
    end
  end

  # ---------------------------------------------------------------------------
  # No contract, no model
  # ---------------------------------------------------------------------------
  describe ".call — when ctx has neither contract nor model" do
    it "skips save_primary and still returns true" do
      ctx = { associated_entries: [] }
      expect(described_class.call(ctx)).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------
  describe ".call — failure path (invalid model)" do
    let(:invalid_model) do
      EntityEntry.new(customer_id: customer.id)
    end

    it "returns false when the model save! raises" do
      ctx = { model: invalid_model }
      expect(described_class.call(ctx)).to be false
    end

    it "sets ctx[:error] with the exception message" do
      ctx = { model: invalid_model }
      described_class.call(ctx)
      expect(ctx[:error]).to be_present
    end

    it "rolls back all changes within the transaction on failure" do
      # A valid model plus a failing bridge entry — the whole transaction must roll back.
      valid_model = entry("WillRollback")

      bridge_entity = create(:entity, customer: customer, property_schema: [
        { "name_slug" => "score", "type" => "String" },
        { "name_slug" => "source_id", "type" => "EntityReference", "entity_id" => entity.id }
      ].to_json)
      good_bridge = build(:entity_entry, customer: customer, entity: bridge_entity, data: { "score" => "90" }.to_json)
      bad_bridge = build(:entity_entry, customer: customer, entity: bridge_entity, data: { "unknown" => "forged" }.to_json)

      ctx = { model: valid_model, bound_entity: entity,
        associated_entries: [{ bridge_entry: good_bridge }, { bridge_entry: bad_bridge }] }
      result = nil
      expect { result = described_class.call(ctx) }.not_to change(EntityEntry, :count)
      expect(result).to be(false)
      expect(ctx[:error]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # save_bridge_entries — skips entries with no bridge_entry
  # ---------------------------------------------------------------------------
  describe ".call — nil bridge_entry is skipped" do
    it "does not raise for association entries that lack a bridge" do
      ctx = { associated_entries: [{ bridge_entry: nil }] }
      expect { described_class.call(ctx) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # link_source_entity — mock-based: verifies the assignment is called
  # ---------------------------------------------------------------------------
  describe ".link_source_entity — mock-based (via bridge entry with EntityReference field)" do
    it "sets the source entity reference field on the bridge entry" do
      primary_model = entry("Primary").tap(&:save!)

      schema         = [{ "type" => "EntityReference", "name_slug" => "source_ref",
                          "entity_id" => 42 }]
      primary_entity = double("entity", id: 42)
      bridge_entity  = double("entity", property_schema_json: schema)
      bridge_entry   = double("bridge_entry", entity: bridge_entity)
      allow(bridge_entry).to receive(:[]=)
      allow(bridge_entry).to receive(:save!)

      ctx = {
        model:              primary_model,
        entity:             primary_entity,
        associated_entries: [{ bridge_entry: bridge_entry }]
      }

      described_class.call(ctx)
      expect(bridge_entry).to have_received(:[]=).with("source_ref", primary_model.id)
    end
  end

  # ---------------------------------------------------------------------------
  # link_source_entity — integration: persists and reloads from DB
  # ---------------------------------------------------------------------------
  describe ".link_source_entity — integration (real entity_entry records)" do
    it "saves bridge entries and wires the source entity id into the EntityReference field" do
      primary_entity = create(:entity, customer: customer)
      model          = create(:entity_entry, customer: customer, entity: primary_entity)
      bridge_entity  = create(:entity, customer: customer)

      # Give bridge_entity a EntityReference property schema pointing at primary_entity
      bridge_entity.update!(property_schema_json: [
        { "name_slug" => "source_id", "type" => "EntityReference", "entity_id" => primary_entity.id }
      ])

      bridge_entry = create(:entity_entry, customer: customer, entity: bridge_entity)
      ctx = {
        model:              model,
        entity:             primary_entity,
        associated_entries: [{ bridge_entry: bridge_entry }]
      }

      result = described_class.call(ctx)
      expect(result).to be(true)
      expect(bridge_entry.reload["source_id"]).to eq(model.id)
    end
  end
end
