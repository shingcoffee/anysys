require "rails_helper"

RSpec.describe FeatureModules::Payment::Registration do
  it_behaves_like "a feature module registration", key: "payment", name: "Payments"

  let(:form) { described_class.input_contract_class.new(OpenStruct.new) }

  def field(name)
    described_class.input_contract_fields.find { |f| f.name == name }
  end

  it "builds an entry path per customer" do
    customer = double(id: 42)
    expect(described_class.entry_path_for(customer)).to eq("/42/payments/checkout/start")
  end

  it "rejects a non-CNY currency in the input contract" do
    form.validate(amount: 1.00, currency: "USD", subject: "x")
    expect(form.errors[:currency]).to be_present
  end

  it "accepts CNY as the input contract currency" do
    expect(form.validate(amount: 1.00, currency: "CNY", subject: "x")).to be(true)
  end

  [0, -1, 0.001, 0.0049].each do |amount|
    it "rejects #{amount} because it does not round to a positive CNY amount" do
      expect(form.validate(amount: amount, currency: "CNY", subject: "x")).to be(false)
      expect(form.errors[:amount]).to be_present
    end
  end

  it "accepts the half-fen boundary that rounds up to one fen" do
    expect(form.validate(amount: 0.005, currency: "CNY", subject: "x")).to be(true)
  end

  [Float::INFINITY, Float::NAN].each do |amount|
    it "rejects a non-finite amount #{amount}" do
      expect(form.validate(amount: amount, currency: "CNY", subject: "x")).to be(false)
      expect(form.errors[:amount]).to be_present
    end
  end

  it "does not expose external_ref as an author-mapped input (derived from the invocation token)" do
    expect(described_class.input_contract_properties).not_to include("external_ref")
    expect(described_class.input_contract_properties).to include("amount", "currency", "subject")
  end

  it "exposes body as the only user_fillable input" do
    fillable = described_class.input_contract_fields.select(&:user_fillable?).map(&:name)
    expect(fillable).to eq(%w[body])
  end

  it "keeps money + identity fields author_only" do
    expect(field("amount").author_only?).to be(true)
    expect(field("currency").author_only?).to be(true)
    expect(field("subject").author_only?).to be(true)
  end
end
