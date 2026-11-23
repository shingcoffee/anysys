# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TenantScoped, type: :concern do
  let(:customer1) { create(:customer, name: 'Customer One') }
  let(:customer2) { create(:customer, name: 'Customer Two') }

  after do
    Current.reset
  end

  describe 'associations' do
    it 'adds belongs_to customer association' do
      entity = Entity.new
      expect(entity).to respond_to(:customer)
      expect(entity).to respond_to(:customer=)
    end
  end

  describe '.for_current_customer' do
    let!(:entity1) { create(:entity, name: 'Entity 1', customer: customer1) }
    let!(:entity2) { create(:entity, name: 'Entity 2', customer: customer2) }
    let!(:entity3) { create(:entity, name: 'Entity 3', customer: customer1) }

    context 'when Current.customer is set' do
      before { Current.customer = customer1 }

      it 'returns only records for current customer' do
        results = Entity.for_current_customer

        expect(results).to include(entity1, entity3)
        expect(results).not_to include(entity2)
      end
    end

    context 'when Current.customer is not set' do
      it 'returns empty relation' do
        results = Entity.for_current_customer

        expect(results).to be_empty
      end
    end
  end

  describe '.for_customer' do
    let!(:entity1) { create(:entity, name: 'Entity A', customer: customer1) }
    let!(:entity2) { create(:entity, name: 'Entity B', customer: customer2) }

    it 'returns records for specified customer id' do
      results = Entity.for_customer(customer1.id)

      expect(results).to include(entity1)
      expect(results).not_to include(entity2)
    end

    it 'returns empty when customer has no records' do
      other_customer = create(:customer)
      results = Entity.for_customer(other_customer.id)

      expect(results).to be_empty
    end
  end

  describe '.unscoped_by_tenant' do
    let!(:entity1) { create(:entity, name: 'Entity X', customer: customer1) }
    let!(:entity2) { create(:entity, name: 'Entity Y', customer: customer2) }

    it 'returns all records regardless of tenant' do
      Current.customer = customer1
      results = Entity.unscoped_by_tenant

      # Note: This still respects other scopes like default_scope { visible }
      expect(results.pluck(:id)).to include(entity1.id, entity2.id)
    end
  end

  describe '.tenant_scoped?' do
    it 'returns true for models including TenantScoped' do
      expect(Entity.tenant_scoped?).to be true
      expect(Flowchart.tenant_scoped?).to be true
      expect(EntityEntry.tenant_scoped?).to be true
    end
  end

  describe 'automatic customer_id assignment on create' do
    before { Current.customer = customer1 }

    it 'sets customer_id from Current.customer when not provided' do
      entity = Entity.create!(name: 'Auto Tenant')

      expect(entity.customer_id).to eq(customer1.id)
    end

    it 'does not override explicitly provided customer_id' do
      entity = Entity.create!(name: 'Explicit Tenant', customer: customer2)

      expect(entity.customer_id).to eq(customer2.id)
    end
  end

  describe 'skip_tenant_customer_assignment!' do
    before { Current.customer = customer1 }

    it 'keeps customer_id nil so the row is a platform Shared Resource' do
      entity = Entity.new(name: 'Platform Shared')
      entity.skip_tenant_customer_assignment!
      entity.save!

      expect(entity.customer_id).to be_nil
      expect(entity).to be_shared
    end

    it 'still fills customer_id when the skip flag is not set' do
      entity = Entity.create!(name: 'Tenant Owned')
      expect(entity.customer_id).to eq(customer1.id)
      expect(entity).to be_customer_owned
    end
  end

  describe 'Current.shared_resources_mode' do
    before do
      Current.customer = customer1
      Current.shared_resources_mode = true
    end

    it 'does not fill customer_id on create' do
      entity = Entity.create!(name: 'From Platform Surface')
      expect(entity.customer_id).to be_nil
    end
  end

  describe 'cross-tenant isolation' do
    let!(:flowchart1) do
      entity1 = create(:entity, name: 'Tenant1 Entity', customer: customer1)
      create(:flowchart, name: 'Flowchart 1', customer: customer1)
    end
    let!(:flowchart2) do
      entity2 = create(:entity, name: 'Tenant2 Entity', customer: customer2)
      create(:flowchart, name: 'Flowchart 2', customer: customer2)
    end

    it 'isolates flowcharts by tenant' do
      Current.customer = customer1
      results = Flowchart.for_current_customer

      expect(results.map(&:name)).to include('Flowchart 1')
      expect(results.map(&:name)).not_to include('Flowchart 2')
    end

    it 'isolates entities by tenant' do
      Current.customer = customer2
      results = Entity.for_current_customer

      expect(results.map(&:name)).to include('Tenant2 Entity')
      expect(results.map(&:name)).not_to include('Tenant1 Entity')
    end
  end
end
