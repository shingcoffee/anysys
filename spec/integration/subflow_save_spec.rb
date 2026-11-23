# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Subflow Save Behavior', type: :integration do
  let(:entity) { create(:entity) }

  let(:subflow_flowchart) do
    create(:flowchart, name: 'Validate User Subflow', customer: entity.customer)
  end

  describe 'configuration with subflow references' do
    let(:flowchart_with_subflow) do
      create(:flowchart, customer: entity.customer, configuration: {
        'elements' => [
          {
            'id' => 'start_1',
            'type' => 'start',
            'x' => 100,
            'y' => 50,
            'width' => 100,
            'height' => 45,
            'label' => 'Start',
            'properties' => {}
          },
          {
            'id' => 'process_1',
            'type' => 'process',
            'x' => 100,
            'y' => 150,
            'width' => 100,
            'height' => 45,
            'label' => 'Prepare Data',
            'properties' => { 'steps' => [] }
          },
          {
            'id' => 'subflow_1',
            'type' => 'subflow',
            'x' => 100,
            'y' => 250,
            'width' => 100,
            'height' => 45,
            'label' => 'Sub-flow: Validate User',
            'properties' => {
              'flowchartId' => subflow_flowchart.id,
              'inputs' => [{ 'value' => 'ctx' }],
              'outputs' => [{ 'value' => 'signal' }, { 'value' => 'ctx' }]
            }
          },
          {
            'id' => 'end_1',
            'type' => 'end',
            'x' => 100,
            'y' => 350,
            'width' => 100,
            'height' => 45,
            'label' => 'End',
            'properties' => {}
          }
        ],
        'connections' => [
          { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
          { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'subflow_1' },
          { 'id' => 'conn_3', 'from' => 'subflow_1', 'to' => 'end_1' }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 },
          'created_at' => Time.current.iso8601
        }
      }.to_json)
    end

    it 'stores subflow as compact reference with flowchartId' do
      subflow_element = flowchart_with_subflow.elements.find { |el| el['type'] == 'subflow' }

      expect(subflow_element).to be_present
      expect(subflow_element['properties']['flowchartId']).to eq(subflow_flowchart.id)
    end

    it 'generates activity code with Subprocess declaration' do
      expect(flowchart_with_subflow.activity).to include('step Subprocess(ValidateUserSubflowActivity)')
    end

    it 'lists the subflow in the activity header comments' do
      code = flowchart_with_subflow.activity

      expect(code).to include(%(# Subflows: ValidateUserSubflowActivity (##{subflow_flowchart.id} "Validate User Subflow")))
    end

    it 'generates regular steps for non-subflow elements' do
      code = flowchart_with_subflow.activity

      expect(code).to include('step :prepare_data')
      expect(code).to include('def prepare_data(ctx, **)')
    end
  end

  describe 'varMappings rejection' do
    def configuration_with_var_mappings
      {
        'elements' => [
          {
            'id' => 'start_1',
            'type' => 'start',
            'x' => 100,
            'y' => 50,
            'width' => 100,
            'height' => 45,
            'label' => 'Start',
            'properties' => {}
          },
          {
            'id' => 'subflow_1',
            'type' => 'subflow',
            'x' => 100,
            'y' => 150,
            'width' => 100,
            'height' => 45,
            'label' => 'Sub-flow: Validate User',
            'properties' => {
              'flowchartId' => subflow_flowchart.id,
              'varMappings' => [
                { 'keyword' => 'user_id', 'value' => 'current_user.id' },
                { 'keyword' => 'status', 'value' => 'active' }
              ]
            }
          },
          {
            'id' => 'end_1',
            'type' => 'end',
            'x' => 100,
            'y' => 250,
            'width' => 100,
            'height' => 45,
            'label' => 'End',
            'properties' => {}
          }
        ],
        'connections' => [
          { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'subflow_1' },
          { 'id' => 'conn_2', 'from' => 'subflow_1', 'to' => 'end_1' }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 }
        }
      }.to_json
    end

    it 'rejects persisting a subflow that still carries unsupported varMappings' do
      expect {
        create(:flowchart, customer: entity.customer, configuration: configuration_with_var_mappings)
      }.to raise_error(ActivityGenerator::Error, /varMappings is not a recognized setting/)
    end
  end

  describe 'activity generator with subflow lookup' do
    # Builds a start → subflow → end flowchart whose single subflow element
    # references +flowchart_id+, then returns the generated activity code.
    def generated_code_referencing(flowchart_id)
      flowchart = create(:flowchart, customer: entity.customer, configuration: {
        'elements' => [
          { 'id' => 'start_1', 'type' => 'start', 'x' => 100, 'y' => 50, 'label' => 'Start', 'properties' => {} },
          {
            'id' => 'subflow_1',
            'type' => 'subflow',
            'x' => 100,
            'y' => 150,
            'label' => 'Sub-flow',
            'properties' => { 'flowchartId' => flowchart_id }
          },
          { 'id' => 'end_1', 'type' => 'end', 'x' => 100, 'y' => 250, 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'subflow_1' },
          { 'id' => 'conn_2', 'from' => 'subflow_1', 'to' => 'end_1' }
        ],
        'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
      }.to_json)

      ActivityGenerator.new(flowchart).generate
    end

    it 'looks up referenced flowchart by id' do
      # Should derive activity class name from the referenced flowchart's name
      expect(generated_code_referencing(subflow_flowchart.id)).to include('ValidateUserSubflowActivity')
    end

    it 'raises when the subflow reference is missing' do
      expect {
        generated_code_referencing(999999) # Non-existent ID
      }.to raise_error(ActivityGenerator::Error, /missing or inaccessible flowchart/)
    end
  end
end
