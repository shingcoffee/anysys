# frozen_string_literal: true

require "rails_helper"

# The assistant designs flowcharts from the palette alone, so every action
# and element carries a model-facing summary and every config field a
# description (FlowchartDefinitions::Assistant::SchemaGenerator).
RSpec.describe "Flowchart schema documentation" do
  def summary_length = (80..700)
  def description_length = (20..360)

  def summary_problems(generator)
    text = generator._metadata[:description].to_s.strip
    problems = []
    problems << "summary is #{text.length} characters (#{summary_length})" unless summary_length.cover?(text.length)
    problems << "summary must end with a full stop" unless text.end_with?(".")
    problems
  end

  def field_problems(schema)
    schema.fields.filter_map do |field|
      text = field.options[:description].to_s.strip
      if text.empty?
        "#{field.name}: missing description"
      elsif !description_length.cover?(text.length)
        "#{field.name}: description is #{text.length} characters (#{description_length})"
      elsif !text.end_with?(".")
        "#{field.name}: description must end with a full stop"
      elsif text.match?(/[^\x00-\x7F‑–—…→]/)
        "#{field.name}: description must be English"
      end
    end
  end

  describe "step actions" do
    CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq.sort_by(&:generator_name).each do |generator|
      it "documents #{generator.generator_name}" do
        problems = summary_problems(generator) + field_problems(generator._config_schema)
        expect(problems).to be_empty, "#{generator.generator_name}:\n  #{problems.join("\n  ")}"
      end
    end
  end

  describe "element types" do
    %w[end decision loop subflow].each do |type|
      it "documents the #{type} element fields" do
        generator = CodeGenerators::GeneratorRegistry.find_element_type(type)
        problems = field_problems(generator._config_schema)
        expect(problems).to be_empty, "#{type}:\n  #{problems.join("\n  ")}"
      end
    end

    it "documents every element type in the palette" do
      FlowchartDefinitions::Palette::ELEMENT_DOCS.each do |doc|
        expect(doc["description"].to_s.length).to be >= 60, "#{doc["type"]} needs a fuller description"
      end
    end
  end

  it "documents the connection fields" do
    expect(field_problems(CodeGenerators::ConnectionSchema.schema)).to be_empty
  end

  it "renders every description into the prompt palette" do
    FlowchartDefinitions::Palette.reset!
    palette = FlowchartDefinitions::Assistant::SchemaGenerator.prompt_palette
    CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq.each do |generator|
      generator._config_schema.fields.each do |field|
        next if field.capabilities.any?

        description = field.options[:description].to_s.strip
        expect(palette).to include(description), "#{generator.generator_name}.#{field.name} is missing from the palette"
      end
    end
  end
end
