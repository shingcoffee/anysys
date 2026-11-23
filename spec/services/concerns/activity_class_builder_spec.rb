# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityClassBuilder do
  let(:test_class) do
    Class.new do
      include ActivityClassBuilder
    end
  end

  let(:instance) { test_class.new }

  describe '#build_activity_class' do
    context 'with valid activity code' do
      let(:valid_code) do
        <<~RUBY
          class TestActivity < Trailblazer::Activity::Railway
            step :validate

            def validate(ctx, **)
              true
            end
          end
        RUBY
      end

      it 'returns the Activity class' do
        result = instance.build_activity_class(valid_code)
        expect(result).to be_a(Class)
        expect(result < Trailblazer::Activity::Railway).to be true
      end
    end

    context 'with blank code' do
      it 'returns nil for nil' do
        expect(instance.build_activity_class(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(instance.build_activity_class('')).to be_nil
      end
    end

    context 'with invalid code' do
      it 'returns nil for syntax errors' do
        invalid_code = 'class Broken < def end'
        expect(instance.build_activity_class(invalid_code)).to be_nil
      end

      it 'returns nil for code without Activity class' do
        no_activity = 'class RegularClass; end'
        expect(instance.build_activity_class(no_activity)).to be_nil
      end
    end
  end

  describe '#derive_node_label' do
    it 'returns "Start" for Start.default' do
      expect(instance.derive_node_label('Start.default')).to eq('Start')
    end

    it 'capitalizes End semantic' do
      expect(instance.derive_node_label('End.success')).to eq('Success')
      expect(instance.derive_node_label('End.failure')).to eq('Failure')
    end

    it 'converts snake_case to Title Case' do
      expect(instance.derive_node_label('validate_input')).to eq('Validate Input')
      expect(instance.derive_node_label('save_to_database')).to eq('Save To Database')
    end

    it 'handles single words' do
      expect(instance.derive_node_label('process')).to eq('Process')
    end

    it 'translates generated helper nodes instead of titleizing the id' do
      expect(instance.derive_node_label('collect_errors')).to eq(I18n.t("flowchart_elements.trace.collect_errors"))
      I18n.with_locale(:"zh-CN") do
        expect(instance.derive_node_label('collect_errors')).to eq(
          I18n.t("flowchart_elements.trace.collect_errors")
        )
        expect(instance.derive_node_label('collect_errors')).not_to eq("Collect Errors")
      end
    end
  end

  describe "subflow loading" do
    let(:customer) { create(:customer) }
    let(:child) { create(:flowchart, :simple, customer: customer) }
    let(:parent) do
      subflow = ->(id) { { "id" => id, "type" => "subflow", "properties" => { "flowchartId" => child.id } } }
      build(:flowchart, customer: customer, configuration: {
        "elements" => [subflow.call("sub_a"), subflow.call("sub_b")], "connections" => [], "metadata" => {}
      }.to_json)
    end
    let(:parent_code) { "class TwoRefParentActivity < Trailblazer::Activity::Railway; end" }

    it "evaluates a child referenced by two subflow elements only once" do
      expect(child.activity).to be_present

      expect {
        expect(instance.build_activity_class(parent_code, flowchart: parent)).to be_a(Class)
      }.not_to output(/already initialized constant/).to_stderr
    end
  end

  describe "runtime-only child lookup" do
    let(:customer) { create(:customer) }
    let(:child) { create(:flowchart, :simple, :launched_status, customer: customer) }
    let(:runtime_parent) do
      record = build(:flowchart, customer: customer, configuration: {
        "elements" => [{ "type" => "subflow", "properties" => { "flowchartId" => child.id } }],
        "connections" => [], "metadata" => {}
      }.to_json)
      FlowchartRuntime::RuntimeFlowchart.new(record, preview: true)
    end
    let(:parent_code) { "class RuntimeParentActivity < Trailblazer::Activity::Railway; end" }

    it "rejects foreign-tenant children" do
      Current.set(customer: create(:customer)) do
        expect(instance.build_activity_class(parent_code, flowchart: runtime_parent)).to be_nil
      end
    end

    it "rejects draft children even when accessible" do
      child.update!(status: :draft)
      Current.set(customer: customer) do
        expect(instance.build_activity_class(parent_code, flowchart: runtime_parent)).to be_nil
      end
    end

    it "loads accessible launched children" do
      Current.set(customer: customer) do
        expect(instance.build_activity_class(parent_code, flowchart: runtime_parent)).to be_a(Class)
      end
    end
  end
end
