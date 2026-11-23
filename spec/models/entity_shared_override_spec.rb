# frozen_string_literal: true

require "rails_helper"

# Per-customer overrides of a shared entity's versioned definition.
RSpec.describe "Shared entity per-customer overrides", type: :model do
  let(:customer_a) { create(:customer) }
  let(:customer_b) { create(:customer) }

  # The shared entity's global default (created in global/owner context).
  let!(:shared) do
    Current.with_customer(nil) do
      Entity.create!(name: "GlobalWidget", description: "global v1")
    end
  end

  def read_description_as(customer)
    Current.with_customer(customer) { Entity.find(shared.id).description }
  end

  def edit_as(customer, description, shared_resources: false)
    Current.with_customer(customer) do
      Current.shared_resources_mode = shared_resources
      e = Entity.find(shared.id)
      e.description = description
      e.save!
    ensure
      Current.shared_resources_mode = false
    end
  end

  describe "read resolution" do
    it "returns the global default when the customer has no override" do
      expect(read_description_as(customer_a)).to eq("global v1")
      expect(read_description_as(nil)).to eq("global v1")
    end
  end

  describe "a customer edit creates an override" do
    before { edit_as(customer_a, "A override") }

    it "shows the override only to that customer" do
      expect(read_description_as(customer_a)).to eq("A override")
      expect(read_description_as(customer_b)).to eq("global v1")
      expect(read_description_as(nil)).to eq("global v1")
    end

    it "records a per-customer head + version and leaves the global default untouched" do
      head = EntityCustomerHead.find_by(entity_id: shared.id, customer_id: customer_a.id)
      expect(head).to be_present
      expect(shared.reload.entity_versions.where(customer_id: customer_a.id).count).to eq(1)
      expect(shared.reload.current_version.content.payload).to include("global v1")
    end
  end

  describe "pinned fork when the global default later changes" do
    before do
      edit_as(customer_a, "A override")
      edit_as(nil, "global v2") # owner ships a new global default
    end

    it "keeps the overriding customer pinned while others follow the new default" do
      expect(read_description_as(customer_a)).to eq("A override")
      expect(read_description_as(customer_b)).to eq("global v2")
    end
  end

  describe "reset to default" do
    before { edit_as(customer_a, "A override") }

    it "drops the override so the customer follows the global default again" do
      Current.with_customer(customer_a) do
        Entity.find(shared.id).reset_customer_override!(customer_a.id)
      end
      expect(read_description_as(customer_a)).to eq("global v1")
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: customer_a.id)).to be_nil
      expect(shared.reload.entity_versions.where(customer_id: customer_a.id)).to be_empty
    end
  end

  describe "tenant isolation of overrides" do
    before do
      edit_as(customer_a, "A override")
      edit_as(customer_b, "B override")
    end

    it "keeps each customer's override independent" do
      expect(read_description_as(customer_a)).to eq("A override")
      expect(read_description_as(customer_b)).to eq("B override")
    end

    it "numbers each override line independently starting at v1" do
      a_v = shared.reload.entity_versions.where(customer_id: customer_a.id).first.version_number
      b_v = shared.reload.entity_versions.where(customer_id: customer_b.id).first.version_number
      expect(a_v).to eq(1)
      expect(b_v).to eq(1)
    end

    it "reset by one customer does not affect another" do
      Current.with_customer(customer_b) do
        Entity.find(shared.id).reset_customer_override!(customer_b.id)
      end
      expect(read_description_as(customer_a)).to eq("A override")
      expect(read_description_as(customer_b)).to eq("global v1")
    end

    it "does not drop versions of a customer-owned entity" do
      owned = Entity.create!(name: "OwnedWidget", customer: customer_a, description: "mine")
      expect(owned.reset_customer_override!(customer_a.id)).to be(false)
      expect(owned.reload.entity_versions.where(customer_id: customer_a.id)).to be_present
    end
  end

  describe "platform-owner customer (81721200) write targeting" do
    let!(:platform) { create(:customer, id: Authentication::User::PLATFORM_CUSTOMER_ID) }

    it "creates a per-customer override when edited outside Shared Resources" do
      edit_as(platform, "owner tenant edit")
      expect(read_description_as(platform)).to eq("owner tenant edit")
      expect(read_description_as(customer_a)).to eq("global v1")
      expect(read_description_as(nil)).to eq("global v1")
      expect(EntityCustomerHead.find_by(entity_id: shared.id, customer_id: platform.id)).to be_present
      expect(shared.reload.entity_versions.where(customer_id: platform.id).count).to eq(1)
    end

    it "advances the global default when edited in Shared Resources mode" do
      edit_as(platform, "owner platform edit", shared_resources: true)
      expect(read_description_as(customer_a)).to eq("owner platform edit")
      expect(read_description_as(nil)).to eq("owner platform edit")
      expect(EntityCustomerHead.where(entity_id: shared.id)).to be_empty
    end
  end
end
