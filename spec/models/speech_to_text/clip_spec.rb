# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::Clip do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }

  before { Current.customer = customer }

  it "is TenantScoped" do
    expect(described_class.included_modules).to include(TenantScoped)
  end

  it "requires customer_id" do
    Current.customer = nil
    clip = described_class.new(user: user, field_dom_id: "field", status: "pending")
    expect(clip).not_to be_valid
    expect(clip.errors[:customer_id]).to be_present
  end

  it "requires field_dom_id" do
    clip = described_class.new(customer: customer, user: user, field_dom_id: "", status: "pending")
    expect(clip).not_to be_valid
    expect(clip.errors[:field_dom_id]).to be_present
  end

  it "restricts status to the pending, processing, and terminal states" do
    clip = described_class.new(customer: customer, user: user, field_dom_id: "f", status: "bogus")
    expect(clip).not_to be_valid
    expect(clip.errors[:status]).to be_present
  end

  described_class::STATUSES.each do |status|
    it "accepts status #{status}" do
      clip = described_class.new(customer: customer, user: user, field_dom_id: "f", status: status)
      expect(clip).to be_valid
    end
  end

  it "keeps field results pollable until the ephemeral clip is pruned" do
    clip = create(:speech_to_text_clip, customer: customer, user: user, status: "succeeded", transcript: "Dictated title")
    expect(clip.reload.transcript).to eq("Dictated title")
    expect(clip).to be_terminal
  end

  it "pins an assistant clip to its enqueue-time conversation" do
    conversation = create(:ai_assistant_conversation, customer: customer, user: user)
    clip = create(:speech_to_text_clip, :assistant, customer: customer, user: user, conversation: conversation)
    expect(clip.reload.conversation).to eq(conversation)
  end

  it "belongs to Authentication::User" do
    clip = create(:speech_to_text_clip, customer: customer, user: user)
    expect(clip.user).to eq(user)
  end

  it "attaches audio via Active Storage" do
    clip = create(:speech_to_text_clip, :with_audio, customer: customer, user: user)
    expect(clip.audio).to be_attached
  end

  it "defaults status to pending" do
    clip = create(:speech_to_text_clip, customer: customer, user: user)
    expect(clip.status).to eq("pending")
  end

  describe "destination" do
    it "defaults to field so a transcript fills the input it was dictated into" do
      clip = described_class.create!(customer: customer, user: user, field_dom_id: "f")
      expect(clip.destination).to eq("field")
      expect(clip.field?).to eq(true)
      expect(clip.assistant?).to eq(false)
    end

    it "restricts destination to the two known routes" do
      clip = described_class.new(customer: customer, user: user, field_dom_id: "f",
                                 status: "pending", destination: "bogus")
      expect(clip).not_to be_valid
      expect(clip.errors[:destination]).to be_present
    end

    described_class::DESTINATIONS.each do |destination|
      it "accepts destination #{destination}" do
        clip = described_class.new(customer: customer, user: user, field_dom_id: "f",
                                   status: "pending", destination: destination)
        expect(clip).to be_valid
      end
    end

    describe ".normalize_destination" do
      it "passes known destinations through" do
        expect(described_class.normalize_destination("assistant")).to eq("assistant")
        expect(described_class.normalize_destination(:field)).to eq("field")
      end

      # Failing closed to "field" keeps an untrusted value from routing a user's
      # dictation into their assistant conversation.
      it "falls back to field for blank, nil and unknown values" do
        expect(described_class.normalize_destination(nil)).to eq("field")
        expect(described_class.normalize_destination("")).to eq("field")
        expect(described_class.normalize_destination("elsewhere")).to eq("field")
      end
    end
  end
end
