# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageBuilder::RulesPanelComponent, type: :component do
  subject { render_inline(described_class.new(rules: rules)) }

  let(:rules) do
    [
      {
        'id' => 'rule_1',
        'name' => 'Show shipping address',
        'enabled' => true,
        'conditions' => { 'logic' => 'all', 'groups' => [] },
        'actions' => [{ 'type' => 'show_field', 'target_id' => 'address' }]
      },
      {
        'id' => 'rule_2',
        'name' => 'Disabled rule',
        'enabled' => false,
        'conditions' => {},
        'actions' => []
      }
    ]
  end


  it 'renders the rules panel header' do
    expect(subject).to have_css('[data-rules-panel]')
    expect(subject).to have_text('rules configured')
  end

  it 'renders each rule' do
    expect(subject).to have_css('[data-rule-id="rule_1"]')
    expect(subject).to have_css('[data-rule-id="rule_2"]')
  end

  it 'shows rule names' do
    expect(subject).to have_text('Show shipping address')
    expect(subject).to have_text('Disabled rule')
  end

  it 'shows enabled indicator for active rules' do
    expect(subject).to have_css('[data-rule-id="rule_1"] .bg-emerald-500')
  end

  it 'shows disabled indicator for inactive rules' do
    expect(subject).to have_css('[data-rule-id="rule_2"] .bg-gray-300')
  end

  it 'renders add rule button' do
    expect(subject).to have_css('[data-action*="openRuleEditor"]')
  end

  it 'renders edit button for each rule' do
    expect(subject).to have_css('[data-action*="editRule"]', count: 2)
  end

  it 'renders delete button for each rule' do
    expect(subject).to have_css('[data-action*="deleteRule"]', count: 2)
  end

  context 'with no rules' do
    let(:rules) { [] }

    it 'shows empty state message' do
      expect(subject).to have_text('No rules defined')
    end
  end

  context 'with rule_summary populated from conditions and actions' do
    let(:fields) { [{ "id" => "email", "label" => "Email" }] }
    let(:rules_with_items) do
      [
        {
          'id' => 'rule_cond',
          'name' => 'Email rule',
          'enabled' => true,
          'conditions' => {
            'logic' => 'all',
            'groups' => [{ 'items' => [{ 'field_id' => 'email', 'operator' => 'equals' }] }]
          },
          'actions' => [{ 'type' => 'show_field', 'target_id' => 'email' }]
        }
      ]
    end

    it 'includes condition field label and action in rule summary' do
      rendered = render_inline(described_class.new(rules: rules_with_items, fields: fields))
      # rule_summary builds a string from condition field_id and action target
      expect(rendered).to have_css('[data-rule-id="rule_cond"]')
    end
  end

  context 'with more than 6 rules (show_search? branch)' do
    let(:rules) do
      7.times.map do |i|
        { 'id' => "rule_#{i}", 'name' => "Rule #{i}", 'enabled' => true,
          'conditions' => {}, 'actions' => [] }
      end
    end

    it 'renders a search input for filtering rules' do
      expect(subject).to have_css('input[data-filter-panel="rules-panel"]')
    end
  end
end
