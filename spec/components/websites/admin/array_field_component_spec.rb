# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Websites::Admin::ArrayFieldComponent, type: :component do
  SCHEMAS = {
    'proof_strip' => %w[label value], 'bento_grid' => %w[span title body image_url],
    'alternating_features' => %w[title body image_url], 'card_grid' => %w[title body image_url href],
    'team_grid' => %w[name role bio image_url], 'faq' => %w[question answer]
  }.freeze

  def render_array(type, count: 2, workspace: true)
    schema = Websites::Admin::SectionEditorComponent.new(section: { type: type }).field_schema.find { |field| field[:kind] == :array }
    items = Array.new(count) { |index| SCHEMAS.fetch(type).index_with { |key| "#{key} #{index + 1}" } }
    render_inline(described_class.new(field: schema, items: items, field_id: 'collection', workspace: workspace, uploadable: true))
    Nokogiri::HTML.fragment(rendered_content)
  end

  SCHEMAS.each do |type, keys|
    it "renders every #{type} item field identically in initial and new-item markup" do
      dom = render_array(type)
      array = dom.at_css('[data-array]')
      expect(array['data-array-kind']).to eq(Websites::SectionKit::ARRAY_PROPS.fetch(type))
      expect(array['data-item-title-key']).to eq((%w[title name question label] & keys).first)
      expect(array.at_css('[data-array-count]').text).to eq('2')
      item = array.at_css('[data-array-list] > [data-array-item]')
      template = array.at_css('template [data-array-item]')
      [item, template].each do |node|
        expect(node.css('[data-prop]').map { |control| control['data-prop'] }.uniq).to match_array(keys)
        expect(node.at_css('[data-item-number]')).to be_present
        expect(node.at_css('[data-item-title]')).to be_present
        expect(node.css('summary button')).to be_empty
      end
      if type == 'proof_strip'
        expect(item.name).to eq('div')
        expect(array.css('details[data-array-item]')).to be_empty
      else
        expect(item.name).to eq('details')
        expect(item.key?('open')).to be(true)
        expect(template.name).to eq('details')
        expect(array.css('[data-array-list] > details')[1].key?('open')).to be(false)
      end
      expect(array.css('[id]').map { |node| node['id'] }.tally.values).to all(eq(1))
    end
  end

  it 'disables add and every duplicate at maximum, with a localized header boundary' do
    dom = render_array('card_grid', count: 12)
    expect(dom.at_css('[data-add-item]').key?('disabled')).to be(true)
    expect(dom.css('[data-array-list] [data-duplicate-item][disabled]').size).to eq(12)
    expect(dom.at_css('[data-array-limit]').text).to eq('12 of 12')
    expect(dom.at_css('[data-array-limit]')['class']).not_to include('hidden')
    expect(dom.css('[data-array-list] [data-remove-item][disabled]')).to be_empty
  end

  it 'disables proof removal at minimum and offers adding when a collection is empty' do
    dom = render_array('proof_strip', count: 4)
    expect(dom.css('[data-array-list] [data-remove-item][disabled]').size).to eq(4)
    dom = render_array('card_grid', count: 0)
    expect(dom.css('[data-array-list] [data-array-item]')).to be_empty
    expect(dom.at_css('[data-add-item]').key?('disabled')).to be(false)
    expect(dom.at_css('template details[data-array-item]')).to be_present
  end

  it 'frames workspace items in one bordered list that disappears when empty, with an accent add action' do
    dom = render_array('card_grid')
    expect(dom.at_css('[data-array-list]')['class'].split).to include('gap-2')
    expect(dom.at_css('[data-array-list]')['class'].split).not_to include('divide-y')
    expect(dom.at_css('[data-array-item]')['class'].split).to include('rounded-lg', 'border')
    add = dom.at_css('[data-add-item]')
    expect(add['class'].split).to include('text-accent')
    expect(add.at_css('svg[aria-hidden="true"]')).to be_present
    expect(add.text.strip).to eq(I18n.t('website.admin.pages.form.add_cards'))
  end

  it 'keeps nonworkspace items expanded with the add button after the template' do
    dom = render_array('card_grid', workspace: false)
    expect(dom.css('details[data-array-item]')).to be_empty
    expect(dom.css('[data-item-title], [data-array-count]')).to be_empty
    expect(dom.at_css('template + [data-add-item]')).to be_present
  end
end
