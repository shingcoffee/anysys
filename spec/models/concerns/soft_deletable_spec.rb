# frozen_string_literal: true

require "rails_helper"

RSpec.describe SoftDeletable, type: :concern do
  let_it_be(:customer) { create(:customer) }

  # Entity uses soft_deletable with deleted_status: :inactive (status :active/:inactive)
  # Flowchart overrides soft_delete_active_status to :draft

  describe "class methods via Entity" do
    let!(:active_entity)   { create(:entity, customer: customer) }
    let!(:inactive_entity) do
      e = create(:entity, customer: customer, name: "Deleted One")
      e.update_columns(status: :inactive)
      e
    end

    describe ".with_deleted" do
      it "returns all records regardless of status" do
        scope = Entity.where(customer_id: customer.id).with_deleted
        expect(scope).to include(active_entity, inactive_entity)
      end
    end

    describe ".only_deleted" do
      it "returns only deleted (inactive) records" do
        scope = Entity.where(customer_id: customer.id).only_deleted
        expect(scope).to include(inactive_entity)
        expect(scope).not_to include(active_entity)
      end
    end

    describe ".soft_delete_active_status" do
      it "returns :active for Entity" do
        expect(Entity.soft_delete_active_status).to eq(:active)
      end
    end
  end

  describe "#soft_delete" do
    let(:entity) { create(:entity, customer: customer) }

    it "transitions entity to inactive" do
      entity.soft_delete
      expect(entity.reload.status).to eq("inactive")
    end
  end

  describe "#restore" do
    let(:entity) do
      e = create(:entity, customer: customer)
      e.update_columns(status: :inactive)
      e
    end

    it "transitions entity back to active" do
      entity.restore
      expect(entity.reload.status).to eq("active")
    end
  end

  describe "#deleted?" do
    let(:entity) { create(:entity, customer: customer) }

    it "returns false when status is nil" do
      entity.status = nil
      expect(entity.deleted?).to be false
    end

    it "returns true when status matches soft_delete_status" do
      entity.status = :inactive
      expect(entity.deleted?).to be true
    end

    it "returns false when status is active" do
      entity.status = :active
      expect(entity.deleted?).to be false
    end
  end

  describe "#active?" do
    let(:entity) { create(:entity, customer: customer) }

    it "returns false when status is nil" do
      # Use write_attribute to bypass enum type casting and force a nil status
      entity.write_attribute(:status, nil)
      expect(entity.status).to be_nil
      expect(entity.active?).to be false
    end

    it "returns true when status equals soft_delete_active_status" do
      entity.status = :active
      expect(entity.active?).to be true
    end

    it "returns false when status is inactive" do
      entity.status = :inactive
      expect(entity.active?).to be false
    end
  end

  describe "Flowchart overrides soft_delete_active_status to :draft" do
    before { Current.customer = customer }
    after  { Current.reset }

    let(:flowchart) { create(:flowchart, customer: customer) }

    it "Flowchart.soft_delete_active_status returns :draft" do
      expect(Flowchart.soft_delete_active_status).to eq(:draft)
    end

    it "#active? returns true when status is :draft" do
      flowchart.status = :draft
      expect(flowchart.active?).to be true
    end

    it "#deleted? returns true when status is :deleted" do
      flowchart.status = :deleted
      expect(flowchart.deleted?).to be true
    end
  end
end
