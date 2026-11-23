require 'rails_helper'

RSpec.describe FlowchartElements::BaseElementComponent, type: :component do
  describe '#initialize' do
    it 'sets default values' do
      component = described_class.new(element_type: :test)

      expect(component.element_type).to eq(:test)
      expect(component.label).to eq('Test')
      expect(component.element_id).to match(/element_[a-z0-9]+/)
      expect(component.position).to eq({})
      expect(component.properties).to eq({})
    end

    it 'accepts custom values' do
      component = described_class.new(
        element_type: :process,
        label: 'Custom Process',
        element_id: 'custom_id',
        position: { x: 100, y: 200 },
        properties: { color: 'blue' }
      )

      expect(component.element_type).to eq(:process)
      expect(component.label).to eq('Custom Process')
      expect(component.element_id).to eq('custom_id')
      expect(component.position).to eq({ x: 100, y: 200 })
      expect(component.properties).to eq({ color: 'blue' })
    end
  end

  describe '#render' do
    it 'renders the base structure' do
      component = described_class.new(element_type: :test, label: 'Test Element')
      render_inline(component)

      expect(page).to have_css('.flowchart-element')
      expect(page).to have_text('Test Element')
    end

    it 'includes data attributes' do
      component = described_class.new(element_type: :process, element_id: 'test_id')
      render_inline(component)

      expect(page).to have_css('[data-element-type="process"]')
      expect(page).to have_css('[data-element-id="test_id"]')
      expect(page).to have_css('[data-drag-source="true"]')
      expect(page).to have_css('[data-flowchart-element="process"]')
    end

    it 'applies base CSS classes' do
      component = described_class.new(element_type: :test)
      render_inline(component)

      expect(page).to have_css('.flowchart-element')
      expect(page).to have_css('.border')
      expect(page).to have_css('.cursor-grab')
    end

    it 'renders SVG icon' do
      component = described_class.new(element_type: :start)
      render_inline(component)

      expect(page).to have_css('svg')
    end
  end

  describe '#render_icon' do
    let(:component) { described_class.new(element_type: :test) }

    it 'returns start icon for start type' do
      component.instance_variable_set(:@element_type, :start)
      expect(component.send(:render_icon)).to include('path')
    end

    it 'returns process icon for unknown type' do
      component.instance_variable_set(:@element_type, :unknown)
      expect(component.send(:render_icon)).to include('path')
    end

    it 'returns appropriate icon for each element type' do
      %w[start end process decision connector document database manual_process delay preparation display].each do |type|
        component.instance_variable_set(:@element_type, type.to_sym)
        icon_html = component.send(:render_icon)
        expect(icon_html).to be_present
        expect(icon_html).to include('svg')
      end
    end
  end

  describe 'private methods' do
    let(:component) { described_class.new(element_type: :test) }

    describe '#base_classes' do
      it 'returns base CSS classes' do
        classes = component.send(:base_classes)
        expect(classes).to include('flowchart-element')
        expect(classes).to include('border')
        expect(classes).to include('cursor-grab')
      end
    end

    describe '#element_classes' do
      it 'combines base and specific classes' do
        allow(component).to receive(:element_specific_classes).and_return('custom-class')
        classes = component.send(:element_classes)
        expect(classes).to include('flowchart-element')
        expect(classes).to include('custom-class')
      end
    end

    describe '#html_attributes' do
      it 'includes required attributes' do
        component = described_class.new(element_type: :test, element_id: 'test_id')
        attrs = component.send(:html_attributes)

        expect(attrs[:id]).to eq('test_id')
        expect(attrs[:class]).to be_present
        expect(attrs[:data]).to include(
          element_type: :test,
          element_id: 'test_id',
          'drag-source' => true,
          'flowchart-element' => :test
        )
      end

      it 'merges custom HTML attributes' do
        component = described_class.new(
          element_type: :test,
          class: 'custom-class',
          data: { custom: 'value' }
        )
        attrs = component.send(:html_attributes)

        expect(attrs[:class]).to include('custom-class')
        expect(attrs[:data][:custom]).to eq('value')
      end
    end

    describe '#icon_classes' do
      it 'returns icon CSS classes' do
        classes = component.send(:icon_classes)
        expect(classes).to include('w-4 h-4')
      end
    end

    describe '#label_classes' do
      it 'returns label CSS classes' do
        classes = component.send(:label_classes)
        expect(classes).to include('text-[10px]')
        expect(classes).to include('leading-tight')
      end
    end
  end
end
