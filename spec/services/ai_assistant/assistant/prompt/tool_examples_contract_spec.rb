# frozen_string_literal: true

require "rails_helper"

RSpec.describe "assistant prompt tool examples stay on the operations contract" do
  let_it_be(:customer) { create(:customer) }
  let(:ops_context) { Operations::Context.new(customer: customer, channel: "assistant") }
  let(:documents_root) { Rails.root.join("app/services/ai_assistant/assistant/prompt/documents") }

  before do
    enable_module!("authentication", customer, name: "Authentication")
      .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
  end

  def tool_examples
    documents_root.glob("*.md").flat_map do |path|
      path.read.scan(/```json\n(.*?)\n```/m).flatten.filter_map do |raw|
        parsed = JSON.parse(raw)
        next unless parsed.is_a?(Hash) && parsed["tool"].present? && parsed.key?("arguments")

        { file: path.basename.to_s, example: parsed }
      end
    end
  end

  it "finds at least one fenced tool-call example" do
    expect(tool_examples).not_to be_empty
  end

  it "validates every documented tool-call payload against the live operation schema" do
    tool_examples.each do |row|
      tool = row[:example].fetch("tool")
      arguments = row[:example].fetch("arguments")
      operation = Operations.for(tool)
      violations, = operation.input_schema(ops_context).validate(arguments)

      expect(violations).to be_empty, lambda {
        details = violations.map(&:as_json)
        "#{row[:file]} #{tool}: #{details}"
      }
    end
  end

  it "keeps every documented create_entity payload within the semantic rules" do
    creates = tool_examples.select { |row| row[:example]["tool"] == "create_entity" }
    expect(creates).not_to be_empty

    creates.each do |row|
      violations = EntityDefinitions::Api::SemanticValidator.for_create(
        row[:example].dig("arguments", "entities"), customer: customer
      )

      expect(violations).to be_empty, -> { "#{row[:file]}: #{violations.map(&:as_json)}" }
    end
  end
end
