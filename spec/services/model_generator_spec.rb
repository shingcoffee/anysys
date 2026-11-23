# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ModelGenerator do
  let(:entity) do
    create(:entity,
      name: 'User Profile',
      property_schema: schema.to_json
    )
  end

  let(:schema) do
    [
      { 'name' => 'name', 'name_slug' => 'name', 'html_type' => 'text' },
      { 'name' => 'age', 'name_slug' => 'age', 'html_type' => 'number' },
      { 'name' => 'email', 'name_slug' => 'email', 'html_type' => 'email' }
    ]
  end

  # Generated source for the shared `entity`/`schema`. Lazy, so the empty-schema
  # context regenerates against its own override.
  let(:code) { described_class.new(entity).generate }

  describe '#generate' do
    it 'generates Ruby code' do
      expect(code).to be_present
    end

    it 'uses EntityEntry.class_eval instead of defining a new class' do
      expect(code).to include('EntityEntry.class_eval do')
      expect(code).not_to match(/class \w+ < EntityEntry/)
    end

    it 'includes attribute_accessor declarations' do
      expect(code).to include('attribute_accessor :name, :string')
      expect(code).to include('attribute_accessor :age, :integer')
      expect(code).to include('attribute_accessor :email, :string')
    end

    it 'includes entity configuration reference in header' do
      expect(code).to include('EntityEntry configuration for: User Profile')
      expect(code).to include('Dynamically extends EntityEntry')
    end

    it 'includes schema info comments' do
      expect(code).to include('# name')
      expect(code).to include('# age')
      expect(code).to include('# email')
    end

    it 'maps html_type to correct Rails types' do
      schema_with_types = [
        { 'name' => 'active', 'name_slug' => 'active', 'html_type' => 'checkbox' },
        { 'name' => 'score', 'name_slug' => 'score', 'html_type' => 'number' },
        { 'name' => 'birthday', 'name_slug' => 'birthday', 'html_type' => 'date' },
        { 'name' => 'notes', 'name_slug' => 'notes', 'html_type' => 'textarea' },
        { 'name' => 'website', 'name_slug' => 'website', 'html_type' => 'url' }
      ]
      entity = create(:entity, name: 'Test', property_schema: schema_with_types.to_json)
      code = described_class.new(entity).generate

      expect(code).to include('attribute_accessor :active, :boolean')
      expect(code).to include('attribute_accessor :score, :integer')
      expect(code).to include('attribute_accessor :birthday, :date')
      expect(code).to include('attribute_accessor :notes, :string')
      expect(code).to include('attribute_accessor :website, :string')
    end

    context 'with empty schema' do
      let(:schema) { [] }

      it 'returns nil for empty attributes' do
        expect(code).to be_nil
      end
    end
  end
end
