# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Instrumentation do
  describe ".subscribe!" do
    it "registers a subscriber on the 'captcha.verify' notification" do
      expect(ActiveSupport::Notifications).to receive(:subscribe).with("captcha.verify")
      described_class.subscribe!
    end

    it "wires the subscription block to build an Event and call #log on a new instance" do
      captured = nil
      allow(ActiveSupport::Notifications).to receive(:subscribe) do |name, &block|
        expect(name).to eq("captcha.verify")
        captured = block
      end
      described_class.subscribe!

      instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(instance)
      expect(instance).to receive(:log).with(instance_of(ActiveSupport::Notifications::Event))

      captured.call("captcha.verify", Time.current, Time.current, "id", { outcome: :success, provider: "aliyun" })
    end
  end

  describe "#log" do
    def build_event(payload)
      ActiveSupport::Notifications::Event.new("captcha.verify", Time.current, Time.current, "id", payload)
    end

    it "logs at info level for a :success outcome" do
      event = build_event(outcome: :success, provider: "aliyun", http_status: 200, score: nil, duration: 0.123)
      expect(Rails.logger).to receive(:info).with(a_string_matching(/outcome=success provider=aliyun http_status=200 score=- duration=123\.0ms/))
      described_class.new.log(event)
    end

    it "logs at warn level for a non-:success outcome" do
      event = build_event(outcome: :invalid, provider: "aliyun", http_status: 200, score: nil, duration: 0.05)
      expect(Rails.logger).to receive(:warn).with(a_string_matching(/outcome=invalid/))
      described_class.new.log(event)
    end

    it "renders a present score in the message" do
      event = build_event(outcome: :success, provider: "turnstile", http_status: 200, score: 0.87, duration: 0.02)
      expect(Rails.logger).to receive(:info).with(a_string_matching(/score=0\.87/))
      described_class.new.log(event)
    end

    it "renders '-' for a nil http_status" do
      event = build_event(outcome: :unreachable, provider: "aliyun", http_status: nil, score: nil, duration: 2.0)
      expect(Rails.logger).to receive(:warn).with(a_string_matching(/http_status=-/))
      described_class.new.log(event)
    end

    it "falls back to the event's own #duration when payload[:duration] is absent" do
      event = ActiveSupport::Notifications::Event.new(
        "captcha.verify", Time.current, Time.current + 0.05, "id",
        { outcome: :success, provider: "aliyun", http_status: 200, score: nil }
      )
      expect(Rails.logger).to receive(:info).with(a_string_matching(/duration=\d+(\.\d+)?ms/))
      described_class.new.log(event)
    end
  end
end
