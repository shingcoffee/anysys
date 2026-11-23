# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAttributeGroupingHelper, type: :helper do
  let(:group) { { "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo", "description" => "Primary contact" } }

  describe "#attribute_group_color_classes" do
    it "returns a bar class string for a known color" do
      classes = helper.attribute_group_color_classes("indigo", variant: :bar)
      expect(classes).to be_a(String)
      expect(classes).to include("indigo")
    end

    it "offers a soft tile variant for every palette color" do
      aggregate_failures do
        EntityAttributeGroupingHelper::COLOR_CLASS_MAP.each_key do |color|
          expect(helper.attribute_group_color_classes(color, variant: :soft)).to match(/\Abg-#{color}-\d+ text-#{color}-600 ring-#{color}-500\/15\z/)
        end
      end
    end

    it "falls back to the default color when given an unknown token" do
      expect(helper.attribute_group_color_classes("neon", variant: :bar))
        .to eq(helper.attribute_group_color_classes(EntityAttributeGroupOptions::DEFAULT_COLOR, variant: :bar))
    end
  end

  describe "#attribute_group_icon" do
    it "renders an SVG element with the css class applied" do
      html = helper.attribute_group_icon("mail", css_class: "w-4 h-4")
      expect(html).to include("<svg")
      expect(html).to include("w-4 h-4")
    end

    it "falls back to the default icon when key is unknown" do
      unknown = helper.attribute_group_icon("not-an-icon", css_class: "w-4 h-4")
      default = helper.attribute_group_icon(EntityAttributeGroupOptions::DEFAULT_ICON, css_class: "w-4 h-4")
      expect(unknown).to eq(default)
    end
  end

  describe "#iterate_grouped_attributes" do
    let(:entity) do
      e = build_stubbed(:entity)
      allow(e).to receive(:grouped_property_schema).and_return([
        { group: group, attributes: [{ "name" => "email" }] },
        { group: nil,   attributes: [{ "name" => "notes" }] }
      ])
      e
    end

    it "yields each section in order" do
      sections = []
      helper.iterate_grouped_attributes(entity) { |g, a| sections << [g && g["name"], a.map { |x| x["name"] }] }
      expect(sections).to eq([["Contact", ["email"]], [nil, ["notes"]]])
    end
  end
end
