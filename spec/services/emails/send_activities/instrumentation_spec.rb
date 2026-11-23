# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::Instrumentation do
  describe "#log" do
    def event(event_name:, send_activity_id: 42, recipients: nil)
      ActiveSupport::Notifications::Event.new(
        "email_send_activity.lifecycle", Time.current, Time.current, "id",
        event: event_name, send_activity_id: send_activity_id, recipients: recipients
      )
    end

    it "logs at info level for a 'started' event" do
      expect(Rails.logger).to receive(:info).with("[email_send_activity] started campaign=42 recipients=-")
      described_class.new.log(event(event_name: "started"))
    end

    it "logs at info level for a 'completed' event, including the recipients count" do
      expect(Rails.logger).to receive(:info).with("[email_send_activity] completed campaign=42 recipients=10")
      described_class.new.log(event(event_name: "completed", recipients: 10))
    end

    it "logs at warn level for a 'failed' event" do
      expect(Rails.logger).to receive(:warn).with("[email_send_activity] failed campaign=42 recipients=-")
      described_class.new.log(event(event_name: "failed"))
    end

    it "renders '-' for recipients when absent" do
      expect(Rails.logger).to receive(:info).with(/recipients=-/)
      described_class.new.log(event(event_name: "started", recipients: nil))
    end
  end

  describe ".subscribe!" do
    it "subscribes a listener on the email_send_activity.lifecycle notification that logs the event" do
      # The app initializer already calls .subscribe! once at boot; calling it
      # again here (as the method itself allows) must not raise, and the
      # notification must still be logged (possibly by more than one
      # subscriber, hence at_least(:once) rather than a strict count).
      allow(Rails.logger).to receive(:info)
      described_class.subscribe!

      ActiveSupport::Notifications.instrument("email_send_activity.lifecycle", event: "started", send_activity_id: 1, recipients: nil)

      expect(Rails.logger).to have_received(:info).with(/started/).at_least(:once)
    end

    it "logs a 'failed' event at warn level through the real subscription" do
      allow(Rails.logger).to receive(:warn)
      described_class.subscribe!

      ActiveSupport::Notifications.instrument("email_send_activity.lifecycle", event: "failed", send_activity_id: 2, recipients: nil)

      expect(Rails.logger).to have_received(:warn).with(/failed/).at_least(:once)
    end
  end
end
