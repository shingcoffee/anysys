# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::DetailGridComponent, type: :component do
  let(:record) { Struct.new(:name, :amount_cents, :paid_at).new("Alpha", 1234, nil) }

  def render_grid(rows)
    render_inline(described_class.new(rows: rows, record: record))
  end

  it "renders a <dl> grid with two columns by default" do
    render_grid([
      { label: "Name",   value: ->(r) { r.name } },
      { label: "Amount", value: ->(r) { r.amount_cents }, format: :money }
    ])

    expect(page).to have_css("dl.grid")
    expect(page).to have_css("dt", text: "Name")
    expect(page).to have_css("dd", text: "Alpha")
    expect(page).to have_css("dd", text: "$12.34")
  end

  it "skips rows whose when: predicate is falsy" do
    render_grid([
      { label: "Name",     value: ->(r) { r.name } },
      { label: "Paid at",  value: ->(r) { r.paid_at }, format: :datetime, when: ->(r) { r.paid_at } }
    ])

    expect(page).to have_css("dt", text: "Name")
    expect(page).not_to have_css("dt", text: "Paid at")
  end

  it "applies sm:col-span-2 when span: 2" do
    render_grid([{ label: "Notes", value: ->(r) { "long text" }, span: 2 }])
    expect(page.find("dt", text: "Notes").find(:xpath, "..")[:class]).to include("sm:col-span-2")
  end

  it "renders :money_large with the hero classes" do
    render_grid([{ label: "Amount", value: ->(r) { r.amount_cents }, format: :money_large }])
    expect(page).to have_css("span.text-3xl.font-mono", text: "$12.34")
  end

  it "applies the refined value classes on dd" do
    render_grid([{ label: "Name", value: ->(r) { r.name } }])
    expect(page.find("dd")[:class]).to include("text-site-base", "break-words")
  end

  it "uses the site label treatment on dt elements" do
    render_grid([{ label: "Name", value: ->(r) { r.name } }])
    expect(page.find("dt")[:class]).to include("uppercase", "tracking-[0.08em]")
  end
end
