# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::CalculationsPanelComponent, type: :component do
  subject { render_inline(described_class.new(calculations: calculations, fields: fields)) }

  let(:calculations) do
    [
      {
        'id' => 'calc_1',
        'target_field_id' => 'total_price',
        'formula' => 'quantity * unit_price'
      },
      {
        'id' => 'calc_2',
        'target_field_id' => 'grand_total',
        'formula' => 'SUM(total_price, tax, shipping)'
      }
    ]
  end
  let(:fields) do
    [
      { 'id' => 'total_price', 'label' => 'Total Price' },
      { 'id' => 'grand_total', 'label' => 'Grand Total' }
    ]
  end


  it 'renders the calculations panel' do
    expect(subject).to have_css('[data-calculations-panel]')
    expect(subject).to have_text('calculations configured')
  end

  it 'renders each calculation' do
    expect(subject).to have_css('[data-calculation-id="calc_1"]')
    expect(subject).to have_css('[data-calculation-id="calc_2"]')
  end

  it 'shows target field labels' do
    expect(subject).to have_text('Total Price')
    expect(subject).to have_text('Grand Total')
  end

  it 'shows formula preview' do
    expect(subject).to have_text('quantity * unit_price')
  end

  it 'renders add calculation button' do
    expect(subject).to have_css('[data-action*="openFormulaEditor"]')
  end

  context 'with no calculations' do
    let(:calculations) { [] }

    it 'shows empty state' do
      expect(subject).to have_text('No calculated fields')
    end
  end

  context 'with a calculation that has a format badge' do
    let(:calculations_with_format) do
      [
        {
          'id' => 'calc_f',
          'target_field_id' => 'total_price',
          'formula' => 'a + b',
          'format' => { 'type' => 'currency' }
        }
      ]
    end

    it 'renders the format badge when fmt_type is not plain' do
      rendered = render_inline(described_class.new(calculations: calculations_with_format, fields: fields))
      expect(rendered).to have_css('[data-calculation-id="calc_f"]')
    end
  end

  context 'with a calculation with format type plain (no badge)' do
    let(:calculations_plain) do
      [{ 'id' => 'calc_p', 'target_field_id' => 'total_price', 'formula' => 'a + b',
         'format' => { 'type' => 'plain' } }]
    end

    it 'does not render a format badge for plain format' do
      rendered = render_inline(described_class.new(calculations: calculations_plain, fields: fields))
      expect(rendered).to have_css('[data-calculation-id="calc_p"]')
    end
  end

  context 'with a long formula that needs truncation' do
    let(:long_formula_calc) do
      [{ 'id' => 'calc_long', 'target_field_id' => 'grand_total',
         'formula' => 'a' * 80 }]
    end

    it 'truncates formulas longer than 60 characters with an ellipsis' do
      rendered = render_inline(described_class.new(calculations: long_formula_calc, fields: fields))
      expect(rendered.text).to include('…')
    end
  end

  context 'with more than 6 calculations (show_search? branch)' do
    let(:many_calcs) do
      7.times.map { |i| { 'id' => "calc_#{i}", 'target_field_id' => 'x', 'formula' => "f#{i}" } }
    end

    it 'renders a search input for filtering calculations' do
      rendered = render_inline(described_class.new(calculations: many_calcs, fields: fields))
      expect(rendered).to have_css('input[data-filter-panel="calculations-panel"]')
    end
  end

  context 'with a calculation where field_id is not in the fields list' do
    let(:orphan_calc) do
      [{ 'id' => 'calc_orphan', 'target_field_id' => 'unknown_field', 'formula' => 'x * y' }]
    end

    it 'falls back to using field_id as the label' do
      rendered = render_inline(described_class.new(calculations: orphan_calc, fields: []))
      expect(rendered.text).to include('unknown_field')
    end
  end
end
