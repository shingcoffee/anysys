# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JsonSerializable, type: :concern do
  let_it_be(:customer) { create(:customer) }
  let(:base_attrs) do
    { icon: 'custom', color: '#6366f1', customer: customer }
  end

  def new_entity(name, extra = {})
    Entity.new(base_attrs.merge(extra).merge(name: name))
  end

  describe 'default-value isolation' do
    # If the literal default Array/Hash is reused across instances, mutating one
    # instance's parsed value pollutes every other instance that falls back to
    # the default. Each instance must receive an independent copy.

    it 'returns a distinct default Array per instance' do
      a = new_entity('A')
      b = new_entity('B')

      a_assocs = a.associations_json
      b_assocs = b.associations_json

      expect(a_assocs).to eq([])
      expect(b_assocs).to eq([])
      expect(a_assocs).not_to equal(b_assocs)
    end

    it 'does not leak mutations across instances' do
      a = new_entity('A')
      b = new_entity('B')

      a.associations_json << { 'target_entity_id' => 99 }

      expect(b.associations_json).to eq([])
    end

    it 'returns a distinct default Hash per instance' do
      a = new_entity('A')
      b = new_entity('B')

      a_props = a.default_properties_json
      b_props = b.default_properties_json

      expect(a_props).to eq({})
      expect(b_props).to eq({})
      expect(a_props).not_to equal(b_props)
    end

    it 'does not leak default Hash mutations across instances' do
      a = new_entity('A')
      b = new_entity('B')

      a.default_properties_json['x'] = 1

      expect(b.default_properties_json).to eq({})
    end

    it 'preserves an explicitly assigned value through the JSON round-trip' do
      entity = new_entity('C')
      entity.associations_json = [{ 'target_entity_id' => 5 }]

      expect(entity.associations_json).to eq([{ 'target_entity_id' => 5 }])
    end
  end

  describe 'branch coverage — getter edge cases' do
    # String blank value with Array default -> deep_dup of default
    it 'returns deep_dup of Array default when JSON string is blank' do
      entity = new_entity('D', associations: '')
      result = entity.associations_json
      expect(result).to eq([])
    end

    # String blank value with Hash default -> deep_dup of default
    it 'returns deep_dup of Hash default when JSON string is blank' do
      entity = new_entity('E', default_properties: '')
      result = entity.default_properties_json
      expect(result).to eq({})
    end

    # nil value with Array default -> deep_dup
    it 'returns deep_dup of Array default when value is nil' do
      entity = new_entity('F')
      entity.associations = nil
      result = entity.associations_json
      expect(result).to eq([])
    end

    # nil value with Hash default -> deep_dup
    it 'returns deep_dup of Hash default when value is nil (hash default)' do
      entity = new_entity('G')
      entity.default_properties = nil
      result = entity.default_properties_json
      expect(result).to eq({})
    end

    # Non-String, non-nil value is passed through as-is (the `else` branch in json_attribute getter)
    it 'passes through non-String non-nil values directly' do
      entity = new_entity('H')
      # Ensure the ivar cache is clear, then stub the raw column reader to return an Integer
      allow(entity).to receive(:associations).and_return(42)
      # clear any cached parse result
      entity.remove_instance_variable(:@associations_json) if entity.instance_variable_defined?(:@associations_json)
      result = entity.associations_json
      expect(result).to eq(42)
    end

    it 'preserves malformed entity definitions as nil for model validation' do
      entity = new_entity('I', associations: '{invalid json}')
      result = entity.associations_json
      expect(result).to be_nil
      expect(entity).not_to be_valid
      expect(entity.errors.of_kind?(:associations, :invalid)).to be(true)
      expect(entity.associations).to eq('{invalid json}')
    end

    it 'returns independent defaults for a generic JSON accessor on malformed input' do
      klass = Class.new do
        include JsonSerializable
        attr_accessor :payload
        json_attribute :payload, default: []
      end
      first, second = klass.new, klass.new
      first.payload = second.payload = '{invalid json}'

      expect(first.payload_json).to eq([])
      expect(second.payload_json).to eq([])
      expect(first.payload_json).not_to equal(second.payload_json)
      first.payload_json << 'local mutation'
      expect(second.payload_json).to eq([])
    end

    # reload clears memoized ivars
    it 'clears parsed cache on reload' do
      entity = create(:entity, base_attrs.merge(name: 'J'))
      # Warm the cache
      _ = entity.associations_json
      expect(entity.instance_variable_defined?(:@associations_json)).to be true
      entity.reload
      expect(entity.instance_variable_defined?(:@associations_json)).to be false
    end

    # NOTE: Two branches in the getter (json_serializable.rb:54 and :56) cover the case
    # where `default` is neither Array nor Hash (e.g. nil or a scalar). All json_attribute
    # declarations in the current codebase use Array or Hash defaults, so those `else`
    # sub-branches (returning `default` directly) are never reached. They are genuine
    # dead code given the current models and would only activate if a model added
    # `json_attribute :foo` with no default or a scalar default.
  end
end
