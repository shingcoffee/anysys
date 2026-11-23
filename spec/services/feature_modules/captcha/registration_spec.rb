# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Captcha::Registration do
  it_behaves_like "a feature module registration",
                  key: "captcha", name: "Captcha", inactive: true, required: false

  describe ".sidebar_contributions" do
    it "exposes the customer settings link" do
      contributions = described_class.sidebar_contributions(double("controller"))
      labels = contributions[:settings].map(&:label)
      expect(labels).to include("Captcha")
    end
  end
end
