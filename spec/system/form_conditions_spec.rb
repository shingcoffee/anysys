# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Form conditional logic', type: :system do
  let(:customer) { create(:customer) }

  describe 'conditional rules configuration' do
    let(:config) do
      {
        'pages' => [{
          'id' => 'page_1',
          'name' => 'Page 1',
          'fields' => [
            {
              'id' => 'has_pet',
              'property_type' => 'boolean',
              'property_slug' => 'has_pet',
              'label' => 'Do you have a pet?'
            },
            {
              'id' => 'pet_name',
              'property_type' => 'string',
              'property_slug' => 'pet_name',
              'label' => 'Pet name'
            }
          ]
        }],
        'fields' => [],
        'metadata' => {},
        'rules' => [{
          'id' => 'rule_1',
          'name' => 'Show pet name',
          'enabled' => true,
          'conditions' => {
            'logic' => 'all',
            'groups' => [{
              'logic' => 'all',
              'items' => [{
                'field_id' => 'has_pet',
                'operator' => 'equals',
                'value' => true
              }]
            }]
          },
          'actions' => [{
            'type' => 'show_field',
            'target_id' => 'pet_name'
          }]
        }],
        'calculations' => []
      }
    end

    let!(:page_record) { create(:page, customer: customer, name: 'Test Form', configuration: config.to_json) }

    it 'creates page with conditional rules configuration' do
      expect(page_record.configuration_json['rules']).to be_present
      expect(page_record.configuration_json['rules'].length).to eq(1)
    end

    it 'has properly structured conditions' do
      rule = page_record.configuration_json['rules'].first
      expect(rule['conditions']['logic']).to eq('all')
      expect(rule['conditions']['groups']).to be_present
    end

    it 'has properly structured actions' do
      rule = page_record.configuration_json['rules'].first
      expect(rule['actions'].first['type']).to eq('show_field')
      expect(rule['actions'].first['target_id']).to eq('pet_name')
    end
  end

  describe 'calculated fields configuration' do
    let(:config) do
      {
        'pages' => [{
          'id' => 'page_1',
          'name' => 'Order Form',
          'fields' => [
            { 'id' => 'quantity', 'property_type' => 'number', 'property_slug' => 'quantity', 'label' => 'Quantity' },
            { 'id' => 'price', 'property_type' => 'number', 'property_slug' => 'price', 'label' => 'Price' },
            { 'id' => 'total', 'property_type' => 'number', 'property_slug' => 'total', 'label' => 'Total' }
          ]
        }],
        'fields' => [],
        'metadata' => {},
        'rules' => [],
        'calculations' => [{
          'id' => 'calc_1',
          'target_field_id' => 'total',
          'formula' => 'quantity * price'
        }]
      }
    end

    let!(:page_record) { create(:page, customer: customer, name: 'Order Form', configuration: config.to_json) }

    it 'creates page with calculations configuration' do
      expect(page_record.configuration_json['calculations']).to be_present
      expect(page_record.configuration_json['calculations'].length).to eq(1)
    end

    it 'has properly structured calculation' do
      calc = page_record.configuration_json['calculations'].first
      expect(calc['target_field_id']).to eq('total')
      expect(calc['formula']).to eq('quantity * price')
    end
  end

  describe 'page content generation with runtime controller' do
    let(:entity) do
      create(:entity, customer: customer, property_schema: %w[name qty price total].map { |slug|
        { "name_slug" => slug, "type" => "String" }
      }.to_json)
    end
    around { |example| Current.set(customer: customer, user: nil, shared_resources_mode: false) { example.run } }
    # Configuration updated to satisfy Pages::ConfigurationValidator:
    # - all field references in formulas must exist in pages[].fields
    # - target_field_id must reference an existing field
    # - formula field tokens must be in {field_id} form
    let(:config) do
      {
        'pages' => [{
          'id' => 'page_1',
          'name' => 'Page 1',
          'fields' => [
            { 'id' => 'f1',    'property_type' => 'string', 'html_type' => 'text',   'property_slug' => 'name',  'label' => 'Name' },
            { 'id' => 'qty',   'property_type' => 'number', 'html_type' => 'number', 'property_slug' => 'qty',   'label' => 'Qty' },
            { 'id' => 'price', 'property_type' => 'number', 'html_type' => 'number', 'property_slug' => 'price', 'label' => 'Price' },
            { 'id' => 'total', 'property_type' => 'number', 'html_type' => 'number', 'property_slug' => 'total', 'label' => 'Total' }
          ]
        }],
        'fields' => [],
        'metadata' => {},
        'rules' => [{ 'id' => 'r1', 'enabled' => true, 'conditions' => { 'logic' => 'all', 'groups' => [] }, 'actions' => [] }],
        'calculations' => [{ 'id' => 'c1', 'target_field_id' => 'total', 'formula' => '{qty} + {price}' }]
      }
    end

    let!(:page_record) { create(:page, customer: customer, entity: entity, name: 'Test Page', configuration: config.to_json) }

    it 'generates content with condition-runtime controller' do
      content = page_record.generate_content
      expect(content).to include('data-controller="condition-runtime"')
    end

    it 'includes rules as data attribute' do
      content = page_record.generate_content
      expect(content).to include('data-condition-runtime-rules-value')
    end

    it 'includes calculations as data attribute' do
      content = page_record.generate_content
      expect(content).to include('data-condition-runtime-calculations-value')
    end

    it 'includes field ID in wrapper' do
      content = page_record.generate_content
      expect(content).to include('data-field-id="f1"')
    end
  end
end
