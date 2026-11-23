# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Prompt::Sections::WebsiteSectionKit do
  let(:customer) { create(:customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer) }
  let(:context) { AiAssistant::Assistant::Prompt::Context.new(conversation: conversation, mode: :entity) }

  def render = described_class.new(context).render

  it "drops itself when the Website module is off" do
    expect(render).to be_nil
  end

  context "when the Website module is on" do
    before { enable_module!("website", customer) }

    let(:content) { render }

    def row_for(type)
      content.lines.find { |line| line.start_with?("| `#{type}` |") }
    end

    it "lists every section type in its picker group with its purpose" do
      Websites::SectionKit.groups.each do |group, types|
        types.each do |type|
          expect(row_for(type)).to include("| #{group} |", described_class.purposes.fetch(type))
        end
      end
    end

    it "lists every prop of every type, from the live field schema" do
      Websites::SectionKit::TYPES.each do |type|
        keys = Websites::SectionFields.schema_for(type).flat_map { |field| [field[:key], *Array(field[:item_fields]).pluck(:key)] }
        keys.each { |key| expect(row_for(type)).to include("`#{key}`") }
      end
    end

    it "marks image and link props and spells out choices and list bounds" do
      expect(row_for("hero_split")).to include("`visual_url` **image**", "`primary_href` **link**")
      expect(row_for("hero_cinematic")).to include("`tone` choice(`light`/`dark`)")
      expect(row_for("rich_text")).to include("`body` long text")
      expect(row_for("proof_strip")).to include("`items` list[4–6] of {`label` text, `value` text}")
      expect(row_for("bento_grid")).to include("`span` choice(`hero`/`wide`/`unit`)", "`image_url` **image**")
      expect(row_for("card_grid")).to include("`href` **link**")
    end

    it "keeps the prop formatting rules from the document above the table" do
      expect(content).to include("**link**", "`upload:N`")
      expect(content).not_to include("### Purposes")
    end

    it "describes the static preview, text-only hero, and optional featured badge" do
      expect(row_for("ai_preview")).to include("Static", "`prompt` long text", "`review_note` long text", "`items` list[1–4]", "`status` text")
      expect(row_for("hero_centered")).to include("`media_mode` choice(`image`/`none`)", "default", "compact text-only")
      expect(row_for("pricing")).to include("`featured_label` text", "localized badge")
      expect(content).to include("`hero_centered` with `media_mode: none`")
    end
  end

  # The purposes are the only prose in the table; a type added to the kit
  # without one, or a purpose left behind for a removed type, fails here.
  it "has exactly one purpose for every section type" do
    expect(described_class.purposes.keys).to match_array(Websites::SectionKit::TYPES)
  end

  it "treats every non-link URL prop as an image" do
    url_keys = Websites::SectionKit::TYPES.flat_map do |type|
      Websites::SectionFields.schema_for(type).flat_map { |field| [field, *Array(field[:item_fields])] }
    end.pluck(:key).select { |key| key.end_with?("_url") }.uniq

    expect(url_keys - Websites::SectionKit::HREF_KEYS).to match_array(Websites::SectionKit::IMAGE_KEYS)
  end
end
