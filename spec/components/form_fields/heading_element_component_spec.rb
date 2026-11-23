# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::HeadingElementComponent, type: :component do
  it 'renders h2 by default' do
    render_inline(described_class.new(text: 'Section Title'))
    expect(page).to have_css('h2', text: 'Section Title')
  end

  it 'renders specified heading level' do
    render_inline(described_class.new(text: 'Main Title', level: 1))
    expect(page).to have_css('h1', text: 'Main Title')
  end

  it 'renders with custom alignment' do
    render_inline(described_class.new(text: 'Centered', alignment: 'center'))
    expect(page).to have_css('.text-center')
  end

  describe "wrapper_margin responds to field_spacing theme" do
    def wrapper_class(**opts)
      render_inline(described_class.new(text: 'Heading', **opts)).css("div").first["class"]
    end

    it "emits mt-3 (normal) wrapper by default" do
      expect(wrapper_class).to include("mt-3")
    end

    it "emits mt-2 for tight field_spacing" do
      expect(wrapper_class(theme: { "field_spacing" => "tight" })).to include("mt-2")
    end

    it "emits mt-4 for relaxed field_spacing" do
      expect(wrapper_class(theme: { "field_spacing" => "relaxed" })).to include("mt-4")
    end
  end
end
