# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::TranscribeJob do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }

  before { Current.customer = customer }

  it "sets Current.customer from the clip and calls Transcribe" do
    clip = create(:speech_to_text_clip, :with_audio, customer: customer, user: user)
    expect(SpeechToText::Activities::Transcribe).to receive(:call).with(clip: clip) do
      expect(Current.customer).to eq(customer)
    end
    described_class.new.perform(clip.id)
  end

  it "resets Current.customer after perform" do
    clip = create(:speech_to_text_clip, :with_audio, customer: customer, user: user)
    allow(SpeechToText::Activities::Transcribe).to receive(:call)
    described_class.new.perform(clip.id)
    expect(Current.customer).to be_nil
  end

  it "is a no-op when the clip is gone" do
    expect(SpeechToText::Activities::Transcribe).not_to receive(:call)
    expect { described_class.new.perform(-1) }.not_to raise_error
  end
end
