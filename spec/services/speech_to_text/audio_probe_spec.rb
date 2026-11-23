# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpeechToText::AudioProbe do
  it "measures decoded compressed audio and rewinds the upload" do
    upload = SpeechToTextAudioFixtures.upload(duration: 2)
    seconds = described_class.call(upload: upload, max_duration: 3)

    expect(seconds).to be_within(0.001).of(2)
    expect(upload[:io].pos).to eq(0)
  end

  it "rejects 61 seconds of highly compressed silence below the request byte ceiling" do
    upload = SpeechToTextAudioFixtures.upload(duration: 61)
    expect(upload[:io].size).to be < SpeechToText::AudioFormats.max_bytes_for(
      60, filename: upload[:filename], content_type: upload[:content_type]
    )
    expect { described_class.call(upload: upload, max_duration: 60) }
      .to raise_error(described_class::TooLong)
  end

  it "rejects bytes with audio metadata but no decodable audio" do
    upload = { io: StringIO.new("not audio"), filename: "clip.webm", content_type: "audio/webm" }
    expect { described_class.call(upload: upload, max_duration: 60) }
      .to raise_error(described_class::InvalidAudio)
  end

  it "reports a controlled configuration error when the decoder is absent" do
    allow(ENV).to receive(:fetch).with("STT_FFMPEG_PATH", "ffmpeg").and_return("/missing/stt-ffmpeg")
    expect { described_class.call(upload: SpeechToTextAudioFixtures.upload, max_duration: 60) }
      .to raise_error(described_class::Unavailable)
  end
end
