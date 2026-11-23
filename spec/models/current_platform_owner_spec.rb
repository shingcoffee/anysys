# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current, 'platform owner context', type: :model do
  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer) { create(:customer, name: 'Target Customer') }

  after { described_class.reset }

  describe 'platform owner attributes' do
    it 'stores platform_owner_context attribute' do
      described_class.platform_owner_context = true
      expect(described_class.platform_owner_context).to be true
    end

    it 'stores original_customer attribute' do
      described_class.original_customer = platform_customer
      expect(described_class.original_customer).to eq(platform_customer)
    end

    it 'stores acting_as_customer attribute' do
      described_class.acting_as_customer = target_customer
      expect(described_class.acting_as_customer).to eq(target_customer)
    end
  end

  describe '#platform_owner_context?' do
    it 'returns true when platform_owner_context is true' do
      described_class.platform_owner_context = true
      expect(described_class.platform_owner_context?).to be true
    end

    it 'returns false when platform_owner_context is false' do
      described_class.platform_owner_context = false
      expect(described_class.platform_owner_context?).to be false
    end

    it 'returns false when platform_owner_context is nil' do
      expect(described_class.platform_owner_context?).to be false
    end
  end
end
