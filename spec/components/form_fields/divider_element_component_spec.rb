# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::DividerElementComponent, type: :component do
  it 'renders horizontal rule' do
    render_inline(described_class.new)
    expect(page).to have_css('hr')
  end

  it 'renders with label when provided' do
    render_inline(described_class.new(label: 'Or continue with'))
    expect(page).to have_text('Or continue with')
  end

  it 'applies explicit sm spacing' do
    render_inline(described_class.new(spacing: 'sm'))
    expect(page).to have_css('.my-2')
  end

  it 'applies explicit lg spacing' do
    render_inline(described_class.new(spacing: 'lg'))
    expect(page).to have_css('.my-8')
  end

  describe "md spacing responds to field_spacing theme key" do
    it "defaults to my-5 (normal spacing) when no theme provided" do
      render_inline(described_class.new(spacing: 'md'))
      expect(page).to have_css('.my-5')
    end

    it "uses my-3 for tight field_spacing" do
      render_inline(described_class.new(spacing: 'md', theme: { "field_spacing" => "tight" }))
      expect(page).to have_css('.my-3')
    end

    it "uses my-5 for normal field_spacing" do
      render_inline(described_class.new(spacing: 'md', theme: { "field_spacing" => "normal" }))
      expect(page).to have_css('.my-5')
    end

    it "uses my-6 for relaxed field_spacing" do
      render_inline(described_class.new(spacing: 'md', theme: { "field_spacing" => "relaxed" }))
      expect(page).to have_css('.my-6')
    end
  end

  describe "label background masking" do
    it "uses bg-white by default (no theme / default form_background)" do
      render_inline(described_class.new(label: "Section"))
      expect(page).to have_css("span.bg-white")
    end

    it "uses bg-amber-50/60 for warm form_background theme" do
      render_inline(described_class.new(label: "Section", theme: { "form_background" => "warm" }))
      expect(page).to have_css("span.bg-amber-50\\/60")
    end

    it "uses bg-gray-50 for gray form_background theme" do
      render_inline(described_class.new(label: "Section", theme: { "form_background" => "gray" }))
      expect(page).to have_css("span.bg-gray-50")
    end
  end
end
