# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::SegmentCalculator do
  def count(text, **limits) = described_class.call(text: text, **limits)

  it "counts the complete GSM default alphabet as single septets" do
    text = described_class::GSM_DEFAULT.join
    expect(count(text)).to include(encoding: :gsm7, units: text.length, segments: 1)
  end

  it "counts extensions (including form feed and euro) as two septets" do
    expect(count("\f^{}\\[~]|€")).to include(encoding: :gsm7, units: 20)
  end

  it "uses 160/153 GSM boundaries" do
    expect(count("a" * 160)[:segment_units]).to eq([160])
    expect(count("a" * 161)[:segment_units]).to eq([153, 8])
    expect(count("a" * 306)[:segments]).to eq(2)
    expect(count("a" * 307)[:segments]).to eq(3)
  end

  it "never splits the two-septet GSM escape at a multipart boundary" do
    expect(count("a" * 152 + "^" + "a" * 152)).to include(units: 306, segments: 3, segment_units: [152, 153, 1])
    expect(count("^" * 153)[:segment_units]).to eq([152, 152, 2])
  end

  it "uses UTF-16 70/67 boundaries for non-GSM text" do
    expect(count("界" * 70)).to include(encoding: :utf16, units: 70, segments: 1)
    expect(count("界" * 71)[:segment_units]).to eq([67, 4])
    expect(count("界" * 134)[:segments]).to eq(2)
  end

  it "counts astral emoji as two UTF-16 units and does not split surrogates" do
    expect(count("😀" * 35)).to include(units: 70, segments: 1)
    expect(count("😀" * 67)).to include(units: 134, segments: 3, segment_units: [66, 66, 2])
    expect(count("界" * 66 + "😀" + "界" * 66)[:segment_units]).to eq([66, 67, 1])
  end

  it "uses Unicode for non-GSM ASCII controls and does not smart-encode punctuation" do
    expect(count("\t")).to include(encoding: :utf16, units: 1)
    expect(count("\e")).to include(encoding: :utf16, units: 1)
    expect(count("“hello”")).to include(encoding: :utf16, units: 7)
  end

  it "allows provider-specific multipart capacities (152/66)" do
    expect(count("a" * 305, gsm_multipart: 152)[:segment_units]).to eq([152, 152, 1])
    expect(count("界" * 133, unicode_multipart: 66)[:segment_units]).to eq([66, 66, 1])
  end

  it "returns zero segments for empty rendered text" do
    expect(count("")).to include(units: 0, segments: 0, segment_units: [])
  end

  [nil, [], "\xFF".dup.force_encoding("UTF-8")].each do |text|
    it "rejects invalid text #{text.inspect}" do
      expect { count(text) }.to raise_error(ArgumentError)
    end
  end

  it "rejects unsupported and invalid capacity overrides" do
    expect { count("abc", unicode_multipart: 1) }.to raise_error(ArgumentError)
    expect { count("abc", gsm_single: "160") }.to raise_error(ArgumentError)
    expect { count("abc", template_code: "SMS_1") }.to raise_error(ArgumentError)
  end
end
