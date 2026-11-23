# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ExpressionEvaluator do
  subject(:evaluate) { described_class.evaluate(expression, ctx) }

  let(:ctx) { {} }

  # ---------------------------------------------------------------------------
  # Nil / empty input
  # ---------------------------------------------------------------------------
  describe "nil and empty expressions" do
    context "when expression is nil" do
      let(:expression) { nil }

      it "returns nil" do
        expect(evaluate).to be_nil
      end
    end

    context "when expression is an empty string" do
      let(:expression) { "" }

      it "returns 0" do
        expect(evaluate).to eq(0)
      end
    end

    context "when expression is whitespace only" do
      let(:expression) { "   " }

      it "returns 0" do
        expect(evaluate).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Simple arithmetic
  # ---------------------------------------------------------------------------
  describe "simple arithmetic" do
    context "addition" do
      let(:expression) { "2 + 3" }

      it "returns 5" do
        expect(evaluate).to eq(5)
      end
    end

    context "subtraction" do
      let(:expression) { "10 - 4" }

      it "returns 6" do
        expect(evaluate).to eq(6)
      end
    end

    context "multiplication" do
      let(:expression) { "3 * 7" }

      it "returns 21" do
        expect(evaluate).to eq(21)
      end
    end

    context "division" do
      let(:expression) { "15 / 3" }

      it "returns 5" do
        expect(evaluate).to eq(5)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Operator precedence
  # ---------------------------------------------------------------------------
  describe "operator precedence" do
    context "* before +" do
      let(:expression) { "2 + 3 * 4" }

      it "returns 14" do
        expect(evaluate).to eq(14)
      end
    end

    context "/ before -" do
      let(:expression) { "20 - 10 / 2" }

      it "returns 15" do
        expect(evaluate).to eq(15)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Parentheses
  # ---------------------------------------------------------------------------
  describe "parentheses" do
    context "forcing addition before multiplication" do
      let(:expression) { "(2 + 3) * 4" }

      it "returns 20" do
        expect(evaluate).to eq(20)
      end
    end

    context "nested parentheses" do
      let(:expression) { "((2 + 3) * (1 + 1))" }

      it "returns 10" do
        expect(evaluate).to eq(10)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unary minus
  # ---------------------------------------------------------------------------
  describe "unary minus" do
    context "unary minus on literal" do
      let(:expression) { "-5 + 3" }

      it "returns -2" do
        expect(evaluate).to eq(-2)
      end
    end

    context "double unary minus" do
      let(:expression) { "--5" }

      it "returns 5" do
        expect(evaluate).to eq(5)
      end
    end

    context "unary minus in subexpression" do
      let(:expression) { "(-3) * 4" }

      it "returns -12" do
        expect(evaluate).to eq(-12)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Field references
  # ---------------------------------------------------------------------------
  describe "field references" do
    let(:ctx) { { quantity: 5, unit_price: 20 } }

    context "simple field multiplication" do
      let(:expression) { "quantity * unit_price" }

      it "returns the product" do
        expect(evaluate).to eq(100)
      end
    end

    context "field with literal offset" do
      let(:expression) { "quantity * unit_price + 10" }

      it "returns 110" do
        expect(evaluate).to eq(110)
      end
    end

    context "field with string key in ctx" do
      let(:ctx) { { "quantity" => 7 } }
      let(:expression) { "quantity * 3" }

      it "resolves string-keyed ctx" do
        expect(evaluate).to eq(21)
      end
    end

    context "undefined field reference" do
      let(:expression) { "undefined_field + 1" }

      it "treats nil as 0 and returns 1" do
        expect(evaluate).to eq(1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Dotted (nested) field references
  # ---------------------------------------------------------------------------
  describe "dotted field references" do
    let(:ctx) { { record: { amount: 50 } } }

    context "one level of nesting" do
      let(:expression) { "record.amount * 0.1" }

      it "returns 5.0" do
        expect(evaluate).to eq(5.0)
      end
    end

    context "nested field in larger expression" do
      let(:ctx) { { order: { price: 100, qty: 3 } } }
      let(:expression) { "order.price * order.qty" }

      it "returns 300" do
        expect(evaluate).to eq(300)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Division by zero
  # ---------------------------------------------------------------------------
  describe "division by zero" do
    context "literal zero divisor" do
      let(:expression) { "10 / 0" }

      it "returns 0 safely" do
        expect(evaluate).to eq(0)
      end
    end

    context "field-reference zero divisor" do
      let(:ctx) { { divisor: 0 } }
      let(:expression) { "100 / divisor" }

      it "returns 0 safely" do
        expect(evaluate).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # String literals and concatenation
  # ---------------------------------------------------------------------------
  describe "string literals and concatenation" do
    context "simple string concatenation" do
      let(:expression) { 'CONCAT("hello", " ", "world")' }

      it 'returns "hello world"' do
        expect(evaluate).to eq("hello world")
      end
    end

    context "string + field reference" do
      let(:ctx) { { name: "Alice" } }
      let(:expression) { 'CONCAT("Hello, ", name)' }

      it "concatenates correctly" do
        expect(evaluate).to eq("Hello, Alice")
      end
    end

    context "number coerced to string when concatenated to a string" do
      let(:expression) { 'CONCAT("value: ", to_string(42))' }

      it "returns concatenated result" do
        expect(evaluate).to eq("value: 42")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Numeric functions — single-argument
  # ---------------------------------------------------------------------------
  describe "numeric functions" do
    describe "round" do
      it "rounds 3.7 to 4" do
        expect(described_class.evaluate("round(3.7)", {})).to eq(4)
      end

      it "rounds 3.2 to 3" do
        expect(described_class.evaluate("round(3.2)", {})).to eq(3)
      end
    end

    describe "ceil" do
      it "returns ceiling of 3.1 as 4" do
        expect(described_class.evaluate("ceil(3.1)", {})).to eq(4)
      end
    end

    describe "floor" do
      it "returns floor of 3.9 as 3" do
        expect(described_class.evaluate("floor(3.9)", {})).to eq(3)
      end
    end

    describe "abs" do
      it "returns absolute value of -7" do
        expect(described_class.evaluate("abs(-7)", {})).to eq(7)
      end

      it "leaves positive values unchanged" do
        expect(described_class.evaluate("abs(5)", {})).to eq(5)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Binary functions: min, max
  # ---------------------------------------------------------------------------
  describe "binary functions" do
    describe "min" do
      it "returns the smaller of two values" do
        expect(described_class.evaluate("min(5, 3)", {})).to eq(3)
      end

      it "works with field references" do
        expect(described_class.evaluate("min(a, b)", { a: 10, b: 7 })).to eq(7)
      end
    end

    describe "max" do
      it "returns the larger of two values" do
        expect(described_class.evaluate("max(5, 3)", {})).to eq(5)
      end

      it "works with field references" do
        expect(described_class.evaluate("max(a, b)", { a: 10, b: 7 })).to eq(10)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Type coercion functions
  # ---------------------------------------------------------------------------
  describe "coercion functions" do
    describe "to_number" do
      it "converts a string literal to a number" do
        expect(described_class.evaluate('to_number("42")', {})).to eq(42)
      end

      it "passes through a numeric value unchanged" do
        expect(described_class.evaluate("to_number(3.5)", {})).to eq(3.5)
      end
    end

    describe "to_string" do
      it "converts a number to its string representation" do
        expect(described_class.evaluate("to_string(99)", {})).to eq("99")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Functions inside larger expressions
  # ---------------------------------------------------------------------------
  describe "functions embedded in expressions" do
    it "uses round result in arithmetic" do
      expect(described_class.evaluate("round(3.7) * 2", {})).to eq(8)
    end

    it "uses min as a sub-expression" do
      expect(described_class.evaluate("min(10, 5) + 3", {})).to eq(8)
    end
  end

  # ---------------------------------------------------------------------------
  # Complex expressions
  # ---------------------------------------------------------------------------
  describe "complex expressions" do
    context "(price * quantity) - discount" do
      let(:ctx) { { price: 25, quantity: 4, discount: 10 } }
      let(:expression) { "(price * quantity) - discount" }

      it "returns 90" do
        expect(evaluate).to eq(90)
      end
    end

    context "nested arithmetic with multiple operators" do
      let(:ctx) { { a: 10, b: 3, c: 2 } }
      let(:expression) { "a * b + c * b - a" }

      # 10*3 + 2*3 - 10 = 30 + 6 - 10 = 26
      it "respects full precedence chain" do
        expect(evaluate).to eq(26)
      end
    end

    context "expression with function and fields" do
      let(:ctx) { { subtotal: 99.6, tax_rate: 0.1 } }
      let(:expression) { "round(subtotal * tax_rate)" }

      it "returns 10" do
        expect(evaluate).to eq(10)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------
  describe "error handling" do
    context "expression exceeds maximum length" do
      let(:expression) { "1 + " * 300 + "1" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError, /maximum length/)
      end
    end

    context "unknown function" do
      let(:expression) { "evil(1)" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError, /undefined function/i)
      end
    end

    context "unexpected character in expression" do
      let(:expression) { "1 @ 2" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError, /parse error/i)
      end
    end

    context "mismatched parentheses — missing closing" do
      let(:expression) { "(2 + 3" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError)
      end
    end

    context "mismatched parentheses — extra closing" do
      let(:expression) { "2 + 3)" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError)
      end
    end

    context "round with a decimal-places argument (dentaku built-in)" do
      let(:expression) { "round(1.256, 2)" }

      it "rounds to the requested precision" do
        expect(evaluate).to eq(1.26)
      end
    end

    context "trailing operator with no right-hand operand" do
      let(:expression) { "5 +" }

      it "raises ExpressionError" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError)
      end
    end

    context "deeply nested expression exceeding MAX_DEPTH" do
      # Build an expression nested more than 20 levels deep.
      let(:expression) { "(" * 21 + "1" + ")" * 21 }

      it "raises ExpressionError about nesting depth" do
        expect { evaluate }.to raise_error(FlowchartRuntime::ExpressionError, /nesting depth/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Floating-point literals
  # ---------------------------------------------------------------------------
  describe "floating-point literals" do
    context "decimal addition" do
      let(:expression) { "1.5 + 2.5" }

      it "returns 4.0" do
        expect(evaluate).to eq(4.0)
      end
    end

    context "decimal multiplication" do
      let(:expression) { "0.5 * 10" }

      it "returns 5.0" do
        expect(evaluate).to eq(5.0)
      end
    end
  end
end
