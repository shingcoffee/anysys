# frozen_string_literal: true

module CodeGenerators
  module Shared
    # Ruby source for config data in the house style (`{"key" => 1}`,
    # `{name: "x"}`, `["a", "b"]`). Hash#inspect on Ruby 3.2 omits the spaces
    # around `=>`, so generators route literals through here instead.
    module RubyLiteral
      SYMBOL_KEY = /\A[a-z_][a-zA-Z0-9_]*[?!]?\z/

      module_function

      def emit(value)
        case value
        when Hash then emit_hash(value)
        when Array then "[#{value.map { |item| emit(item) }.join(', ')}]"
        when BigDecimal then value.to_s("F")
        else value.inspect
        end
      end

      def emit_hash(hash)
        return "{}" if hash.empty?

        pairs = hash.map do |key, item|
          if key.is_a?(Symbol) && SYMBOL_KEY.match?(key.name)
            "#{key.name}: #{emit(item)}"
          else
            "#{emit(key)} => #{emit(item)}"
          end
        end
        "{#{pairs.join(', ')}}"
      end
    end
  end
end
