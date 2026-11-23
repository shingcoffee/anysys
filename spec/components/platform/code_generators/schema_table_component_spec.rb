# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::SchemaTableComponent, type: :component do
  let(:schema) do
    CodeGenerators::ConfigSchema.new(action_name: "schema_table_fixture").tap do |schema|
      schema.instance_eval do
        enum :mode, %w[fast safe], default: "fast", required: true
        integer :limit, min: 1, max: 50, default: 10, group: :advanced
        template :note, visible: { mode: "safe" }
        requires :note, when: { mode: %w[safe] }
      end
    end
  end

  def row(html, name)
    html.css("tbody tr").find { |tr| tr.at_css("td").text.include?(name) }.css("td").map { |td| td.text.squish }
  end

  it "describes each field's role, default, requirement, visibility and allowed values" do
    html = render_inline(described_class.new(fields: schema.fields))

    expect(html.css("thead th").map(&:text)).to eq(["Field", "Type", "Default", "Required", "Shown when", "Allowed"])
    expect(row(html, "mode")).to eq(["mode", "enum", '"fast"', "Yes", "—", "fast, safe"])
    expect(row(html, "limit")).to eq(["limit advanced", "integer", "10", "—", "—", "1…50"])
    expect(row(html, "note")).to eq(["note", "template", "—", "Conditional mode = safe", "mode = safe", "—"])
  end

  it "shows an empty state for generators without configuration" do
    html = render_inline(described_class.new(fields: []))

    expect(html.text).to include("This generator takes no configuration.")
    expect(html.css("table")).to be_empty
  end
end
