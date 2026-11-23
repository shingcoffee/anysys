# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::OperandConverter do
  let(:converter) { Class.new { include CodeGenerators::Shared::OperandConverter }.new }

  describe "#condition_operand_to_ruby" do
    it "converts ctx.field to ctx[:field]" do
      expect(converter.condition_operand_to_ruby("ctx.user")).to eq("ctx[:user]")
    end

    it "reads ctx.nested.path through Step.dig so a record root works" do
      expect(converter.condition_operand_to_ruby("ctx.user.email"))
        .to eq("FlowchartRuntime::Step.dig(ctx[:user], :email)")
      expect(converter.condition_operand_to_ruby("ctx.order.customer.email"))
        .to eq("FlowchartRuntime::Step.dig(ctx[:order], :customer, :email)")
    end

    it "evaluates a nested path against string-keyed params and a missing parent" do
      source = converter.condition_operand_to_ruby("ctx.params.amount")
      evaluate = ->(ctx) { eval(source, binding) } # rubocop:disable Security/Eval

      expect(evaluate.call({ params: { "amount" => "120" } })).to eq("120")
      expect(evaluate.call({})).to be_nil
    end

    it "converts 'signal' to ctx[:signal]" do
      expect(converter.condition_operand_to_ruby("signal")).to eq("ctx[:signal]")
    end

    it "converts 'ctx' to ctx" do
      expect(converter.condition_operand_to_ruby("ctx")).to eq("ctx")
    end

    it "passes through integers" do
      expect(converter.condition_operand_to_ruby("42")).to eq("42")
    end

    it "passes through floats" do
      expect(converter.condition_operand_to_ruby("3.14")).to eq("3.14")
    end

    it "wraps strings in quotes" do
      expect(converter.condition_operand_to_ruby("hello")).to eq("\"hello\"")
    end

    it "returns 'nil' for blank input" do
      expect(converter.condition_operand_to_ruby(nil)).to eq("nil")
      expect(converter.condition_operand_to_ruby("")).to eq("nil")
    end

    it "emits JSON booleans as Ruby literals, not quoted strings" do
      expect(converter.condition_operand_to_ruby(true)).to eq("true")
      expect(converter.condition_operand_to_ruby(false)).to eq("false")
    end

    it "still quotes the text true/false/null" do
      expect(converter.condition_operand_to_ruby("true")).to eq('"true"')
      expect(converter.condition_operand_to_ruby("false")).to eq('"false"')
      expect(converter.condition_operand_to_ruby("null")).to eq('"null"')
    end
  end

  it "accepts bracket ctx references" do
    expect(converter.condition_operand_to_ruby("ctx[:orders]")).to eq("ctx[:orders]")
  end

  it "accepts string-key bracket ctx references" do
    expect(converter.condition_operand_to_ruby('ctx["orders"]')).to eq("ctx[:orders]")
    expect(converter.condition_operand_to_ruby("ctx['orders']")).to eq("ctx[:orders]")
  end

  it "quotes unsafe ctx[system(...)] forms without splicing them" do
    expect(converter.condition_operand_to_ruby('ctx[system("id")]')).to eq('ctx[system("id")]'.inspect)
  end

end
