# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::SourceDocument do
  let(:source) do
    <<~RUBY
      # frozen_string_literal: true

      module CodeGenerators
        module ElementTypes
          class SampleGenerator < BaseGenerator
            generator_metadata do
              description "Sample"
            end

            def generate_body
              <<~CODE
                true
              CODE
            end
          end
        end
      end
    RUBY
  end

  it "reads the class body between the class line and its end" do
    expect(described_class.new(source).body).to eq(<<-BODY)
      generator_metadata do
        description "Sample"
      end

      def generate_body
        <<~CODE
          true
        CODE
      end
    BODY
  end

  it "replaces only the class body, normalising line endings" do
    edited = described_class.new(source).with_body("      def generate_body\r\n        \"true\"\r\n      end")
    expect(edited).to eq(<<~RUBY)
      # frozen_string_literal: true

      module CodeGenerators
        module ElementTypes
          class SampleGenerator < BaseGenerator
            def generate_body
              "true"
            end
          end
        end
      end
    RUBY
  end

  it "keeps multibyte text intact" do
    edited = described_class.new(source).with_body('      description "订单"')
    expect(edited).to include('description "订单"').and end_with("    end\n  end\nend\n")
  end

  CodeGenerators::GeneratorRegistry.all.each do |klass|
    it "roundtrips the class body of #{klass.name} through the editor unchanged" do
      original = File.read(Rails.root.join("app/services", "#{klass.name.underscore}.rb"))
      body = described_class.new(original).body
      saved = CodeGenerators::SourceAssembler.new({ methods_body: body }, source: original).assemble

      expect(saved).to eq(original)
      expect(CodeGenerators::GeneratorValidator.validate_source(saved)).to be_empty
    end
  end
end
