# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::RedriveWebhookEventsJob do
  describe "#perform" do
    it "delegates to Payments::Cron::RedriveWebhookEvents" do
      expect(Payments::Cron::RedriveWebhookEvents).to receive(:perform)

      described_class.perform_now
    end
  end
end
