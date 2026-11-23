# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::DailyMaintenanceJob do
  describe "#perform" do
    let(:cron_classes) do
      [
        Payments::Cron::DownloadBills,
        Payments::Cron::ReapStalePaymentMethods,
        Payments::Cron::PruneWebhookEvents
      ]
    end

    before do
      cron_classes.each { |c| allow(c).to receive(:perform) }
    end

    it "calls all crons in order" do
      described_class.perform_now

      expect(cron_classes).to all(have_received(:perform).ordered)
    end

    describe "error isolation between crons" do
      before do
        allow(Payments::Cron::DownloadBills).to receive(:perform).and_raise(StandardError, "download exploded")
        [Payments::Cron::ReapStalePaymentMethods, Payments::Cron::PruneWebhookEvents]
          .each { |c| allow(c).to receive(:perform) }
      end

      it "does not propagate the error and still runs later crons" do
        expect { described_class.perform_now }.not_to raise_error
        expect(Payments::Cron::ReapStalePaymentMethods).to have_received(:perform)
        expect(Payments::Cron::PruneWebhookEvents).to have_received(:perform)
      end
    end
  end
end
