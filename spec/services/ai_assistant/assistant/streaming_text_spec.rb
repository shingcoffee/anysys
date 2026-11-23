# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::StreamingText do
  def prefix
    '{"intent":"chat","reply":"'
  end

  # A document cut off mid-value, which is what every frame but the last looks
  # like. Built as a literal rather than with to_json so an example can stop it
  # inside an escape, which is the whole point.
  def document(reply)
    prefix + reply
  end

  def closed(reply)
    %(#{document(reply)}"})
  end

  def visible(raw)
    described_class.visible(raw)
  end

  describe "a complete document" do
    it "shows the reply value" do
      expect(visible(closed("Hello"))).to eq("Hello")
    end

    it "shows only the reply, never the wire fields around it" do
      raw = '{"intent":"chat","reply":"Added Student.","operation":"create_entity"}'

      expect(visible(raw)).to eq("Added Student.")
    end

    it "returns an empty string for a blank response" do
      expect(visible(nil)).to eq("")
      expect(visible("")).to eq("")
      expect(visible("   \n ")).to eq("")
    end
  end

  describe "a document that is still arriving" do
    it "shows nothing before the reply key exists" do
      expect(visible("{")).to eq("")
      expect(visible('{"intent":"ch')).to eq("")
      expect(visible('{"intent":"chat","re')).to eq("")
    end

    it "shows nothing when the reply key has arrived but its value has not" do
      expect(visible(prefix)).to eq("")
    end

    it "shows the prose written so far mid-value" do
      expect(visible(document("Hel"))).to eq("Hel")
      expect(visible(document("Hello there, I can"))).to eq("Hello there, I can")
    end

    it "stops cleanly on a truncated escape rather than showing the backslash" do
      expect(visible(document("Hi") + "\\")).to eq("Hi")
    end

    it "stops cleanly on a half-transmitted unicode escape" do
      expect(visible(document('Hi \\'))).to eq("Hi ")
      expect(visible(document('Hi \\u'))).to eq("Hi ")
      expect(visible(document('Hi \\u26'))).to eq("Hi ")
      expect(visible(document('Hi \\u26a'))).to eq("Hi ")
    end

    it "decodes a unicode escape once all four digits have arrived" do
      expect(visible(document('Hi \\u26a1'))).to eq("Hi ⚡")
    end

    it "never raises on any prefix of a document carrying escapes" do
      raw = '{"intent":"chat","reply":"Tab\\there \\u26a1 and \\ud83d\\ude00 done"}'

      (0..raw.length).each do |length|
        prefix = raw[0, length]

        expect { visible(prefix) }.not_to raise_error
        expect(visible(prefix)).to be_valid_encoding
      end
    end
  end

  describe "a fenced document" do
    it "strips a json fence" do
      expect(visible("```json\n#{closed("Hello")}")).to eq("Hello")
    end

    it "strips a bare fence" do
      expect(visible("```\n#{closed("Hello")}")).to eq("Hello")
    end

    it "shows nothing while only the fence has arrived" do
      expect(visible("```json\n")).to eq("")
    end
  end

  describe "escape decoding" do
    described_class::SIMPLE_ESCAPES.each do |marker, decoded|
      it "decodes the #{marker.inspect} escape to #{decoded.inspect}" do
        expect(visible(closed("A\\#{marker}B"))).to eq("A#{decoded}B")
      end
    end

    it "passes an unknown escape through as its own character" do
      expect(visible(closed('A\\qB'))).to eq("AqB")
    end
  end

  # Regression: a vendor escapes a non-BMP character as a UTF-16 surrogate
  # pair. Packing either half on its own produces bytes that are not valid
  # UTF-8, which made Markdown.render raise and took the whole turn down.
  describe "non-BMP characters" do
    let(:emoji_document) { '{"intent":"chat","reply":"Hi \ud83d\ude00 there"}' }

    it "recombines a surrogate pair into one character" do
      expect(visible(emoji_document)).to eq("Hi 😀 there")
    end

    it "produces valid UTF-8" do
      expect(visible(emoji_document)).to be_valid_encoding
    end

    it "produces prose Markdown can render" do
      expect { AiAssistant::Assistant::Markdown.render(visible(emoji_document)) }.not_to raise_error
      expect(AiAssistant::Assistant::Markdown.render(visible(emoji_document))).to include("😀")
    end

    it "produces prose that survives being broadcast as JSON" do
      expect { visible(emoji_document).to_json }.not_to raise_error
    end

    it "treats a high surrogate whose low half has not arrived as incomplete" do
      expect(visible('{"intent":"chat","reply":"Hi \ud83d')).to eq("Hi ")
      expect(visible('{"intent":"chat","reply":"Hi \ud83d\ud')).to eq("Hi ")
      expect(visible('{"intent":"chat","reply":"Hi \ud83d\ude')).to eq("Hi ")
    end

    it "drops an unpaired high surrogate rather than emitting invalid bytes" do
      result = visible('{"intent":"chat","reply":"\ud83dabcdefg"}')

      expect(result).to eq("abcdefg")
      expect(result).to be_valid_encoding
    end

    it "drops a high surrogate followed by a second high surrogate" do
      result = visible('{"intent":"chat","reply":"\ud83d\ud83dtail"}')

      expect(result).to eq("tail")
      expect(result).to be_valid_encoding
    end

    it "decodes a pair that arrives at the very end of the buffer" do
      expect(visible('{"intent":"chat","reply":"\ud83d\ude00')).to eq("😀")
    end
  end

  describe "a model that answered in prose instead of the wire format" do
    it "shows the prose verbatim" do
      expect(visible("Sure, pages live under Maintenance.")).to eq("Sure, pages live under Maintenance.")
    end

    it "trims surrounding whitespace" do
      expect(visible("  Hello  \n")).to eq("Hello")
    end

    # A leading brace alone is not enough to key on: prose before the document
    # would otherwise put the whole wire object on screen.
    it "shows only the reply when prose precedes the document" do
      result = visible('Sure! {"intent":"chat","reply":"Hi"}')

      expect(result).to eq("Hi")
      expect(result).not_to include("intent")
      expect(result).not_to include("Sure!")
    end

    it "shows only the reply when prose precedes a still-arriving document" do
      expect(visible('Sure! {"intent":"chat","reply":"Hi th')).to eq("Hi th")
    end
  end
end
