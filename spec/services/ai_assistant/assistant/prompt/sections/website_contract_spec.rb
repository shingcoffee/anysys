# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::WebsiteContract do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation, mode: :entity) }

  def render = described_class.new(context).render

  it "drops itself when the Website module is off" do
    expect(render).to be_nil
  end

  context "when the Website module is on" do
    before { enable_module!("website", customer) }

    it "replaces the reply envelope for apply_website and keeps questions on clarify and chat" do
      content = render

      expect(content).to start_with("## Website output contract")
      expect(content).to include("follows THIS contract instead of the reply envelope")
      expect(content).to include("`questions` / `assumptions`")
      expect(content).not_to include("entities")
    end

    it "states the limits from the live constants" do
      expect(render).to include(
        "at most #{Websites::Assistant::Extraction::MAX_PAGES} pages per reply and " \
        "#{Websites::Assistant::Extraction::MAX_SECTIONS} sections per page"
      )
    end

    it "embeds the example as parseable JSON" do
      raw = render[/```json\n(.*?)\n```/m, 1]

      expect(JSON.parse(raw)).to eq(described_class::EXAMPLE)
    end
  end

  # The example is the strongest signal the model has; it must be a document
  # the server would accept.
  describe "the example" do
    let(:example) { described_class::EXAMPLE }
    let(:pages) { example["pages"] }
    let(:sections) { pages.flat_map { |page| page["sections"] } }

    it "parses as a persistable apply_website document" do
      extraction = Websites::Assistant::Extraction.parse(JSON.generate(example))

      expect(extraction).to be_persistable
      expect(example.keys).to eq(%w[intent reply pages])
    end

    it "stays within the page and section limits" do
      expect(pages.size).to be <= Websites::Assistant::Extraction::MAX_PAGES
      expect(pages).to all(satisfy { |page| page["sections"].size <= Websites::Assistant::Extraction::MAX_SECTIONS })
    end

    it "uses only known section types and their schema props" do
      sections.each do |section|
        schema = Websites::SectionFields.schema_for(section["type"]).index_by { |field| field[:key] }

        expect(Websites::SectionKit.known?(section["type"])).to be(true)
        section["props"].each do |key, value|
          field = schema.fetch(key) { raise "#{section["type"]} has no prop #{key}" }
          case field[:kind]
          when :select then expect(field[:options]).to include(value)
          when :array
            item_keys = field[:item_fields].pluck(:key)
            expect(value.size).to be_between(field[:min], field[:max])
            value.each { |item| expect(item.keys - item_keys).to be_empty }
          else expect(value).to be_a(String)
          end
        end
      end
    end

    it "links only to pages in the same document and places images by token" do
      slugs = pages.map { |page| page["slug"].presence || page["title"].parameterize }
      hrefs = sections.flat_map { |section| section["props"].slice(*Websites::SectionKit::HREF_KEYS).values }
      images = sections.flat_map do |section|
        props = section["props"]
        [props["image_url"], props["visual_url"], *Array(props["cards"]).pluck("image_url")].compact
      end

      expect(hrefs).to all(satisfy { |href| slugs.include?(href) })
      expect(images).to all(satisfy { |value| Websites::Assistant::Uploads.token?(value) })
    end
  end
end
