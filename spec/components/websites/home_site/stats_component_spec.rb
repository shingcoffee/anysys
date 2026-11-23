# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::StatsComponent, type: :component do
  it "renders saved figures as an escaped description list with gradient values and a literal column count" do
    html = render_inline(described_class.new(theme: website_theme, props: { items: [
      { value: "<b>1</b>", label: "workspace" }, { value: "< 5 min", label: "to drafts" }, { value: "0", label: "code" }
    ] }))
    expect(html.css("dl > div").map { |node| [node.at_css("dd").text, node.at_css("dt").text] }).to eq([
      ["<b>1</b>", "workspace"], ["< 5 min", "to drafts"], ["0", "code"]
    ])
    expect(html.css("b")).to be_empty
    expect(html.at_css("dl")["class"]).to include("min-[280px]:grid-cols-2", "lg:grid-cols-3", "lg:divide-x")
    expect(html.at_css("dd")["class"]).to include("bg-clip-text", "text-[36px]", "lg:text-[56px]", "tabular-nums")
  end

  it "uses four desktop columns for four figures and tracks zh-CN headings normally" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, props: { items: Array.new(4) { |index| { value: index.to_s, label: "项 #{index}" } } }))
      expect(html.at_css("dl")["class"]).to include("lg:grid-cols-4")
      expect(html.at_css("dd")["class"]).to include("tracking-normal")
    end
  end

  it "skips figures without a value and renders nothing when no figure remains" do
    html = render_inline(described_class.new(theme: website_theme, props: { items: [{ value: "6", label: "blocks" }, { value: " ", label: "Orphan" }, nil] }))
    expect(html.css("dd").map(&:text)).to eq(["6"])
    expect(html.at_css("dl")["class"]).to include("lg:grid-cols-1")
    html = render_inline(described_class.new(theme: website_theme, props: { items: [{ label: "Only label" }] }))
    expect(html.css("section")).to be_empty
  end
end
