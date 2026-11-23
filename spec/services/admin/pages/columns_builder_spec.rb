# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::ColumnsBuilder do
  it "returns slim sort/search columns for the ops list" do
    keys = described_class.call.map { |c| c[:key] }
    expect(keys).to eq(%i[name visibility launched updated_at])
  end

  it "does not include entity_name or field_count" do
    keys = described_class.call.map { |c| c[:key] }
    expect(keys).not_to include(:entity_name, :field_count)
  end
end
