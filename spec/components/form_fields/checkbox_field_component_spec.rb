# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::CheckboxFieldComponent, type: :component do
  def render_checkbox(field_name: :agree, label: 'Agree', **opts)
    render_inline(described_class.new(field_name: field_name, label: label, **opts))
  end

  it 'renders a checkbox input' do
    render_checkbox
    expect(page).to have_css('input[type="checkbox"]')
  end

  it 'renders with the fixed value="1" attribute' do
    render_checkbox
    expect(page).to have_css('input[type="checkbox"][value="1"]')
  end

  it 'renders the label text' do
    render_checkbox(label: 'Accept Terms')
    expect(page).to have_text('Accept Terms')
  end

  it 'humanizes field_name when the label is omitted' do
    render_inline(described_class.new(field_name: :agree_to_terms))
    expect(page).to have_text('Agree to terms')
  end

  it 'renders unchecked by default' do
    render_checkbox
    expect(page).not_to have_checked_field(type: 'checkbox')
  end

  it 'renders checked when checked: true' do
    render_checkbox(checked: true)
    expect(page).to have_checked_field(type: 'checkbox')
  end

  it 'applies the indigo focus ring class by default' do
    render_checkbox
    expect(page).to have_css('input.focus\\:ring-indigo-500')
  end

  it 'applies the theme primary color to the focus ring when supplied' do
    render_checkbox(theme: { 'primary_color' => 'blue' })
    expect(page).to have_css('input.focus\\:ring-blue-500')
  end

  it 'wraps the input and label in a flex row' do
    render_checkbox
    expect(page).to have_css('div.flex.items-center')
  end

  it 'uses field_name as the input name attribute' do
    render_checkbox(field_name: :newsletter, label: 'Newsletter')
    expect(page).to have_css('input[name="newsletter"]')
  end
end
