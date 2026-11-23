# frozen_string_literal: true

module CodeGenerators
  class CodeIntrospector
    OUTPUT_PATTERN = /ctx\[:(\w+)\]\s*=[^=]/
    READ_BRACKET  = /ctx\[:(\w+)\](?!\s*=[^=])/
    READ_DIG      = /ctx\.dig\(:(\w+)/
    READ_FETCH    = /ctx\.fetch\(:(\w+)/

    class << self
      def analyze(code_string)
        return { inputs: [], outputs: [] } if code_string.to_s.strip.empty?

        cleaned = strip_non_code(code_string)

        outputs = cleaned.scan(OUTPUT_PATTERN).flatten.uniq
        all_reads = cleaned.scan(READ_BRACKET).flatten
        all_reads += cleaned.scan(READ_DIG).flatten
        all_reads += cleaned.scan(READ_FETCH).flatten
        inputs = all_reads.uniq

        inputs.reject! { |k| k.start_with?("_") }
        outputs.reject! { |k| k.start_with?("_") }

        pure_outputs = outputs - inputs
        mixed = outputs & inputs
        pure_inputs = inputs - outputs

        {
          inputs: (pure_inputs + mixed).uniq.sort,
          outputs: (pure_outputs + mixed).uniq.sort
        }
      end

      private

      def strip_non_code(code)
        result = code.gsub(/<<~\w+.*?^\s*\w+$/m, "")
        result = result.gsub(/"(?:[^"\\]|\\.)*"/, '""')
        result = result.gsub(/'(?:[^'\\]|\\.)*'/, "''")
        result = result.gsub(/#.*$/, "")
        result
      end
    end
  end
end
