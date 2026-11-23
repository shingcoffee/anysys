# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::ImageElementComponent, type: :component do
  let(:image_url) { 'https://example.com/photo.jpg' }

  def render_image(**opts)
    render_inline(described_class.new(image_url: image_url, **opts))
  end

  it 'renders an image when URL is provided' do
    render_image(alt_text: 'A photo')
    expect(page).to have_css('img[src="https://example.com/photo.jpg"]')
    expect(page).to have_css('img[alt="A photo"]')
  end

  it 'renders a placeholder when no URL is provided' do
    render_image(image_url: '')
    expect(page).not_to have_css('img')
    expect(page).to have_text('No image URL provided')
  end

  it 'defaults to center alignment' do
    render_image
    expect(page).to have_css('.text-center')
  end

  it 'supports left alignment' do
    render_image(alignment: 'left')
    expect(page).to have_css('.text-left')
  end

  it 'supports right alignment' do
    render_image(alignment: 'right')
    expect(page).to have_css('.text-right')
  end

  it 'defaults alt_text to empty string' do
    render_image
    expect(page).to have_css('img[alt=""]')
  end
end
