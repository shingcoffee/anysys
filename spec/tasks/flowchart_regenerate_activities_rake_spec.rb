# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "flowcharts:regenerate_activities" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/flowchart_regenerate_activities",
      [Rails.root.join("lib").to_s],
      []
    )
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
  end

  let(:task) { Rake::Task["flowcharts:regenerate_activities"] }

  before do
    task.reenable
  end

  def invoke_task
    original = $stdout
    buffer = StringIO.new
    $stdout = buffer
    begin
      task.invoke
    ensure
      @last_task_output = buffer.string
      $stdout = original
    end
    @last_task_output
  end

  def last_task_output
    @last_task_output
  end

  def simple_configuration
    {
      "elements" => [
        {
          "id" => "start_1",
          "type" => "start",
          "x" => 150,
          "y" => 100,
          "width" => 100,
          "height" => 45,
          "label" => "Begin",
          "properties" => { "inputs" => [], "outputs" => [] }
        },
        {
          "id" => "process_1",
          "type" => "process",
          "x" => 150,
          "y" => 200,
          "width" => 100,
          "height" => 45,
          "label" => "Process",
          "properties" => { "steps" => [], "inputs" => [], "outputs" => [] }
        },
        {
          "id" => "end_1",
          "type" => "end",
          "x" => 150,
          "y" => 300,
          "width" => 100,
          "height" => 45,
          "label" => "End",
          "properties" => {}
        }
      ],
      "connections" => [
        { "id" => "conn_1", "from" => "start_1", "to" => "process_1" },
        { "id" => "conn_2", "from" => "process_1", "to" => "end_1" }
      ],
      "metadata" => {
        "canvas" => { "width" => 1200, "height" => 800 }
      }
    }.to_json
  end

  def unsupported_configuration
    {
      "elements" => [
        {
          "id" => "start_1",
          "type" => "start",
          "label" => "Begin",
          "properties" => { "inputs" => [], "outputs" => [] }
        },
        {
          "id" => "fork_1",
          "type" => "fork",
          "label" => "Fork",
          "properties" => {}
        },
        {
          "id" => "end_1",
          "type" => "end",
          "label" => "End",
          "properties" => {}
        }
      ],
      "connections" => [
        { "id" => "conn_1", "from" => "start_1", "to" => "fork_1" },
        { "id" => "conn_2", "from" => "fork_1", "to" => "end_1" }
      ],
      "metadata" => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
  end

  it "generates but does not persist when DRY_RUN=1" do
    flowchart = create(:flowchart, :simple, configuration: simple_configuration)
    flowchart.update_column(:activity, "OLD_ACTIVITY")

    ClimateControl.modify(DRY_RUN: "1", CUSTOMER_ID: flowchart.customer_id.to_s) do
      output = invoke_task

      expect(flowchart.reload.activity).to eq("OLD_ACTIVITY")
      expect(output).to include("dry_run=1")
      expect(output).to include("summary total=1 succeeded=1 failed=0")
      expect(output).not_to match(/Trailblazer|frozen_string_literal|class \w+Activity/)
    end
  end

  it "scopes regeneration to CUSTOMER_ID" do
    customer_a = create(:customer)
    customer_b = create(:customer)
    flowchart_a = create(
      :flowchart,
      :simple,
      customer: customer_a,
      configuration: simple_configuration
    )
    flowchart_b = create(
      :flowchart,
      :simple,
      customer: customer_b,
      configuration: simple_configuration
    )
    flowchart_a.update_column(:activity, "KEEP_A")
    flowchart_b.update_column(:activity, "KEEP_B")

    ClimateControl.modify(CUSTOMER_ID: customer_a.id.to_s) do
      output = invoke_task

      expect(flowchart_a.reload.activity).not_to eq("KEEP_A")
      expect(flowchart_a.activity).to include("Trailblazer")
      expect(flowchart_b.reload.activity).to eq("KEEP_B")
      expect(output).to include("customer_id=#{customer_a.id}")
      expect(output).to include("summary total=1 succeeded=1 failed=0")
      expect(output).not_to include(flowchart_a.activity)
    end
  end

  it "reports one invalid flowchart, continues others, and exits non-zero" do
    customer = create(:customer)
    entity = create(:entity, customer: customer)
    good = create(
      :flowchart,
      :simple,
      customer: customer,
      configuration: simple_configuration
    )
    bad = create(
      :flowchart,
      :simple,
      customer: customer,
      configuration: simple_configuration
    )
    good.update_column(:activity, "OLD_GOOD")
    bad.update_column(:activity, "OLD_BAD")

    allow(ActivityGenerator).to receive(:new).and_wrap_original do |method, flowchart|
      generator = method.call(flowchart)
      if flowchart.id == bad.id
        allow(generator).to receive(:generate).and_raise(
          ActivityGenerator::Error.new(code: :invalid_generator_config, message: "boom for #{flowchart.id}")
        )
      end
      generator
    end

    ClimateControl.modify(CUSTOMER_ID: customer.id.to_s) do
      expect {
        invoke_task
      }.to raise_error(SystemExit, /1 flowcharts failed regeneration/) { |error|
        expect(error.status).not_to eq(0)
      }

      expect(good.reload.activity).not_to eq("OLD_GOOD")
      expect(bad.reload.activity).to eq("OLD_BAD")
      expect(last_task_output).to include("fail flowchart_id=#{bad.id}")
      expect(last_task_output).to include("boom for #{bad.id}")
      expect(last_task_output).to include("summary total=2 succeeded=1 failed=1")
      expect(last_task_output).not_to match(/frozen_string_literal|class \w+Activity/)
    end
  end
end
