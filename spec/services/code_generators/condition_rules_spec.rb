# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConditionRules do
  def group(*rows)
    { "type" => "group", "joins" => Array.new([rows.size - 1, 0].max, "AND"), "conditions" => rows }
  end

  def field_row(left: "ctx.status", operator: "==", right: "active")
    { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
  end

  def count_row(entity_id: 7, operator: ">", value: 0)
    { "kind" => "query_count", "queryConfig" => { "entityId" => entity_id }, "countOperator" => operator, "countValue" => value }
  end

  def codes(condition, **options)
    described_class.errors(condition, field: "condition", **options).map { |error| [error.field, error.code] }
  end

  it "accepts valid field and record-count rows" do
    expect(codes(group(field_row, field_row(operator: "is_true", right: ""), count_row))).to eq([])
  end

  it "leaves blank and non-Hash values to the schema" do
    [nil, "", "ctx.flag", 1].each { |value| expect(codes(value, required: true)).to eq([]) }
  end

  it "requires a group shape with a rows array" do
    expect(codes({ "leftOperand" => "ctx.a", "operator" => "is_true" })).to eq([["condition", :invalid_condition]])
    expect(codes({ "type" => "group", "conditions" => "x" })).to eq([["condition", :invalid_condition]])
  end

  it "rejects an empty group only when required" do
    expect(codes(group, required: true)).to eq([["condition", :empty_condition]])
    expect(codes(group)).to eq([])
  end

  it "reports each invalid row with its position" do
    rows = [
      "x",
      group(field_row),
      field_row(left: " "),
      field_row(operator: ""),
      field_row(operator: "~="),
      field_row(right: " "),
      field_row(operator: "matches_regex", right: "("),
      count_row(entity_id: nil),
      count_row(operator: "=")
    ]
    errors = described_class.errors(group(*rows), field: "stopWhen")
    expect(errors.map(&:code)).to eq(%i[invalid_row nested_group missing_left missing_operator unknown_operator
      missing_right invalid_regex missing_entity unknown_count_operator])
    expect(errors.map(&:field).uniq).to eq(["stopWhen"])
    expect(errors.last.message).to eq("Condition row 9 needs a count comparison")
    expect(errors[5].message).to eq("Condition row 6 needs a value for ==")
  end

  it "recognises query-count rows by kind, with symbol keys" do
    row = { kind: "query_count", queryConfig: { entityId: 3 }, countOperator: "<=" }
    expect(codes(group(row))).to eq([])
  end

  it "validates a row without kind query_count as a field row" do
    row = { conditionType: "query_count", queryConfig: { entityId: 3 }, countOperator: "<=" }
    expect(codes(group(row))).not_to be_empty
  end

  it "translates messages at call time" do
    I18n.with_locale(:"zh-CN") do
      message = described_class.errors(group(field_row(operator: "~=")), field: "condition").first.message
      expect(message).to eq("第 1 行条件的运算符无效")
    end
  end
end
