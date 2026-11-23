# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::SpacerElementComponent, type: :component do
  def render_spacer(**opts)
    render_inline(described_class.new(**opts))
  end

  it 'renders with default medium height' do
    render_spacer
    expect(page).to have_css('.h-8')
  end

  it 'renders small height' do
    render_spacer(height: 'sm')
    expect(page).to have_css('.h-4')
  end

  it 'renders large height' do
    render_spacer(height: 'lg')
    expect(page).to have_css('.h-12')
  end

  it 'renders extra large height' do
    render_spacer(height: 'xl')
    expect(page).to have_css('.h-20')
  end

  it 'falls back to medium for invalid height' do
    render_spacer(height: 'invalid')
    expect(page).to have_css('.h-8')
  end
end
