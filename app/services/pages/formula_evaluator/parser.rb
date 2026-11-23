# frozen_string_literal: true

module Pages
  class FormulaEvaluator
    # Recursive-descent parser that consumes the token stream produced by
    # Tokenizer and returns an AST composed of plain hashes:
    #
    #   { type: :literal,    value: }
    #   { type: :identifier, name:  }
    #   { type: :binary,     operator:, left:, right: }
    #   { type: :call,       name:, args: [] }
    #
    # Mirrors the parse phase of the client-side FormulaEngine.
    class Parser
      def self.call(tokens)
        new(tokens).parse
      end

      def initialize(tokens)
        @tokens = tokens
        @pos    = 0
      end

      def parse
        parse_expression
      end

      private

      # Operator precedence levels (low → high):
      #   comparison  >  additive  >  multiplicative  >  primary

      def parse_expression
        parse_comparison
      end

      def parse_comparison
        left = parse_additive
        while peek && peek[:type] == :operator && %w[> < >= <= == !=].include?(peek[:value])
          op = advance[:value]
          left = { type: :binary, operator: op, left: left, right: parse_additive }
        end
        left
      end

      def parse_additive
        left = parse_multiplicative
        while peek && peek[:type] == :operator && %w[+ -].include?(peek[:value])
          op = advance[:value]
          left = { type: :binary, operator: op, left: left, right: parse_multiplicative }
        end
        left
      end

      def parse_multiplicative
        left = parse_primary
        while peek && peek[:type] == :operator && %w[* / %].include?(peek[:value])
          op = advance[:value]
          left = { type: :binary, operator: op, left: left, right: parse_primary }
        end
        left
      end

      def parse_primary # rubocop:disable Metrics/MethodLength
        token = peek
        raise "Unexpected end of expression" unless token

        case token[:type]
        when :lparen
          advance
          expr = parse_expression
          raise "Expected )" unless peek && peek[:type] == :rparen

          advance
          expr
        when :number, :string
          advance
          { type: :literal, value: token[:value] }
        when :function
          parse_function_call
        when :identifier
          advance
          { type: :identifier, name: token[:value] }
        else
          raise "Unexpected token: #{token[:type]}"
        end
      end

      def parse_function_call
        name = advance[:value]
        raise "Expected (" unless peek && peek[:type] == :lparen

        advance # opening paren
        args = []
        until peek && peek[:type] == :rparen
          raise "Unterminated function call" unless peek

          args << parse_expression
          advance if peek && peek[:type] == :comma
        end
        advance # closing paren
        { type: :call, name: name, args: args }
      end

      def peek  = @tokens[@pos]
      def advance
        tok = @tokens[@pos]
        @pos += 1
        tok
      end
    end
  end
end
