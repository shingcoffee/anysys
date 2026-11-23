# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::TextareaFieldComponent, type: :component do
  # Defaults to a labelled "Bio" textarea; override any arg.
  def render_textarea(**opts)
    render_inline(described_class.new(**{ field_name: :bio, label: 'Bio' }.merge(opts)))
  end

  it 'renders a textarea element' do
    render_textarea
    expect(page).to have_css('textarea')
  end

  it 'renders the label' do
    render_textarea(label: 'About You')
    expect(page).to have_text('About You')
  end

  it 'humanizes field_name when label is omitted' do
    render_inline(described_class.new(field_name: :cover_letter))
    expect(page).to have_text('Cover letter')
  end

  it 'defaults to 3 rows' do
    render_textarea
    expect(page).to have_css('textarea[rows="3"]')
  end

  it 'renders with a custom rows count' do
    render_textarea(rows: 8)
    expect(page).to have_css('textarea[rows="8"]')
  end

  it 'renders the current value as textarea content' do
    render_textarea(value: 'Hello world')
    expect(page).to have_css('textarea', text: 'Hello world')
  end

  it 'renders empty textarea when value is nil' do
    render_textarea
    expect(page).to have_css('textarea', text: '')
  end

  it 'renders the required asterisk when required: true' do
    render_textarea(required: true)
    expect(page).to have_css('span.text-red-500', text: '*')
  end

  it 'does not render required asterisk by default' do
    render_textarea
    expect(page).not_to have_css('span.text-red-500')
  end

  it 'sets the required attribute on the textarea when required: true' do
    render_textarea(required: true)
    expect(page).to have_css('textarea[required]')
  end

  it 'renders placeholder when provided' do
    render_textarea(placeholder: 'Tell us about yourself')
    expect(page).to have_css('textarea[placeholder="Tell us about yourself"]')
  end

  it 'uses field_name as the textarea name attribute' do
    render_textarea(field_name: :description, label: 'Description')
    expect(page).to have_css('textarea[name="description"]')
  end

  it 'includes resize-none in input classes' do
    render_textarea
    expect(page).to have_css('textarea.resize-none')
  end

  it 'applies indigo ring class by default' do
    render_textarea
    # resolve_input_classes emits "ring-indigo-500" (without the "focus:" prefix as a CSS class token)
    expect(page).to have_css('textarea.ring-indigo-500')
  end

  it 'applies a different theme color when theme is supplied' do
    render_textarea(theme: { 'primary_color' => 'blue' })
    expect(page).to have_css('textarea.ring-blue-500')
  end
end
