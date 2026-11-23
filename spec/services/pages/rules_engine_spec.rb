# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::RulesEngine do
  let(:rules) do
    [
      {
        "enabled" => true,
        "conditions" => {
          "logic" => "all",
          "groups" => [
            {
              "logic" => "all",
              "items" => [
                { "field_id" => "employment_type", "operator" => "equals", "value" => "employed" }
              ]
            }
          ]
        },
        "actions" => [
          { "type" => "show_field", "target_id" => "employer_name" },
          { "type" => "show_field", "target_id" => "salary" }
        ]
      }
    ]
  end

  let(:calculations) do
    [
      {
        "target_field_id" => "total_cost",
        "formula" => "quantity * unit_price",
        "format" => { "type" => "currency", "decimals" => 2 }
      }
    ]
  end

  let(:config) { { "rules" => rules, "calculations" => calculations } }
  let(:engine) { described_class.new(config) }

  describe "#filter_hidden_fields" do
    context "when field should be visible" do
      it "keeps visible fields" do
        params = { "employment_type" => "employed", "employer_name" => "Acme", "salary" => "50000" }
        result = engine.filter_hidden_fields(params)
        expect(result).to include("employer_name" => "Acme", "salary" => "50000")
      end
    end

    context "when field should be hidden" do
      it "strips hidden fields" do
        params = { "employment_type" => "unemployed", "employer_name" => "Acme", "salary" => "50000" }
        result = engine.filter_hidden_fields(params)
        expect(result).not_to include("employer_name", "salary")
      end
    end

    context "with hide_field action" do
      let(:rules) do
        [
          {
            "enabled" => true,
            "conditions" => {
              "logic" => "all",
              "groups" => [
                {
                  "logic" => "all",
                  "items" => [
                    { "field_id" => "is_minor", "operator" => "equals", "value" => "true" }
                  ]
                }
              ]
            },
            "actions" => [
              { "type" => "hide_field", "target_id" => "drivers_license" }
            ]
          }
        ]
      end

      it "hides field when condition matches" do
        params = { "is_minor" => "true", "drivers_license" => "DL123" }
        result = engine.filter_hidden_fields(params)
        expect(result).not_to include("drivers_license")
      end

      it "keeps field when condition does not match" do
        params = { "is_minor" => "false", "drivers_license" => "DL123" }
        result = engine.filter_hidden_fields(params)
        expect(result).to include("drivers_license" => "DL123")
      end
    end
  end

  describe "#compute_hidden_fields" do
    it "returns set of hidden field IDs" do
      values = { "employment_type" => "unemployed" }
      hidden = engine.compute_hidden_fields(values)
      expect(hidden).to include("employer_name", "salary")
    end

    it "returns empty set when all conditions match" do
      values = { "employment_type" => "employed" }
      hidden = engine.compute_hidden_fields(values)
      expect(hidden).to be_empty
    end
  end

  describe "#evaluate_calculations" do
    it "evaluates formula and returns computed values" do
      values = { "quantity" => "5", "unit_price" => "20" }
      results = engine.evaluate_calculations(values)
      expect(results["total_cost"]).to eq(100.0)
    end

    it "applies currency format" do
      values = { "quantity" => "3", "unit_price" => "7.5" }
      results = engine.evaluate_calculations(values)
      expect(results["total_cost"]).to eq(22.5)
    end

    it "handles division by zero" do
      calcs = [{ "target_field_id" => "result", "formula" => "10 / 0" }]
      engine = described_class.new("calculations" => calcs)
      results = engine.evaluate_calculations({})
      expect(results["result"]).to eq(0.0)
    end

    it "applies percent format (the UI emits 'percent')" do
      calcs = [{ "target_field_id" => "rate", "formula" => "0.25", "format" => { "type" => "percent", "decimals" => 0 } }]
      engine = described_class.new("calculations" => calcs)
      results = engine.evaluate_calculations({})
      expect(results["rate"]).to eq(25.0)
    end
  end

  describe "formula functions in calculations" do
    it "evaluates built-in functions (not just arithmetic)" do
      calcs = [{ "target_field_id" => "out", "formula" => "ROUND(SUM(1, 2, 3) / 2, 1)" }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["out"]).to eq(3.0)
    end

    it "evaluates {field} reference tokens against submitted values" do
      calcs = [{ "target_field_id" => "total", "formula" => "{quantity} * {unit_price}" }]
      engine = described_class.new("calculations" => calcs)
      results = engine.evaluate_calculations({ "quantity" => "5", "unit_price" => "20" })
      expect(results["total"]).to eq(100.0)
    end
  end

  describe "#evaluate_calculations apply_format branches (lines 241-246)" do
    it "applies 'number' format with custom decimals" do
      calcs = [{ "target_field_id" => "result", "formula" => "1.2345",
                 "format" => { "type" => "number", "decimals" => 2 } }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["result"]).to eq(1.23)
    end

    it "applies 'number' format defaulting to 0 decimals" do
      calcs = [{ "target_field_id" => "result", "formula" => "3.7",
                 "format" => { "type" => "number" } }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["result"]).to eq(4)
    end

    it "applies 'percentage' format (line 243)" do
      calcs = [{ "target_field_id" => "rate", "formula" => "0.5",
                 "format" => { "type" => "percentage", "decimals" => 1 } }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["rate"]).to eq(50.0)
    end

    it "returns the raw value for unknown format type (else branch, line 245)" do
      calcs = [{ "target_field_id" => "val", "formula" => "42",
                 "format" => { "type" => "unknown" } }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["val"]).to eq(42.0)
    end

    it "skips calculation when result is nil" do
      calcs = [{ "target_field_id" => "out", "formula" => "{missing}" }]
      engine = described_class.new("calculations" => calcs)
      expect(engine.evaluate_calculations({})["out"]).to be_nil
    end
  end

  describe "field_id -> property_slug resolution (real saved configs)" do
    # In real configs, rules/calcs reference page field ids (field_*), while
    # submitted params are keyed by the entity property_slug.
    let(:config) do
      {
        "pages" => [
          { "fields" => [
            { "id" => "field_a", "property_slug" => "quantity" },
            { "id" => "field_b", "property_slug" => "unit_price" },
            { "id" => "field_c", "property_slug" => "total_cost" }
          ] }
        ],
        "rules" => [
          {
            "enabled" => true,
            "conditions" => { "logic" => "all", "groups" => [
              { "logic" => "all", "items" => [
                { "field_id" => "field_a", "operator" => "greater_than", "value" => "0" }
              ] }
            ] },
            "actions" => [{ "type" => "show_field", "target_id" => "field_b" }]
          }
        ],
        "calculations" => [
          { "target_field_id" => "field_c", "formula" => "{field_a} * {field_b}" }
        ]
      }
    end
    let(:engine) { described_class.new(config) }

    it "evaluates conditions against the slug-keyed submitted params" do
      expect(engine.compute_hidden_fields("quantity" => "3")).to be_empty
      expect(engine.compute_hidden_fields("quantity" => "0")).to include("unit_price")
    end

    it "strips the hidden field by its slug key" do
      result = engine.filter_hidden_fields("quantity" => "0", "unit_price" => "9.99")
      expect(result).not_to include("unit_price")
    end

    it "computes the calculation from {field_id} tokens and keys the result by slug" do
      results = engine.evaluate_calculations({ "quantity" => "4", "unit_price" => "2.5" })
      expect(results).to eq("total_cost" => 10.0)
    end
  end

  describe "#validate_submission" do
    it "returns empty errors for valid submission" do
      params = { "employment_type" => "employed", "employer_name" => "Acme" }
      errors = engine.validate_submission(params)
      expect(errors).to be_empty
    end

    it "returns errors for hidden field injection" do
      params = { "employment_type" => "unemployed", "employer_name" => "Injected" }
      errors = engine.validate_submission(params)
      expect(errors).to include(/employer_name/)
    end
  end

  describe "condition evaluation" do
    context "with various operators" do
      let(:engine) { described_class.new("rules" => [], "calculations" => []) }

      it "evaluates equals" do
        hidden = build_and_check("equals", "status", "active", { "status" => "active" })
        expect(hidden).to be_empty
      end

      it "evaluates not_equals" do
        hidden = build_and_check("not_equals", "status", "active", { "status" => "inactive" })
        expect(hidden).to be_empty
      end

      it "evaluates greater_than" do
        hidden = build_and_check("greater_than", "amount", "100", { "amount" => "150" })
        expect(hidden).to be_empty
      end

      it "evaluates less_than" do
        hidden = build_and_check("less_than", "amount", "100", { "amount" => "50" })
        expect(hidden).to be_empty
      end

      it "evaluates is_empty" do
        hidden = build_and_check("is_empty", "name", nil, { "name" => "" })
        expect(hidden).to be_empty
      end

      it "evaluates is_not_empty" do
        hidden = build_and_check("is_not_empty", "name", nil, { "name" => "Alice" })
        expect(hidden).to be_empty
      end

      it "evaluates contains" do
        hidden = build_and_check("contains", "tags", "ruby", { "tags" => "ruby,rails" })
        expect(hidden).to be_empty
      end

      it "evaluates between" do
        hidden = build_and_check("between", "score", [0, 100], { "score" => "50" })
        expect(hidden).to be_empty
      end

      # ----- additional operators added for coverage -----

      it "evaluates not_contains (line 170)" do
        hidden = build_and_check("not_contains", "bio", "spam", { "bio" => "clean text" })
        expect(hidden).to be_empty
      end

      it "evaluates starts_with (line 172)" do
        hidden = build_and_check("starts_with", "code", "AB", { "code" => "AB123" })
        expect(hidden).to be_empty
      end

      it "evaluates ends_with (line 174)" do
        hidden = build_and_check("ends_with", "code", "99", { "code" => "XY99" })
        expect(hidden).to be_empty
      end

      it "evaluates greater_or_equal — condition met (lines 182-183)" do
        hidden = build_and_check("greater_or_equal", "score", "10", { "score" => "10" })
        expect(hidden).to be_empty
      end

      it "evaluates greater_or_equal — blank field returns false (guard at 182)" do
        hidden = build_and_check("greater_or_equal", "score", "10", {})
        expect(hidden).to include("target_field")
      end

      it "evaluates less_or_equal — condition met (lines 185-186)" do
        hidden = build_and_check("less_or_equal", "score", "100", { "score" => "50" })
        expect(hidden).to be_empty
      end

      it "evaluates less_or_equal — blank field returns false" do
        hidden = build_and_check("less_or_equal", "score", "100", {})
        expect(hidden).to include("target_field")
      end

      it "evaluates between — blank field returns false (line 188)" do
        hidden = build_and_check("between", "score", [0, 100], {})
        expect(hidden).to include("target_field")
      end

      it "evaluates between — compare_value not an array returns false (line 189)" do
        hidden = build_and_check("between", "score", "50", { "score" => "50" })
        expect(hidden).to include("target_field")
      end

      it "evaluates is_selected with array field value (line 197-198)" do
        hidden = build_and_check("is_selected", "tags", "ruby", { "tags" => %w[ruby rails] })
        expect(hidden).to be_empty
      end

      it "evaluates is_selected with scalar string value (line 200)" do
        hidden = build_and_check("is_selected", "status", "active", { "status" => "active" })
        expect(hidden).to be_empty
      end

      it "evaluates is_not_selected with array field value (lines 203-204)" do
        hidden = build_and_check("is_not_selected", "tags", "java", { "tags" => %w[ruby rails] })
        expect(hidden).to be_empty
      end

      it "evaluates is_not_selected with scalar value (line 206)" do
        hidden = build_and_check("is_not_selected", "status", "inactive", { "status" => "active" })
        expect(hidden).to be_empty
      end

      it "evaluates matches_regex (line 209)" do
        hidden = build_and_check("matches_regex", "code", "^[A-Z]+$", { "code" => "ABC" })
        expect(hidden).to be_empty
      end

      it "returns false for an invalid regex without raising (RegexpError rescue, line 213)" do
        # RegexpError is rescued → evaluate_condition returns false → condition didn't match.
        # A show_field action adds the target to hidden when the condition does NOT match,
        # so target_field ends up hidden.
        expect { build_and_check("matches_regex", "code", "[invalid", { "code" => "ABC" }) }
          .not_to raise_error
        hidden = build_and_check("matches_regex", "code", "[invalid", { "code" => "ABC" })
        expect(hidden).to include("target_field")
      end

      it "returns false for an unknown operator (else branch, line 211)" do
        hidden = build_and_check("unknown_op", "field", "val", { "field" => "val" })
        expect(hidden).to include("target_field")
      end
    end

    context "evaluate_group with empty items returns true (line 146)" do
      it "treats a group with no items as always-true" do
        rules = [
          {
            "enabled" => true,
            "conditions" => {
              "logic" => "all",
              "groups" => [{ "logic" => "all", "items" => [] }]
            },
            "actions" => [{ "type" => "show_field", "target_id" => "x" }]
          }
        ]
        engine = described_class.new("rules" => rules)
        expect(engine.compute_hidden_fields({})).to be_empty
      end
    end

    context "evaluate_group with OR item logic (line 153)" do
      it "uses any? when group logic is not 'all'" do
        rules = [
          {
            "enabled" => true,
            "conditions" => {
              "logic" => "all",
              "groups" => [
                {
                  "logic" => "any",
                  "items" => [
                    { "field_id" => "a", "operator" => "equals", "value" => "1" },
                    { "field_id" => "b", "operator" => "equals", "value" => "2" }
                  ]
                }
              ]
            },
            "actions" => [{ "type" => "show_field", "target_id" => "target" }]
          }
        ]
        engine = described_class.new("rules" => rules)
        # only b matches (a != "1"), but group logic is any → condition matches
        expect(engine.compute_hidden_fields("b" => "2")).to be_empty
      end
    end

    context "with OR logic" do
      it "matches when any group matches" do
        rules = [
          {
            "enabled" => true,
            "conditions" => {
              "logic" => "any",
              "groups" => [
                {
                  "logic" => "all",
                  "items" => [
                    { "field_id" => "country", "operator" => "equals", "value" => "US" }
                  ]
                },
                {
                  "logic" => "all",
                  "items" => [
                    { "field_id" => "country", "operator" => "equals", "value" => "CA" }
                  ]
                }
              ]
            },
            "actions" => [
              { "type" => "show_field", "target_id" => "state" }
            ]
          }
        ]

        engine = described_class.new("rules" => rules)
        hidden = engine.compute_hidden_fields({ "country" => "CA" })
        expect(hidden).to be_empty
      end
    end
  end

  describe "initialization" do
    it "accepts a page-like object" do
      page = double("Page", configuration_json: config)
      engine = described_class.new(page)
      expect(engine.rules).to eq(rules)
    end

    it "handles nil config" do
      page = double("Page", configuration_json: nil)
      engine = described_class.new(page)
      expect(engine.rules).to eq([])
    end
  end

  private

  def build_and_check(operator, field_id, value, form_values)
    rules = [
      {
        "enabled" => true,
        "conditions" => {
          "logic" => "all",
          "groups" => [
            {
              "logic" => "all",
              "items" => [
                { "field_id" => field_id, "operator" => operator, "value" => value }
              ]
            }
          ]
        },
        "actions" => [
          { "type" => "show_field", "target_id" => "target_field" }
        ]
      }
    ]

    engine = described_class.new("rules" => rules)
    engine.compute_hidden_fields(form_values)
  end
end

# -----------------------------------------------------------------------
# Standalone branch-coverage spec — remaining arms not reached in the
# main describe block above
# -----------------------------------------------------------------------

RSpec.describe Pages::RulesEngine, "branch coverage additions" do
  describe "field_slug_map construction — fields with missing id or slug are skipped (line 39 :else)" do
    it "does not crash when a field is missing id or property_slug" do
      config = {
        "pages" => [{ "fields" => [
          { "id" => nil,      "property_slug" => "a" },   # id nil → skipped
          { "id" => "fid1",   "property_slug" => nil },   # slug nil → skipped
          { "id" => "fid2",   "property_slug" => "b" }    # valid
        ] }],
        "rules" => [],
        "calculations" => []
      }
      engine = described_class.new(config)
      # field_slug_map should only contain the valid mapping
      expect(engine.send(:resolve_key, "fid2")).to eq("b")
      expect(engine.send(:resolve_key, "fid1")).to eq("fid1")   # passes through unchanged
    end
  end

  describe "evaluate_calculations — blank target or formula is skipped (lines 62, 69 :then)" do
    it "skips a calculation with a blank target_field_id" do
      config = { "calculations" => [{ "target_field_id" => "", "formula" => "1 + 1" }] }
      engine = described_class.new(config)
      expect(engine.evaluate_calculations({})).to eq({})
    end

    it "skips a calculation with a blank formula" do
      config = { "calculations" => [{ "target_field_id" => "out", "formula" => "" }] }
      engine = described_class.new(config)
      expect(engine.evaluate_calculations({})).to eq({})
    end

    it "skips a calculation whose formula evaluates to nil (line 92 :then next-if result.nil?)" do
      config = { "calculations" => [{ "target_field_id" => "out", "formula" => "{missing_field}" }] }
      engine = described_class.new(config)
      expect(engine.evaluate_calculations({})).to eq({})
    end
  end

  describe "evaluate_conditions — empty conditions hash returns true (line 130 all? :then)" do
    it "evaluate_conditions returns true for empty conditions hash" do
      engine = described_class.new("rules" => [], "calculations" => [])
      # conditions is nil → returns true (line 130 :then)
      expect(engine.send(:evaluate_conditions, nil, {})).to eq(true)
    end

    it "evaluate_conditions returns true for empty groups array (line 133 :then)" do
      engine = described_class.new("rules" => [], "calculations" => [])
      expect(engine.send(:evaluate_conditions, { "groups" => [] }, {})).to eq(true)
    end
  end

  describe "resolve_key — passes through unknown ids (line 159 :else)" do
    it "returns the id unchanged when not in the slug map" do
      engine = described_class.new("rules" => [], "calculations" => [])
      expect(engine.send(:resolve_key, "unknown_id")).to eq("unknown_id")
    end
  end

  describe "formula_value_map — provides both slug and id keys (lines 176-179)" do
    it "drops a self-referencing calculated target instead of trusting the submitted value" do
      config = {
        "pages" => [{ "fields" => [
          { "id" => "field_qty", "property_slug" => "quantity" }
        ] }],
        "calculations" => [
          { "target_field_id" => "field_qty", "formula" => "{field_qty} * 2" }
        ],
        "rules" => []
      }
      engine = described_class.new(config)
      # Submitted params use slug key "quantity"
      results = engine.evaluate_calculations({ "quantity" => "5" })
      expect(results).to eq({})
    end

    it "passes through when submitted params do not include the slug key (line 178 :else — values.key? false)" do
      config = {
        "pages" => [{ "fields" => [
          { "id" => "field_x", "property_slug" => "x_field" }
        ] }],
        "calculations" => [{ "target_field_id" => "field_x", "formula" => "{field_x} + 0" }],
        "rules" => []
      }
      engine = described_class.new(config)
      # "x_field" is NOT a key in the submitted params, so the if branch does NOT fire
      # (values.key?(slug) is false)
      results = engine.evaluate_calculations({})
      expect(results).to eq({})  # formula returns nil → skipped
    end
  end

  describe "evaluate_conditions — empty hash (conditions.empty? :then — loc_line=6 arm)" do
    it "returns true when conditions is an empty hash" do
      engine = described_class.new("rules" => [], "calculations" => [])
      # conditions = {} → conditions.nil? is false, conditions.empty? is true → returns true
      expect(engine.send(:evaluate_conditions, {}, {})).to eq(true)
    end
  end

  describe "evaluate_conditions — logic 'all' with all-true results (group_results.all? :then)" do
    it "returns true when logic is 'all' and every group result is true" do
      rules = [{
        "enabled" => true,
        "conditions" => {
          "logic" => "all",
          "groups" => [
            { "logic" => "all", "items" => [
              { "field_id" => "a", "operator" => "equals", "value" => "1" }
            ] }
          ]
        },
        "actions" => [{ "type" => "hide_field", "target_id" => "tgt" }]
      }]
      engine = described_class.new("rules" => rules)
      # condition matches → group returns true → all? true → matched = true → hide_field fires
      hidden = engine.compute_hidden_fields("a" => "1")
      expect(hidden).to include("tgt")
    end
  end

  describe "evaluate_group — logic 'all' with all-true item results (item_results.all? :then)" do
    it "returns true when group logic is 'all' and every item result is true" do
      rules = [{
        "enabled" => true,
        "conditions" => {
          "logic" => "all",
          "groups" => [
            { "logic" => "all", "items" => [
              { "field_id" => "a", "operator" => "equals", "value" => "x" },
              { "field_id" => "b", "operator" => "equals", "value" => "y" }
            ] }
          ]
        },
        "actions" => [{ "type" => "hide_field", "target_id" => "tgt" }]
      }]
      engine = described_class.new("rules" => rules)
      hidden = engine.compute_hidden_fields("a" => "x", "b" => "y")
      expect(hidden).to include("tgt")
    end
  end
end
