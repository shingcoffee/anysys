# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::CalloutElementComponent, type: :component do
  ROSE_THEME = { "accent_color" => "rose", "primary_color" => "rose" }.freeze

  def render_callout(content_text: 'Note', **opts)
    render_inline(described_class.new(content_text: content_text, **opts))
  end

  it 'renders the callout content text' do
    render_callout(content_text: 'Important information here.')
    expect(page).to have_text('Important information here.')
  end

  it 'renders with a left accent border' do
    render_callout
    expect(page).to have_css('.border-l-4')
    expect(page).to have_css('.border-indigo-400')
  end

  it 'renders with an indigo background' do
    render_callout
    expect(page).to have_css('.bg-indigo-100')
  end

  it 'renders the text in a paragraph' do
    render_callout(content_text: 'Callout text')
    expect(page).to have_css('p', text: 'Callout text')
  end

  # Task C — d. element components render with default theme {} AND with a
  # non-default palette; rose accent applied to callout bg and border
  describe "theme propagation" do
    it "accepts theme: {} without error (default theme)" do
      expect { render_callout(theme: {}) }.not_to raise_error
    end

    it "applies the rose accent background (bg-rose-100) for a rose accent theme" do
      render_callout(content_text: 'Rose note', theme: ROSE_THEME)
      expect(page).to have_css('.bg-rose-100')
    end

    it "applies the rose accent border (border-rose-400) for a rose accent theme" do
      render_callout(content_text: 'Rose border', theme: ROSE_THEME)
      expect(page).to have_css('.border-rose-400')
    end

    it "applies the rose accent text (text-rose-600) for a rose accent theme" do
      render_callout(content_text: 'Rose text', theme: ROSE_THEME)
      expect(page).to have_css('p.text-rose-600')
    end
  end
end
