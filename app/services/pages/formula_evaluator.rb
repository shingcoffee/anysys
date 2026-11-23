# frozen_string_literal: true

require_relative "formula_evaluator/coercion_helpers"
require_relative "formula_evaluator/tokenizer"
require_relative "formula_evaluator/parser"

module Pages
  # Server-side formula evaluation that mirrors the client engine
  # (app/javascript/lib/formula_engine.js) so persisted calculation results
  # match the live preview shown in the page builder.
  #
  # Supports the same surface: numbers, quoted strings, {field} reference
  # tokens, arithmetic/comparison operators, and the 31 built-in functions
  # (Math / Logic / Text / Date). Returns nil on blank or malformed input
  # rather than raising.
  #
  # @example
  #   Pages::FormulaEvaluator.evaluate("ROUND({qty} * {price}, 2)",
  #                                    "qty" => 3, "price" => 2.5) # => 7.5
  class FormulaEvaluator
    include CoercionHelpers

    def self.evaluate(formula, values = {})
      new(values).evaluate(formula)
    end

    def initialize(values = {})
      @values = values || {}
    end

    def evaluate(formula)
      return nil if formula.nil? || formula.to_s.strip.empty?

      tokens = Tokenizer.call(formula.to_s)
      ast    = Parser.call(tokens)
      execute(ast)
    rescue StandardError
      nil
    end

    private

    # ---- Evaluator (mirrors FormulaEngine#execute) ---------------------------

    def execute(node)
      return nil unless node

      case node[:type]
      when :literal
        node[:value]
      when :identifier
        v = @values[node[:name]]
        v.nil? ? @values[node[:name].to_sym] : v
      when :binary
        eval_binary(node)
      when :call
        eval_call(node)
      end
    end

    def eval_binary(node)
      left  = execute(node[:left])
      right = execute(node[:right])
      op    = node[:operator]

      if left.nil? || right.nil?
        return (op == "==" ? left == right : left != right) if %w[== !=].include?(op)

        return nil
      end

      case op
      when "+" then num(left) + num(right)
      when "-" then num(left) - num(right)
      when "*" then num(left) * num(right)
      when "/" then num(right).zero? ? 0 : num(left) / num(right)
      when "%" then num(right).zero? ? 0 : num(left) % num(right)
      when ">"  then num(left) > num(right)
      when "<"  then num(left) < num(right)
      when ">=" then num(left) >= num(right)
      when "<=" then num(left) <= num(right)
      when "==" then loose_eq(left, right)
      when "!=" then !loose_eq(left, right)
      end
    end

    def eval_call(node)
      fn = functions[node[:name]]
      raise "Unknown function: #{node[:name]}" unless fn

      fn.call(node[:args].map { |a| execute(a) })
    end

    # ---- Built-in functions (mirror FormulaEngine#registerFunctions) --------

    def functions
      @functions ||= {
        # Math
        "SUM"      => ->(a) { a.sum { |v| num(v) } },
        "SUBTRACT" => ->(a) { num(a[0]) - num(a[1]) },
        "MULTIPLY" => ->(a) { a.reduce(1) { |p, v| p * num(v) } },
        "DIVIDE"   => ->(a) { num(a[1]).zero? ? 0 : num(a[0]) / num(a[1]) },
        "MIN"      => ->(a) { a.map { |v| num(v) }.min },
        "MAX"      => ->(a) { a.map { |v| num(v) }.max },
        "AVERAGE"  => ->(a) { nums = a.map { |v| num(v) }; nums.sum / nums.length },
        "ROUND"    => ->(a) { factor = 10**(a[1].nil? ? 0 : a[1].to_i); (num(a[0]) * factor).round / factor.to_f },
        "FLOOR"    => ->(a) { num(a[0]).floor },
        "CEIL"     => ->(a) { num(a[0]).ceil },
        "ABS"      => ->(a) { num(a[0]).abs },
        "MOD"      => ->(a) { num(a[0]) % num(a[1]) },
        # Logic
        "IF"       => ->(a) { truthy?(a[0]) ? a[1] : a[2] },
        "AND"      => ->(a) { a.all? { |v| truthy?(v) } },
        "OR"       => ->(a) { a.any? { |v| truthy?(v) } },
        "NOT"      => ->(a) { !truthy?(a[0]) },
        "SWITCH"   => ->(a) { switch(a[0], a[1..]) },
        # Text
        "CONCAT"   => ->(a) { a.map { |v| stringify(v) }.join },
        "UPPER"    => ->(a) { stringify(a[0]).upcase },
        "LOWER"    => ->(a) { stringify(a[0]).downcase },
        "TRIM"     => ->(a) { stringify(a[0]).strip },
        "LENGTH"   => ->(a) { stringify(a[0]).length },
        "LEFT"     => ->(a) { stringify(a[0])[0, a[1].to_i] || "" },
        "RIGHT"    => ->(a) { right_str(stringify(a[0]), a[1].to_i) },
        # Date
        "TODAY"    => ->(_a) { Date.today },
        "NOW"      => ->(_a) { Time.now },
        "YEAR"     => ->(a) { to_date(a[0])&.year },
        "MONTH"    => ->(a) { to_date(a[0])&.month },
        "DAY"      => ->(a) { to_date(a[0])&.day },
        "DATE_DIFF" => ->(a) { date_diff(a[0], a[1], a[2] || "days") },
        "DATE_ADD"  => ->(a) { date_add(a[0], a[1].to_i, a[2] || "days") }
      }
    end
  end
end
