# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::UiConfigSchema do
  it "seeds End with the visible responseType default only" do
    expect(described_class.defaults_for("end")).to eq("responseType" => "none")
    expect(described_class.defaults_for("end")).not_to have_key("httpStatus")
    expect(described_class.defaults_for("end")).not_to have_key("returnValue")
  end

  it "seeds Start with no config defaults" do
    expect(described_class.defaults_for("start")).to eq({})
  end

  it "does not seed a hidden End returnValue" do
    fields = described_class.element_fields_for("end")
    names = fields.map { |field| field["name"] || field["key"] }
    expect(names).to include("responseType", "returnValue")
    expect(names).not_to include("httpStatus", "responseBody")
  end
end
