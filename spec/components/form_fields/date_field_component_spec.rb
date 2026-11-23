# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::DateFieldComponent, type: :component do
  # field_name/label default to a birthday date field; pass overrides to vary a single example.
  def render_field(**opts)
    render_inline(described_class.new(field_name: :birthday, label: 'Birthday', **opts))
  end

  it 'renders a date input' do
    render_field
    expect(page).to have_css('input[type="date"]')
  end

  it 'renders the label' do
    render_field(label: 'Date of Birth')
    expect(page).to have_text('Date of Birth')
  end

  it 'humanizes field_name when label is omitted' do
    render_inline(described_class.new(field_name: :start_date))
    expect(page).to have_text('Start date')
  end

  it 'reflects value in the input' do
    render_field(value: '1990-06-15')
    expect(page).to have_field('Birthday', with: '1990-06-15')
  end

  it 'renders the required asterisk when required: true' do
    render_field(required: true)
    expect(page).to have_css('span.text-red-500', text: '*')
  end

  it 'does not render required asterisk by default' do
    render_field
    expect(page).not_to have_css('span.text-red-500')
  end

  it 'sets the required attribute on the input when required: true' do
    render_field(required: true)
    expect(page).to have_css('input[required]')
  end

  it 'renders a placeholder when provided' do
    render_field(placeholder: 'YYYY-MM-DD')
    expect(page).to have_css('input[placeholder="YYYY-MM-DD"]')
  end

  it 'uses field_name as the input name attribute' do
    render_field(field_name: :event_date, label: 'Event Date')
    expect(page).to have_css('input[name="event_date"]')
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
