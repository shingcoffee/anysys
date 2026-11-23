require 'rails_helper'

RSpec.describe FlowchartElements::ProcessElementComponent, type: :component do
  subject(:component) { described_class.new }

  describe '#initialize' do
    it 'sets element_type to process' do
      expect(component.element_type).to eq(:process)
    end

    it 'sets default label to Process' do
      expect(component.label).to eq('Process')
    end
  end

  describe '#render' do
    it 'renders with blue styling' do
      render_inline(component)

      expect(page).to have_css('[data-element-type="process"]')
      expect(page).to have_text('Process')
    end

    it 'includes process-specific data attributes' do
      render_inline(component)

      expect(page).to have_css('[data-element-type="process"]')
      expect(page).to have_css('[data-flowchart-element="process"]')
    end
  end

  describe 'element_specific_classes' do
    it 'returns blue color scheme classes' do
      classes = component.send(:element_specific_classes)

      expect(classes).to include('bg-blue-50')
      expect(classes).to include('border-blue-400')
      expect(classes).to include('text-blue-800')
      expect(classes).to include('hover:border-blue-600')
    end
  end
end
