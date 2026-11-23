# frozen_string_literal: true

require "rails_helper"

RSpec.describe "flowchart structure prompt few-shot examples" do
  let(:examples) do
    Rails.root.join("app/services/flowchart_definitions/structure_schema.prompt.txt").read
         .lines.select { |line| line.start_with?('{"intent"') }.map { |line| JSON.parse(line) }
  end

  it "never builds a second record in a page-bound flowchart" do
    flowcharts = examples.filter_map { |example| example["flowchart"] }
    expect(flowcharts).not_to be_empty

    flowcharts.each do |flowchart|
      actions = flowchart["elements"].flat_map { |element| Array(element["steps"]).map { |step| step["action"] } }
      expect(actions).not_to include("new_model"), flowchart["name"]
    end
  end
end
