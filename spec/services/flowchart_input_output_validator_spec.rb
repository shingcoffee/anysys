# spec/services/flowchart_input_output_validator_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlowchartInputOutputValidator do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:flowchart) { create(:flowchart, :simple, customer: customer) }

  def flowchart_for(configuration)
    create(:flowchart, customer: customer, configuration: configuration)
  end

  describe '.call' do
    it 'returns a result object' do
      result = described_class.call(flowchart)

      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
    end

    it 'returns valid? true for a simple flowchart with no inputs' do
      result = described_class.call(flowchart)

      expect(result.valid?).to be true
      expect(result.errors).to be_empty
    end
  end

  describe 'implicit keys' do
    it 'loads implicit keys from config file' do
      validator = described_class.new(flowchart)

      expect(validator.send(:implicit_keys)).to include('bound_entity', 'customer_id')
    end

    it 'treats PublicSubmission-seeded keys as implicit, including audience' do
      validator = described_class.new(flowchart)

      expect(validator.send(:implicit_keys)).to include(
        'params', 'bound_entity', 'customer_id', 'authentication',
        'current_user_id', 'current_user_role', 'audience', 'device_type',
        'request_ip', 'user_agent', 'locale', 'request_id', 'flowchart_id'
      )
    end

    it 'lists every key a run is seeded with' do
      implicit = described_class.new(flowchart).send(:implicit_keys)

      expect(CodeGenerators::ConfigSchema::SEEDED_KEYS - implicit.to_a).to be_empty
    end

    it 'accepts an audit_log step that reads the request metadata keys by default' do
      config = CodeGenerators::ElementTypes::Process::Utility::AuditLogGenerator.sample_input
      audit = flowchart_for({
        'elements' => [
          { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
          { 'id' => 'el_2', 'type' => 'process', 'label' => 'Audit',
            'properties' => { 'steps' => [{ 'action' => 'audit_log', 'config' => config }] } },
          { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
          { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
        ],
        'metadata' => {}
      }.to_json)

      expect(described_class.call(audit).errors).to be_empty
    end
  end

  describe 'reachability' do
    let(:config_with_chain) do
      {
        'elements' => [
          { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
          { 'id' => 'el_2', 'type' => 'process', 'label' => 'Process', 'properties' => { 'steps' => [] } },
          { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
          { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
        ],
        'metadata' => {}
      }.to_json
    end

    let(:flowchart_with_chain) { flowchart_for(config_with_chain) }

    it 'computes predecessors for each element' do
      validator = described_class.new(flowchart_with_chain)
      predecessors = validator.send(:build_predecessors)

      expect(predecessors['el_1']).to eq([])
      expect(predecessors['el_2']).to contain_exactly('el_1')
      expect(predecessors['el_3']).to contain_exactly('el_1', 'el_2')
    end
  end

  describe 'output collection' do
    let(:config_with_outputs) do
      {
        'elements' => [
          { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
          {
            'id' => 'el_2',
            'type' => 'process',
            'label' => 'Process',
            'properties' => {
              'steps' => [
                { 'action' => 'assign_value', 'config' => { 'resultVar' => 'user_name', 'valueType' => 'string', 'stringValue' => 'John' } }
              ]
            }
          },
          { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
        ],
        'connections' => [
          { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
          { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
        ],
        'metadata' => {}
      }.to_json
    end

    let(:flowchart_with_outputs) { flowchart_for(config_with_outputs) }

    it 'collects effective outputs per element' do
      validator = described_class.new(flowchart_with_outputs)
      outputs = validator.send(:collect_element_outputs)

      expect(outputs['el_2']).to include('user_name')
      expect(outputs['el_1']).to be_empty
      expect(outputs['el_3']).to be_empty
    end

    context 'with io_overrides renamed_to' do
      let(:config_with_rename) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'answer', 'valueType' => 'integer', 'integerValue' => 42 } }
                ],
                'io_overrides' => {
                  'outputs' => [{ 'pin' => 'answer', 'renamed_to' => 'answer_abc123' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_with_rename) { flowchart_for(config_with_rename) }

      it 'uses renamed_to as effective output key' do
        validator = described_class.new(flowchart_with_rename)
        outputs = validator.send(:collect_element_outputs)

        expect(outputs['el_2']).to include('answer_abc123')
        expect(outputs['el_2']).not_to include('answer')
      end
    end
  end

  describe 'input validation' do
    context 'when input has no upstream output' do
      let(:config_with_missing_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_with_missing) { flowchart_for(config_with_missing_input) }

      it 'returns invalid with error for missing input' do
        result = described_class.call(flowchart_with_missing)

        expect(result.valid?).to be false
        expect(result.errors.size).to eq(1)
        expect(result.errors.first[:missing_input]).to eq('api_url')
        expect(result.errors.first[:element_id]).to eq('el_2')
      end
    end

    context 'when input is satisfied by upstream output' do
      let(:config_with_satisfied_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Set URL',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'api_url', 'valueType' => 'string', 'stringValue' => 'https://api.example.com' } }
                ]
              }
            },
            {
              'id' => 'el_3',
              'type' => 'process',
              'label' => 'Call API',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_4', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' },
            { 'id' => 'c3', 'from' => 'el_3', 'to' => 'el_4' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_satisfied) { flowchart_for(config_with_satisfied_input) }

      it 'returns valid' do
        result = described_class.call(flowchart_satisfied)

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'when a build_contract step consumes the implicit audience key' do
      let(:config_with_audience) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Build contract',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'model', 'valueType' => 'null' } },
                  { 'action' => 'build_contract', 'config' => { 'contractClass' => 'EntityEntryContract' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      it 'reports no missing-input problem' do
        result = described_class.call(flowchart_for(config_with_audience))

        expect(result.errors.map { |e| e[:missing_input] }).not_to include('audience')
        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'when input is an implicit key' do
      let(:config_with_implicit_input) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'cid', 'valueType' => 'ctx_ref', 'ctxRefVariable' => 'customer_id' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_implicit) { flowchart_for(config_with_implicit_input) }

      it 'returns valid because implicit keys are excluded' do
        result = described_class.call(flowchart_implicit)

        expect(result.valid?).to be true
      end
    end

    context 'when input is satisfied by the element\'s own earlier output' do
      let(:config_with_self_output) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'api_url', 'valueType' => 'string', 'stringValue' => 'https://api.example.com' } },
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ]
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_self_output) { flowchart_for(config_with_self_output) }

      it 'returns valid because the element emits the pin itself' do
        result = described_class.call(flowchart_self_output)

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'when input is satisfied by the element\'s own renamed output' do
      let(:config_with_self_rename) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'api_url', 'valueType' => 'string', 'stringValue' => 'https://api.example.com' } },
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ],
                'io_overrides' => {
                  'outputs' => [{ 'pin' => 'api_url', 'renamed_to' => 'api_url_xyz' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_self_rename) { flowchart_for(config_with_self_rename) }

      it 'returns valid (runtime rewrite resolves the self-read against the renamed self-output)' do
        result = described_class.call(flowchart_self_rename)

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'when input has io_override that resolves via own effective output (overridden + own_effective match)' do
      # This exercises the branch: overridden=true && own_effective_outputs.include?(effective_key)
      # Element el_2 emits 'result' and renames it to 'aliased_result' via output override.
      # It also reads 'aliased_result' via an input override that maps 'api_url' -> 'aliased_result'.
      # So the effective_key ('aliased_result') IS in own_effective_outputs → no error.
      let(:config_override_resolved_by_own_effective) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'assign_value', 'config' => { 'resultVar' => 'result', 'valueType' => 'string', 'stringValue' => 'x' } },
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ],
                'io_overrides' => {
                  'outputs' => [{ 'pin' => 'result', 'renamed_to' => 'aliased_result' }],
                  'inputs'  => [{ 'pin' => 'api_url', 'override_key' => 'aliased_result' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_override_own_effective) { flowchart_for(config_override_resolved_by_own_effective) }

      it 'returns valid when overridden key is satisfied by element own effective output' do
        result = described_class.call(flowchart_override_own_effective)
        expect(result.valid?).to be true
      end
    end

    context 'when a connection references a non-existent target element (key not in reverse_graph)' do
      # Covers the branch: `reverse_graph.key?(conn['to'])` is false → skip adding to predecessors
      let(:config_dangling_connection) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            { 'id' => 'el_2', 'type' => 'end',   'label' => 'End',   'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_1', 'to' => 'ghost_id' }  # ghost_id not in elements
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_dangling) { flowchart_for(config_dangling_connection) }

      it 'does not raise and returns a valid result' do
        expect { described_class.call(flowchart_dangling) }.not_to raise_error
        result = described_class.call(flowchart_dangling)
        expect(result.valid?).to be true
      end
    end

    context 'when input has tombstone override' do
      let(:config_with_tombstone) do
        {
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} },
            {
              'id' => 'el_2',
              'type' => 'process',
              'label' => 'Process',
              'properties' => {
                'steps' => [
                  { 'action' => 'api_call', 'config' => { 'url' => 'ctx[:api_url]', 'method' => 'GET' } }
                ],
                'io_overrides' => {
                  'inputs' => [{ 'pin' => 'api_url', 'override_key' => '' }]
                }
              }
            },
            { 'id' => 'el_3', 'type' => 'end', 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 'el_1', 'to' => 'el_2' },
            { 'id' => 'c2', 'from' => 'el_2', 'to' => 'el_3' }
          ],
          'metadata' => {}
        }.to_json
      end

      let(:flowchart_tombstone) { flowchart_for(config_with_tombstone) }

      it 'returns valid because tombstone means user said no producer needed' do
        result = described_class.call(flowchart_tombstone)

        expect(result.valid?).to be true
      end
    end

    context 'when configuration rows are not objects' do
      it 'does not raise TypeError when an element is a string' do
        fc = flowchart_for({
          'elements' => ['nope', { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => {} }],
          'connections' => [],
          'metadata' => {}
        }.to_json)

        expect { described_class.call(fc) }.not_to raise_error
      end

      it 'does not raise TypeError when properties is not a hash' do
        fc = flowchart_for({
          'elements' => [
            { 'id' => 'el_1', 'type' => 'start', 'label' => 'Start', 'properties' => 'oops' }
          ],
          'connections' => [ 'dangling' ],
          'metadata' => {}
        }.to_json)

        expect { described_class.call(fc) }.not_to raise_error
      end
    end
  end
end
