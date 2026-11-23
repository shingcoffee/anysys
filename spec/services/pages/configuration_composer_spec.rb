# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ConfigurationComposer do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, name: "User", customer: customer, property_schema: [
      { "name" => "Name",  "name_slug" => "name",  "type" => "String" },
      { "name" => "Email", "name_slug" => "email", "type" => "String" }
    ].to_json)
  end

  def compose(page, template_key: nil, theme_preset_key: nil)
    described_class.call(page: page, template_key: template_key, theme_preset_key: theme_preset_key)
  end

  context "when the page has no entity" do
    it "is a no-op and leaves configuration untouched" do
      page = Page.new_with_defaults(name: "Blank", customer: customer)
      before = page.configuration_json.deep_dup

      compose(page)

      expect(page.configuration_json).to eq(before)
    end
  end

  context "when the page is entity-backed" do
    let(:page) { Page.new_with_defaults(name: "User Page", customer: customer, entity_id: entity.id) }

    it "populates configuration pages named after the entity" do
      compose(page)

      pages = page.configuration_json["pages"]
      expect(pages.first["name"]).to eq("User")
      expect(page.configuration_json).not_to have_key("fields")
    end

    it "records the effective layout template key in metadata (defaults to 'default')" do
      compose(page)
      expect(page.configuration_json.dig("metadata", "layout_template_key")).to eq("default")
    end

    it "applies a selected theme preset" do
      compose(page, template_key: "blank", theme_preset_key: "bold")
      expect(page.configuration_json["theme"]).to eq(ThemeResolver::THEME_PRESETS["bold"])
    end

    it "skips template application for a 'blank' template" do
      compose(page, template_key: "blank")
      expect(page.configuration_json.dig("metadata", "layout_template_key")).to be_nil
    end

    it "populates from an explicit entity snapshot rather than the live head" do
      live = entity
      snapshot = Entity.find(live.id)
      snapshot.property_schema_json = [
        { "name" => "OnlyThen", "name_slug" => "only_then", "html_type" => "text" }
      ]
      described_class.call(page: page, template_key: "blank", theme_preset_key: nil, entity: snapshot)
      slugs = page.configuration_json["pages"].flat_map { |p| p["fields"] }.map { |f| f["property_slug"] }
      expect(slugs).to include("only_then")
      expect(slugs).not_to include("email")
    end
  end
end
