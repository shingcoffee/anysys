# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::RulesEngine do
  def calculation(target, formula)
    { "target_field_id" => target, "formula" => formula }
  end

  it "orders reverse-declared dependencies and ignores forged intermediates" do
    engine = described_class.new("calculations" => [calculation("final", "{subtotal} + 1"), calculation("subtotal", "{quantity} * 2")])
    expect(engine.apply({ "quantity" => "3", "subtotal" => "999", "final" => "999" }))
      .to eq("quantity" => "3", "subtotal" => 6.0, "final" => 7.0)
  end

  it "drops cycles and their dependents while evaluating independent targets" do
    engine = described_class.new("calculations" => [
      calculation("a", "{b} + 1"), calculation("b", "{a} + 1"),
      calculation("downstream", "SUM({a}, 1)"), calculation("independent", "2 + 3")
    ])
    expect(engine.apply({ "a" => "999", "b" => "999", "downstream" => "999" }))
      .to eq("independent" => 5.0)
  end

  it "drops forged targets even when the formula is blank, malformed or duplicated" do
    engine = described_class.new("calculations" => [
      calculation("blank", ""), calculation("bad", "UNKNOWN()"), calculation("duplicate", "1"), calculation("duplicate", "2")
    ])
    expect(engine.apply({ "blank" => "999", "bad" => "999", "duplicate" => "999" })).to eq({})
  end

  it "uses recomputed values for visibility rules" do
    engine = described_class.new(
      "calculations" => [calculation("total", "{quantity} * 2")],
      "rules" => [{ "conditions" => { "groups" => [{ "items" => [
        { "field_id" => "total", "operator" => "greater_than", "value" => "10" }
      ] }] }, "actions" => [{ "type" => "show_field", "target_id" => "details" }] }]
    )
    expect(engine.apply({ "quantity" => "1", "total" => "999", "details" => "forged" }))
      .to eq("quantity" => "1", "total" => 2.0)
  end

  it "recomputes downstream values after hidden inputs are removed" do
    engine = described_class.new("calculations" => [calculation("total", "{secret} * 2")],
      "rules" => [{ "actions" => [{ "type" => "hide_field", "target_id" => "secret" }] }])
    expect(engine.apply({ "secret" => "99", "total" => "999" })).to eq({})
  end

  it "maps field ids recursively and keeps same-named namespace fields distinct" do
    engine = described_class.new("pages" => [{ "fields" => [{ "field_type" => "columns", "columns" => [{ "fields" => [
      { "id" => "primary", "property_slug" => "score" },
      { "id" => "bridge", "property_slug" => "score", "source" => "bridge", "source_section" => "Enrollment" },
      { "id" => "total", "property_slug" => "total" }
    ] }] }] }], "calculations" => [calculation("total", "{primary} + {bridge}")])
    expect(engine.evaluate_calculations({ "score" => "2", "assoc.enrollment.score" => "3" })).to eq("total" => 5.0)
  end

  it "drops forged targets under both their field id and property slug" do
    engine = described_class.new("pages" => [{ "fields" => [{ "id" => "field_total", "property_slug" => "total" }] }],
      "calculations" => [calculation("field_total", "{missing}")])
    expect(engine.apply({ "field_total" => "999", "total" => "999" })).to eq({})
  end
end
