# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::ReconcileMessagesJob do
  describe "#perform" do
    it "delegates to Emails::Cron::RecoverMessages.call" do
      expect(Emails::Cron::RecoverMessages).to receive(:call)
      described_class.new.perform
    end

    it "is enqueued on the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "runs the reconcile cron end-to-end when performed via perform_now" do
      customer = create(:customer)
      enable_module!("email", customer, name: "Email")
      msg = create(:email_message, customer: customer, status: "queued")
      msg.update_columns(created_at: 2.hours.ago)

      described_class.perform_now

      expect(msg.reload.status).to eq("queued")
      expect(msg.delivery_enqueued_at).to be_present
    end
  end
end
