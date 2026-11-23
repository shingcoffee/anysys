# frozen_string_literal: true

require "rails_helper"

# Integration smoke test: every generator's generate_body must compile as valid Ruby.
# Groups output by category (directory) so regression location is obvious.
RSpec.describe "Code generators smoke", type: :integration do
  root = Rails.root.join("app/services/code_generators/element_types")
  Dir.glob(root.join("**/*_generator.rb")).each { |f| require f }

  def self.class_for(path)
    rel = Pathname(path).relative_path_from(Rails.root.join("app/services/code_generators/element_types")).to_s
    segments = rel.sub(/_generator\.rb\z/, "").split("/")
    parts = segments.map { |s| s.split("_").map(&:capitalize).join }
    const = "CodeGenerators::ElementTypes::#{parts.join("::")}Generator"
    const.constantize
  end

  categories = Dir.glob(root.join("**/*_generator.rb")).group_by { |f| Pathname(f).dirname.basename.to_s }

  categories.each do |category, files|
    describe "#{category} category" do
      files.sort.each do |file|
        klass = class_for(file)

        it "#{klass.name.demodulize} generate_body is syntactically valid Ruby" do
          sample = klass.respond_to?(:sample_input) ? (klass.sample_input || {}) : {}
          element = if klass.respond_to?(:generator_kind) && klass.generator_kind == :element_type
                      { "properties" => sample }
          else
                      { "config" => sample }
          end
          body = klass.new(element, {}).generate_body
          next if body.nil?
          expect { RubyVM::InstructionSequence.compile(body.to_s) }.not_to raise_error, \
            -> { "#{klass.name} produced invalid Ruby:\n#{body}" }
        end
      end
    end
  end
end
