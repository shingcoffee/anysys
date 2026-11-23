# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Emails::TemplateTokenBulkFormComponent, type: :component do
  it "preserves a failed bulk submission supplied as an array or indexed hash" do
    entity = double(id: 7)
    token = double(entity_id: 7)
    row = { attribute_slug: "title", name: "Submitted name" }
    [[row], { "0" => row }, [{ "attribute_slug" => "title", "name" => "Submitted name" }]].each do |submitted|
      component = described_class.new(token: token, entities: [entity], entity_attributes: { "7" => [["Title", "title"]] },
        existing_slugs: {}, submitted_fields: submitted, url: "/tokens", cancel_path: "/tokens")
      retained = component.fields_for(entity).first.last
      expect(retained[:attribute_slug]).to eq("title")
      expect(retained[:name]).to eq("Submitted name")
    end
  end
end
