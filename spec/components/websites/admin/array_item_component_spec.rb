# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Websites::Admin::ArrayItemComponent, type: :component do
  def render_item(type: 'card_grid', item: {}, **options)
    schema = Websites::Admin::SectionEditorComponent.new(section: { type: type }).field_schema.find { |field| field[:kind] == :array }
    render_inline(described_class.new(fields: schema[:item_fields], item: item, field_id: 'item_2', number: 2, workspace: true, **options))
    Nokogiri::HTML.fragment(rendered_content).at_css('[data-array-item]')
  end

  it 'identifies an item in its native summary with no interactive children or ID lookup' do
    item = render_item(item: { title: 'North gallery', image_url: 'https://cdn.example.org/north.jpg' })
    summary = item.at_css('summary')
    expect(item.name).to eq('details')
    expect(summary.at_css('[data-item-number]').text).to eq('2')
    expect(summary.at_css('[data-item-title]').text).to eq('North gallery')
    expect(summary.at_css('[data-item-image]')['data-action']).to eq('error->website-builder#itemImageError')
    expect(summary.css('button, input, a, [id], [tabindex]')).to be_empty
    expect(summary.next_element.element_children.first.at_css('[data-duplicate-item]')).to be_present
    expect(item.css('[data-prop="title"]').size).to eq(1)
  end

  it 'reserves header room for the floating toolbar only while it is showing' do
    accordion = render_item(item: { title: 'North gallery' })
    expect(accordion['class'].split).to include('group/item', 'relative')
    expect(accordion.at_css('summary')['class'].split).to include('@min-[21rem]/content:group-open/item:pr-38')

    simple = render_item(type: 'proof_strip', simple: true, item: { label: 'Visitors', value: '12k' })
    expect(simple.name).to eq('div')
    expect(simple.element_children.first['class'].split).to include('@min-[21rem]/content:pr-38')
    expect(simple.element_children.first['class']).not_to include('group-open')
  end

  it 'uses localized fallback identity without changing the stored blank title' do
    I18n.with_locale('zh-CN') do
      item = render_item
      expect(item.at_css('[data-item-title]').text).to eq('条目 2')
      expect(item.at_css('[data-prop="title"]')['value']).to eq('')
      expect(item.at_css('[data-duplicate-item]')['aria-label']).to eq('复制第 2 项：条目 2')
      expect(item.at_css('[data-item-image]')['src']).to be_nil
    end
  end

  it 'escapes titles and never renders unsafe summary image URLs' do
    title = '<script>alert(1)</script>'
    item = render_item(item: { title: title, image_url: 'javascript:alert(1)' })
    expect(item.at_css('[data-item-title]').text).to eq(title)
    expect(item.css('script')).to be_empty
    expect(item.at_css('[data-item-image]')['src']).to be_nil
    expect(item.at_css('[data-prop="image_url"]')['value']).to eq('javascript:alert(1)')
  end

  it 'preserves literal backreferences in contextual item action labels' do
    item = render_item(item: { title: 'Gallery \\&' })
    expect(item.at_css('[data-duplicate-item]')['aria-label']).to eq('Duplicate item 2: Gallery \\&')
  end

  it 'pairs team identity and places bento span after copy and media' do
    item = render_item(type: 'team_grid', title_key: 'name', item: { name: 'Alex', role: 'Curator' })
    expect(item.at_css('[data-item-title]').text).to eq('Alex')
    pair = item.at_css('[data-prop="name"]').ancestors.find { |node| node['class'].to_s.include?('@min-[24rem]/content:grid-cols-2') }
    expect(pair.css('[data-prop]').map { |node| node['data-prop'] }).to eq(%w[name role])
    item = render_item(type: 'bento_grid', item: { span: 'wide' })
    expect(item.css('[data-prop]').map { |node| node['data-prop'] }.uniq).to eq(%w[title body image_url span])
    expect(item.at_css('input[type="radio"][value="wide"]').key?('checked')).to be(true)
  end

  it 'uses two resizable rows for repeated short descriptions while longer answers and bios keep three' do
    %w[card_grid bento_grid alternating_features].each do |type|
      item = render_item(type: type, item: { body: "First\nSecond\nThird" })
      body = item.at_css('textarea[data-prop="body"]')
      expect(body['rows']).to eq('2')
      expect(body['class'].split).to include('resize-y', 'input-field')
      expect(body.text).to eq("First\nSecond\nThird")
    end
    expect(render_item(type: 'faq').at_css('textarea')['rows']).to eq('3')
    expect(render_item(type: 'team_grid').at_css('textarea')['rows']).to eq('3')
  end
end
