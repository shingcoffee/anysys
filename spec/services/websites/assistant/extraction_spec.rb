# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Assistant::Extraction do
  let(:document) do
    {
      intent: "apply_website",
      reply: "  Built your home page.  ",
      pages: [ { title: "Home", sections: [ { type: "statement", props: { headline: "Hi" } } ] } ]
    }
  end

  describe ".parse" do
    it "decodes a document and deep-stringifies its pages" do
      extraction = described_class.parse(document.to_json)

      expect(extraction).to be_valid
      expect(extraction).to be_persistable
      expect(extraction.intent).to eq("apply_website")
      expect(extraction.reply).to eq("Built your home page.")
      expect(extraction.pages.first.dig("sections", 0, "props", "headline")).to eq("Hi")
      expect(extraction.as_json.keys).to eq(%w[intent reply pages])
    end

    it "reads a fenced json block" do
      text = "Here you go:\n```json\n#{document.to_json}\n```"

      expect(described_class.parse(text)).to be_valid
    end

    it "reads the first object span when the model wrapped JSON in prose" do
      expect(described_class.parse("Sure! #{document.to_json} Enjoy.")).to be_valid
    end

    it "is valid but not persistable without pages" do
      extraction = described_class.parse(document.except(:pages).to_json)

      expect(extraction).to be_valid
      expect(extraction).not_to be_persistable
      expect(extraction.pages).to eq([])
    end

    it "rejects another intent" do
      expect(described_class.parse(document.merge(intent: "apply_entities").to_json)).not_to be_valid
    end

    it "rejects a blank reply" do
      expect(described_class.parse(document.merge(reply: "  ").to_json)).not_to be_valid
    end

    it "rejects pages that are not an array of objects" do
      expect(described_class.parse(document.merge(pages: [ "Home" ]).to_json)).not_to be_valid
      expect(described_class.parse(document.merge(pages: { title: "Home" }).to_json)).not_to be_valid
    end

    it "rejects text that is not JSON" do
      extraction = described_class.parse("not json at all")

      expect(extraction).not_to be_valid
      expect(extraction.error).to eq(:invalid)
    end
  end

  describe ".website_document?" do
    it "is true for an apply_website document" do
      expect(described_class.website_document?(document.to_json)).to be(true)
    end

    it "is true even when the rest of the document is invalid, so the website processor answers it" do
      expect(described_class.website_document?(document.merge(reply: "").to_json)).to be(true)
    end

    it "is false for other intents, prose, broken JSON and non-strings" do
      expect(described_class.website_document?({ intent: "chat", reply: "apply_website?" }.to_json)).to be(false)
      expect(described_class.website_document?("I will apply_website later")).to be(false)
      expect(described_class.website_document?('{"intent": "apply_website", ')).to be(false)
      expect(described_class.website_document?(nil)).to be(false)
      expect(described_class.website_document?(42)).to be(false)
    end
  end
end
