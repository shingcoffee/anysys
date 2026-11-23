# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CardTableComponent, type: :component do
  it "renders the title in a section header when given" do
    render_inline(described_class.new(headers: [{ label: "Name" }], empty: false, empty_text: "x", title: "My Table"))
    expect(page).to have_css("h2.section-header", text: "My Table")
  end

  it "omits the title header when no title is given" do
    render_inline(described_class.new(headers: [{ label: "Name" }], empty: false, empty_text: "x"))
    expect(page).to have_no_css("h2.section-header")
  end

  it "renders column headers with their alignment classes" do
    render_inline(described_class.new(
                    headers: [{ label: "Name", align: :left }, { label: "Amt", align: :right }],
                    empty: false, empty_text: "x"
                  ))
    expect(page).to have_css("th.text-left", text: "Name")
    expect(page).to have_css("th.text-right", text: "Amt")
  end

  it "omits an alignment class for a header with no align (action column)" do
    render_inline(described_class.new(headers: [{ label: "" }], empty: false, empty_text: "x"))
    expect(page.find("th")[:class]).to eq("px-4 py-3")
  end

  it "yields the row content when not empty" do
    render_inline(described_class.new(headers: [{ label: "Name" }], empty: false, empty_text: "Nothing here")) do
      "<tr><td>Row content</td></tr>".html_safe
    end
    expect(page).to have_text("Row content")
    expect(page).to have_no_text("Nothing here")
  end

  it "renders a colspan empty row spanning all headers when empty" do
    render_inline(described_class.new(
                    headers: [{ label: "A" }, { label: "B" }, { label: "C" }],
                    empty: true, empty_text: "No records"
                  )) do
      "<tr><td>should not render</td></tr>".html_safe
    end
    cell = page.find("td")
    expect(cell[:colspan]).to eq("3")
    expect(cell).to have_text("No records")
    expect(page).to have_no_text("should not render")
  end
end
