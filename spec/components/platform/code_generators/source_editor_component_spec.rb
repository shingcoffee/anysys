# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::SourceEditorComponent, type: :component do
  it "renders a labelled, unwrapped textarea with a line-number gutter" do
    html = render_inline(described_class.new(name: "methods_body", value: "a\nb\nc", label: "Source"))

    textarea = html.at_css("textarea#generator-source-editor[name='methods_body']")
    expect(textarea.text).to eq("a\nb\nc")
    expect(textarea["aria-label"]).to eq("Source")
    expect(textarea["wrap"]).to eq("off")
    expect(textarea["data-action"]).to include("input->source-editor#refresh", "keydown->source-editor#keydown")
    expect(html.at_css("[data-source-editor-target='gutter']").text.split).to eq(%w[1 2 3])
    expect(html.at_css("[data-controller='source-editor']")["class"]).to include("h-[32rem]")
  end

  it "fills its container when asked" do
    html = render_inline(described_class.new(name: "body", value: "", label: "Source", id: "x", fill: true))

    expect(html.at_css("[data-controller='source-editor']")["class"]).to include("h-full")
    expect(html.at_css("textarea#x")).to be_present
  end
end
