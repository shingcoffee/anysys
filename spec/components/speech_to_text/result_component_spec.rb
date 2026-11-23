# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::ResultComponent, type: :component do
  def render_result(**opts)
    render_inline(described_class.new(
      clip_id: "clip-1",
      field_id: "field_name",
      status: "succeeded",
      transcript: "hello",
      error: nil,
      **opts
    ))
  end

  it "renders a hidden node with the clip id and result controller" do
    render_result
    expect(page).to have_css("#speech_to_text_result_clip-1[data-controller='speech-to-text-result']")
    expect(page).to have_css("[data-speech-to-text-result-field-id-value='field_name']")
    expect(page).to have_css("[data-speech-to-text-result-status-value='succeeded']")
    expect(page).to have_css("[data-speech-to-text-result-transcript-value='hello']")
  end

  it "passes a failed status and error without a transcript" do
    render_result(status: "failed", transcript: nil, error: "vendor_down")
    expect(page).to have_css("[data-speech-to-text-result-status-value='failed']")
    expect(page).to have_css("[data-speech-to-text-result-error-value='vendor_down']")
    expect(page).to have_css("[data-speech-to-text-result-transcript-value='']")
  end

  it "exposes #dom_id from the clip id" do
    component = described_class.new(clip_id: "abc", field_id: "f", status: "pending")
    expect(component.dom_id).to eq("speech_to_text_result_abc")
  end
end
