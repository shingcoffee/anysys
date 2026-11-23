# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::ComparisonComponent, type: :component do
  let(:included) { described_class::INCLUDED.first }
  let(:excluded) { described_class::EXCLUDED.first }

  def render_table(**props)
    render_inline(described_class.new(theme: website_theme, props: {
      heading: "Why Anysys", column_1: "Anysys", column_2: "Patchwork", column_3: " ",
      rows: [{ title: "Records", value_1: included, value_2: excluded }, { title: "<b>Website</b>", value_1: "Built in", value_2: "Extra tool" }, { title: " " }]
    }.merge(props)))
  end

  it "renders a semantic scrollable table with the first named column as the hero" do
    html = render_table
    expect(html.at_css("h2").text).to eq("Why Anysys")
    expect(html.css("thead th[scope='col']").map { |node| node.text.strip }).to eq([I18n.t("website.public.comparison.feature"), "Anysys", "Patchwork"])
    expect(html.css("tbody th[scope='row']").map(&:text)).to eq(["Records", "<b>Website</b>"])
    expect(html.css("b")).to be_empty
    expect(html.at_css("table").parent["class"]).to include("overflow-x-auto", "rounded-[2rem]")
    expect(html.at_css("table")["class"]).not_to include("min-w-[34rem]")
    expect(render_table(column_3: "Spreadsheets").at_css("table")["class"]).to include("min-w-[34rem]")
    hero = html.css("thead th")[1]
    expect(hero.at_css("span")["class"]).to include("rounded-full", "from-violet-600")
    expect(html.css("tbody tr").first.css("td").first["class"]).to include("bg-violet-50/40")
  end

  it "marks included and excluded cells with icons and screen-reader text, keeping custom cell text" do
    html = render_table
    first, second = html.css("tbody tr").map { |row| row.css("td") }
    expect(first[0].at_css(".sr-only").text).to eq(I18n.t("website.public.comparison.included"))
    expect(first[0].css("svg path").map { |node| node["d"] }).to eq(["m5 10.5 3.2 3L15 6.5"])
    expect(first[1].at_css(".sr-only").text).to eq(I18n.t("website.public.comparison.not_included"))
    expect(first[1].at_css("span")["class"]).to include("text-slate-400")
    expect(second[0].text.strip).to eq("Built in")
    expect(second[0].css("svg path").map { |node| node["d"] }).to eq(["m5 10.5 3.2 3L15 6.5"])
    expect(second[1].text.strip).to eq("Extra tool")
    expect(second[1].css("svg path").map { |node| node["d"] }).to eq(["M5 10h10"])
    expect(html.css("svg").map { |node| node["focusable"] }).to all(eq("false"))
  end

  it "renders nothing without both a named column and a titled row" do
    expect(render_table(rows: [{ title: " " }]).css("section")).to be_empty
    expect(render_table(column_1: "", column_2: "").css("section")).to be_empty
  end
end
