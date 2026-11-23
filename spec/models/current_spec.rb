# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current, type: :model do
  let(:customer) { create(:customer, name: 'Test Tenant') }

  after do
    described_class.reset
  end

  describe 'attributes' do
    it 'stores customer attribute' do
      described_class.customer = customer
      expect(described_class.customer).to eq(customer)
    end

    it 'stores request_id attribute' do
      described_class.request_id = 'req-123'
      expect(described_class.request_id).to eq('req-123')
    end

    it 'stores user_agent attribute' do
      described_class.user_agent = 'RSpec/1.0'
      expect(described_class.user_agent).to eq('RSpec/1.0')
    end

    it 'stores ip_address attribute' do
      described_class.ip_address = '127.0.0.1'
      expect(described_class.ip_address).to eq('127.0.0.1')
    end
  end

  describe '#customer_id' do
    context 'when customer is set' do
      before { described_class.customer = customer }

      it 'returns the customer id' do
        expect(described_class.customer_id).to eq(customer.id)
      end
    end

    context 'when customer is not set' do
      it 'returns nil' do
        expect(described_class.customer_id).to be_nil
      end
    end
  end

  describe '#customer?' do
    context 'when customer is set' do
      before { described_class.customer = customer }

      it 'returns true' do
        expect(described_class.customer?).to be true
      end
    end

    context 'when customer is not set' do
      it 'returns false' do
        expect(described_class.customer?).to be false
      end
    end
  end

  describe '#customer_id=' do
    it 'sets customer by finding customer with given id' do
      described_class.customer_id = customer.id
      expect(described_class.customer).to eq(customer)
    end

    it 'sets customer to nil when id not found' do
      described_class.customer_id = 99999999
      expect(described_class.customer).to be_nil
    end

    it 'does nothing when id is blank' do
      described_class.customer = customer
      described_class.customer_id = nil
      expect(described_class.customer).to eq(customer)
    end
  end

  describe '.with_customer' do
    it 'sets customer for duration of block' do
      other_customer = create(:customer, name: 'Other Tenant')

      described_class.customer = customer

      result = described_class.with_customer(other_customer) do
        expect(described_class.customer).to eq(other_customer)
        'block_result'
      end

      expect(result).to eq('block_result')
      expect(described_class.customer).to eq(customer)
    end

    it 'restores original customer even on exception' do
      described_class.customer = customer

      expect {
        described_class.with_customer(create(:customer)) do
          raise 'Test error'
        end
      }.to raise_error('Test error')

      expect(described_class.customer).to eq(customer)
    end
  end

  describe 'thread safety' do
    it 'isolates values between threads' do
      described_class.customer = customer

      thread_customer = nil
      thread = Thread.new do
        described_class.customer = create(:customer, name: 'Thread Tenant')
        thread_customer = described_class.customer
      end
      thread.join

      expect(described_class.customer).to eq(customer)
      expect(thread_customer).not_to eq(customer)
    end
  end

  describe 'reset' do
    it 'clears all attributes' do
      described_class.customer = customer
      described_class.request_id = 'req-123'
      described_class.ip_address = '127.0.0.1'

      described_class.reset

      expect(described_class.customer).to be_nil
      expect(described_class.request_id).to be_nil
      expect(described_class.ip_address).to be_nil
    end
  end
end
