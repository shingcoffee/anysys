# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::ParagraphElementComponent, type: :component do
  it 'renders paragraph text' do
    render_inline(described_class.new(content_text: 'Please fill out all required fields.'))
    expect(page).to have_css('p', text: 'Please fill out all required fields.')
  end

  it 'defaults to left alignment' do
    render_inline(described_class.new(content_text: 'Text'))
    expect(page).to have_css('.text-left')
  end

  it 'supports center alignment' do
    render_inline(described_class.new(content_text: 'Centered', alignment: 'center'))
    expect(page).to have_css('.text-center')
  end

  it 'supports right alignment' do
    render_inline(described_class.new(content_text: 'Right', alignment: 'right'))
    expect(page).to have_css('.text-right')
  end
end
