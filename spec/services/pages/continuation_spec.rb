# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Continuation do
  def forge(payload, purpose: described_class::PURPOSE, expires_in: described_class::EXPIRES_IN)
    Rails.application.message_verifier(described_class::PURPOSE)
         .generate(payload, purpose: purpose, expires_in: expires_in)
  end

  describe ".sign and .verify" do
    it "round-trips action_key and sanitized prefill" do
      token = described_class.sign(action_key: "enroll", prefill: { "course" => "12", "bad-key" => "x" })

      expect(described_class.verify(token)).to eq(
        action_key: "enroll",
        prefill: { "course" => "12" }
      )
    end

    it "returns a payload with only action_key and prefill (no customer id)" do
      token = described_class.sign(action_key: "enroll", prefill: { "course" => "12" })
      payload = described_class.verify(token)

      expect(payload.keys).to contain_exactly(:action_key, :prefill)
      expect(payload).not_to have_key(:customer_id)
      expect(payload).not_to have_key("customer_id")
    end

    it "returns nil for a tampered token and does not raise" do
      token = described_class.sign(action_key: "enroll", prefill: {})

      expect { described_class.verify("#{token}x") }.not_to raise_error
      expect(described_class.verify("#{token}x")).to be_nil
    end

    it "returns nil after 3 days plus one second" do
      token = described_class.sign(action_key: "enroll", prefill: { "course" => "12" })

      travel_to(3.days.from_now + 1.second) do
        expect(described_class.verify(token)).to be_nil
      end
    end

    it "returns nil for a token signed with another purpose" do
      token = forge({ "action_key" => "enroll", "prefill" => {} }, purpose: "other")

      expect(described_class.verify(token)).to be_nil
    end

    it "returns nil for an oversized token" do
      expect(described_class.verify("x" * (described_class::MAX_TOKEN_BYTES + 1))).to be_nil
    end

    it "returns nil for garbage and non-string tokens" do
      expect(described_class.verify("%%%not-a-token")).to be_nil
      expect(described_class.verify(nil)).to be_nil
      expect(described_class.verify(123)).to be_nil
      expect(described_class.verify({})).to be_nil
    end

    it "drops invalid prefill keys and values on verify" do
      keys = (1..11).to_h { |n| [ "field_#{n}", n.to_s ] }
      token = forge({
        "action_key" => "enroll",
        "prefill" => keys.merge("course-id" => "1", "toolong" => "x" * 201, "nested" => { "a" => "b" })
      })

      expect(described_class.verify(token)).to eq(
        action_key: "enroll",
        prefill: (1..10).to_h { |n| [ "field_#{n}", n.to_s ] }
      )
    end

    it "rejects a signed payload whose action key is malformed" do
      token = forge({ "action_key" => "Enroll", "prefill" => { "course" => "12" } })

      expect(described_class.verify(token)).to be_nil
    end

    it "strips a forged customer_id from the verified payload" do
      token = forge({
        "action_key" => "enroll",
        "prefill" => { "course" => "12" },
        "customer_id" => 999
      })
      payload = described_class.verify(token)

      expect(payload.keys).to contain_exactly(:action_key, :prefill)
      expect(payload[:action_key]).to eq("enroll")
      expect(payload[:prefill]).to eq("course" => "12")
    end
  end
end
