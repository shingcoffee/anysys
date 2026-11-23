# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Instrumentation do
  describe "#log" do
    def event(outcome:, provider: "smtp")
      ActiveSupport::Notifications::Event.new(
        "email.send", Time.current, Time.current, "id",
        outcome: outcome, provider: provider, duration: nil
      )
    end

    it "logs at info level for a 'sent' outcome" do
      expect(Rails.logger).to receive(:info).with("[email] send outcome=sent provider=smtp")
      described_class.new.log(event(outcome: "sent"))
    end

    it "logs at info level for a 'suppressed' outcome" do
      expect(Rails.logger).to receive(:info).with(/outcome=suppressed/)
      described_class.new.log(event(outcome: "suppressed"))
    end

    it "logs at warn level for a 'failed' outcome" do
      expect(Rails.logger).to receive(:warn).with("[email] send outcome=failed provider=smtp")
      described_class.new.log(event(outcome: "failed"))
    end

    it "renders '-' for the provider when absent" do
      expect(Rails.logger).to receive(:info).with("[email] send outcome=sent provider=-")
      described_class.new.log(event(outcome: "sent", provider: nil))
    end
  end

  describe ".subscribe!" do
    it "subscribes a listener on the email.send notification that logs the outcome" do
      # The app initializer already calls .subscribe! once at boot; calling it
      # again here (as the method itself allows) must not raise, and the
      # notification must still be logged (possibly by more than one
      # subscriber, hence at_least(:once) rather than a strict count).
      allow(Rails.logger).to receive(:info)
      described_class.subscribe!

      ActiveSupport::Notifications.instrument("email.send", outcome: "sent", provider: "smtp", duration: nil)

      expect(Rails.logger).to have_received(:info).with(/outcome=sent/).at_least(:once)
    end
  end
end
