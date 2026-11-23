# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::ReconcileSendActivitiesJob, type: :job do
  describe "#perform" do
    it "delegates to Emails::SendActivities::Cron::ReconcileSendActivities.call" do
      expect(Emails::SendActivities::Cron::ReconcileSendActivities).to receive(:call)
      described_class.new.perform
    end

    it "is enqueued on the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "runs the reconcile cron end-to-end when performed via perform_now" do
      customer = create(:customer)
      enable_module!("email", customer, name: "Email")
      stalled  = create(:email_send_activity, :processing, customer: customer)
      stalled.update_columns(claimed_at: 1.hour.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(stalled.id)

      expect(stalled.reload.claimed_at).to be_within(5.seconds).of(Time.current)
    end

    it "does not re-drive a stalled campaign while its Email module is disabled" do
      customer = create(:customer)
      email_module = enable_module!("email", customer, name: "Email")
      FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: email_module).update!(status: :suspended)
      stalled = create(:email_send_activity, :processing, customer: customer)
      stalled.update_columns(claimed_at: 1.hour.ago)
      claimed_at = stalled.reload.claimed_at

      expect { described_class.perform_now }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      expect(stalled.reload.claimed_at).to eq(claimed_at)
    end
  end
end
