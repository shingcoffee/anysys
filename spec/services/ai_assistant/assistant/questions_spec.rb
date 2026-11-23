# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Questions do
  describe ".sanitize" do
    def sanitize(raw)
      described_class.sanitize(raw)
    end

    def item(**overrides)
      {
        "prompt" => "Which stages does your pipeline use?",
        "type" => "multiple",
        "options" => %w[Qualification Proposal],
        "default" => %w[Qualification]
      }.merge(overrides)
    end

    it "returns an empty array unless the input is an Array" do
      expect(sanitize(nil)).to eq([])
      expect(sanitize("nope")).to eq([])
      expect(sanitize({ "prompt" => "Which?" })).to eq([])
    end

    it "drops non-Hash items and items whose prompt is missing or blank" do
      expect(sanitize([nil, "x", [], { "prompt" => "  " }, { "prompt" => 1 }])).to eq([])
    end

    it "squishes the prompt, truncates it to MAX_PROMPT_LENGTH with an ellipsis, and keeps a prompt at the limit" do
      long = "A" * (described_class::MAX_PROMPT_LENGTH + 1)
      exact = "B" * described_class::MAX_PROMPT_LENGTH
      rows = sanitize([item("prompt" => "  Which   stages?  "), item("prompt" => long), item("prompt" => exact)])

      expect(rows[0]["prompt"]).to eq("Which stages?")
      expect(rows[1]["prompt"]).to eq("#{"A" * (described_class::MAX_PROMPT_LENGTH - 1)}…")
      expect(rows[1]["prompt"].length).to eq(described_class::MAX_PROMPT_LENGTH)
      expect(rows[2]["prompt"]).to eq(exact)
    end

    it "keeps only String options, squishes them, drops blanks and over-long labels, and de-duplicates case-insensitively" do
      rows = sanitize([
        item(
          "options" => [
            "  Qualification  ",
            "",
            12,
            nil,
            "qualification",
            "Proposal",
            "X" * (described_class::MAX_OPTION_LENGTH + 1),
            "Y" * described_class::MAX_OPTION_LENGTH
          ]
        )
      ])

      expect(rows[0]["options"]).to eq(["Qualification", "Proposal", "Y" * described_class::MAX_OPTION_LENGTH])
    end

    it "keeps the first MAX_OPTIONS unique option spellings" do
      options = (1..described_class::MAX_OPTIONS + 2).map { |n| "Option #{n}" }
      rows = sanitize([item("options" => options)])

      expect(rows[0]["options"]).to eq(options.first(described_class::MAX_OPTIONS))
    end

    it "infers type single when the type is missing or unknown and at least two options remain" do
      rows = sanitize([
        item("type" => nil),
        item("type" => "choice"),
        item("type" => :single)
      ])

      expect(rows.map { |row| row["type"] }).to eq(%w[single single single])
    end

    it "infers type text when the type is missing or unknown and fewer than two options remain" do
      rows = sanitize([
        item("type" => nil, "options" => ["Only"], "default" => nil),
        item("type" => "choice", "options" => [], "default" => "Hours")
      ])

      expect(rows[0]).to include("type" => "text", "options" => [], "default" => nil)
      expect(rows[1]).to include("type" => "text", "options" => [], "default" => "Hours")
    end

    it "demotes single and multiple to text when fewer than two options remain, using the leftover option as the text default when none was usable" do
      rows = sanitize([
        item("type" => "single", "options" => ["Link to Account"], "default" => nil),
        item("type" => "multiple", "options" => ["Only"], "default" => ["Nope"]),
        item("type" => "single", "options" => ["Link to Account"], "default" => "  Store as text  "),
        item("type" => "multiple", "options" => [], "default" => nil)
      ])

      expect(rows[0]).to include("type" => "text", "options" => [], "default" => "Link to Account")
      expect(rows[1]).to include("type" => "text", "options" => [], "default" => "Only")
      expect(rows[2]).to include("type" => "text", "options" => [], "default" => "Store as text")
      expect(rows[3]).to include("type" => "text", "options" => [], "default" => nil)
    end

    it "resolves a single default to the canonical option, else nil" do
      rows = sanitize([
        item("type" => "single", "options" => ["Link to Account", "Store as text"], "default" => "  link to account  "),
        item("type" => "single", "options" => ["Link to Account", "Store as text"], "default" => "Neither"),
        item("type" => "single", "options" => ["Link to Account", "Store as text"], "default" => ["Link to Account"])
      ])

      expect(rows.map { |row| row["default"] }).to eq(["Link to Account", nil, nil])
    end

    it "resolves a multiple default from an array or a bare string, filtered to canonical options and de-duplicated" do
      options = ["Qualification", "Proposal", "Negotiation"]
      rows = sanitize([
        item("options" => options, "default" => ["  proposal  ", "Qualification", "proposal", "Missing"]),
        item("options" => options, "default" => "negotiation"),
        item("options" => options, "default" => "Missing"),
        item("options" => options, "default" => { "Qualification" => true }),
        item("options" => options, "default" => nil)
      ])

      expect(rows[0]["default"]).to eq(%w[Proposal Qualification])
      expect(rows[1]["default"]).to eq(%w[Negotiation])
      expect(rows[2]["default"]).to eq([])
      expect(rows[3]["default"]).to eq([])
      expect(rows[4]["default"]).to eq([])
    end

    it "squishes and truncates a text default, and drops a blank or non-String one" do
      long = "C" * (described_class::MAX_TEXT_DEFAULT_LENGTH + 1)
      rows = sanitize([
        item("type" => "text", "options" => [], "default" => "  Mon–Sat 8:00–18:00  "),
        item("type" => "text", "options" => ["ignored"], "default" => long),
        item("type" => "text", "options" => [], "default" => "  "),
        item("type" => "text", "options" => [], "default" => 12)
      ])

      expect(rows[0]).to include("type" => "text", "options" => [], "default" => "Mon–Sat 8:00–18:00")
      expect(rows[1]["default"]).to eq("#{"C" * (described_class::MAX_TEXT_DEFAULT_LENGTH - 1)}…")
      expect(rows[2]["default"]).to be_nil
      expect(rows[3]["default"]).to be_nil
    end

    it "keeps the first MAX_QUESTIONS valid items and assigns ids after filtering" do
      rows = sanitize(
        [{ "prompt" => "" }] + (1..described_class::MAX_QUESTIONS + 2).map { |n| item("prompt" => "Question #{n}") }
      )

      expect(rows.map { |row| row["id"] }).to eq(%w[q1 q2 q3 q4 q5])
      expect(rows.map { |row| row["prompt"] }).to eq((1..5).map { |n| "Question #{n}" })
    end

    it "emits string keys in stable order and never raises on junk input" do
      rows = sanitize([item])

      expect(rows.first.keys).to eq(%w[id prompt type options default])
      expect { sanitize([Object.new, { "prompt" => "Q", "options" => Object.new }]) }.not_to raise_error
      expect(sanitize([Object.new])).to eq([])
    end
  end

  describe ".sanitize_assumptions" do
    def sanitize(raw)
      described_class.sanitize_assumptions(raw)
    end

    it "wraps a bare String, squishes, drops blanks and non-strings, truncates, and de-duplicates case-insensitively" do
      long = "D" * (described_class::MAX_ASSUMPTION_LENGTH + 1)

      expect(sanitize("  Amount is in your reporting currency.  ")).to eq(["Amount is in your reporting currency."])
      expect(sanitize([
        "  Amount is in your reporting currency.  ",
        "amount is in your reporting currency.",
        "",
        12,
        long,
        "Keep this one."
      ])).to eq([
        "Amount is in your reporting currency.",
        "#{"D" * (described_class::MAX_ASSUMPTION_LENGTH - 1)}…",
        "Keep this one."
      ])
    end

    it "keeps the first MAX_ASSUMPTIONS unique values and returns [] for anything else" do
      values = (1..described_class::MAX_ASSUMPTIONS + 2).map { |n| "Assumption #{n}" }

      expect(sanitize(values)).to eq(values.first(described_class::MAX_ASSUMPTIONS))
      expect(sanitize(nil)).to eq([])
      expect(sanitize({ "a" => "b" })).to eq([])
      expect { sanitize(Object.new) }.not_to raise_error
    end
  end
end
