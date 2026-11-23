# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::SelectFieldComponent, type: :component do
  let(:string_options) { %w[Red Green Blue] }
  let(:array_options)  { [['United States', 'us'], ['Canada', 'ca'], ['Mexico', 'mx']] }

  # Defaults to a labelled colour select over string_options; override any arg.
  def render_select(**opts)
    render_inline(described_class.new(**{ field_name: :color, label: 'Color', options: string_options }.merge(opts)))
  end

  it 'renders a select element' do
    render_select
    expect(page).to have_css('select')
  end

  it 'renders the label' do
    render_select(label: 'Favourite Color')
    expect(page).to have_text('Favourite Color')
  end

  it 'humanizes field_name when label is omitted' do
    render_inline(described_class.new(field_name: :country_code, options: array_options))
    expect(page).to have_text('Country code')
  end

  it 'uses field_name as the select name attribute' do
    render_select(field_name: :status, label: 'Status')
    expect(page).to have_css('select[name="status"]')
  end

  # ---------------------------------------------------------------------------
  # include_blank — default behaviour
  # ---------------------------------------------------------------------------
  it 'renders a blank option by default' do
    render_select
    expect(page).to have_css('option[value=""]')
  end

  it 'renders "Select..." as the blank option text when no placeholder given' do
    render_select
    expect(page).to have_css('option[value=""]', text: 'Select...')
  end

  it 'uses placeholder as blank option text when provided' do
    render_select(placeholder: 'Pick a colour')
    expect(page).to have_css('option[value=""]', text: 'Pick a colour')
  end

  it 'omits blank option when include_blank: false' do
    render_select(include_blank: false)
    expect(page).not_to have_css('option[value=""]')
  end

  # ---------------------------------------------------------------------------
  # String options
  # ---------------------------------------------------------------------------
  it 'renders each string option' do
    render_select
    string_options.each do |opt|
      expect(page).to have_css('option', text: opt)
    end
  end

  it 'marks the matching string option as selected' do
    render_select(value: 'Green')
    expect(page).to have_css('option[selected]', text: 'Green')
    expect(page).not_to have_css('option[selected]', text: 'Red')
  end

  # ---------------------------------------------------------------------------
  # Array [label, value] options
  # ---------------------------------------------------------------------------
  it 'renders each [label, value] option with the correct value attribute' do
    render_select(field_name: :country, label: 'Country', options: array_options)
    expect(page).to have_css('option[value="us"]', text: 'United States')
    expect(page).to have_css('option[value="ca"]', text: 'Canada')
    expect(page).to have_css('option[value="mx"]', text: 'Mexico')
  end

  it 'marks the matching array option as selected' do
    render_select(field_name: :country, label: 'Country', options: array_options, value: 'ca')
    expect(page).to have_css('option[value="ca"][selected]')
    expect(page).not_to have_css('option[value="us"][selected]')
  end

  it 'does not mark any option selected when value is nil' do
    render_select(field_name: :country, label: 'Country', options: array_options)
    expect(page).not_to have_css('option[value="us"][selected]')
    expect(page).not_to have_css('option[value="ca"][selected]')
  end

  # ---------------------------------------------------------------------------
  # required / theme
  # ---------------------------------------------------------------------------
  it 'renders the required asterisk when required: true' do
    render_select(required: true)
    expect(page).to have_css('span.text-red-500', text: '*')
  end

  it 'does not render required asterisk by default' do
    render_select
    expect(page).not_to have_css('span.text-red-500')
  end

  it 'applies indigo ring class by default' do
    render_select
    # resolve_input_classes emits "ring-indigo-500" (without the "focus:" prefix as a CSS class token)
    expect(page).to have_css('select.ring-indigo-500')
  end

  it 'applies a different theme color when theme is supplied' do
    render_select(theme: { 'primary_color' => 'blue' })
    expect(page).to have_css('select.ring-blue-500')
  end

  it 'submits a multi-select as an array and marks every selected option' do
    render_select(field_name: "entity[colors]", multiple: true, value: %w[Red Blue])
    expect(page).to have_css('select[multiple][name="entity[colors][]"]')
    expect(page).to have_css('option[selected]', count: 2)
    expect(page).not_to have_css('option[value=""]')
  end

  describe 'quick_add (+ Add New for entity-backed dropdowns)' do
    let(:quick_add) do
      { url: '/1/admin/entities/9/entries/new?label_field=code', label: '+ Add New', title: 'Add Student',
        dialog: '#entity-quick-add-dialog-2' }
    end

    it 'wraps the select in the entity-quick-add controller with its values and dialog outlet' do
      render_select(options: array_options, quick_add: quick_add, data: { conditions: [] })
      wrapper = page.find('div.contents[data-controller="entity-quick-add"]')
      expect(wrapper['data-entity-quick-add-url-value']).to eq(quick_add[:url])
      expect(wrapper['data-entity-quick-add-title-value']).to eq('Add Student')
      expect(wrapper['data-entity-quick-add-entity-quick-add-dialog-outlet']).to eq('#entity-quick-add-dialog-2')

      select = wrapper.find('select')
      expect(select['data-entity-quick-add-target']).to eq('select')
      expect(select['data-action']).to eq('change->entity-quick-add#change')
      expect(select['data-conditions']).to eq('[]')
    end

    it 'puts a blank-valued add-new option last after the placeholder' do
      render_select(options: array_options, quick_add: quick_add)
      options = page.all('option')
      expect(options.map(&:text)).to eq([I18n.t('comp_form_fields.select.blank_option'), 'United States', 'Canada', 'Mexico', '+ Add New'])
      expect(options.last['value']).to eq('')
      expect(options.last['data-quick-add-option']).to eq('true')
      expect(page.all('option[data-quick-add-option]').size).to eq(1)
      expect(page).not_to have_css('option[selected]')
    end

    it 'keeps the current value selected' do
      render_select(options: array_options, quick_add: quick_add, value: 'ca')
      expect(page.all('option[selected]').map(&:text)).to eq(['Canada'])
    end

    it 'leads with the first real option when there is no placeholder' do
      render_select(options: array_options, quick_add: quick_add, include_blank: false)
      expect(page.all('option').map(&:text)).to eq(['United States', 'Canada', 'Mexico', '+ Add New'])
      expect(page).not_to have_css('option[selected]')
    end

    it 'keeps a placeholder ahead of the add-new option for an empty list' do
      render_select(options: [], quick_add: quick_add, include_blank: false)
      expect(page.all('option').map(&:text)).to eq([I18n.t('comp_form_fields.select.blank_option'), '+ Add New'])
    end

    it 'is ignored for multi-selects' do
      render_select(options: array_options, quick_add: quick_add, multiple: true)
      expect(page).not_to have_css('[data-controller]')
      expect(page).not_to have_css('option[data-quick-add-option]')
    end

    it 'leaves the legacy markup untouched without quick_add' do
      render_select(options: array_options)
      expect(page).not_to have_css('[data-controller]')
      expect(page).not_to have_css('option[selected]')
    end
  end
end
