# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::NumberFieldComponent, type: :component do
  # field_name/label default to a quantity field; pass overrides to vary a single example.
  def render_field(**opts)
    render_inline(described_class.new(field_name: :quantity, label: 'Quantity', **opts))
  end

  it 'renders a number input' do
    render_field
    expect(page).to have_css('input[type="number"]')
  end

  it 'renders the label' do
    render_field(label: 'Item Quantity')
    expect(page).to have_text('Item Quantity')
  end

  it 'humanizes field_name when label is omitted' do
    render_inline(described_class.new(field_name: :item_count))
    expect(page).to have_text('Item count')
  end

  it 'reflects value in the input' do
    render_field(value: '5')
    expect(page).to have_field('Quantity', with: '5')
  end

  it 'does not render a min attribute when min is not given' do
    render_field
    expect(page).not_to have_css('input[min]')
  end

  it 'renders the min attribute when supplied' do
    render_field(min: 0)
    expect(page).to have_css('input[min="0"]')
  end

  it 'does not render a max attribute when max is not given' do
    render_field
    expect(page).not_to have_css('input[max]')
  end

  it 'renders the max attribute when supplied' do
    render_field(max: 100)
    expect(page).to have_css('input[max="100"]')
  end

  it 'does not render a step attribute when step is not given' do
    render_field
    expect(page).not_to have_css('input[step]')
  end

  it 'renders the step attribute when supplied' do
    render_field(field_name: :price, label: 'Price', step: 0.01)
    expect(page).to have_css('input[step="0.01"]')
  end

  it 'renders all three constraints together' do
    render_field(field_name: :score, label: 'Score', min: 0, max: 10, step: 1)
    expect(page).to have_css('input[min="0"][max="10"][step="1"]')
  end

  it 'renders the required asterisk when required: true' do
    render_field(required: true)
    expect(page).to have_css('span.text-red-500', text: '*')
  end

  it 'does not render required asterisk by default' do
    render_field
    expect(page).not_to have_css('span.text-red-500')
  end

  it 'renders placeholder when provided' do
    render_field(placeholder: 'Enter amount')
    expect(page).to have_css('input[placeholder="Enter amount"]')
  end

  it 'uses field_name as the input name attribute' do
    render_field(field_name: :age, label: 'Age')
    expect(page).to have_css('input[name="age"]')
  end

  it 'applies indigo ring class by default' do
    render_field
    # resolve_input_classes emits "ring-indigo-500" (without the "focus:" prefix as a CSS class token)
    expect(page).to have_css('input.ring-indigo-500')
  end

  it 'applies a different theme color when theme is supplied' do
    render_field(theme: { 'primary_color' => 'blue' })
    expect(page).to have_css('input.ring-blue-500')
  end
end
