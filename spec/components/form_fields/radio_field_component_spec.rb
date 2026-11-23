# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::RadioFieldComponent, type: :component do
  let(:options) do
    [
      { 'label' => 'Option A', 'value' => 'a' },
      { 'label' => 'Option B', 'value' => 'b' },
      { 'label' => 'Option C', 'value' => 'c' }
    ]
  end

  def render_radio(**opts)
    render_inline(described_class.new(field_name: :choice, options: options, **opts))
  end

  it 'renders radio buttons for each option' do
    render_radio(label: 'Pick one')
    expect(page).to have_css('input[type="radio"]', count: 3)
  end

  it 'renders labels for each option' do
    render_radio
    expect(page).to have_text('Option A')
    expect(page).to have_text('Option B')
    expect(page).to have_text('Option C')
  end

  it 'renders in inline layout when specified' do
    render_radio(layout: 'inline')
    expect(page).to have_css('.flex.flex-wrap')
  end

  it 'marks selected option' do
    render_radio(value: 'b')
    expect(page).to have_checked_field('Option B')
  end
end
