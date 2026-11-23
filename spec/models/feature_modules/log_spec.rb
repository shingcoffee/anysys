# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Log, type: :model do
  subject(:log) { build(:feature_module_log) }

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires action" do
      log.action = nil
      expect(log).not_to be_valid
    end

    it "allows a missing entity_entry" do
      log.entity_entry = nil
      expect(log).to be_valid
    end
  end

  describe "scopes" do
    let_it_be(:customer) { create(:customer) }
    let(:feature_mod) { create(:feature_module) }

    describe ".recent" do
      it "orders by created_at desc" do
        old_log = create(:feature_module_log, customer: customer, feature_module: feature_mod, created_at: 1.day.ago)
        new_log = create(:feature_module_log, customer: customer, feature_module: feature_mod, created_at: Time.current)
        expect(described_class.recent.first).to eq(new_log)
      end
    end

    describe ".failures" do
      it "returns only failure logs" do
        success_log = create(:feature_module_log, customer: customer, feature_module: feature_mod, status: :success)
        failure_log = create(:feature_module_log, :failure, customer: customer, feature_module: feature_mod)
        expect(described_class.failures).to include(failure_log)
        expect(described_class.failures).not_to include(success_log)
      end
    end
  end
end
