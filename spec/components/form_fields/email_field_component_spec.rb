# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::EmailFieldComponent, type: :component do
  # field_name/label default to an email field; pass overrides to vary a single example.
  def render_field(**opts)
    render_inline(described_class.new(field_name: :email, label: 'Email', **opts))
  end

  it 'renders an email input' do
    render_field
    expect(page).to have_css('input[type="email"]')
  end

  it 'renders the label' do
    render_field(label: 'Email Address')
    expect(page).to have_text('Email Address')
  end

  it 'humanizes field_name when label is omitted' do
    render_inline(described_class.new(field_name: :contact_email))
    expect(page).to have_text('Contact email')
  end

  it 'reflects value in the input' do
    render_field(value: 'user@example.com')
    expect(page).to have_field('Email', with: 'user@example.com')
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

  it 'renders placeholder when provided' do
    render_field(placeholder: 'you@example.com')
    expect(page).to have_css('input[placeholder="you@example.com"]')
  end

  it 'uses field_name as the input name attribute' do
    render_field(field_name: :work_email, label: 'Work Email')
    expect(page).to have_css('input[name="work_email"]')
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
