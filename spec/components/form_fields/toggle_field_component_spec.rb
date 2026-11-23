# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::ToggleFieldComponent, type: :component do
  # Defaults to a labelled "Active" toggle; override any arg.
  def render_toggle(**opts)
    render_inline(described_class.new(**{ field_name: :active, label: 'Active' }.merge(opts)))
  end

  it 'renders toggle switch' do
    render_toggle
    expect(page).to have_css('input[type="checkbox"]')
    expect(page).to have_css('[data-toggle-switch]')
  end

  it 'renders label' do
    render_toggle(label: 'Enable Feature')
    expect(page).to have_text('Enable Feature')
  end

  it 'renders checked state' do
    render_toggle(value: true)
    expect(page).to have_checked_field(type: 'checkbox')
  end

  it 'renders description when provided' do
    render_toggle(description: 'Toggle this to activate')
    expect(page).to have_text('Toggle this to activate')
  end
end
