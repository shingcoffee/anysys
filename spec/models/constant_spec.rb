require 'rails_helper'

RSpec.describe Constant, type: :model do
  let_it_be(:customer) { create(:customer) }

  describe 'associations' do
    it 'has an optional customer association' do
      constant = described_class.new
      expect(constant).to respond_to(:customer)
      expect(constant).to respond_to(:customer=)
    end
  end

  describe 'validations' do
    it 'rejects duplicate option values' do
      constant = described_class.new(
        name: 'Test',
        options: ['option1', 'option2', 'option1']
      )
      expect(constant).not_to be_valid
      expect(constant.errors[:options]).to include(/must be unique/)
    end

    it 'rejects all-blank option values' do
      constant = described_class.new(
        name: 'Test',
        options: ['', '  ']
      )
      expect(constant).not_to be_valid
      expect(constant.errors[:options]).to include(/must contain at least one non-blank value/)
    end

    it 'allows unique option values' do
      constant = described_class.new(
        name: 'Test',
        options: ['option1', 'option2', 'option3']
      )
      expect(constant).to be_valid
    end

    it 'trims whitespace and detects duplicates' do
      constant = described_class.new(
        name: 'Test',
        options: ['option1', ' option1 ', 'option2']
      )
      expect(constant).not_to be_valid
      expect(constant.errors[:options]).to include(/must be unique/)
    end

    it 'validates presence of name' do
      constant = described_class.new(options: [])
      expect(constant).not_to be_valid
      expect(constant.errors[:name]).to include("can't be blank")
    end

    context 'for shared constants' do
      it 'validates uniqueness of name globally' do
        create(:constant, :shared, name: 'Global Constant')
        constant = described_class.new(name: 'Global Constant', options: [])
        expect(constant).not_to be_valid
        expect(constant.errors[:name]).to include("has already been taken")
      end

      it 'enforces unique names at the database level for shared rows' do
        create(:constant, :shared, name: 'DB Enforced')
        duplicate = build(:constant, :shared, name: 'DB Enforced')
        expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it 'does not require customer_id' do
        constant = described_class.new(name: 'Shared Constant', options: ['A', 'B'])
        expect(constant).to be_valid
        expect(constant.customer_id).to be_nil
      end

      it 'is customer-owned when a customer_id is set' do
        constant = described_class.new(name: 'Shared Constant', options: ['A', 'B'], customer_id: customer.id)
        expect(constant).to be_valid
        expect(constant).to be_customer_owned
      end
    end

    context 'for customer_specific constants' do
      it 'validates uniqueness of name within customer scope' do
        create(:constant, :customer_specific, name: 'Status', customer: customer)
        constant = described_class.new(name: 'Status', options: [], customer: customer)
        expect(constant).not_to be_valid
        expect(constant.errors[:name]).to include("has already been taken")
      end

      it 'allows same name for different customers' do
        customer2 = create(:customer)
        create(:constant, :customer_specific, name: 'Status', customer: customer)
        constant = described_class.new(name: 'Status', options: ['A'], customer: customer2)
        expect(constant).to be_valid
      end

      it 'is a platform Shared Resource when customer_id is omitted' do
        constant = described_class.new(name: 'Customer Constant', options: ['A', 'B'])
        expect(constant).to be_valid
        expect(constant).to be_shared
      end
    end

    it 'is customer-owned when a customer is assigned' do
      constant = described_class.new(name: 'Test', options: ['option1'], customer: customer)
      expect(constant).to be_customer_owned
      expect(constant).to be_valid
    end

    it 'validates presence of options' do
      constant = described_class.new(name: 'Test')
      constant.options = nil
      expect(constant).not_to be_valid
      expect(constant.errors[:options]).to include("can't be blank")
    end
  end

  describe 'shared identity' do
    it 'treats nil customer_id as shared and a set customer_id as customer-owned' do
      constant = create(:constant, :shared)
      expect(constant.shared?).to be true
      expect(constant.customer_owned?).to be false

      constant.update!(customer: customer)
      expect(constant.shared?).to be false
      expect(constant.customer_owned?).to be true
    end
  end

  describe 'scopes' do
    let!(:shared_constant) { create(:constant, :shared, name: 'Shared') }
    let!(:customer_specific_constant) { create(:constant, :customer_specific, name: 'Customer Specific', customer: customer) }

    describe '.shared' do
      it 'returns only shared constants' do
        expect(described_class.shared).to include(shared_constant)
        expect(described_class.shared).not_to include(customer_specific_constant)
      end
    end

    describe '.customer_owned' do
      it 'returns only customer-owned constants' do
        expect(described_class.customer_owned).to include(customer_specific_constant)
        expect(described_class.customer_owned).not_to include(shared_constant)
      end
    end

    describe '.ordered' do
      let!(:constant_b) { create(:constant, :shared, name: 'B Constant') }
      let!(:constant_a) { create(:constant, :shared, name: 'A Constant') }
      let!(:constant_c) { create(:constant, :shared, name: 'C Constant') }

      it 'returns constants ordered by name' do
        ordered_names = described_class.where(name: ['A Constant', 'B Constant', 'C Constant']).ordered.pluck(:name)
        expect(ordered_names).to eq(['A Constant', 'B Constant', 'C Constant'])
      end
    end

    describe '.accessible' do
      let(:customer2) { create(:customer) }
      let!(:customer2_constant) { create(:constant, :customer_specific, name: 'Customer 2 Constant', customer: customer2) }

      context 'with current customer' do
        before { Current.customer_id = customer.id }
        after { Current.reset }

        it 'returns current customer constants and shared constants' do
          result = described_class.accessible
          expect(result).to include(shared_constant, customer_specific_constant)
          expect(result).not_to include(customer2_constant)
        end
      end

      context 'without current customer' do
        before { Current.reset }

        it 'returns only shared constants' do
          result = described_class.accessible
          expect(result).to include(shared_constant)
          expect(result).not_to include(customer_specific_constant, customer2_constant)
        end
      end
    end
  end

  describe 'callbacks' do
    describe '#ensure_options_is_array' do
      it 'converts nil options to empty array' do
        constant = described_class.new(name: 'Test', options: nil)
        constant.valid?
        expect(constant.options).to eq([])
      end

      it 'converts non-array options to array' do
        constant = described_class.new(name: 'Test', options: 'single_value')
        constant.valid?
        expect(constant.options).to eq(['single_value'])
      end

      it 'keeps array options as array' do
        constant = described_class.new(name: 'Test', options: ['value1', 'value2'])
        constant.valid?
        expect(constant.options).to eq(['value1', 'value2'])
      end
    end
  end

  describe 'database structure' do
    it 'has the correct columns' do
      expect(described_class.column_names).to include('name', 'customer_id', 'options', 'created_at', 'updated_at')
      expect(described_class.column_names).not_to include('constant_type')
    end

    it 'has name column with null constraint' do
      column = described_class.columns_hash['name']
      expect(column.null).to be false
    end
  end
end
