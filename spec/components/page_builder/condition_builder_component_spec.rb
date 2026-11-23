# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::ConditionBuilderComponent, type: :component do
  let(:field_id) { 'field_123' }
  let(:available_fields) do
    [
      { 'id' => 'field_1', 'label' => 'First Name' },
      { 'id' => 'field_2', 'label' => 'Email' }
    ]
  end
  let(:conditions) do
    [
      { 'field_id' => 'field_1', 'operator' => 'equals', 'value' => 'test', 'logic' => 'and' }
    ]
  end

  it 'renders the condition builder container' do
    render_inline(described_class.new(field_id: field_id, conditions: conditions, available_fields: available_fields))
    expect(page).to have_css('[data-condition-builder]')
  end

  it 'renders add condition button' do
    render_inline(described_class.new(field_id: field_id, conditions: [], available_fields: available_fields))
    expect(page).to have_button('Add Condition')
  end

  it 'renders show/hide action selector' do
    render_inline(described_class.new(field_id: field_id, conditions: conditions, available_fields: available_fields, action: 'show'))
    expect(page).to have_text('Show this field when')
  end
end
