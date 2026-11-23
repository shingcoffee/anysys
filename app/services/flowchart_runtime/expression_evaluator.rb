# frozen_string_literal: true

require "dentaku"

module FlowchartRuntime
  class ExpressionError < StandardError; end

  # FlowchartRuntime::ExpressionEvaluator
  #
  # Safely evaluates infix math and string expressions. Parsing and evaluation
  # are delegated to the dentaku gem (safe, no eval/send, explicit function
  # registry); this module is a thin wrapper that owns the app-level contract:
  #
  #   - Arithmetic: +  -  *  /  with standard precedence and parentheses
  #   - Functions: round, ceil, floor, abs, min, max, to_number, to_string
  #     (plus dentaku's built-ins, e.g. IF, SUM, CONCAT for strings)
  #   - Field references (bare identifiers resolved from ctx; symbol or
  #     string keys) and dotted references: record.amount → ctx[:record][:amount]
  #   - Unreferenced/unknown fields evaluate as 0
  #   - Division by zero evaluates to 0 instead of raising
  #   - Double-quoted or single-quoted string literals
  #
  # Safety guardrails (wrapper-owned):
  #   - Maximum expression length: 1000 characters
  #   - Maximum parenthesis nesting depth: 20
  #   - Raises FlowchartRuntime::ExpressionError on malformed input
  #
  # Usage:
  #   FlowchartRuntime::ExpressionEvaluator.evaluate("quantity * unit_price + 10",
  #                                                   { quantity: 5, unit_price: 20 })
  #   #=> 110
  module ExpressionEvaluator
    class Error < ExpressionError; end

    MAX_LENGTH = 1000
    MAX_DEPTH  = 20

    module_function

    # Public entry point.
    #
    # @param expression [String, nil]
    # @param ctx        [Hash]   keys may be symbols or strings; may be nested
    # @return [Numeric, String, nil]
    # @raise  [FlowchartRuntime::ExpressionError]
    def evaluate(expression, ctx = {})
      return nil if expression.nil?

      expr = expression.to_s.strip
      return 0 if expr.empty?

      guard_length!(expr)
      guard_depth!(expr)

      calc = calculator
      data = bind_context(calc, expr, ctx)
      normalize_number(calc.evaluate!(expr, data))
    rescue Dentaku::ZeroDivisionError, ZeroDivisionError
      0
    rescue Dentaku::Error, Dentaku::ParseError, Dentaku::TokenizerError => e
      raise Error, e.message
    end

    # ---------------------------------------------------------------------------
    # Internals
    # ---------------------------------------------------------------------------

    # Fresh calculator per call: Dentaku::Calculator carries mutable memory,
    # so a shared instance would not be thread-safe.
    def calculator
      Dentaku::Calculator.new.tap do |calc|
        calc.add_function(:ceil,      :numeric, ->(x) { number(x).ceil })
        calc.add_function(:floor,     :numeric, ->(x) { number(x).floor })
        calc.add_function(:to_number, :numeric, ->(x) { number(x) })
        calc.add_function(:to_string, :string,  ->(x) { normalize_number(x).to_s })
      end
    end

    # Resolve the expression's identifiers; any not supplied by ctx binds to 0
    # so formulas over sparse runtime contexts degrade gracefully.
    def bind_context(calc, expr, ctx)
      ctx     = ctx.is_a?(Hash) ? ctx : {}
      missing = calc.dependencies(expr, ctx)
      ctx.merge(missing.index_with { 0 })
    end

    def guard_length!(expr)
      return if expr.length <= MAX_LENGTH

      raise Error, "Expression exceeds maximum length of #{MAX_LENGTH} characters"
    end

    def guard_depth!(expr)
      depth = 0
      expr.each_char do |ch|
        depth += 1 if ch == "("
        depth -= 1 if ch == ")"
        if depth > MAX_DEPTH
          raise Error, "Expression exceeds maximum nesting depth of #{MAX_DEPTH}"
        end

      end
    end

    def number(val)
      case val
      when Integer, Float, BigDecimal then val
      when String then val.include?(".") ? val.to_f : val.to_i
      when NilClass then 0
      else val.to_f
      end
    end

    # Dentaku returns BigDecimal for non-integer math; expose plain Ruby
    # numerics so callers see 5.0 rather than 0.5e1.
    def normalize_number(value)
      case value
      when BigDecimal then value.frac.zero? ? value.to_i : value.to_f
      else value
      end
    end

  end
end
