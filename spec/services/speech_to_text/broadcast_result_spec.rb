# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::BroadcastResult do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }
  let(:clip) { create(:speech_to_text_clip, customer: customer, user: user, status: "succeeded", transcript: "A dictated title") }

  it "publishes the durable field transcript on the clip owner's stream" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [:ai_assistant, customer.id, user.id],
      hash_including(target: "speech_to_text_result_#{clip.id}", html: include("A dictated title"))
    )
    described_class.call(clip: clip)
  end

  it "keeps a terminal transcript pollable when rendering fails" do
    allow(ApplicationController).to receive(:render).and_raise(RuntimeError, "renderer down")
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
    expect { described_class.call(clip: clip) }.not_to raise_error
    expect(clip.reload).to have_attributes(status: "succeeded", transcript: "A dictated title")
  end
end
