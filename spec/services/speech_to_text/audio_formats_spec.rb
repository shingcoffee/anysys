# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::AudioFormats do
  describe ".permitted_mime?" do
    it "accepts the types the dictate widget and desktop client produce" do
      %w[audio/webm audio/ogg audio/wav audio/mpeg audio/mp4 audio/m4a audio/aac audio/flac audio/amr]
        .each { |mime| expect(described_class.permitted_mime?(mime)).to eq(true), "expected #{mime}" }
    end

    it "strips MediaRecorder codec parameters before matching" do
      expect(described_class.permitted_mime?("audio/webm;codecs=opus")).to eq(true)
      expect(described_class.permitted_mime?("AUDIO/WEBM; codecs=opus")).to eq(true)
    end

    it "rejects non-audio and unknown audio types instead of trusting the audio/ prefix" do
      [ "text/plain", "application/octet-stream", "audio/x-not-real", "", nil ]
        .each { |mime| expect(described_class.permitted_mime?(mime)).to eq(false), "expected #{mime.inspect}" }
    end
  end

  describe ".vendor_format" do
    it "keeps the format tokens the Aliyun Flash Recognizer expects" do
      expect(described_class.vendor_format(:aliyun, filename: "clip.wav", content_type: "audio/wav")).to eq("wav")
      expect(described_class.vendor_format(:aliyun, filename: "clip.webm", content_type: "audio/webm")).to eq("opus")
      expect(described_class.vendor_format(:aliyun, filename: "clip.m4a", content_type: "audio/x-m4a")).to eq("mp4")
      expect(described_class.vendor_format(:aliyun, filename: "clip.mp3", content_type: "audio/mpeg")).to eq("mp3")
    end

    it "keeps the MediaFormat tokens AWS Transcribe expects" do
      expect(described_class.vendor_format(:aws, filename: "clip.webm", content_type: "audio/webm")).to eq("webm")
      expect(described_class.vendor_format(:aws, filename: "clip.flac", content_type: "audio/flac")).to eq("flac")
      expect(described_class.vendor_format(:aws, filename: "clip.m4a", content_type: "audio/x-m4a")).to eq("m4a")
    end

    it "keeps the Converse audio format tokens AWS Bedrock Nova accepts" do
      expect(described_class.vendor_format(:bedrock, filename: "clip.wav", content_type: "audio/wav")).to eq("wav")
      expect(described_class.vendor_format(:bedrock, filename: "clip.mp3", content_type: "audio/mpeg")).to eq("mp3")
      expect(described_class.vendor_format(:bedrock, filename: "clip.ogg", content_type: "audio/ogg")).to eq("ogg")
      expect(described_class.vendor_format(:bedrock, filename: "clip.aac", content_type: "audio/aac")).to eq("aac")
      expect(described_class.vendor_format(:bedrock, filename: "clip.flac", content_type: "audio/flac")).to eq("flac")
      expect(described_class.vendor_format(:bedrock, filename: "clip.mp4", content_type: "audio/mp4")).to eq("mp4")
      expect(described_class.vendor_format(:bedrock, filename: "clip.m4a", content_type: "audio/x-m4a")).to eq("mp4")
      expect(described_class.vendor_format(:bedrock, filename: "clip.webm", content_type: "audio/webm")).to eq(nil)
      expect(described_class.vendor_format(:bedrock, filename: "clip.amr", content_type: "audio/amr")).to eq(nil)
    end

    it "prefers the extension over a mismatched Content-Type" do
      expect(described_class.vendor_format(:aws, filename: "clip.wav", content_type: "audio/webm")).to eq("wav")
    end

    it "falls back to the MIME type when there is no usable extension" do
      expect(described_class.vendor_format(:aws, filename: "clip", content_type: "audio/ogg")).to eq("ogg")
    end

    it "returns the caller's default for unrecognised input" do
      expect(described_class.vendor_format(:aws, filename: "x.txt", content_type: "text/plain", default: "webm"))
        .to eq("webm")
    end
  end

  describe ".max_bytes_for" do
    it "uses a compressed worst-case bitrate for codec containers" do
      expect(described_class.max_bytes_for(60, filename: "clip.webm", content_type: "audio/webm"))
        .to eq(60 * described_class::COMPRESSED_BYTES_PER_SECOND)
    end

    it "allows a much larger ceiling for uncompressed containers" do
      expect(described_class.max_bytes_for(60, filename: "clip.wav", content_type: "audio/wav"))
        .to eq(60 * described_class::UNCOMPRESSED_BYTES_PER_SECOND)
    end

    it "scales linearly with the duration cap" do
      short = described_class.max_bytes_for(60, filename: "c.webm", content_type: "audio/webm")
      long  = described_class.max_bytes_for(120, filename: "c.webm", content_type: "audio/webm")
      expect(long).to eq(short * 2)
    end

    it "assumes the most permissive rate for an unknown family" do
      expect(described_class.bytes_per_second(filename: "x.bin", content_type: "application/octet-stream"))
        .to eq(described_class::UNCOMPRESSED_BYTES_PER_SECOND)
    end

    # Both signals are client-controlled, so a mismatched pair must not let the
    # caller buy the roomier of the two ceilings.
    it "takes the lower rate when the filename claims a rate the body does not" do
      expect(described_class.max_bytes_for(60, filename: "clip.wav", content_type: "audio/webm"))
        .to eq(60 * described_class::COMPRESSED_BYTES_PER_SECOND)
    end

    it "takes the lower rate when the content type claims a rate the filename does not" do
      expect(described_class.max_bytes_for(60, filename: "clip.webm", content_type: "audio/wav"))
        .to eq(60 * described_class::COMPRESSED_BYTES_PER_SECOND)
    end

    it "still resolves a rate when only one signal is recognisable" do
      expect(described_class.bytes_per_second(filename: "clip.webm", content_type: nil))
        .to eq(described_class::COMPRESSED_BYTES_PER_SECOND)
      expect(described_class.bytes_per_second(filename: nil, content_type: "audio/webm"))
        .to eq(described_class::COMPRESSED_BYTES_PER_SECOND)
    end

    # vendor_format must keep extension-wins: vendors key their decoder on it.
    it "does not change vendor format resolution, which still prefers the extension" do
      expect(described_class.vendor_format(:aliyun, filename: "clip.wav", content_type: "audio/webm"))
        .to eq(described_class.vendor_format(:aliyun, filename: "clip.wav", content_type: nil))
    end
  end

  it "keeps one canonical list rather than a per-vendor table" do
    expect(described_class::MIME_TYPES).to include("audio/webm", "audio/wav")
    expect(described_class::EXTENSIONS).to include("webm", "wav", "m4a")
    expect(described_class::MIME_TYPES.uniq).to eq(described_class::MIME_TYPES)
  end
end
