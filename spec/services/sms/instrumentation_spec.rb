# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Instrumentation do
  describe "#log" do
    def event(outcome:, provider: "aliyun", duration: 0.123)
      ActiveSupport::Notifications::Event.new(
        "sms.send", Time.current, Time.current + duration.to_f, "id",
        outcome: outcome, provider: provider, duration: duration
      )
    end

    it "logs at info level for a 'sent' outcome" do
      expect(Rails.logger).to receive(:info).with(/outcome=sent provider=aliyun/)
      described_class.new.log(event(outcome: "sent"))
    end

    it "logs at info level for a 'suppressed' outcome" do
      expect(Rails.logger).to receive(:info).with(/outcome=suppressed/)
      described_class.new.log(event(outcome: "suppressed"))
    end

    it "logs at warn level for a 'failed' outcome" do
      expect(Rails.logger).to receive(:warn).with(/outcome=failed/)
      described_class.new.log(event(outcome: "failed"))
    end

    it "logs at warn level for a 'transport_error' outcome" do
      expect(Rails.logger).to receive(:warn).with(/outcome=transport_error/)
      described_class.new.log(event(outcome: "transport_error"))
    end

    it "renders the duration in milliseconds when present" do
      expect(Rails.logger).to receive(:info).with(/duration=123\.0ms/)
      described_class.new.log(event(outcome: "sent", duration: 0.123))
    end

    it "renders '-' for the duration when absent (e.g. failed/suppressed paths)" do
      expect(Rails.logger).to receive(:warn).with(/duration=-/)
      described_class.new.log(event(outcome: "failed", duration: nil))
    end

    it "renders '-' for the provider when absent (e.g. suppressed with no resolved vendor)" do
      expect(Rails.logger).to receive(:info).with(/provider=-/)
      described_class.new.log(event(outcome: "suppressed", provider: nil))
    end
  end

  describe ".subscribe!" do
    it "subscribes a listener on the sms.send notification that logs the outcome" do
      # The app initializer already calls .subscribe! once at boot; calling it
      # again here (as the method itself allows) must not raise, and the
      # notification must still be logged (possibly by more than one
      # subscriber, hence at_least(:once) rather than a strict count).
      allow(Rails.logger).to receive(:info)
      described_class.subscribe!

      ActiveSupport::Notifications.instrument("sms.send", outcome: "sent", provider: "aliyun", duration: 0.01)

      expect(Rails.logger).to have_received(:info).with(/outcome=sent/).at_least(:once)
    end
  end
end
