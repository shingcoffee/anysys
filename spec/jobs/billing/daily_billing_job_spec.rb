# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::DailyBillingJob do
  describe "#perform" do
    let(:cron_classes) do
      [
        Billing::Cron::ReconcileCollections,
        Billing::Cron::RenewSubscriptions,
        Billing::Cron::CollectDueInvoices,
        Billing::Cron::Dunning,
        Billing::Cron::TrialEndingNotices,
        Billing::Cron::RevokePaymentMethods,
        Billing::Cron::DispatchNotices
      ]
    end

    before do
      cron_classes.each { |c| allow(c).to receive(:perform) }
    end

    it "coordinates reconciliation before renewal and debt expiry" do
      described_class.perform_now

      expect(cron_classes).to all(have_received(:perform).ordered)
    end

    describe "error isolation between crons" do
      before do
        allow(Billing::Cron::RenewSubscriptions).to receive(:perform).and_raise(StandardError, "renewal exploded")
        [
          Billing::Cron::CollectDueInvoices,
          Billing::Cron::Dunning,
          Billing::Cron::TrialEndingNotices
        ].each { |c| allow(c).to receive(:perform) }
      end

      it "does not propagate the error and still runs later crons" do
        expect { described_class.perform_now }.not_to raise_error
        expect(Billing::Cron::CollectDueInvoices).to have_received(:perform)
        expect(Billing::Cron::Dunning).to have_received(:perform)
        expect(Billing::Cron::TrialEndingNotices).to have_received(:perform)
      end
    end
  end
end
