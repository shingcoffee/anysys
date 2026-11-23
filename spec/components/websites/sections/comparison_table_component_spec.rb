# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ComparisonTableComponent, type: :component do
  let(:props) do
    {
      "heading" => "Compare models",
      "column_1" => "Aero",
      "column_2" => "Terra",
      "column_4" => "",
      "rows" => [
        { "title" => "Range", "value_1" => "410 mi", "value_2" => "350 mi" },
        { "title" => "Tow package", "value_1" => "—", "value_2" => "✓" },
        { "title" => "" }
      ]
    }
  end

  it "renders a column per named header and a row per titled feature" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Compare models")
    expect(page).to have_css("thead th[scope='col']", count: 3)
    expect(page).to have_css("thead th", text: "Aero")
    expect(page).to have_css("tbody th[scope='row']", count: 2)
    expect(page).to have_css("td", text: "410 mi")
  end

  it "turns check marks and dashes into accessible included / not included cells" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    row = page.find("tbody tr", text: "Tow package")
    expect(row).to have_css("svg", count: 1)
    expect(row).to have_css(".sr-only", text: I18n.t("website.public.comparison.included"))
    expect(row).to have_css(".sr-only", text: I18n.t("website.public.comparison.not_included"))
    expect(page).to have_css(".sr-only", text: I18n.t("website.public.comparison.feature"))
  end

  it "classifies cell values" do
    component = described_class.new(props: props, theme: website_theme, customer_id: 42)
    column = { number: 1 }

    expect(component.cell({ "value_1" => "✔" }, column)).to eq(:included)
    expect(component.cell({ "value_1" => "" }, column)).to eq(:excluded)
    expect(component.cell({ "value_1" => "×" }, column)).to eq(:excluded)
    expect(component.cell({ "value_1" => "3.1 s" }, column)).to eq("3.1 s")
  end

  it "omits the table when there are no columns" do
    render_inline(described_class.new(props: { "heading" => "Plans", "rows" => [{ "title" => "Users" }] }, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("h2", text: "Plans")
    expect(page).not_to have_css("table")
  end

  it "renders a style override on the first column header" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "column_1" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='column_1'][style*='#be123c']")
  end
end
