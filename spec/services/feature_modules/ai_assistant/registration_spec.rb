# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::AiAssistant::Registration do
  it_behaves_like "a feature module registration",
                  key: "ai_assistant", name: "AI Assistant",
                  inactive: true, required: false

  describe ".configuration_schema" do
    subject(:schema) { described_class.configuration_schema }

    it "includes language select with auto/en/zh-CN defaulting to auto" do
      expect(schema["language"]).to include(
        "type" => "select",
        "options" => %w[auto en zh-CN],
        "default" => "auto"
      )
    end

    it "includes max_duration_seconds number defaulting to 60" do
      expect(schema["max_duration_seconds"]).to include("type" => "number", "default" => 60)
    end

    it "does not freeze I18n inside the schema" do
      dumped = schema.to_json
      expect(dumped).not_to include("Dictate")
    end
  end

  it "exposes configuration_keys for the generic settings page" do
    expect(described_class.configuration_keys).to match_array(%i[language max_duration_seconds])
  end

  describe ".sidebar_contributions" do
    it "exposes settings only and no entries" do
      contributions = described_class.sidebar_contributions(double("controller"))
      expect(contributions[:entries]).to eq([])
      expect(contributions[:settings].map(&:label)).to include("AI Assistant")
    end
  end

  describe "handoff DSL" do
    let(:customer) { instance_double(Customer, id: 11) }

    it "points entry_path at the admin assistant" do
      expect(described_class.entry_path_for(customer)).to eq("/11/admin/assistant")
    end

    it "declares a default_exit of customer_home" do
      expect(described_class.default_exit_config).to eq(kind: "route", name: "customer_home")
    end

    it "provision! is a no-op" do
      expect(described_class.provision!(customer)).to be_nil
    end
  end
end
