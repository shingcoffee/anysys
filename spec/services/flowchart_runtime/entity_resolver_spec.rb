# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::EntityResolver do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }

  describe ".find" do
    it "returns an entity owned by the tenant" do
      entity = create(:entity, customer: customer)
      expect(described_class.find(entity.id, customer_id: customer.id)).to eq(entity)
    end

    it "refuses an entity owned by another tenant" do
      entity = create(:entity, customer: other_customer)
      expect { described_class.find(entity.id, customer_id: customer.id) }
        .to raise_error(described_class::Error)
    end

    it "refuses when no customer scope is supplied" do
      entity = create(:entity, customer: customer)
      expect { described_class.find(entity.id, customer_id: nil) }
        .to raise_error(described_class::Error)
    end

    it "raises for a missing entity" do
      expect { described_class.find(0, customer_id: customer.id) }
        .to raise_error(described_class::Error)
    end
  end

  describe ".accessible?" do
    it "is true for the tenant's own entity" do
      entity = create(:entity, customer: customer)
      expect(described_class.accessible?(entity.id, customer_id: customer.id)).to be(true)
    end

    it "is false for another tenant's entity" do
      entity = create(:entity, customer: other_customer)
      expect(described_class.accessible?(entity.id, customer_id: customer.id)).to be(false)
    end

    it "is false without a customer scope" do
      entity = create(:entity, customer: customer)
      expect(described_class.accessible?(entity.id, customer_id: nil)).to be(false)
    end
  end
end
