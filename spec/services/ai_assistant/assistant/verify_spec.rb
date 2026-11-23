# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::Verify do
  let_it_be(:customer) { create(:customer) }

  it "accepts an entity that has a current version" do
    entity = create(:entity, :with_name_status_schema, customer: customer)
    result = described_class.call(kind: "entity", record: entity, customer: customer)
    expect(result.ok).to eq(true)
    expect(result.issues).to eq([])
  end

  it "rejects another tenant's record" do
    other = create(:customer)
    entity = create(:entity, customer: other)
    result = described_class.call(kind: "entity", record: entity, customer: customer)
    expect(result.ok).to eq(false)
    expect(result.issues).not_to be_empty
  end

  it "accepts a flowchart with start and end elements" do
    flowchart = create(:flowchart, :simple, customer: customer)
    result = described_class.call(kind: "flowchart", record: flowchart, customer: customer)
    expect(result.ok).to eq(true)
  end

  it "flags a flowchart with no start element" do
    flowchart = create(:flowchart, :empty, customer: customer)
    result = described_class.call(kind: "flowchart", record: flowchart, customer: customer)
    expect(result.ok).to eq(false)
    expect(result.issues.join).to include("start")
  end

  describe "website pages" do
    let(:website) { create(:website, customer: customer) }

    it "accepts a page whose sections are all known types" do
      website_page = create(
        :website_page,
        website: website,
        sections: [{ "id" => "sec_1", "type" => "rich_text", "props" => { "heading" => "Hi" } }]
      )

      result = described_class.call(kind: "website_page", record: website_page, customer: customer)

      expect(result.ok).to eq(true)
    end

    it "flags a page without sections" do
      website_page = create(:website_page, website: website, sections: [])

      result = described_class.call(kind: "website_page", record: website_page, customer: customer)

      expect(result.issues).to eq([I18n.t("ai_assistant.assistant.verify.website_page_empty")])
    end

    it "flags an unknown section type" do
      website_page = create(:website_page, website: website)
      website_page.update_columns(sections: [{ "id" => "sec_1", "type" => "marquee", "props" => {} }])

      result = described_class.call(kind: "website_page", record: website_page, customer: customer)

      expect(result.issues).to eq(
        [I18n.t("ai_assistant.assistant.verify.website_page_unknown_section", type: "marquee")]
      )
    end

    it "rejects another tenant's website page" do
      foreign = create(:website_page, website: create(:website, customer: create(:customer)))

      result = described_class.call(kind: "website_page", record: foreign, customer: customer)

      expect(result.ok).to eq(false)
    end
  end

  it "does not leak the exception message when page render fails" do
    page = create(:page, customer: customer)
    allow(PageContentGenerator).to receive(:new).and_raise(RuntimeError, "secret SQL from users")

    result = described_class.call(kind: "page", record: page, customer: customer)

    expect(result.ok).to eq(false)
    expect(result.issues.join).to eq("Page preview could not be generated.")
    expect(result.issues.join).not_to include("secret SQL")
  end
end
