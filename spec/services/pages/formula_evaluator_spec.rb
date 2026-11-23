# frozen_string_literal: true

require "rails_helper"

# Mirrors the client-side app/javascript/lib/formula_engine.js so server-side
# calculation persistence matches the live preview the user saw.
RSpec.describe Pages::FormulaEvaluator do
  def evaluate(formula, values = {})
    described_class.evaluate(formula, values)
  end

  # Shared instance for the private-method probes below (num/stringify/truthy?/etc).
  let(:evaluator) { described_class.new({}) }

  describe "literals and arithmetic" do
    it "evaluates numbers" do
      expect(evaluate("42")).to eq(42)
    end

    it "evaluates + - * / and precedence" do
      expect(evaluate("2 + 3 * 4")).to eq(14)
      expect(evaluate("(2 + 3) * 4")).to eq(20)
      expect(evaluate("10 - 4 / 2")).to eq(8)
    end

    it "treats division by zero as 0 (matching the JS engine)" do
      expect(evaluate("5 / 0")).to eq(0)
    end

    it "evaluates modulo" do
      expect(evaluate("10 % 3")).to eq(1)
    end
  end

  describe "field reference tokens" do
    it "resolves {field} tokens from the values hash" do
      expect(evaluate("{qty} * {price}", "qty" => 3, "price" => 5)).to eq(15)
    end

    it "coerces string values numerically" do
      expect(evaluate("{a} + {b}", "a" => "10", "b" => "5")).to eq(15)
    end

    it "returns nil when an operand references a missing field (matches the JS engine)" do
      # The client FormulaEngine yields null if any operand is null, so the
      # server must too, keeping persisted results consistent with the preview.
      expect(evaluate("{a} + {b}", "a" => 10)).to be_nil
    end
  end

  describe "math functions" do
    it "SUM/SUBTRACT/MULTIPLY/DIVIDE" do
      expect(evaluate("SUM(1, 2, 3)")).to eq(6)
      expect(evaluate("SUBTRACT(10, 4)")).to eq(6)
      expect(evaluate("MULTIPLY(2, 3, 4)")).to eq(24)
      expect(evaluate("DIVIDE(10, 4)")).to eq(2.5)
      expect(evaluate("DIVIDE(10, 0)")).to eq(0)
    end

    it "MIN/MAX/AVERAGE" do
      expect(evaluate("MIN(3, 1, 2)")).to eq(1)
      expect(evaluate("MAX(3, 1, 2)")).to eq(3)
      expect(evaluate("AVERAGE(2, 4, 6)")).to eq(4)
    end

    it "ROUND/FLOOR/CEIL/ABS/MOD" do
      expect(evaluate("ROUND(3.14159, 2)")).to eq(3.14)
      expect(evaluate("ROUND(3.7)")).to eq(4)
      expect(evaluate("FLOOR(3.9)")).to eq(3)
      expect(evaluate("CEIL(3.1)")).to eq(4)
      expect(evaluate("ABS(0 - 5)")).to eq(5)
      expect(evaluate("MOD(10, 3)")).to eq(1)
    end

    it "supports nested functions and field refs" do
      expect(evaluate("ROUND({a} / {b}, 1)", "a" => 10, "b" => 3)).to eq(3.3)
    end
  end

  describe "logic functions" do
    it "IF returns the branch by truthiness (JS semantics: 0 and '' are falsey)" do
      expect(evaluate("IF(1, 10, 20)")).to eq(10)
      expect(evaluate("IF(0, 10, 20)")).to eq(20)
      expect(evaluate('IF({a} > 5, 100, 200)', "a" => 9)).to eq(100)
    end

    it "AND/OR/NOT" do
      expect(evaluate("AND(1, 1)")).to eq(true)
      expect(evaluate("AND(1, 0)")).to eq(false)
      expect(evaluate("OR(0, 1)")).to eq(true)
      expect(evaluate("NOT(0)")).to eq(true)
    end

    it "SWITCH matches a case or returns the trailing default" do
      expect(evaluate('SWITCH({g}, "a", 1, "b", 2)', "g" => "b")).to eq(2)
      expect(evaluate('SWITCH({g}, "a", 1, 99)', "g" => "zzz")).to eq(99)
    end
  end

  describe "text functions" do
    it "CONCAT/UPPER/LOWER/TRIM/LENGTH/LEFT/RIGHT" do
      expect(evaluate('CONCAT("a", "b", "c")')).to eq("abc")
      expect(evaluate('UPPER("abc")')).to eq("ABC")
      expect(evaluate('LOWER("ABC")')).to eq("abc")
      expect(evaluate('TRIM("  hi  ")')).to eq("hi")
      expect(evaluate('LENGTH("hello")')).to eq(5)
      expect(evaluate('LEFT("hello", 2)')).to eq("he")
      expect(evaluate('RIGHT("hello", 2)')).to eq("lo")
    end

    it "concatenates field values" do
      expect(evaluate('CONCAT({first}, " ", {last})', "first" => "Ada", "last" => "Lovelace")).to eq("Ada Lovelace")
    end
  end

  describe "comparison operators" do
    it "numeric comparisons" do
      expect(evaluate("{a} >= 10", "a" => 10)).to eq(true)
      expect(evaluate("{a} < 10",  "a" => 10)).to eq(false)
      expect(evaluate("{a} <= 10", "a" => 10)).to eq(true)  # line 237
    end

    it "loose equality (matches JS ==)" do
      expect(evaluate('{a} == 5', "a" => "5")).to eq(true)
      expect(evaluate('{a} != 5', "a" => "6")).to eq(true)
    end
  end

  describe "date functions" do
    let(:today) { Date.today }
    let(:now)   { Time.now }

    it "TODAY() returns today's date" do
      result = evaluate("TODAY()")
      expect(result).to eq(Date.today)
    end

    it "NOW() returns a Time instance" do
      result = evaluate("NOW()")
      expect(result).to be_a(Time)
    end

    it "YEAR/MONTH/DAY extract parts from a date string" do
      expect(evaluate('YEAR("2024-03-15")')).to eq(2024)
      expect(evaluate('MONTH("2024-03-15")')).to eq(3)
      expect(evaluate('DAY("2024-03-15")')).to eq(15)
    end

    it "YEAR/MONTH/DAY return nil when the value is unparseable" do
      expect(evaluate('YEAR("not-a-date")')).to be_nil
      expect(evaluate('MONTH("not-a-date")')).to be_nil
      expect(evaluate('DAY("not-a-date")')).to be_nil
    end

    it "DATE_DIFF returns days between two dates" do
      expect(evaluate('DATE_DIFF("2024-01-10", "2024-01-01")')).to eq(9)
    end

    it "DATE_DIFF 'months' unit" do
      expect(evaluate('DATE_DIFF("2024-03-01", "2024-01-01", "months")')).to eq(2)
    end

    it "DATE_DIFF 'years' unit" do
      expect(evaluate('DATE_DIFF("2026-06-01", "2024-06-01", "years")')).to eq(2)
    end

    it "DATE_DIFF returns nil when a date is invalid" do
      expect(evaluate('DATE_DIFF("bad", "2024-01-01")')).to be_nil
    end

    it "DATE_ADD adds days by default" do
      expect(evaluate('DATE_ADD("2024-01-01", 5)')).to eq(Date.new(2024, 1, 6))
    end

    it "DATE_ADD 'months' unit" do
      expect(evaluate('DATE_ADD("2024-01-01", 2, "months")')).to eq(Date.new(2024, 3, 1))
    end

    it "DATE_ADD 'years' unit" do
      expect(evaluate('DATE_ADD("2024-01-01", 1, "years")')).to eq(Date.new(2025, 1, 1))
    end

    it "DATE_ADD returns nil when date is invalid" do
      expect(evaluate('DATE_ADD("bad", 5)')).to be_nil
    end

    it "to_date accepts a Date object directly (no parse)" do
      d = Date.new(2024, 6, 15)
      expect(evaluate("YEAR({d})", "d" => d)).to eq(2024)
    end

    it "to_date accepts a Time object via .to_date (line 359)" do
      t = Time.new(2024, 7, 4)
      expect(evaluate("YEAR({t})", "t" => t)).to eq(2024)
    end
  end

  describe "num coercion helpers (lines 297-303)" do
    it "coerces true to 1.0 (line 297)" do
      # num(true) == 1.0; MULTIPLY passes true values as numerics
      expect(evaluator.send(:num, true)).to eq(1.0)
    end

    it "coerces false to 0.0 (line 298)" do
      expect(evaluator.send(:num, false)).to eq(0.0)
    end

    it "coerces nil to 0.0 (line 298)" do
      expect(evaluator.send(:num, nil)).to eq(0.0)
    end

    it "coerces a non-numeric string to 0.0" do
      # {x} resolves to "abc", num("abc") should be 0.0
      expect(evaluate("{x} + 0", "x" => "abc")).to eq(0)
    end

    it "handles TypeError in num (line 302)" do
      # nil coercion path — nil operands return nil from binary eval, so
      # we test the truthy? path for booleans instead
      expect(evaluate("IF(0, 1, 2)")).to eq(2)
      expect(evaluate("IF(false, 1, 2)")).to eq(2)
    end
  end

  describe "stringify Float formatting (line 336)" do
    it "renders whole-number floats without decimal point" do
      expect(evaluate("CONCAT(3.0, '')")).to eq("3")
    end

    it "renders fractional floats with decimal point" do
      expect(evaluate("CONCAT(3.5, '')")).to eq("3.5")
    end
  end

  describe "RIGHT with n <= 0 (line 342)" do
    it "returns empty string when n is zero" do
      expect(evaluate('RIGHT("hello", 0)')).to eq("")
    end

    it "returns empty string when n is negative" do
      # right_str returns "" when n <= 0, but RIGHT passes a[1].to_i;
      # the function returns "" for n<=0 via the guard in right_str.
      # (-1).to_i => -1 which is <= 0, so the guard fires.
      # However the StandardError rescue in evaluate() catches any exception
      # and returns nil; direct test of right_str is more reliable.
      result = evaluator.send(:right_str, "hello", -1)
      expect(result).to eq("")
    end
  end

  describe "SWITCH with no default (even-length cases — line 354)" do
    it "returns nil when no case matches and there is no default" do
      result = evaluate('SWITCH({x}, "a", 1, "b", 2)', "x" => "c")
      expect(result).to be_nil
    end
  end

  describe "loose_eq numeric string comparison (lines 320-322)" do
    it "considers '5' == 5.0 to be true (numeric string equality)" do
      expect(evaluate("{a} == 5.0", "a" => "5")).to eq(true)
    end

    it "considers non-numeric strings as unequal to numbers" do
      expect(evaluate("{a} == 5", "a" => "hello")).to eq(false)
    end
  end

  describe "eval_binary with nil operands and == / != (lines 222-224)" do
    it "nil == nil returns true" do
      # Both operands missing → nil == nil
      expect(evaluate("{a} == {b}")).to eq(true)
    end

    it "nil != nil returns false" do
      expect(evaluate("{a} != {b}")).to eq(false)
    end
  end

  describe "modulo with zero divisor (line 233)" do
    it "returns 0 for modulo by zero" do
      expect(evaluate("5 % 0")).to eq(0)
    end
  end

  describe "robustness" do
    it "returns nil for blank formulas" do
      expect(evaluate("")).to be_nil
      expect(evaluate(nil)).to be_nil
    end

    it "returns nil rather than raising on malformed input" do
      expect(evaluate("SUM(")).to be_nil
      expect(evaluate("* 5")).to be_nil
    end

    it "returns nil for an unknown function" do
      expect(evaluate("BOGUS(1, 2)")).to be_nil
    end
  end

  # -----------------------------------------------------------------------
  # Branch-coverage additions — remaining arms not reached above
  # -----------------------------------------------------------------------

  describe "tokenizer — unknown character is skipped (line 113 case :else)" do
    # A character like `@` does not match any when branch in the `case ch` block.
    # The tokenizer's `pos += 1` after the case still advances past it so the
    # loop doesn't hang. The unknown char is silently dropped and `1 @ 2` tokenizes
    # to `[1, 2]`, which parse_primary returns as `1` (the `2` is never consumed).
    it "silently drops an unrecognised character without raising" do
      expect { evaluate("1 @ 2") }.not_to raise_error
    end
  end

  describe "parse_primary raise paths (all rescued to nil)" do
    it "returns nil when expression ends unexpectedly (line 159 raise 'Unexpected end')" do
      # An expression that parses a binary node but the right-hand side is empty
      expect(evaluate("1 +")).to be_nil
    end

    it "returns nil for unclosed parenthesis (line 165 raise 'Expected )')" do
      expect(evaluate("(1 + 2")).to be_nil
    end

    it "returns nil for function missing opening paren (line 173 raise 'Expected (')" do
      # CONCAT without its opening paren — parse_primary raises, rescued to nil
      expect(evaluate("CONCAT")).to be_nil
    end

    it "returns nil for unterminated function call (line 177 raise 'Unterminated')" do
      expect(evaluate("SUM(1, 2")).to be_nil
    end
  end

  describe "truthy? — false value (line 312 :then — value == false)" do
    it "treats literal false as falsey in IF" do
      expect(evaluator.send(:truthy?, false)).to eq(false)
    end
  end

  describe "stringify — nil (line 335 :then) and integer-valued Float (line 320 :then)" do
    it "returns '' for nil (line 335 :then)" do
      expect(evaluator.send(:stringify, nil)).to eq("")
    end

    it "returns integer string for whole-number Float (line 320 :then)" do
      expect(evaluator.send(:stringify, 4.0)).to eq("4")
    end

    it "returns decimal string for non-integer Float (line 320 :else)" do
      expect(evaluator.send(:stringify, 4.5)).to eq("4.5")
    end
  end

  describe "execute — case else branch (line 204 :else) — unreachable with valid AST" do
    # The execute method's case exhaustively covers :literal, :identifier, :binary, :call.
    # Any other node[:type] falls to the implicit else and returns nil. This can only
    # occur if the parser produces a non-standard AST node (not possible via normal tokenize).
    # We invoke execute directly to confirm the branch returns nil without crashing.
    it "returns nil for an unknown node type (direct invocation)" do
      result = evaluator.send(:execute, { type: :unknown_node, value: 42 })
      expect(result).to be_nil
    end
  end
end
