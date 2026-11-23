# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::DurationPolicy do
  let_it_be(:customer) { create(:customer) }

  let!(:feature_module) { find_or_create_ai_assistant_module! }

  before { ensure_customer_feature_module(customer, feature_module, status: :active) }

  def configure!(value)
    FeatureModules::CustomerAssignment
      .find_by!(customer: customer, feature_module: feature_module)
      .update!(configuration: { "max_duration_seconds" => value }.to_json)
  end

  describe ".max_duration_seconds" do
    it "uses the default when the tenant has configured nothing" do
      expect(described_class.max_duration_seconds(customer_id: customer.id))
        .to eq(described_class::DEFAULT_MAX_DURATION)
    end

    it "honours a configured value" do
      configure!("90")
      expect(described_class.max_duration_seconds(customer_id: customer.id)).to eq(90)
    end

    it "never exceeds the absolute ceiling" do
      configure!("999")
      expect(described_class.max_duration_seconds(customer_id: customer.id))
        .to eq(described_class::ABSOLUTE_MAX_DURATION)
    end

    it "falls back to the default for garbage and non-positive values" do
      [ "nonsense", "0", "-5", nil ].each do |value|
        configure!(value)
        expect(described_class.max_duration_seconds(customer_id: customer.id))
          .to eq(described_class::DEFAULT_MAX_DURATION), "expected fallback for #{value.inspect}"
      end
    end

    it "falls back to the default with no customer" do
      expect(described_class.max_duration_seconds(customer_id: nil))
        .to eq(described_class::DEFAULT_MAX_DURATION)
    end

    # Unreadable configuration must not block dictation, but it must not be
    # silent either: the tenant's configured cap is not being honoured.
    it "logs and falls back to the default when reading the configuration raises" do
      allow(described_class).to receive(:assignment).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:error).with(/DurationPolicy.*boom/)

      expect(described_class.max_duration_seconds(customer_id: customer.id))
        .to eq(described_class::DEFAULT_MAX_DURATION)
    end
  end

  describe ".clamp" do
    it "clamps to the absolute ceiling and defaults non-numbers" do
      expect(described_class.clamp(30)).to eq(30)
      expect(described_class.clamp(500)).to eq(described_class::ABSOLUTE_MAX_DURATION)
      expect(described_class.clamp("x")).to eq(described_class::DEFAULT_MAX_DURATION)
    end
  end
end
