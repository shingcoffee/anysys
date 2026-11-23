# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ChargeDueSubscriptionsJob do
  describe "#perform" do
    it "delegates to Payments::Cron::ChargeDueSubscriptions" do
      expect(Payments::Cron::ChargeDueSubscriptions).to receive(:perform)

      described_class.perform_now
    end
  end
end
