# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe FeatureModules::HandoffCompletion do
  # A self-contained stub registration: amount is author_only+required, body is
  # optional user_fillable, tier is a user_fillable enum (to exercise casting).
  let(:fields) do
    [
      FeatureModules::HandoffField.new(name: "amount_cents", validates: { presence: true, numericality: { only_integer: true } }, type: "integer", source: "author_only"),
      FeatureModules::HandoffField.new(name: "body", validates: {}, type: "string", source: "user_fillable"),
      FeatureModules::HandoffField.new(name: "tier", validates: { inclusion: { in: %w[BASIC PRO] } }, type: "string", source: "user_fillable")
    ]
  end

  let(:contract_class) do
    Class.new(Reform::Form) do
      property :amount_cents
      property :body
      property :tier
      validates :amount_cents, presence: true, numericality: { only_integer: true }
      validates :tier, inclusion: { in: %w[BASIC PRO] }, allow_nil: true
    end
  end

  let(:registration) { double(input_contract_fields: fields, input_contract_class: contract_class) }
  let(:invocation)   { { module_key: "stub", input: { amount_cents: 2500 } }.with_indifferent_access }

  describe ".needs_completion?" do
    it "is true when any field is user_fillable" do
      expect(described_class.needs_completion?(registration)).to be(true)
    end

    it "is false when every field is author_only" do
      only_author = double(input_contract_fields: [fields.first], input_contract_class: contract_class)
      expect(described_class.needs_completion?(only_author)).to be(false)
    end
  end

  describe ".complete!" do
    it "merges casted user_fillable values over the invocation input" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "body" => "thanks", "tier" => "pro" }, registration: registration)
      expect(result).to be_ok
      expect(result.input).to include(amount_cents: 2500, body: "thanks", tier: "PRO") # enum case-normalized
    end

    it "drops author_only and unknown keys (mass-assignment guard)" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "amount_cents" => "1", "evil" => "x", "body" => "ok" }, registration: registration)
      expect(result).to be_ok
      expect(result.input[:amount_cents]).to eq(2500) # NOT 1
      expect(result.input).not_to have_key(:evil)
    end

    it "returns errors and no input when the merged result is invalid" do
      result = described_class.complete!(session: {}, invocation: invocation,
                                         user_params: { "tier" => "GOLD" }, registration: registration)
      expect(result).not_to be_ok
      expect(result.input).to be_nil
      expect(result.errors[:tier]).to be_present
    end

    it "reads unpermitted Rails params without accepting author-only keys or nested values" do
      result = described_class.complete!(session: {}, invocation: invocation,
        user_params: ActionController::Parameters.new(amount_cents: "1", body: { text: "forged" }, tier: "pro"), registration: registration)
      expect(result).to be_ok
      expect(result.input).to include(amount_cents: 2500, tier: "PRO")
      expect(result.input).not_to have_key(:body)
    end

    it "preserves mapped fillable values when the user omits them" do
      invocation[:input][:body] = "mapped"
      result = described_class.complete!(session: {}, invocation: invocation, user_params: {}, registration: registration)
      expect(result).to be_ok
      expect(result.input[:body]).to eq("mapped")
    end
  end
end
