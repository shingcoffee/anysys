# frozen_string_literal: true

module Pages
  class FormulaEvaluator
    # Converts a raw formula string into a flat list of typed token hashes.
    # Mirrors the tokenize phase of the client-side FormulaEngine.
    #
    # Token shapes:
    #   { type: :number,     value: Float    }
    #   { type: :string,     value: String   }
    #   { type: :identifier, value: String   }
    #   { type: :function,   value: String   }
    #   { type: :operator,   value: String   }
    #   { type: :lparen }
    #   { type: :rparen }
    #   { type: :comma  }
    class Tokenizer
      def self.call(formula)
        new(formula).tokens
      end

      def initialize(formula)
        @formula = formula
        @pos     = 0
        @len     = formula.length
        @tokens  = []
      end

      def tokens
        while @pos < @len
          ch = @formula[@pos]

          if ch =~ /\s/
            @pos += 1
            next
          end

          if ch =~ /\d/
            scan_number
            next
          end

          if ch == '"' || ch == "'"
            scan_string(ch)
            next
          end

          if ch == "{"
            scan_field_reference
            next
          end

          if ch =~ /[a-zA-Z_]/
            scan_identifier
            next
          end

          two = @formula[@pos, 2]
          if %w[>= <= == != && ||].include?(two)
            @tokens << { type: :operator, value: two }
            @pos += 2
            next
          end

          if %w[+ - * / % > <].include?(ch)
            @tokens << { type: :operator, value: ch }
            @pos += 1
            next
          end

          case ch
          when "(" then @tokens << { type: :lparen }
          when ")" then @tokens << { type: :rparen }
          when "," then @tokens << { type: :comma }
          end
          @pos += 1
        end

        @tokens
      end

      private

      def scan_number
        num = +""
        while @pos < @len && @formula[@pos] =~ /[\d.]/
          num << @formula[@pos]
          @pos += 1
        end
        @tokens << { type: :number, value: num.to_f }
      end

      def scan_string(quote)
        @pos += 1
        str = +""
        while @pos < @len && @formula[@pos] != quote
          str << @formula[@pos]
          @pos += 1
        end
        @pos += 1 # closing quote
        @tokens << { type: :string, value: str }
      end

      def scan_field_reference
        @pos += 1
        ident = +""
        while @pos < @len && @formula[@pos] != "}"
          ident << @formula[@pos]
          @pos += 1
        end
        @pos += 1 # closing brace
        @tokens << { type: :identifier, value: ident.strip }
      end

      def scan_identifier
        ident = +""
        while @pos < @len && @formula[@pos] =~ /[a-zA-Z0-9_]/
          ident << @formula[@pos]
          @pos += 1
        end
        is_function = @formula[@pos] == "("
        @tokens << { type: is_function ? :function : :identifier, value: ident }
      end
    end
  end
end
