# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::AudioUpload do
  describe ".wrap" do
    it "returns the same object when already wrapped" do
      wrapped = described_class.new(nil)
      expect(described_class.wrap(wrapped)).to be(wrapped)
    end
  end

  describe "the hash shape" do
    let(:upload) do
      described_class.new(io: StringIO.new("bytes"), filename: "clip.webm", content_type: "audio/webm")
    end

    it "reads io, filename, content_type and byte_size" do
      expect(upload).to be_present
      expect(upload.filename).to eq("clip.webm")
      expect(upload.content_type).to eq("audio/webm")
      expect(upload.byte_size).to eq(5)
    end

    it "accepts string keys" do
      upload = described_class.new("io" => StringIO.new("x"), "filename" => "a.wav", "content_type" => "audio/wav")
      expect(upload.filename).to eq("a.wav")
      expect(upload.content_type).to eq("audio/wav")
    end
  end

  describe "an uploaded file" do
    it "reads the Rack metadata and attaches the file directly" do
      upload = described_class.new(audio_upload)
      expect(upload.content_type).to eq("audio/webm")
      expect(upload.filename).to end_with(".webm")
      expect(upload.byte_size).to eq(File.size(UploadHelpers::AUDIO_FIXTURE))
    end
  end

  describe "a bare IO" do
    it "exposes the IO with no filename and no declared type" do
      upload = described_class.new(StringIO.new("bytes"))
      expect(upload.io).to be_a(StringIO)
      expect(upload.filename).to be_nil
      expect(upload.content_type).to be_nil
    end
  end

  # Callers must be able to distinguish "unknown" from "fine", so unknown reads
  # return nil rather than a permissive default.
  describe "unknown metadata" do
    it "reports a blank source as blank" do
      expect(described_class.new(nil)).to be_blank
      expect(described_class.new(nil).byte_size).to be_nil
    end

    it "returns nil content_type when the client sent none" do
      upload = described_class.new(io: StringIO.new("x"), filename: "clip.webm", content_type: nil)
      expect(upload.content_type).to be_nil
    end

    it "returns nil content_type when the client sent whitespace" do
      upload = described_class.new(io: StringIO.new("x"), filename: "clip.webm", content_type: "  ")
      expect(upload.content_type).to be_nil
    end

    it "returns nil byte_size when the IO cannot report a length" do
      io = Object.new
      def io.present? = true
      def io.blank? = false

      expect(described_class.new(io: io, filename: "clip.webm", content_type: "audio/webm").byte_size).to be_nil
    end

    it "falls back to byte_size for an object exposing only that" do
      io = double("blob", present?: true, blank?: false, byte_size: 99)
      allow(io).to receive(:respond_to?).with(:size).and_return(false)
      allow(io).to receive(:respond_to?).with(:byte_size).and_return(true)
      expect(described_class.new(io: io, filename: "a.wav", content_type: "audio/wav").byte_size).to eq(99)
    end
  end

  describe "#attach_to" do
    let_it_be(:customer) { create(:customer) }
    let_it_be(:user) { create(:user, customer: customer) }

    before { Current.customer = customer }

    it "attaches an uploaded file" do
      clip = create(:speech_to_text_clip, customer: customer, user: user)
      described_class.new(audio_upload).attach_to(clip.audio)
      expect(clip.reload.audio).to be_attached
      expect(clip.audio.content_type).to eq("audio/webm")
    end

    it "attaches a hash payload with its declared filename and type" do
      clip = create(:speech_to_text_clip, customer: customer, user: user)
      described_class.new(io: StringIO.new("bytes"), filename: "note.wav", content_type: "audio/wav")
                     .attach_to(clip.audio)
      expect(clip.reload.audio.filename.to_s).to eq("note.wav")
      expect(clip.audio.content_type).to eq("audio/wav")
    end

    it "names an unnamed IO with the fallback filename" do
      clip = create(:speech_to_text_clip, customer: customer, user: user)
      described_class.new(io: StringIO.new("bytes"), content_type: "audio/webm").attach_to(clip.audio)
      expect(clip.reload.audio.filename.to_s).to eq(described_class::FALLBACK_FILENAME)
    end
  end
end
