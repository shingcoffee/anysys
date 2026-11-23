# frozen_string_literal: true

module CodeGenerators
  module Shared
    module OperandConverter
      IDENT_SEGMENT_RE = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

      def condition_operand_to_ruby(operand)
        return "nil" if operand.nil?
        return "true" if operand == true
        return "false" if operand == false

        # A numeric JSON value (e.g. `"rightOperand": 5`) lands here as
        # Integer/Float. `Integer#blank?` returns false but `Integer#start_with?`
        # is undefined and raises NoMethodError. Coerce to string here so the
        # branches below — all of which operate on String input — are safe.
        if operand.is_a?(Numeric)
          return operand.to_s
        end

        operand = operand.to_s
        return "nil" if operand.empty?

        if operand.start_with?("ctx.")
          ctx_operand_path(operand.delete_prefix("ctx.").split(".").reject(&:empty?))
        elsif (m = operand.match(/\Actx\[:([a-zA-Z_][a-zA-Z0-9_]*)\]((?:\[:[a-zA-Z_][a-zA-Z0-9_]*\])*)\z/))
          ctx_operand_path([m[1], *m[2].scan(/\[:(\w+)\]/).flatten])
        elsif (m = operand.match(/\Actx\["([a-zA-Z_][a-zA-Z0-9_]*)"\]\z/)) ||
              (m = operand.match(/\Actx\['([a-zA-Z_][a-zA-Z0-9_]*)'\]\z/))
          # String-key bracket form → symbol key (same safe identifier rule).
          "ctx[:#{m[1]}]"
        elsif operand == "signal"
          "ctx[:signal]"
        elsif operand == "ctx"
          "ctx"
        elsif operand.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\z/)
          # Strict decimal numeric literal: no leading-zero octal trap
          # (Ruby would parse "0123" as octal 83), supports negatives and
          # scientific notation. Anything else falls through to String#inspect.
          operand
        else
          operand.inspect
        end
      end

      private

      # Every segment must be a Ruby identifier (`ctx.1st_item` would emit an
      # invalid symbol). Nested paths go through Step.dig, which reads hashes
      # and records alike (Hash#dig raises on a record) and a missing parent
      # reads as nil.
      def ctx_operand_path(parts)
        return "nil" if parts.empty? || !parts.all? { |part| part.match?(IDENT_SEGMENT_RE) }

        root, *rest = parts
        return "ctx[:#{root}]" if rest.empty?

        "FlowchartRuntime::Step.dig(ctx[:#{root}], #{rest.map { |part| ":#{part}" }.join(', ')})"
      end
    end
  end
end
