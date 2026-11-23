# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntryFieldComponent, type: :component do
  def descriptor(**attributes)
    double("Field", **{
      slug: "title", label: "Course title", help_text: nil, html_type: "text",
      required: false, options: [], constraints: {}, full_width: false, invalid_literal: false
    }.merge(attributes))
  end

  def render_field(value: nil, errors: [], **attributes)
    render_inline(described_class.new(field: descriptor(**attributes), value: value, errors: errors))
  end

  it "associates the authored label, help and inline errors with the native control" do
    rendered = render_field(value: "My course", help_text: "Public title", required: true, errors: ["cannot be blank"])
    input = rendered.at_css("input#entry_title")

    expect(rendered.at_css("label")["for"]).to eq(input["id"])
    expect(input["name"]).to eq("entry[data][title]")
    expect(input["value"]).to eq("My course")
    expect(input["required"]).to eq("required")
    expect(input["aria-invalid"]).to eq("true")
    expect(input["aria-describedby"]).to eq("entry_title_help entry_title_errors")
    expect(input["class"]).to include("input-field", "w-full", "min-w-0", "min-h-11", "!border-danger")
    expect(rendered.at_css("#entry_title_help").text).to eq("Public title")
    expect(rendered.at_css("#entry_title_errors").text).to include("cannot be blank")
    expect(rendered.css("label").size).to eq(1)
  end

  it "omits unused descriptions, invalid state, required status and autofocus on GET" do
    rendered = render_field
    input = rendered.at_css("input")
    expect(input["aria-describedby"]).to be_nil
    expect(input["aria-invalid"]).to be_nil
    expect(input["required"]).to be_nil
    expect(rendered.css("[autofocus], ul, p")).to be_empty
  end

  it "escapes authored metadata, attempts and error messages" do
    hostile = '<img src=x onerror="alert(1)">'
    rendered = render_field(label: hostile, help_text: hostile, value: hostile, errors: [hostile])
    expect(rendered.css("img, script")).to be_empty
    expect(rendered.at_css("label").text.strip).to eq(hostile)
    expect(rendered.at_css("input")["value"]).to eq(hostile)
    expect(rendered.at_css("ul").text).to include(hostile)
  end

  %w[text search tel url email].each do |type|
    it "renders #{type} as a scalar control with only supported constraints" do
      rendered = render_field(html_type: type, constraints: { minlength: 2, maxlength: 60, onclick: "unsafe()" })
      input = rendered.at_css("input")
      expect(input["type"]).to eq(type)
      expect(input["minlength"]).to eq("2")
      expect(input["maxlength"]).to eq("60")
      expect(input["onclick"]).to be_nil
    end
  end

  it "renders a full-width textarea and preserves an explicitly blank attempt" do
    rendered = render_field(html_type: "textarea", value: "")
    expect(rendered.at_css("textarea").text).to eq("")
    expect(rendered.at_css("textarea")["name"]).to eq("entry[data][title]")
    expect(rendered.at_css("div")["class"]).to include("md:col-span-2")
  end

  it "renders native numeric constraints and a zero value without coercion" do
    rendered = render_field(html_type: "number", value: 0, constraints: { min: 0, max: 10, step: "any" })
    input = rendered.at_css("input[type='number']")
    expect(input["value"]).to eq("0")
    expect(%w[min max step].map { |attribute| input[attribute] }).to eq(%w[0 10 any])
  end

  it "renders a native ISO date" do
    rendered = render_field(html_type: "date", value: "2026-10-21")
    expect(rendered.at_css("input[type='date']")["value"]).to eq("2026-10-21")
  end

  it "renders a native local datetime" do
    rendered = render_field(html_type: "datetime-local", value: "2026-10-21T08:30")
    input = rendered.at_css("input[type='datetime-local']")
    expect(input["value"]).to eq("2026-10-21T08:30")
    expect(input["id"]).to eq("entry_title")
  end

  [
    ["number", "not a number", { min: 0, max: 10, step: 1 }, "numeric"],
    ["number", "NaN", { step: "any" }, "decimal"],
    ["date", "2026-02-30", {}, nil],
    ["datetime-local", "2026-10-21 08:30", {}, nil]
  ].each do |type, value, constraints, inputmode|
    it "preserves rejected #{type} literal #{value.inspect} through a text rerender" do
      rendered = render_field(html_type: type, value: value, constraints: constraints, invalid_literal: true, errors: ["invalid"])
      input = rendered.at_css("input")
      expect(input["type"]).to eq("text")
      expect(input["value"]).to eq(value)
      expect(input["inputmode"]).to eq(inputmode)
      expect(%w[min max step].map { |attribute| input[attribute] }).to eq([nil, nil, nil])
      expect(input["aria-describedby"]).to eq("entry_title_errors")
    end
  end

  it "uses static select values independently of their labels and retains defaults" do
    rendered = render_field(html_type: "select", value: "online", options: [["Remote learning", "online"], ["In person", "onsite"]])
    expect(rendered.at_css("option[selected]")["value"]).to eq("online")
    expect(rendered.at_css("option[selected]").text).to eq("Remote learning")
    expect(rendered.at_css("option[value='']").text).to eq(I18n.t("comp_form_fields.select.blank_option"))
  end

  it "keeps a rejected scalar choice selected and escaped on a validation rerender" do
    rejected = "<script>bad()</script>"
    rendered = render_field(html_type: "select", value: rejected, options: [["Valid", "valid"]], errors: ["unavailable"])
    option = rendered.at_css("option[selected]")
    expect(option["value"]).to eq(rejected)
    expect(option.text).to eq(I18n.t("admin_misc.entities.entry_form.errors.rejected_value", value: rejected))
    expect(rendered.css("script")).to be_empty
  end

  it "sends the blank sentinel before a multi-select and retains an explicit empty selection" do
    rendered = render_field(html_type: "multi-select", value: [], options: [["Alpha", "a"], ["Beta", "b"]])
    hidden = rendered.at_css("input[type='hidden']")
    select = rendered.at_css("select[multiple]")
    expect(hidden["name"]).to eq("entry[data][title][]")
    expect(hidden["value"]).to eq("")
    expect(select["name"]).to eq(hidden["name"])
    expect(rendered.css("option[selected]")).to be_empty
    expect(hidden.next_element).to eq(select)
    expect(select.parent["class"]).to include("md:col-span-2")
  end

  it "retains every submitted multi-select value including a rejected choice" do
    rendered = render_field(html_type: "multi-select", value: %w[a rejected], options: [["Alpha", "a"], ["Beta", "b"]], errors: ["unavailable"])
    expect(rendered.css("option[selected]").map { |option| option["value"] }).to eq(%w[a rejected])
  end

  it "groups radio options semantically with distinct IDs, labels, values and error descriptions" do
    rendered = render_field(html_type: "radio", value: "b", required: true,
                            options: [["Alpha", "a"], ["Beta", "b"]], help_text: "Pick one", errors: ["invalid"])
    expect(rendered.at_css("fieldset > legend").text).to include("Course title")
    inputs = rendered.css("input[type='radio']")
    expect(inputs.map { |input| input["id"] }).to eq(%w[entry_title entry_title_1])
    expect(inputs.map { |input| input["aria-describedby"] }.uniq).to eq(["entry_title_help entry_title_errors"])
    expect(rendered.at_css("input[checked]")["value"]).to eq("b")
    inputs.each do |input|
      expect(rendered.at_css("label[for='#{input['id']}']")).not_to be_nil
      expect(input["name"]).to eq("entry[data][title]")
      expect(input["required"]).to eq("required")
    end
  end

  it "echoes a rejected radio attempt inline without adding it to the allowed controls" do
    rendered = render_field(html_type: "radio", value: "forged", options: [["Alpha", "a"]], errors: ["unavailable"])
    expect(rendered.css("input").map { |input| input["value"] }).to eq(["a"])
    expect(rendered.at_css("ul").text).to include(I18n.t("admin_misc.entities.entry_form.errors.rejected_value", value: "forged"))
  end

  %w[checkbox switch].each do |type|
    it "sends unchecked #{type} as 0 without forcing a required boolean to be checked" do
      rendered = render_field(html_type: type, value: "0", required: true, help_text: "A boolean value", errors: ["invalid"])
      hidden = rendered.at_css("input[type='hidden']")
      checkbox = rendered.at_css("input[type='checkbox']")
      expect(hidden["value"]).to eq("0")
      expect(hidden["name"]).to eq(checkbox["name"])
      expect(checkbox["value"]).to eq("1")
      expect(checkbox["id"]).to eq("entry_title")
      expect(checkbox["required"]).to be_nil
      expect(checkbox["checked"]).to be_nil
      expect(checkbox["aria-invalid"]).to eq("true")
      expect(checkbox["aria-describedby"]).to eq("entry_title_help entry_title_errors")
      expect(rendered.at_css("label[for='entry_title']")).not_to be_nil
    end

    it "retains a checked #{type} with its 1 value" do
      rendered = render_field(html_type: type, value: "1")
      expect(rendered.at_css("input[type='checkbox'][checked]")["value"]).to eq("1")
    end
  end

  it "requires an explicit supported control rather than interpreting schema class names" do
    expect { render_field(html_type: "Kernel") }.to raise_error(KeyError)
  end
end
