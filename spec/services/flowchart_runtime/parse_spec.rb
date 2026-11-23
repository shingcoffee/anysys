# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Parse do
  it "parses json through FlowchartRuntime::Json with a byte cap" do
    expect(described_class.apply('{"count":2}', format: "json")).to eq("count" => 2)
    expect { described_class.apply("{" + ("a" * described_class::MAX_BYTES), format: "json") }
      .to raise_error(described_class::Error)
  end

  it "parses csv with headers, delimiter, skip rows, and column types" do
    rows = described_class.apply("skip\nid,qty\n1,2\n", format: "csv", skip_rows: 1, csv_headers: true,
                                                       col_types: { "qty" => "integer" })
    expect(rows).to eq([{ "id" => "1", "qty" => 2 }])
  end

  it "parses yaml, toml, and xml with YAML.safe_load" do
    expect(described_class.apply("count: 2", format: "yaml")).to eq("count" => 2)
    expect(described_class.apply("count = 2", format: "toml")).to eq("count" => 2)
    expect(described_class.apply("<root><n>1</n></root>", format: "xml", xml_root: "root")).to include("n" => "1")
  end

  it "refuses YAML aliases and ruby objects" do
    expect { described_class.apply("a: &x 1\nb: *x", format: "yaml") }.to raise_error(described_class::Error)
    expect { described_class.apply("--- !ruby/object:Object {}", format: "yaml") }
      .to raise_error(described_class::Error)
  end

  it "does not parse properties files" do
    expect { described_class.apply("a=1", format: "properties") }.to raise_error(described_class::Error)
  end
end
