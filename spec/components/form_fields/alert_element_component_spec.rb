# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::AlertElementComponent, type: :component do
  def render_alert(content_text:, **opts)
    render_inline(described_class.new(content_text: content_text, **opts))
  end

  it 'renders the alert content text' do
    render_alert(content_text: 'Please verify your email.')
    expect(page).to have_text('Please verify your email.')
  end

  it 'defaults to the blue info variant' do
    render_alert(content_text: 'Info alert')
    expect(page).to have_css('.bg-blue-50')
    expect(page).to have_css('.border-blue-200')
  end

  it 'renders the yellow warning variant' do
    render_alert(content_text: 'Warning', variant: 'warning')
    expect(page).to have_css('.bg-yellow-50')
    expect(page).to have_css('.border-yellow-200')
  end

  it 'renders the green success variant' do
    render_alert(content_text: 'Success', variant: 'success')
    expect(page).to have_css('.bg-green-50')
    expect(page).to have_css('.border-green-200')
  end

  it 'renders the red danger variant' do
    render_alert(content_text: 'Error', variant: 'danger')
    expect(page).to have_css('.bg-red-50')
    expect(page).to have_css('.border-red-200')
  end

  it 'renders an SVG icon' do
    render_alert(content_text: 'Alert')
    expect(page).to have_css('svg')
  end
end
