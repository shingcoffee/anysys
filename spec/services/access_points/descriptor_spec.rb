# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::Descriptor do
  let(:base_attrs) do
    {
      subject_type: "Route",
      subject_key:  "admin/maintenance/flowcharts",
      subject_id:   nil,
      actions:      [:read, :create],
      group_key:    "admin.maintenance",
      label:        "Flowcharts",
      description:  nil
    }
  end

  it "constructs successfully with valid attrs" do
    d = described_class.new(**base_attrs)
    expect(d.subject_type).to eq("Route")
    expect(d.actions).to eq([:read, :create])
  end

  it "rejects when actions is not an array of symbols" do
    expect { described_class.new(**base_attrs.merge(actions: ["read"])) }
      .to raise_error(ArgumentError)
  end

  it "permits subject_id to be nil" do
    expect(described_class.new(**base_attrs.merge(subject_id: nil))).to be_a(described_class)
  end
end
