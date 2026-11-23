require 'rails_helper'

RSpec.describe FlowchartElements::StartElementComponent, type: :component do
  subject(:component) { described_class.new }

  describe '#initialize' do
    it 'sets element_type to start' do
      expect(component.element_type).to eq(:start)
    end

    it 'sets default label to Start' do
      expect(component.label).to eq('Start')
    end

    it 'allows custom label' do
      component = described_class.new(label: 'Begin Process')
      expect(component.label).to eq('Begin Process')
    end
  end

  describe '#render' do
    it 'renders with green styling' do
      render_inline(component)

      expect(page).to have_css('[data-element-type="start"]')
      expect(page).to have_text('Start')
    end

    it 'includes start-specific data attributes' do
      render_inline(component)

      expect(page).to have_css('[data-element-type="start"]')
      expect(page).to have_css('[data-flowchart-element="start"]')
    end
  end

  describe 'element_specific_classes' do
    it 'returns green color scheme classes' do
      classes = component.send(:element_specific_classes)

      expect(classes).to include('bg-green-50')
      expect(classes).to include('border-green-400')
      expect(classes).to include('text-green-800')
      expect(classes).to include('hover:border-green-600')
    end
  end
end
