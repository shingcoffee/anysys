# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityGenerator do
  def self.removed_structural_examples(_description, &_block)
    # Historical expectations for removed structural controls are intentionally
    # not registered as examples; replacement rejection coverage lives in
    # activity_generator_structural_spec.rb.
  end

  let(:entity) { create(:entity) }

  let(:simple_flowchart) do
    create(:flowchart, :simple)
  end

  let(:complex_flowchart) do
    create(:flowchart, :complex)
  end

  describe '#generate' do
    context 'with a simple flowchart' do
      let(:default_flowchart) { create(:flowchart) }

      it 'generates valid Ruby code' do
        generator = described_class.new(default_flowchart)
        code = generator.generate

        expect(code).to be_present
      end

      it 'generates a Trailblazer::Activity::Railway class' do
        generator = described_class.new(default_flowchart)
        code = generator.generate

        expect(code).to include('Trailblazer::Activity::Railway')
      end

      it 'includes the flowchart name in the class name' do
        default_flowchart.update!(name: 'My Test Flow')
        generator = described_class.new(default_flowchart.reload)
        code = generator.generate

        expect(code).to include('class MyTestFlowActivity')
      end
    end

    context 'with a complex flowchart' do
      let(:complex_flowchart) do
        create(:flowchart, name: "Order Routing", configuration: {
          "elements" => [
            { "id" => "start_1", "type" => "start", "label" => "Start", "properties" => {} },
            { "id" => "el_a", "type" => "process", "label" => "New Model", "properties" => { "steps" => [] } },
            { "id" => "el_b", "type" => "process", "label" => "Build Contract", "properties" => { "steps" => [] } },
            { "id" => "d1", "type" => "decision", "label" => "Is Large Order",
              "properties" => {
                "routeBy" => "condition",
                "condition" => {
                  "type" => "group",
                  "joins" => [],
                  "conditions" => [
                    { "kind" => "field", "leftOperand" => "ctx.big", "operator" => "is_true", "rightOperand" => "" }
                  ]
                }
              } },
            { "id" => "p1", "type" => "process", "label" => "Manual Review", "properties" => { "steps" => [] } },
            { "id" => "p2", "type" => "process", "label" => "Auto Approve", "properties" => { "steps" => [] } },
            { "id" => "p3", "type" => "process", "label" => "Finalize", "properties" => { "steps" => [] } },
            { "id" => "end_1", "type" => "end", "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "c1", "from" => "start_1", "to" => "el_a" },
            { "id" => "c2", "from" => "el_a", "to" => "el_b" },
            { "id" => "c3", "from" => "el_b", "to" => "d1" },
            { "id" => "c4", "from" => "d1", "to" => "p1", "matchValue" => "true" },
            { "id" => "c5", "from" => "d1", "to" => "p2", "matchValue" => "false" },
            { "id" => "c6", "from" => "p1", "to" => "p3" },
            { "id" => "c7", "from" => "p2", "to" => "p3" },
            { "id" => "c8", "from" => "p3", "to" => "end_1" }
          ],
          "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
        }.to_json)
      end

      it "generates named steps, CANVAS, and wiring for a split chain plus diamond" do
        code = described_class.new(complex_flowchart).generate

        expect(code).to include("step :new_model")
        expect(code).to include("step :build_contract")
        expect(code).to include("step :is_large_order")
        expect(code).to include("step :manual_review")
        expect(code).to include("step :auto_approve")
        expect(code).to include("step :finalize")
        expect(code).to include('new_model: "el_a"')
        expect(code).to include('build_contract: "el_b"')
        expect(code).to include('is_large_order: "d1"')
        expect(code).to include('finalize: "p3"')
        expect(code).to include("Output(Routes::IsLargeOrder::Yes, :yes) => Id(:manual_review)")
        expect(code).to include("Output(Routes::IsLargeOrder::No, :no) => Id(:auto_approve)")
        expect(code).to include("Output(:success) => Track(:failure)")
        expect(code).to include("fail :collect_errors")
      end

      it "generates methods for each process and the collect_errors failure step" do
        code = described_class.new(complex_flowchart).generate

        expect(code).to include("def new_model")
        expect(code).to include("def build_contract")
        expect(code).to include("def is_large_order")
        expect(code).to include("def manual_review")
        expect(code).to include("def auto_approve")
        expect(code).to include("def finalize")
        expect(code).to include("def collect_errors")
      end
    end

    context 'with an empty flowchart' do
      let(:empty_flowchart) do
        create(:flowchart, :empty)
      end

      it 'returns nil when no elements exist' do
        generator = described_class.new(empty_flowchart)
        code = generator.generate

        expect(code).to be_nil
      end
    end

    context 'with bound entity (non-blueprint)' do
      let(:entity_with_attributes) do
        create(:entity,
          name: 'User Profile',
          property_schema: [
            { 'name' => 'email', 'name_slug' => 'email', 'type' => 'Types::String', 'validators' => ['presence', 'format_email'] },
            { 'name' => 'age', 'name_slug' => 'age', 'type' => 'Types::Integer', 'validators' => ['numericality'] }
          ].to_json
        )
      end

      let(:flowchart_with_entity) do
        create(:flowchart)
      end

      it 'includes entity information in header' do
        generator = described_class.new(flowchart_with_entity, entity: entity_with_attributes)
        code = generator.generate

        expect(code).to include('# Checked against entity: User Profile')
        expect(code).not_to include('# Model class:')
        expect(code).not_to include('# Contract class:')
      end

      it 'does not generate prepare_context step (handled by the request controller)' do
        generator = described_class.new(flowchart_with_entity)
        code = generator.generate

        expect(code).not_to include('step :prepare_context')
        expect(code).not_to include('def prepare_context')
      end
    end
  end

  describe 'class name derivation' do
    let(:default_flowchart) { create(:flowchart) }

    it 'converts flowchart name with spaces to PascalCase' do
      default_flowchart.update!(name: 'user registration flow')
      generator = described_class.new(default_flowchart.reload)
      code = generator.generate

      expect(code).to include('class UserRegistrationFlowActivity')
    end

    it 'handles names with special characters' do
      default_flowchart.update!(name: 'Test Flow 1')
      generator = described_class.new(default_flowchart.reload)
      code = generator.generate

      expect(code).to match(/class \w+Activity/)
    end

    it 'strips newlines from the flowchart name to prevent Ruby comment injection' do
      default_flowchart.update!(name: "Evil\n# injected")
      code = described_class.new(default_flowchart.reload).generate

      lines = code.lines.first(5).join
      expect(lines).not_to include("\n# injected")
      expect(lines).to include('# Generated from flowchart')
      expect(lines).to include("Evil")
    end

    it 'produces a valid Ruby class name even when the flowchart name starts with a digit' do
      default_flowchart.update!(name: "123 Start")
      code = described_class.new(default_flowchart.reload).generate

      class_line = code.lines.find { |l| l.include?("class ") }
      expect(class_line).to match(/class [A-Z]\w+Activity/)
      # The class literal must be parseable as a constant.
      expect(class_line).not_to match(/class \d/)
    end
  end

  describe 'method name derivation from element label' do
    let(:flowchart_with_labeled_steps) do
      create(:flowchart, configuration: {
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
            'label' => 'Validate User Input',
            'properties' => {
              'steps' => [{ 'action' => 'validate_contract', 'selectionLabels' => ['Validate', 'Contract'] }]
            }
          },
          {
            'id' => 'process_2',
            'type' => 'process',
            'x' => 100,
            'y' => 250,
            'width' => 100,
            'height' => 45,
            'label' => 'Save Entity Record',
            'properties' => {
              'steps' => [{ 'action' => 'save_model' }]
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
          { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'process_2' },
          { 'id' => 'conn_3', 'from' => 'process_2', 'to' => 'end_1' }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 },
          'created_at' => Time.current.iso8601
        }
      }.to_json)
    end

    it 'derives method name from element label instead of step action' do
      generator = described_class.new(flowchart_with_labeled_steps)
      code = generator.generate

      expect(code).to include('def validate_user_input')
      expect(code).to include('def save_entity_record')
    end

    it 'normalizes label to snake_case method name' do
      generator = described_class.new(flowchart_with_labeled_steps)
      code = generator.generate

      expect(code).to include('step :validate_user_input')
      expect(code).to include('step :save_entity_record')
    end

    context 'when element has no label' do
      let(:flowchart_without_label) do
        create(:flowchart, configuration: {
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
              'label' => '',
              'properties' => { 'steps' => [] }
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
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json)
      end

      it 'falls back to element type when label is empty' do
        generator = described_class.new(flowchart_without_label)
        code = generator.generate

        expect(code).to include('def process')
      end
    end

    context 'when multiple elements have the same label' do
      let(:flowchart_duplicate_labels) do
        create(:flowchart, configuration: {
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
              'label' => 'Validate Data',
              'properties' => { 'steps' => [] }
            },
            {
              'id' => 'process_2',
              'type' => 'process',
              'x' => 100,
              'y' => 250,
              'width' => 100,
              'height' => 45,
              'label' => 'Validate Data',
              'properties' => { 'steps' => [] }
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
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'process_2' },
            { 'id' => 'conn_3', 'from' => 'process_2', 'to' => 'end_1' }
          ],
          'metadata' => {
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json)
      end

      it 'ensures unique method names by appending suffix' do
        generator = described_class.new(flowchart_duplicate_labels)
        code = generator.generate

        expect(code).to include('def validate_data(ctx, **)')
        expect(code).to include('def validate_data_1(ctx, **)')
      end
    end

    context 'when a label pre-occupies a dedup-suffix slot' do
      # Labels ["Process Order", "Process Order 1", "Process Order"] normalize to
      # [process_order, process_order_1, process_order]. A naive dedup would emit
      # process_order_1 twice — duplicate def's at the class level.
      let(:flowchart_colliding_dedup) do
        create(:flowchart, configuration: {
          'elements' => [
            { 'id' => 's', 'type' => 'start', 'x' => 0, 'y' => 0, 'width' => 100, 'height' => 45, 'label' => 'Start', 'properties' => {} },
            { 'id' => 'p1', 'type' => 'process', 'x' => 0, 'y' => 100, 'width' => 100, 'height' => 45, 'label' => 'Process Order', 'properties' => { 'steps' => [] } },
            { 'id' => 'p2', 'type' => 'process', 'x' => 0, 'y' => 200, 'width' => 100, 'height' => 45, 'label' => 'Process Order 1', 'properties' => { 'steps' => [] } },
            { 'id' => 'p3', 'type' => 'process', 'x' => 0, 'y' => 300, 'width' => 100, 'height' => 45, 'label' => 'Process Order', 'properties' => { 'steps' => [] } },
            { 'id' => 'e', 'type' => 'end', 'x' => 0, 'y' => 400, 'width' => 100, 'height' => 45, 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 's', 'to' => 'p1' },
            { 'id' => 'c2', 'from' => 'p1', 'to' => 'p2' },
            { 'id' => 'c3', 'from' => 'p2', 'to' => 'p3' },
            { 'id' => 'c4', 'from' => 'p3', 'to' => 'e' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 }, 'created_at' => Time.current.iso8601 }
        }.to_json)
      end

      it 'does not emit duplicate def names when a sibling label pre-occupies the suffix slot' do
        generator = described_class.new(flowchart_colliding_dedup)
        code = generator.generate

        # Each def name must appear at most once at the class level.
        def_matches = code.scan(/^\s*def\s+(\w+)\(/).map(&:first)
        process_defs = def_matches.select { |n| n.start_with?("process_order") }
        expect(process_defs.uniq.size).to eq(process_defs.size),
          "Expected unique def names; got duplicates: #{process_defs.tally.select { |_, c| c > 1 }.inspect}"
      end
    end
  end

  describe 'blueprint flowchart (no entity bound)' do
    let(:blueprint_flowchart) do
      create(:flowchart, :shared_type, name: 'Blueprint Flow', configuration: {
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
            'label' => 'Create Record',
            'properties' => {
              'steps' => [{ 'action' => 'new_model' }]
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
          { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
          { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 },
          'created_at' => Time.current.iso8601
        }
      }.to_json)
    end

    it 'uses FlowchartRuntime::Entries.scope for dynamic model lookup' do
      generator = described_class.new(blueprint_flowchart)
      code = generator.generate

      expect(code).to include('FlowchartRuntime::Entries.scope(ctx)')
    end

    it 'includes shared flowchart annotation in header' do
      generator = described_class.new(blueprint_flowchart)
      code = generator.generate

      expect(code).to include('# Bound entity: supplied at runtime by the submitting page')
    end

    it 'generates proper code without TODO prefix for shared flowcharts' do
      generator = described_class.new(blueprint_flowchart)
      code = generator.generate

      expect(code).not_to include('# TODO: Bind an entity to use actual model/contract')
    end
  end

  describe 'step action code generation' do
    let(:flowchart_with_actions) do
      create(:flowchart, configuration: {
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
            'label' => 'Create Model',
            'properties' => {
              'steps' => [{ 'action' => 'new_model' }]
            }
          },
          {
            'id' => 'process_2',
            'type' => 'process',
            'x' => 100,
            'y' => 250,
            'width' => 100,
            'height' => 45,
            'label' => 'Build Contract',
            'properties' => {
              'steps' => [{ 'action' => 'build_contract' }]
            }
          },
          {
            'id' => 'process_3',
            'type' => 'process',
            'x' => 100,
            'y' => 350,
            'width' => 100,
            'height' => 45,
            'label' => 'Validate Input',
            'properties' => {
              'steps' => [{ 'action' => 'validate_contract' }]
            }
          },
          {
            'id' => 'process_4',
            'type' => 'process',
            'x' => 100,
            'y' => 450,
            'width' => 100,
            'height' => 45,
            'label' => 'Save Record',
            'properties' => {
              'steps' => [{ 'action' => 'save_model' }]
            }
          },
          {
            'id' => 'end_1',
            'type' => 'end',
            'x' => 100,
            'y' => 550,
            'width' => 100,
            'height' => 45,
            'label' => 'End',
            'properties' => {}
          }
        ],
        'connections' => [
          { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
          { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'process_2' },
          { 'id' => 'conn_3', 'from' => 'process_2', 'to' => 'process_3' },
          { 'id' => 'conn_4', 'from' => 'process_3', 'to' => 'process_4' },
          { 'id' => 'conn_5', 'from' => 'process_4', 'to' => 'end_1' }
        ],
        'metadata' => {
          'canvas' => { 'width' => 1200, 'height' => 800 },
          'created_at' => Time.current.iso8601
        }
      }.to_json)
    end

    it 'generates new_model using FlowchartRuntime::Entries.scope' do
      generator = described_class.new(flowchart_with_actions)
      code = generator.generate

      expect(code).to include('ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])')
    end

    it 'generates build_contract using EntityEntryContract.build_for' do
      generator = described_class.new(flowchart_with_actions)
      code = generator.generate

      expect(code).to match(
        /EntityEntryContract\.build_for\(\s*ctx\[:bound_entity\],\s*audience: ctx\[:audience\],\s*writable_slugs: ctx\[:writable_slugs\]\s*\)\n\s*ctx\[:contract\] = form\.new\(ctx\[:model\]\)/
      )
    end

    it 'generates validate_contract that validates ctx[:params]' do
      generator = described_class.new(flowchart_with_actions)
      code = generator.generate

      expect(code).to include('ctx[:contract].validate(ctx[:params] || {})')
    end

    it 'generates save_model that persists the contract' do
      generator = described_class.new(flowchart_with_actions)
      code = generator.generate

      expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
      expect(code).not_to include('ctx[:contract].sync')
    end

    it 'includes entity info in header' do
      generator = described_class.new(flowchart_with_actions)
      code = generator.generate

      expect(code).to include('# Bound entity:')
      expect(code).not_to include('# Model class:')
      expect(code).not_to include('# Contract class:')
    end
  end

  describe 'multi-source support' do
    let_it_be(:customer) { create(:customer) }

    let(:primary_entity) do
      create(:entity,
        name: 'Student',
        customer: customer,
        property_schema: [
          { 'name' => 'student_id', 'name_slug' => 'student_id', 'type' => 'String', 'validators' => [{ 'type' => 'presence' }] }
        ].to_json
      )
    end

    def build_process_element(id, label, action, y: 200)
      steps = action == "route_params" ? [] : [{ "action" => action }]
      {
        'id' => id,
        'type' => 'process',
        'x' => 100,
        'y' => y,
        'width' => 100,
        'height' => 45,
        'label' => label,
        'properties' => { 'steps' => steps }
      }
    end

    def build_flowchart_config(process_elements)
      start_el = {
        'id' => 'start_1', 'type' => 'start', 'x' => 100, 'y' => 50,
        'width' => 100, 'height' => 45, 'label' => 'Start', 'properties' => {}
      }
      end_el = {
        'id' => 'end_1', 'type' => 'end', 'x' => 100, 'y' => 900,
        'width' => 100, 'height' => 45, 'label' => 'End', 'properties' => {}
      }

      all_elements = [start_el] + process_elements + [end_el]
      connections = all_elements.each_cons(2).map.with_index do |(from, to), idx|
        { 'id' => "conn_#{idx}", 'from' => from['id'], 'to' => to['id'] }
      end

      {
        'elements' => all_elements,
        'connections' => connections,
        'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 }, 'created_at' => Time.current.iso8601 }
      }.to_json
    end

    context 'standard flow (no explicit route_params)' do
      let(:flowchart) do
        create(:flowchart, customer: customer, configuration: build_flowchart_config([
          build_process_element('p1', 'Create Student', 'new_model', y: 150),
          build_process_element('p2', 'Build Contract', 'build_contract', y: 250),
          build_process_element('p3', 'Validate', 'validate_contract', y: 350),
          build_process_element('p4', 'Save', 'save_model', y: 450)
        ]))
      end

      it 'generates canonical code for the standard CRUD flow' do
        code = described_class.new(flowchart).generate
        expect(code).to include('ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])')
        expect(code).to match(/EntityEntryContract\.build_for\(\s*ctx\[:bound_entity\],\s*audience: ctx\[:audience\],\s*writable_slugs: ctx\[:writable_slugs\]\s*\)\n\s*ctx\[:contract\] = form\.new\(ctx\[:model\]\)/)
        expect(code).to include('ctx[:contract].validate(ctx[:params] || {})')
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
      end
    end

    context 'multi-source flow with route_params' do
      let(:flowchart) do
        create(:flowchart, customer: customer, configuration: build_flowchart_config([
          build_process_element('p1', 'Route Params', 'route_params', y: 150),
          build_process_element('p2', 'Create Student', 'new_model', y: 250),
          build_process_element('p3', 'Build Contract', 'build_contract', y: 350),
          build_process_element('p4', 'Validate', 'validate_contract', y: 450),
          build_process_element('p5', 'Save', 'save_model', y: 550)
        ]))
      end

      it 'validates the contract against ctx[:params]' do
        code = described_class.new(flowchart).generate
        expect(code).to include('ctx[:contract].validate(ctx[:params] || {})')
      end

      it 'persists the contract in save_model' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
      end

      it 'does not include a Multi-source header annotation' do
        code = described_class.new(flowchart).generate
        expect(code).not_to include('Multi-source:')
      end
    end

    context 'find_model and destroy_model' do
      let(:flowchart) do
        create(:flowchart, customer: customer, configuration: build_flowchart_config([
          build_process_element('p1', 'Find Record', 'find_model', y: 150),
          build_process_element('p2', 'Destroy Record', 'destroy_model', y: 250)
        ]))
      end

      it 'generates find using FlowchartRuntime::Entries.find_by' do
        code = described_class.new(flowchart).generate
        expect(code).to match(/FlowchartRuntime::Entries\.find_by\(\s*ctx,\s*"id" => FlowchartRuntime::Step\.dig\(ctx\[:params\], :id\)\s*\)/)
        expect(code).not_to include('.find(ctx[:id])')
      end

      it 'generates destroy for primary model' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Entries.destroy(ctx, ctx[:model])')
      end
    end

    context 'full multi-source activity flow' do
      let(:flowchart) do
        create(:flowchart, customer: customer, configuration: build_flowchart_config([
          build_process_element('p1', 'Route Params', 'route_params', y: 150),
          build_process_element('p2', 'Create Student', 'new_model', y: 250),
          build_process_element('p3', 'Build Contract', 'build_contract', y: 350),
          build_process_element('p4', 'Validate', 'validate_contract', y: 450),
          build_process_element('p5', 'Save', 'save_model', y: 550)
        ]))
      end

      it 'generates valid Ruby class with correct step flow' do
        code = described_class.new(flowchart).generate
        expect(code).to include('class')
        expect(code).to include('Trailblazer::Activity::Railway')
        expect(code).to include('step :route_params')
        expect(code).to include('step :create_student')
        expect(code).to include('step :build_contract')
        expect(code).to include('step :validate')
        expect(code).to include('step :save')
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
      end
    end

    context 'shared flowchart multi-source' do
      let(:flowchart) do
        create(:flowchart, :shared_type, name: 'Shared CRUD', configuration: build_flowchart_config([
          build_process_element('p1', 'Route Params', 'route_params', y: 150),
          build_process_element('p2', 'Create Model', 'new_model', y: 250),
          build_process_element('p3', 'Build Contract', 'build_contract', y: 350),
          build_process_element('p4', 'Validate', 'validate_contract', y: 450),
          build_process_element('p5', 'Save', 'save_model', y: 550)
        ]))
      end

      it 'generates identical multi-source code as customer_specific' do
        code = described_class.new(flowchart).generate

        # Primary uses Entries.scope (same for both types)
        expect(code).to include('ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])')
        expect(code).to match(/EntityEntryContract\.build_for\(\s*ctx\[:bound_entity\],\s*audience: ctx\[:audience\],\s*writable_slugs: ctx\[:writable_slugs\]\s*\)\n\s*ctx\[:contract\] = form\.new\(ctx\[:model\]\)/)

        # Validate runs against ctx[:params]
        expect(code).to include('ctx[:contract].validate(ctx[:params] || {})')

        # Save persists the contract
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
      end

      it 'does not include TODO prefix' do
        code = described_class.new(flowchart).generate
        expect(code).not_to include('# TODO: Bind an entity')
      end

      it 'includes shared flowchart header' do
        code = described_class.new(flowchart).generate
        expect(code).to include('# Bound entity: supplied at runtime by the submitting page')
        expect(code).not_to include('Multi-source:')
      end
    end
  end

  describe "loop condition code generation" do
    let(:customer) { create(:customer) }

    context "with structured condition" do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Retry Loop", "properties" => {
                "condition" => LoopPhase4SpecHelpers.cond_group("ctx.retry_count", "<", "3"),
                "maxIterations" => 10
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop", "fromPosition" => "bottom", "toPosition" => "top" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end", "fromPosition" => "bottom", "toPosition" => "top" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Loop Test", customer: customer, configuration: config.to_json)
      end

      it "generates a loop condition check method" do
        code = flowchart.activity
        expect(code).to include("def retry_loop")
      end

      it "includes max iterations guard" do
        code = flowchart.activity
        expect(code).to include("_loop_iteration_count")
        expect(code).to include("10")
      end

      it "includes structured condition comparison" do
        code = flowchart.activity
        expect(code).to include("retry_count")
      end
    end

    context "with runOnceFirst while loop type" do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Do While Loop", "properties" => {
                "loopType" => "while",
                "runOnceFirst" => true,
                "condition" => LoopPhase4SpecHelpers.cond_group("ctx.status", "!=", "done"),
                "maxIterations" => 5
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop", "fromPosition" => "bottom", "toPosition" => "top" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end", "fromPosition" => "bottom", "toPosition" => "top" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Do While Test", customer: customer, configuration: config.to_json)
      end

      it "generates a do-while loop method" do
        code = flowchart.activity
        expect(code).to include("def do_while_loop")
      end

      it "includes max iterations guard" do
        code = flowchart.activity
        expect(code).to include("_loop_iteration_count")
        expect(code).to include("state[:count] >= 5")
        expect(code).to include("loop do")
        expect(code).not_to include("5.times")
      end

      it "checks the condition after the first iteration" do
        code = flowchart.activity
        namespace = Module.new
        namespace.module_eval(code)
        signal, (ctx, _) = namespace.const_get(:DoWhileTestActivity).call([{ status: "done" }, {}])
        expect(signal.to_h[:semantic]).to eq(:success)
        expect(ctx[:_loop_iteration_count]).to eq(1)
      end

      it "includes the condition check for subsequent iterations" do
        code = flowchart.activity
        expect(code).to include("status")
        expect(code).to include("done")
      end
    end

    context "with for_each loop type" do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Each Item", "properties" => {
                "loopType" => "for_each",
                "collection" => "items",
                "itemVariable" => "item",
                "indexVariable" => "idx",
                "maxIterations" => 50
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop", "fromPosition" => "bottom", "toPosition" => "top" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end", "fromPosition" => "bottom", "toPosition" => "top" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "For Each Test", customer: customer, configuration: config.to_json)
      end

      it "generates a for-each loop method" do
        code = flowchart.activity
        expect(code).to include("def each_item")
      end

      it "iterates over the collection" do
        code = flowchart.activity
        expect(code).to include("Array(ctx[:items])")
        expect(code).to include("while state[:index] < state[:items].size")
        expect(code).to include("item = state[:items][state[:index]]")
        expect(code).to include("idx = state[:index]")
        expect(code).not_to include("each_with_index")
      end

      it "sets item and index variables in context" do
        code = flowchart.activity
        expect(code).to include("ctx[:item] = item")
        expect(code).to include("ctx[:idx] = idx")
      end

      it "applies max iterations as a failing limit" do
        code = flowchart.activity
        expect(code).to include("fail_limit")
        expect(code).to include("max: 50")
        expect(code).not_to include(".take(")
      end

      it "handles non-array collections" do
        code = flowchart.activity
        expect(code).to include("Array(ctx[:items])")
      end
    end

    context "with for_each loop using default variables" do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Process Items", "properties" => {
                "loopType" => "for_each",
                "collection" => "users",
                "itemVariable" => "",
                "indexVariable" => "",
                "maxIterations" => 100
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Default Vars Test", customer: customer, configuration: config.to_json)
      end

      it "uses default item and index variable names" do
        code = flowchart.activity
        expect(code).to include("item = state[:items][state[:index]]")
        expect(code).to include("index = state[:index]")
        expect(code).to include("ctx[:item] = item")
        expect(code).to include("ctx[:index] = index")
        expect(code).not_to include("each_with_index")
      end
    end

    context "with while loop type (explicit)" do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "While Loop", "properties" => {
                "loopType" => "while",
                "condition" => LoopPhase4SpecHelpers.cond_group("ctx.count", "<", "10"),
                "maxIterations" => 20
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "While Explicit", customer: customer, configuration: config.to_json)
      end

      it "generates a while loop with guard and condition" do
        code = flowchart.activity
        expect(code).to include("state[:count] >= 20")
        expect(code).to include("ctx[:count]")
        expect(code).to include("loop do")
        expect(code).not_to include("20.times")
      end
    end

    context "with legacy string condition" do
      it "rejects a raw-Ruby string condition" do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_loop", "type" => "loop", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Old Loop", "properties" => {
                "loopType" => "while",
                "condition" => "while count < 10",
                "maxIterations" => 5
              } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_loop" },
            { "id" => "conn_2", "from" => "el_loop", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        record = Flowchart.new(name: "Legacy Loop", customer: customer, configuration: config.to_json)
        expect { described_class.new(record).generate }.to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:invalid_generator_config)
          expect(error.details.map(&:code)).to include(:invalid_conditions)
        }
      end
    end
  end

  describe 'subprocess generation for subflow elements' do
    let(:subflow_flowchart) do
      create(:flowchart, name: 'Validate User', customer: entity.customer)
    end

    let(:flowchart_with_subprocess) do
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

    it 'generates Subprocess declaration for subflow elements' do
      generator = described_class.new(flowchart_with_subprocess)
      code = generator.generate

      expect(code).to include('step Subprocess(ValidateUserActivity)')
      expect(code).not_to include('In()')
    end

    it 'includes subprocess in header comments' do
      generator = described_class.new(flowchart_with_subprocess)
      code = generator.generate

      expect(code).to include('# Subflows:')
      expect(code).to include('ValidateUserActivity')
    end

    it 'declares a wired Subprocess without a hand-written circuit method' do
      generator = described_class.new(flowchart_with_subprocess)
      code = generator.generate

      expect(code).to include('step Subprocess(ValidateUserActivity), id: :sub_flow_validate_user')
      expect(code).not_to include('def sub_flow_validate_user')
    end

    it 'generates regular step for process elements' do
      generator = described_class.new(flowchart_with_subprocess)
      code = generator.generate

      expect(code).to include('step :prepare_data')
      expect(code).to include('def prepare_data(ctx, **)')
    end

    describe "hostile subflow flowchartId" do
      def parent_for(flowchart_id)
        create(:flowchart, customer: entity.customer, name: "Parent Flow", configuration: {
          "elements" => [
            { "id" => "start_1", "type" => "start", "label" => "Start", "properties" => {} },
            { "id" => "sf", "type" => "subflow", "label" => "Child", "properties" => { "flowchartId" => flowchart_id } },
            { "id" => "end_1", "type" => "end", "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "c1", "from" => "start_1", "to" => "sf" },
            { "id" => "c2", "from" => "sf", "to" => "end_1" }
          ],
          "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
        }.to_json)
      end

      [
        ->(id) { "#{id}\nclass InjectedHeader; end\n#" },
        ->(id) { "#{id}\n\#{Kernel.exit}\n#" },
        ->(id) { "#{id}\n__END__\n#" },
        ->(id) { "#{id}\u2028class InjectedHeader; end\u2028#" },
        ->(id) { "#{id}\u2029class InjectedHeader; end\u2029#" }
      ].each do |payload_for|
        it "does not inject extra lines and still compiles for #{payload_for.call(14).inspect}" do
          payload = payload_for.call(subflow_flowchart.id)
          code = described_class.new(parent_for(payload)).generate
          expect(code).to be_present
          expect(code).not_to include("class InjectedHeader")
          expect(code).not_to include("__END__")
          expect(code).not_to include("Kernel.exit")
          expect(code).to include("# Subflows: ValidateUserActivity (##{subflow_flowchart.id} \"Validate User\")")
          expect(code.scan(/^class /).size).to eq(1)

          namespace = Module.new
          namespace.const_set("ValidateUserActivity", Class.new(Trailblazer::Activity::Railway))
          expect { namespace.module_eval(code) }.not_to raise_error
        end
      end
    end

    removed_structural_examples 'with variable mappings removed from the synchronous Subprocess contract' do
      let(:flowchart_with_var_mappings) do
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
                  { 'keyword' => 'user_id', 'value' => 'current_user_id' },
                  { 'keyword' => 'status', 'value' => 'user_status' },
                  { 'keyword' => 'role', 'value' => 'user_role' }
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
            'canvas' => { 'width' => 1200, 'height' => 800 },
            'created_at' => Time.current.iso8601
          }
        }.to_json)
      end

      it 'generates Subprocess with In() lambda' do
        generator = described_class.new(flowchart_with_var_mappings)
        code = generator.generate

        expect(code).to include('step Subprocess(ValidateUserActivity)')
        expect(code).to include('In() => ->(ctx, **) do')
      end

      it 'generates merge with new keys mapped from old keys' do
        generator = described_class.new(flowchart_with_var_mappings)
        code = generator.generate

        expect(code).to include('ctx.to_h.merge(')
        expect(code).to include('user_id: ctx[:current_user_id]')
        expect(code).to include('status: ctx[:user_status]')
        expect(code).to include('role: ctx[:user_role]')
      end

      it 'generates except with old keys to remove' do
        generator = described_class.new(flowchart_with_var_mappings)
        code = generator.generate

        expect(code).to include('.except(')
        expect(code).to include(':current_user_id')
        expect(code).to include(':user_status')
        expect(code).to include(':user_role')
      end
    end

    context 'without variable mappings' do
      it 'generates Subprocess with In() pass-through' do
        generator = described_class.new(flowchart_with_subprocess)
        code = generator.generate

        expect(code).to include('step Subprocess(ValidateUserActivity)')
        expect(code).not_to include('In()')
      end
    end

    context 'cross-tenant subflow references' do
      let(:other_customer)  { create(:customer) }
      let(:other_entity)    { create(:entity, customer: other_customer) }
      let(:foreign_subflow) { create(:flowchart, name: 'Foreign Flow', customer: other_customer) }

      let(:flowchart_referencing_foreign) do
        create(:flowchart, customer: entity.customer, configuration: {
          'elements' => [
            { 'id' => 's', 'type' => 'start', 'x' => 0, 'y' => 0, 'width' => 100, 'height' => 45, 'label' => 'Start', 'properties' => {} },
            { 'id' => 'sf', 'type' => 'subflow', 'x' => 0, 'y' => 100, 'width' => 100, 'height' => 45, 'label' => 'Foreign', 'properties' => { 'flowchartId' => foreign_subflow.id } },
            { 'id' => 'e', 'type' => 'end', 'x' => 0, 'y' => 200, 'width' => 100, 'height' => 45, 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 's', 'to' => 'sf' },
            { 'id' => 'c2', 'from' => 'sf', 'to' => 'e' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }.to_json)
      end

      it 'does not embed a Subprocess for a foreign customer\'s flowchart' do
        expect { described_class.new(flowchart_referencing_foreign).generate }
          .to raise_error(ActivityGenerator::Error) { |error|
            expect(error.code).to eq(:invalid_subflow_reference)
          }
      end
    end
  end

  removed_structural_examples 'join element handling (removed structural type)' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    context 'join element generates no-op method' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_join", "type" => "join", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Join Branches", "properties" => {} },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
              "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_join" },
            { "id" => "conn_2", "from" => "el_join", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Join Test", customer: customer, configuration: config.to_json)
      end

      it 'generates a step declaration for the join element' do
        code = described_class.new(flowchart).generate
        expect(code).to include('step :join_branches')
      end

      it 'generates a no-op method body (true) for the join element' do
        code = described_class.new(flowchart).generate
        expect(code).to include('def join_branches(ctx, **)')
        # Wait-all join records branch counter and returns `done` (which is
        # the literal `true` for wait_all strategy).
        expect(code).to match(/def join_branches\(ctx, \*\*\).*# Join: parallel paths joined.*done = true\s+done\s+end/m)
      end
    end
  end

  describe 'step retry/timeout/guard code generation' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    def build_step_flowchart(step_props)
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} },
          { "id" => "el_process", "type" => "process", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Process Step", "properties" => {
              "steps" => [step_props]
            } },
          { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
            "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "conn_1", "from" => "el_start", "to" => "el_process" },
          { "id" => "conn_2", "from" => "el_process", "to" => "el_end" }
        ],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: "Retry Guard Test", customer: customer, configuration: config.to_json)
    end

    context 'with leftover step-level wrapper keys' do
      let(:flowchart) do
        build_step_flowchart({
          "action" => "save_model",
          "retryCount" => 3,
          "retryBackoff" => "exponential",
          "timeout" => 30,
          "guardCondition" => 'ctx[:role] == "admin"'
        })
      end

      it 'emits the action body and ignores guard, retry, and timeout keys' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
        expect(code).not_to include('retry_count')
        expect(code).not_to include('Timeout.timeout')
        expect(code).not_to include('if ctx[:role] == "admin"')
        expect(code).not_to include('sleep')
      end
    end

    context 'with no advanced settings' do
      let(:flowchart) do
        build_step_flowchart({ "action" => "save_model" })
      end

      it 'generates plain step code without wrappers' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Entries.save(ctx, ctx[:contract])')
        expect(code).not_to include('retry_count')
        expect(code).not_to include('Timeout.timeout')
      end
    end
  end

  describe 'decision element condition evaluation' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    context 'with a structured condition' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Check Status", "properties" => {
                "routeBy" => "condition",
                "condition" => {
                  "type" => "group",
                  "joins" => [],
                  "conditions" => [
                    { "kind" => "field", "leftOperand" => "ctx.model.status", "operator" => "==", "rightOperand" => "active" }
                  ]
                }
              } },
            { "id" => "el_yes", "type" => "end", "x" => 300, "y" => 300, "width" => 100, "height" => 45,
              "label" => "Yes End", "properties" => { "responseType" => "none" } },
            { "id" => "el_no", "type" => "end", "x" => 500, "y" => 300, "width" => 100, "height" => 45,
              "label" => "No End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_yes", "matchValue" => "true" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_no", "matchValue" => "false" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Decision Test", customer: customer, configuration: config.to_json)
      end

      it 'generates a step (not pass) for decision elements' do
        code = described_class.new(flowchart).generate
        expect(code).to include('step :check_status')
        expect(code).not_to include('pass :check_status')
      end

      it 'evaluates the condition in the method body' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Step.dig(ctx[:model], :status) == "active"')
      end
    end

    context 'with a compound condition group' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Access Check", "properties" => {
                "routeBy" => "condition",
                "condition" => {
                  "type" => "group",
                  "joins" => ["AND"],
                  "conditions" => [
                    { "kind" => "field", "leftOperand" => "ctx.user.active", "operator" => "is_true", "rightOperand" => "" },
                    { "kind" => "field", "leftOperand" => "ctx.user.role", "operator" => "==", "rightOperand" => "admin" }
                  ]
                }
              } },
            { "id" => "el_yes", "type" => "end", "x" => 300, "y" => 300, "width" => 100, "height" => 45,
              "label" => "Yes End", "properties" => { "responseType" => "none" } },
            { "id" => "el_no", "type" => "end", "x" => 500, "y" => 300, "width" => 100, "height" => 45,
              "label" => "No End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_yes", "matchValue" => "true" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_no", "matchValue" => "false" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Compound Decision", customer: customer, configuration: config.to_json)
      end

      it 'generates compound condition with && operator' do
        code = described_class.new(flowchart).generate
        expect(code).to include('!!FlowchartRuntime::Step.dig(ctx[:user], :active)')
        expect(code).to include('FlowchartRuntime::Step.dig(ctx[:user], :role) == "admin"')
        expect(code).to include('&&')
      end
    end

    context 'with no condition configured' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Empty Decision", "properties" => {} },
            { "id" => "el_yes", "type" => "end", "x" => 300, "y" => 300, "width" => 100, "height" => 45,
              "label" => "Yes End", "properties" => { "responseType" => "none" } },
            { "id" => "el_no", "type" => "end", "x" => 500, "y" => 300, "width" => 100, "height" => 45,
              "label" => "No End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_yes", "matchValue" => "true" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_no", "matchValue" => "false" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        # Invalid decision config must not persist via before_save — build only.
        build(:flowchart, name: "No Condition Decision", customer: customer, configuration: config.to_json)
      end

      it 'rejects the incomplete decision before source emission' do
        expect { described_class.new(flowchart).generate }
          .to raise_error(ActivityGenerator::Error) { |error|
            expect(error.code).to eq(:invalid_generator_config)
            expect(error.details.map(&:to_s)).to include(a_string_matching(/condition is required/i))
          }
      end
    end

    context 'with a malformed nested matches_regex condition' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "label" => "Regex Decision", "properties" => {
              "routeBy" => "condition",
              "condition" => {
                "type" => "group",
                "joins" => [],
                "conditions" => [
                  {
                    "kind" => "field",
                    "leftOperand" => "ctx.code",
                    "operator" => "matches_regex",
                    "rightOperand" => "["
                  }
                ]
              }
            } },
            { "id" => "el_yes", "type" => "end", "label" => "Yes", "properties" => { "responseType" => "none" } },
            { "id" => "el_no", "type" => "end", "label" => "No", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_yes", "matchValue" => "true" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_no", "matchValue" => "false" }
          ],
          "metadata" => {}
        }
        build(:flowchart, name: "Invalid Regex Decision", customer: customer, configuration: config.to_json)
      end

      it 'raises a structured config error before Decision source generation' do
        expect_any_instance_of(CodeGenerators::ElementTypes::Decision::DecisionGenerator)
          .not_to receive(:generate_body)

        expect { described_class.new(flowchart).generate }
          .to raise_error(ActivityGenerator::Error) { |error|
            expect(error.code).to eq(:invalid_generator_config)
            expect(error.element_id).to eq("el_decision")
            expect(error.element_type).to eq("decision")
            expect(error.details.map(&:to_s)).to include(
              "Condition row 1 has an invalid pattern"
            )
          }
      end
    end

    context 'with a value-switch condition and match-valued connections' do
      # The Decision generator is a value-switch: it reads _connection_match_values
      # (not _connection_conditions) and emits a case/when block.
      # ActivityGenerator#build_method must inject _connection_match_values from
      # branch_info[:match_value] so the generator receives the right data.
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
              "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
              "label" => "Route By Status",
              "properties" => {
                "routeBy" => "value",
                "subject" => "ctx[:status]"
              } },
            { "id" => "el_approved", "type" => "process", "x" => 200, "y" => 350, "width" => 100, "height" => 45,
              "label" => "Approve Step", "properties" => { "steps" => [] } },
            { "id" => "el_rejected", "type" => "process", "x" => 600, "y" => 350, "width" => 100, "height" => 45,
              "label" => "Reject Step", "properties" => { "steps" => [] } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 500, "width" => 100, "height" => 45,
              "label" => "End", "properties" => { "responseType" => "none" } }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_approved",
              "label" => "Approved", "matchValue" => "approved" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_rejected",
              "label" => "Rejected", "matchValue" => "rejected" },
            { "id" => "conn_4", "from" => "el_approved", "to" => "el_end" },
            { "id" => "conn_5", "from" => "el_rejected", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Value Switch Decision", customer: customer, configuration: config.to_json)
      end

      it 'generates case/when routing for the value-switch decision' do
        source = described_class.new(flowchart).generate
        expect(source).to include("case").and include('when "approved"').and include('when "rejected"')
      end
    end
  end

  describe 'new step action code generation' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    def build_action_flowchart(action, name: "Action Test")
      config = {
        "elements" => [
          { "id" => "el_start", "type" => "start", "x" => 400, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} },
          { "id" => "el_process", "type" => "process", "x" => 400, "y" => 200, "width" => 100, "height" => 45,
            "label" => "Do Action", "properties" => {
              "steps" => [action]
            } },
          { "id" => "el_end", "type" => "end", "x" => 400, "y" => 300, "width" => 100, "height" => 45,
            "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "conn_1", "from" => "el_start", "to" => "el_process" },
          { "id" => "conn_2", "from" => "el_process", "to" => "el_end" }
        ],
        "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
      }
      create(:flowchart, name: name, customer: customer, configuration: config.to_json)
    end

    context 'hash_manipulate action' do
      let(:flowchart) do
        build_action_flowchart(
          {
            "action" => "hash_manipulate",
            "config" => {
              "sourceVariable" => "data",
              "operation" => "rename_keys",
              "renameMap" => [{ "key" => "old", "value" => "new" }]
            }
          },
          name: "Hash Manipulate Test"
        )
      end

      it 'generates hash manipulate code' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::HashOps')
        expect(code).to include('ctx[:data]')
      end

      context 'with description' do
        let(:flowchart) do
          build_action_flowchart(
            {
              "action" => "hash_manipulate",
              "description" => "normalize emails",
              "config" => { "sourceVariable" => "data", "operation" => "pick", "keys" => %w[email] }
            },
            name: "Hash Manipulate Desc Test"
          )
        end

        it 'still emits HashOps when a step description is present' do
          code = described_class.new(flowchart).generate
          expect(code).to include('FlowchartRuntime::HashOps')
          expect(code).to include('ctx[:data]')
        end
      end
    end

    context 'api_call action' do
      let(:flowchart) do
        build_action_flowchart(
          {
            "action" => "api_call",
            "config" => { "url" => "ctx[:api_url]", "resultVar" => "api_response" }
          },
          name: "API Call Test"
        )
      end

      it 'generates HTTP request code' do
        code = described_class.new(flowchart).generate
        expect(code).to include('ctx[:api_url]')
        expect(code).to include('FlowchartRuntime::Http.request')
        expect(code).to include('ctx[:api_response]')
      end
    end

    context 'create_notification action' do
      let(:flowchart) do
        build_action_flowchart(
          {
            "action" => "create_notification",
            "config" => {
              "title" => { "en" => "Notice" },
              "body" => { "en" => "Sent" }
            }
          },
          name: "Notify Test"
        )
      end

      it 'generates notification code' do
        code = described_class.new(flowchart).generate
        expect(code).to include('FlowchartRuntime::Notifications.create')
      end
    end

    context 'render_response action' do
      let(:flowchart) { build_action_flowchart({ "action" => "render_response" }, name: "Render Test") }

      it 'is no longer a registered step action' do
        expect { described_class.new(flowchart).generate }
          .to raise_error(ActivityGenerator::Error) { |error|
            expect(error.code).to eq(:unknown_step_action)
          }
      end
    end

    context 'unknown step action' do
      let(:flowchart) do
        build_action_flowchart({ "action" => "this_action_does_not_exist" }, name: "Unknown Action Test")
      end

      it 'raises a structured generation error' do
        expect { described_class.new(flowchart).generate }
          .to raise_error(ActivityGenerator::Error) { |error|
            expect(error.code).to eq(:unknown_step_action)
          }
      end
    end
  end

  describe 'structural validation' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    it 'rejects unreachable-from-Start elements' do
      # A -> B -> C and Start -> End. B has an incoming (A) so the prior
      # in-degree check passed, but none of A/B/C is reachable from Start.
      flowchart = build(:flowchart, customer: customer, configuration: {
        "elements" => [
          { "id" => "s",  "type" => "start", "x" => 0, "y" => 0,   "width" => 100, "height" => 45, "label" => "Start",  "properties" => {} },
          { "id" => "e",  "type" => "end",   "x" => 0, "y" => 400, "width" => 100, "height" => 45, "label" => "End",    "properties" => {} },
          { "id" => "a",  "type" => "process", "x" => 500, "y" => 100, "width" => 100, "height" => 45, "label" => "A",  "properties" => { "steps" => [] } },
          { "id" => "b",  "type" => "process", "x" => 500, "y" => 200, "width" => 100, "height" => 45, "label" => "B",  "properties" => { "steps" => [] } },
          { "id" => "c",  "type" => "process", "x" => 500, "y" => 300, "width" => 100, "height" => 45, "label" => "C",  "properties" => { "steps" => [] } }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s", "to" => "e" },
          { "id" => "c2", "from" => "a", "to" => "b" },
          { "id" => "c3", "from" => "b", "to" => "c" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }.to_json)

      # Before the fix, ActivityGenerator#generate returned the activity
      # silently dropping A/B/C. After the fix, validate_structure fails so
      # `generate` returns nil.
      expect(described_class.new(flowchart).generate).to be_nil
    end
  end

  describe '#structure_errors' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    it 'returns the structural validation messages without raising' do
      # Start -> process, no End element.
      flowchart = build(:flowchart, customer: customer, configuration: {
        "elements" => [
          { "id" => "s", "type" => "start", "x" => 0, "y" => 0, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} },
          { "id" => "p", "type" => "process", "x" => 0, "y" => 100, "width" => 100, "height" => 45,
            "label" => "Work", "properties" => { "steps" => [] } }
        ],
        "connections" => [{ "id" => "c1", "from" => "s", "to" => "p" }],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }.to_json)
      generator = described_class.new(flowchart)

      errors = generator.structure_errors

      expect(errors).to include("Missing End element")
    end

    it 'does not mutate state: repeated calls agree and #generate still works afterwards' do
      flowchart = create(:flowchart, customer: customer)
      generator = described_class.new(flowchart)

      first = generator.structure_errors
      second = generator.structure_errors

      expect(first).to eq([])
      expect(second).to eq(first)
      expect(generator.generate).to be_present
    end

    it 'reports the same messages on every call for an invalid structure' do
      flowchart = build(:flowchart, customer: customer, configuration: {
        "elements" => [
          { "id" => "s", "type" => "start", "x" => 0, "y" => 0, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} }
        ],
        "connections" => [],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }.to_json)
      generator = described_class.new(flowchart)

      errors = generator.structure_errors
      expect(generator.structure_errors).to eq(errors) # idempotent across calls
      expect(errors).to include("Missing End element")
      expect(generator.generate).to be_nil
    end
  end

  describe 'unknown element type handling' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    it 'raises instead of silently emitting a no-op body' do
      flowchart = build(:flowchart, configuration: {
        "elements" => [
          { "id" => "s", "type" => "start", "x" => 0, "y" => 0, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} },
          { "id" => "mystery", "type" => "totally_unknown_type", "x" => 0, "y" => 100,
            "width" => 100, "height" => 45, "label" => "Mystery", "properties" => {} },
          { "id" => "e", "type" => "end", "x" => 0, "y" => 200, "width" => 100, "height" => 45,
            "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s", "to" => "mystery" },
          { "id" => "c2", "from" => "mystery", "to" => "e" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }.to_json)

      expect { described_class.new(flowchart).generate }
        .to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:unknown_element_type)
        }
    end

    it "raises for persisted 'error_handler' nodes (deleted element type)" do
      flowchart = build(:flowchart, configuration: {
        "elements" => [
          { "id" => "s", "type" => "start", "x" => 0, "y" => 0, "width" => 100, "height" => 45,
            "label" => "Start", "properties" => {} },
          { "id" => "eh", "type" => "error_handler", "x" => 0, "y" => 100,
            "width" => 100, "height" => 45, "label" => "Legacy Handler", "properties" => {} },
          { "id" => "e", "type" => "end", "x" => 0, "y" => 200, "width" => 100, "height" => 45,
            "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s", "to" => "eh" },
          { "id" => "c2", "from" => "eh", "to" => "e" }
        ],
        "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
      }.to_json)

      expect { described_class.new(flowchart).generate }
        .to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:unknown_element_type)
        }
    end
  end

  removed_structural_examples 'join element and compound guard code generation (removed structural type)' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    # Flowchart topology:
    #   start -> decision -> branch_0_process -> join (mergedBranches: [branch_0, branch_1])
    #                     -> branch_1_process -> join
    #                     join -> post_join_process -> end
    #
    # With 2 out of 2 branches joined, the post-join step should have NO guard.
    context 'with a join element that covers all branches (no guard on downstream)' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 50,
              "width" => 100, "height" => 45, "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 150,
              "width" => 100, "height" => 45, "label" => "Check Flag",
              "properties" => {
                "condition" => { "leftOperand" => "ctx.flag", "operator" => "==", "rightOperand" => "true" }
              } },
            { "id" => "el_branch0", "type" => "process", "x" => 200, "y" => 250,
              "width" => 100, "height" => 45, "label" => "Branch Zero Step",
              "properties" => { "steps" => [] } },
            { "id" => "el_branch1", "type" => "process", "x" => 600, "y" => 250,
              "width" => 100, "height" => 45, "label" => "Branch One Step",
              "properties" => { "steps" => [] } },
            { "id" => "el_join", "type" => "join", "x" => 400, "y" => 350,
              "width" => 100, "height" => 45, "label" => "Join Branches",
              "properties" => {
                "sourceDecisionId" => "el_decision",
                "joinedBranches" => ["branch_0", "branch_1"]
              } },
            { "id" => "el_post", "type" => "process", "x" => 400, "y" => 450,
              "width" => 100, "height" => 45, "label" => "Post Join Step",
              "properties" => { "steps" => [] } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 550,
              "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_branch0" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_branch1" },
            { "id" => "conn_4", "from" => "el_branch0", "to" => "el_join" },
            { "id" => "conn_5", "from" => "el_branch1", "to" => "el_join" },
            { "id" => "conn_6", "from" => "el_join", "to" => "el_post" },
            { "id" => "conn_7", "from" => "el_post", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "All Branches Joined", customer: customer, configuration: config.to_json)
      end

      it 'generates a no-op method body (true) for the join element' do
        code = described_class.new(flowchart).generate
        expect(code).to include('def join_branches(ctx, **)')
        expect(code).to match(/def join_branches\(ctx, \*\*\).*# Join: parallel paths joined.*done = true\s+done\s+end/m)
      end

      it 'generates a step declaration for the join element' do
        code = described_class.new(flowchart).generate
        expect(code).to include('step :join_branches')
      end

      it 'generates no guard for the post-join step when all branches are joined' do
        code = described_class.new(flowchart).generate
        expect(code).to include('def post_join_step(ctx, **)')
        # When all branches are joined, no guard should be emitted.
        # Extract just the post_join_step method body and verify it has no guard.
        post_join_method = code[/# Post Join Step\n  def post_join_step.*?\n  end/m]
        expect(post_join_method).to be_present
        expect(post_join_method).not_to include('return true unless')
      end
    end

    # Flowchart topology (3-branch switch — 2 branches joined, 1 unjoined):
    #   start -> switch -> branch_0_step
    #                   -> branch_1_step -> join (mergedBranches: [branch_0, branch_1])
    #                   -> branch_2_step (unjoined, separate path)
    #                   join -> downstream_step -> end
    #
    # 2 out of 3 branches joined => compound guard [:branch_0, :branch_1].include?(ctx[:_route_0])
    context 'with a join element that covers a subset of branches (compound guard on downstream)' do
      let(:flowchart) do
        config = {
          "elements" => [
            { "id" => "el_start", "type" => "start", "x" => 400, "y" => 50,
              "width" => 100, "height" => 45, "label" => "Start", "properties" => {} },
            { "id" => "el_decision", "type" => "decision", "x" => 400, "y" => 150,
              "width" => 100, "height" => 45, "label" => "Route Traffic",
              "properties" => {
                "condition" => { "leftOperand" => "ctx.route", "operator" => "==", "rightOperand" => "fast" }
              } },
            { "id" => "el_branch0", "type" => "process", "x" => 100, "y" => 250,
              "width" => 100, "height" => 45, "label" => "Fast Path",
              "properties" => { "steps" => [] } },
            { "id" => "el_branch1", "type" => "process", "x" => 400, "y" => 250,
              "width" => 100, "height" => 45, "label" => "Medium Path",
              "properties" => { "steps" => [] } },
            { "id" => "el_branch2", "type" => "process", "x" => 700, "y" => 250,
              "width" => 100, "height" => 45, "label" => "Slow Path",
              "properties" => { "steps" => [] } },
            # Join branch_0 and branch_1 — compound join (2 of 3)
            { "id" => "el_join", "type" => "join", "x" => 250, "y" => 350,
              "width" => 100, "height" => 45, "label" => "Fast Medium Join",
              "properties" => {
                "sourceDecisionId" => "el_decision",
                "joinedBranches" => ["branch_0", "branch_1"]
              } },
            { "id" => "el_downstream", "type" => "process", "x" => 250, "y" => 450,
              "width" => 100, "height" => 45, "label" => "Downstream Step",
              "properties" => { "steps" => [] } },
            { "id" => "el_end", "type" => "end", "x" => 400, "y" => 550,
              "width" => 100, "height" => 45, "label" => "End", "properties" => {} }
          ],
          "connections" => [
            { "id" => "conn_1", "from" => "el_start", "to" => "el_decision" },
            { "id" => "conn_2", "from" => "el_decision", "to" => "el_branch0" },
            { "id" => "conn_3", "from" => "el_decision", "to" => "el_branch1" },
            { "id" => "conn_4", "from" => "el_decision", "to" => "el_branch2" },
            { "id" => "conn_5", "from" => "el_branch0", "to" => "el_join" },
            { "id" => "conn_6", "from" => "el_branch1", "to" => "el_join" },
            { "id" => "conn_7", "from" => "el_join", "to" => "el_downstream" },
            { "id" => "conn_8", "from" => "el_downstream", "to" => "el_end" },
            { "id" => "conn_9", "from" => "el_branch2", "to" => "el_end" }
          ],
          "metadata" => { "canvas" => { "width" => 2000, "height" => 1500 } }
        }
        create(:flowchart, name: "Partial Branch Join", customer: customer, configuration: config.to_json)
      end

      it 'generates a no-op method body (true) for the join element' do
        code = described_class.new(flowchart).generate
        expect(code).to include('def fast_medium_join(ctx, **)')
        # The join element itself may have a compound guard but the body is always just true
        join_method = code[/# Fast Medium Join\n  def fast_medium_join.*?\n  end/m]
        expect(join_method).to be_present
        expect(join_method).to include('true')
      end

      it 'generates a compound guard with .include? for the downstream step' do
        code = described_class.new(flowchart).generate
        expect(code).to include('def downstream_step(ctx, **)')
        downstream_method = code[/# Downstream Step\n  def downstream_step.*?\n  end/m]
        expect(downstream_method).to be_present
        expect(downstream_method).to include('.include?(ctx[:_route_0])')
      end

      it 'uses the correct branch list in the compound guard' do
        code = described_class.new(flowchart).generate
        downstream_method = code[/# Downstream Step\n  def downstream_step.*?\n  end/m]
        expect(downstream_method).to include('[:branch_0, :branch_1].include?(ctx[:_route_0])')
      end
    end
  end

  describe 'config-aware code generation (integration)' do
    let(:customer) { create(:customer) }
    let(:entity) { create(:entity, customer: customer) }

    context 'with configured step actions' do
      let(:configured_flowchart) do
        create(:flowchart, configuration: {
          'elements' => [
            {
              'id' => 'start_1', 'type' => 'start', 'x' => 100, 'y' => 50,
              'width' => 100, 'height' => 45, 'label' => 'Start',
              'properties' => { 'inputs' => [], 'outputs' => [] }
            },
            {
              'id' => 'process_1', 'type' => 'process', 'x' => 100, 'y' => 150,
              'width' => 100, 'height' => 45, 'label' => 'Make API Call',
              'properties' => {
                'steps' => [{
                  'action' => 'api_call',
                  'config' => {
                    'httpMethod' => 'POST',
                    'url' => '"https://api.example.com/users"',
                    'authType' => 'bearer',
                    'authToken' => 'ctx[:token]',
                    'resultVar' => 'api_response'
                  },
                  'description' => 'Call user API'
                }],
                'inputs' => [], 'outputs' => []
              }
            },
            {
              'id' => 'end_1', 'type' => 'end', 'x' => 100, 'y' => 250,
              'width' => 100, 'height' => 45, 'label' => 'End',
              'properties' => {}
            }
          ],
          'connections' => [
            { 'id' => 'conn_1', 'from' => 'start_1', 'to' => 'process_1' },
            { 'id' => 'conn_2', 'from' => 'process_1', 'to' => 'end_1' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }.to_json)
      end

      it 'generates config-parameterized API call code' do
        code = described_class.new(configured_flowchart).generate
        expect(code).to be_present
        expect(code).to include('FlowchartRuntime::Http.request')
        expect(code).to include(':post')
        expect(code).to include('ctx[:api_response]')
        expect(code).to include('Bearer')
        expect(code).to include('https://api.example.com/users')
      end

      it 'generates code with find_model config' do
        find_flowchart = create(:flowchart, configuration: {
          'elements' => [
            { 'id' => 's', 'type' => 'start', 'x' => 0, 'y' => 0, 'width' => 100, 'height' => 45, 'label' => 'Start', 'properties' => { 'inputs' => [], 'outputs' => [] } },
            { 'id' => 'p', 'type' => 'process', 'x' => 0, 'y' => 100, 'width' => 100, 'height' => 45, 'label' => 'Find User',
              'properties' => { 'steps' => [{ 'action' => 'find_model', 'config' => { 'findBy' => 'attribute', 'findField' => 'email', 'findValue' => 'email', 'resultVar' => 'user' } }], 'inputs' => [], 'outputs' => [] }
            },
            { 'id' => 'e', 'type' => 'end', 'x' => 0, 'y' => 200, 'width' => 100, 'height' => 45, 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 's', 'to' => 'p' },
            { 'id' => 'c2', 'from' => 'p', 'to' => 'e' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }.to_json)

        code = described_class.new(find_flowchart).generate
        expect(code).to include('FlowchartRuntime::Entries.find_by(ctx, "email" => ctx[:email])')
        expect(code).to include('ctx[:user]')
        expect(code).to include('FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :findValue)')
        expect(code).not_to include('find_by!(email:')
      end

      it 'handles new action types' do
        log_flowchart = create(:flowchart, configuration: {
          'elements' => [
            { 'id' => 's', 'type' => 'start', 'x' => 0, 'y' => 0, 'width' => 100, 'height' => 45, 'label' => 'Start', 'properties' => { 'inputs' => [], 'outputs' => [] } },
            { 'id' => 'p', 'type' => 'process', 'x' => 0, 'y' => 100, 'width' => 100, 'height' => 45, 'label' => 'Log Event',
              'properties' => { 'steps' => [{ 'action' => 'log', 'config' => { 'logLevel' => 'warn', 'messageTemplate' => 'Something happened', 'logger' => 'rails' } }], 'inputs' => [], 'outputs' => [] }
            },
            { 'id' => 'e', 'type' => 'end', 'x' => 0, 'y' => 200, 'width' => 100, 'height' => 45, 'label' => 'End', 'properties' => {} }
          ],
          'connections' => [
            { 'id' => 'c1', 'from' => 's', 'to' => 'p' },
            { 'id' => 'c2', 'from' => 'p', 'to' => 'e' }
          ],
          'metadata' => { 'canvas' => { 'width' => 1200, 'height' => 800 } }
        }.to_json)

        code = described_class.new(log_flowchart).generate
        expect(code).to include('FlowchartRuntime::Log.write')
        expect(code).to include('Something happened')
      end
    end
  end
end

RSpec.describe ActivityGenerator, "element-level I/O collision handling" do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  def build_flowchart_config(elements, connections)
    {
      "elements"    => elements,
      "connections" => connections,
      "metadata"    => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
  end

  def flowchart_with(elements:, connections:)
    build(:flowchart, customer: customer, configuration: build_flowchart_config(elements, connections))
  end

  it "rejects still-unsupported structural elements before collision rewriting" do
    start_el = { "id" => "s", "type" => "start", "x" => 100, "y" => 50,
                 "width" => 100, "height" => 45, "label" => "Start",
                 "properties" => {} }
    fork_el  = { "id" => "a", "type" => "fork", "x" => 100, "y" => 150,
                 "width" => 100, "height" => 45, "label" => "A",
                 "properties" => {} }
    end_el   = { "id" => "e", "type" => "end", "x" => 100, "y" => 350,
                 "width" => 100, "height" => 45, "label" => "End",
                 "properties" => {} }

    flow = flowchart_with(
      elements:    [start_el, fork_el, end_el],
      connections: [
        { "id" => "c1", "from" => "s", "to" => "a" },
        { "id" => "c2", "from" => "a", "to" => "e" }
      ]
    )

    expect { described_class.new(flow).generate }
      .to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:unsupported_structural_element)
      }
  end

  it "does not emit an isolateCtx snapshot wrapper even when the property is present" do
    start_el = { "id" => "s", "type" => "start", "x" => 100, "y" => 50,
                 "width" => 100, "height" => 45, "label" => "Start",
                 "properties" => {} }
    process  = { "id" => "p", "type" => "process", "x" => 100, "y" => 150,
                 "width" => 100, "height" => 45, "label" => "P",
                 "properties" => { "isolateCtx" => "true", "steps" => [] } }
    end_el   = { "id" => "e", "type" => "end", "x" => 100, "y" => 250,
                 "width" => 100, "height" => 45, "label" => "End",
                 "properties" => {} }
    flow = flowchart_with(
      elements:    [start_el, process, end_el],
      connections: [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]
    )
    out = described_class.new(flow).generate
    expect(out).not_to include("_original_ctx = ctx")
    expect(out).not_to include("_original_ctx.replace(ctx)")
  end
end
