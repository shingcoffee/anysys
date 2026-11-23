# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::DateTimeFieldComponent, type: :component do
  def render_field(**opts)
    render_inline(described_class.new(field_name: :opens_at, label: 'Opens At', **opts))
  end

  it 'renders a datetime-local input with its label' do
    render_field
    expect(page).to have_css('input[type="datetime-local"][name="opens_at"]')
    expect(page).to have_text('Opens At')
  end

  it 'reflects value in the input' do
    render_field(value: '2026-09-01T08:30')
    expect(page).to have_field('Opens At', with: '2026-09-01T08:30')
  end

  it 'sets the required attribute and asterisk when required: true' do
    render_field(required: true)
    expect(page).to have_css('input[required]')
    expect(page).to have_css('span.text-red-500', text: '*')
  end

  it 'renders only the input when input_only: true' do
    render_field(input_only: true, id: 'entry_opens_at')
    expect(page).to have_css('input#entry_opens_at[type="datetime-local"]')
    expect(page).not_to have_css('label')
  end
end
