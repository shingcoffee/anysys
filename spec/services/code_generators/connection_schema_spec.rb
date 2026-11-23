# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConnectionSchema do
  it "declares only label and description" do
    names = described_class.schema.fields.map(&:name)
    expect(names).to eq(%w[label description])
    expect(names).not_to include("priority")
  end

  it "accepts a labelled connection and ignores no extra priority field via schema names" do
    expect(described_class.schema.validate_config("label" => "Yes", "description" => "taken")).to eq([])
  end

  it "reports undeclared keys such as priority" do
    errors = described_class.schema.validate_config("priority" => 1)
    expect(errors).to include(have_attributes(field: "priority", code: :unknown_field))
  end
end
