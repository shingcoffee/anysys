# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::FormFieldComponent, type: :component do
  def render_field(**options)
    render_inline(described_class.new(id: "field_ab12", slug: "name", field_name: "entity[name]", label: "Name",
                                      html_type: "text", **options))
  end

  it "draws the entry form's field chrome around the page's name and id" do
    rendered = render_field(value: "Ada", required: true, help_text: "Legal name", placeholder: "Full name")
    input = rendered.at_css("input#field_ab12")

    expect(rendered.at_css("div.min-w-0.space-y-1\\.5 > label[for='field_ab12']").text).to include("Name", "*")
    expect(input["name"]).to eq("entity[name]")
    expect(input["value"]).to eq("Ada")
    expect(input["placeholder"]).to eq("Full name")
    expect(input["required"]).to eq("required")
    expect(input["aria-describedby"]).to eq("field_ab12_help")
    expect(input["class"]).to include("input-field", "min-h-11")
    expect(rendered.at_css("#field_ab12_help").text).to eq("Legal name")
  end

  it "posts nothing for a cleared checkbox or multi-select" do
    checkbox = render_field(html_type: "checkbox", value: "1")
    multi = render_field(html_type: "multi-select", options: [%w[A a]])

    expect(checkbox.css("input[type='hidden']")).to be_empty
    expect(checkbox.at_css("input[type='checkbox']")["checked"]).to be_present
    expect(multi.css("input[type='hidden']")).to be_empty
    expect(multi.at_css("select")["name"]).to eq("entity[name][]")
  end

  it "offers the select placeholder and selects the given value" do
    select = render_field(html_type: "select", options: [%w[Applicant applicant], %w[Enrolled enrolled]], value: "applicant").at_css("select")

    expect(select.css("option").map(&:text)).to eq([I18n.t("comp_form_fields.select.blank_option"), "Applicant", "Enrolled"])
    expect(select.at_css("option[selected]")["value"]).to eq("applicant")
  end

  it "passes condition data to the control" do
    input = render_field(data: { conditions: "[]" }).at_css("input")

    expect(input["data-conditions"]).to eq("[]")
  end
end
