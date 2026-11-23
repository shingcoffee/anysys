# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RandomIdGeneratable do
  # Use Customer as the test subject since it includes the concern
  let(:model_class) { Customer }

  describe 'class configuration' do
    it 'has default digits of 8 and max_attempts of 10' do
      aggregate_failures do
        expect(model_class.random_id_digits).to eq(8)
        expect(model_class.random_id_max_attempts).to eq(10)
      end
    end
  end

  describe '.random_id_min' do
    it 'returns the minimum value for 8 digits' do
      expect(model_class.random_id_min).to eq(10_000_000)
    end
  end

  describe '.random_id_max' do
    it 'returns the maximum value for 8 digits' do
      expect(model_class.random_id_max).to eq(99_999_999)
    end
  end

  describe '.generate_unique_random_id' do
    it 'generates an ID within the valid range' do
      id = model_class.generate_unique_random_id
      expect(id).to be >= 10_000_000
      expect(id).to be <= 99_999_999
    end

    it 'generates unique IDs' do
      ids = 10.times.map { model_class.generate_unique_random_id }
      expect(ids.uniq.length).to eq(10)
    end
  end

  describe 'before_create callback' do
    it 'assigns a random ID on create' do
      customer = model_class.create!(name: 'Test Customer', industry: :technology)
      expect(customer.id).not_to be_nil
      expect(customer.id.to_s.length).to eq(8)
    end

    it 'does not overwrite an explicitly set ID' do
      customer = model_class.new(name: 'Test Customer', industry: :technology)
      customer.id = 12345678
      customer.save!
      expect(customer.id).to eq(12345678)
    end
  end

  describe 'configurable via DSL' do
    # Create a test class to verify DSL works
    let(:test_class) do
      Class.new(ApplicationRecord) do
        self.table_name = 'customers'
        include RandomIdGeneratable
        random_id digits: 6, max_attempts: 5
      end
    end

    it 'configures digits, max_attempts, and derived min/max for 6-digit IDs' do
      aggregate_failures do
        expect(test_class.random_id_digits).to eq(6)
        expect(test_class.random_id_max_attempts).to eq(5)
        expect(test_class.random_id_min).to eq(100_000)
        expect(test_class.random_id_max).to eq(999_999)
      end
    end
  end
end
