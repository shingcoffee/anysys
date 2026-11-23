# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::Contracts::Transcription do
  def form_for(audio:, field_dom_id: "entity_entry_title", language: "auto", destination: "field")
    described_class.new(described_class::Input.new).tap do |form|
      form.validate(audio: audio, field_dom_id: field_dom_id, language: language, destination: destination)
    end
  end

  def valid_audio
    { io: StringIO.new("fake-audio"), filename: "clip.webm", content_type: "audio/webm" }
  end

  it "is valid with audio and field_dom_id" do
    expect(form_for(audio: valid_audio).errors).to be_empty
  end

  it "accepts a parameterised MediaRecorder Content-Type" do
    audio = { io: StringIO.new("x"), filename: "dictation.webm", content_type: "audio/webm;codecs=opus" }
    expect(form_for(audio: audio).errors).to be_empty
  end

  it "adds a localized error when audio is blank" do
    form = form_for(audio: nil)
    expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_blank"))
  end

  it "adds a localized error when audio exceeds 25 MB" do
    io = instance_double(StringIO, present?: true, blank?: false, size: 25.megabytes + 1)
    form = form_for(audio: { io: io, filename: "big.webm", content_type: "audio/webm" })
    expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_too_large"))
  end

  it "adds a localized error when Content-Type is not an allowed audio type" do
    form = form_for(audio: { io: StringIO.new("x"), filename: "x.txt", content_type: "text/plain" })
    expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_content_type"))
  end

  it "adds a localized error when field_dom_id is blank" do
    form = form_for(audio: valid_audio, field_dom_id: "  ")
    expect(form.errors[:field_dom_id]).to include(I18n.t("speech_to_text.errors.field_dom_id_blank"))
  end

  # Fail-closed regression: a client that simply omitted `content_type` used to
  # skip the MIME check entirely, and an IO that reported no length used to skip
  # the 25 MB cap — either one put unvalidated bytes in front of a paid vendor.
  describe "fails closed on missing metadata" do
    it "rejects an upload with no Content-Type" do
      form = form_for(audio: { io: StringIO.new("x"), filename: "clip.webm", content_type: nil })
      expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_content_type"))
    end

    it "rejects an upload with a blank Content-Type" do
      form = form_for(audio: { io: StringIO.new("x"), filename: "clip.webm", content_type: "  " })
      expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_content_type"))
    end

    it "rejects an upload whose size cannot be determined" do
      io = Object.new
      def io.present? = true
      def io.blank? = false

      form = form_for(audio: { io: io, filename: "clip.webm", content_type: "audio/webm" })
      expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_size_unknown"))
    end

    it "rejects a non-audio type that merely starts with the audio prefix conventions" do
      form = form_for(audio: { io: StringIO.new("x"), filename: "clip.bin", content_type: "audio/x-not-real" })
      expect(form.errors[:audio]).to include(I18n.t("speech_to_text.errors.audio_content_type"))
    end
  end

  # Request-shape validation belongs in the contract, not only in the model's
  # inclusion validation, so a bad value is a 422 rather than a silent coercion.
  describe "destination" do
    it "accepts each known destination" do
      SpeechToText::Clip::DESTINATIONS.each do |value|
        expect(form_for(audio: valid_audio, destination: value).errors).to be_empty,
          "expected #{value.inspect} to be accepted"
      end
    end

    it "allows a blank destination so the enqueue activity can apply the default" do
      expect(form_for(audio: valid_audio, destination: nil).errors).to be_empty
      expect(form_for(audio: valid_audio, destination: "").errors).to be_empty
    end

    it "adds a localized error for an unknown destination" do
      form = form_for(audio: valid_audio, destination: "webhook")
      expect(form.errors[:destination]).to include(I18n.t("speech_to_text.errors.audio_destination"))
    end
  end
end
