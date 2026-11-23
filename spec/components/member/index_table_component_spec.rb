# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::IndexTableComponent, type: :component do
  IndexTableRow = Struct.new(:id, :name, :amount_cents, :status, keyword_init: true)

  let(:records) do
    [
      IndexTableRow.new(id: 1, name: "Alpha", amount_cents: 1000, status: "succeeded"),
      IndexTableRow.new(id: 2, name: "Beta",  amount_cents: 2050, status: "pending")
    ]
  end

  let(:columns) do
    [
      { label: "Name",   value: ->(r) { r.name } },
      { label: "Amount", value: ->(r) { r.amount_cents }, format: :money, align: :right },
      { label: "Status", value: ->(r) { r.status }, format: :status_pill }
    ]
  end

  let(:row_path) { ->(r) { "/things/#{r.id}" } }

  def render_table(**opts)
    render_inline(described_class.new(
      **{ records: records, columns: columns, row_path: row_path }.merge(opts)
    ))
  end

  it "renders a header for each column" do
    render_table
    %w[Name Amount Status].each { |h| expect(page).to have_css("th", text: h) }
  end

  it "renders one body row per record" do
    render_table
    expect(page).to have_css("tbody tr", count: 2)
    expect(page).to have_css("td", text: "Alpha")
    expect(page).to have_css("td", text: "Beta")
  end

  it "applies right alignment to columns with align: :right" do
    render_table
    amount_cells = page.all("td").select { |c| c.text.match?(/\$\d/) }
    expect(amount_cells).not_to be_empty
    amount_cells.each { |c| expect(c[:class]).to include("text-right") }
  end

  it "renders status_pill format as a badge" do
    render_table
    expect(page).to have_css("span.badge.badge-success", text: I18n.t("common.status.succeeded"))
    expect(page).to have_css("span.badge.badge-warning", text: I18n.t("common.status.pending"))
  end

  it "renders a trailing 'View' link per row to row_path.call(record)" do
    render_table
    expect(page).to have_link("View", href: "/things/1")
    expect(page).to have_link("View", href: "/things/2")
  end

  it "uses the configured row_label for the trailing link" do
    render_table(row_label: "Open")
    expect(page).to have_link("Open", href: "/things/1")
  end

  it "wraps the table in an overflow-x-auto div for mobile horizontal scroll" do
    render_table
    expect(page).to have_css("div.overflow-x-auto > table")
  end

  it "hides the table below md and stacks each record as a card" do
    render_table
    expect(page).to have_css("div.hidden.md\\:block.overflow-x-auto > table")
    expect(page).to have_css("div.md\\:hidden article", count: 2)
    expect(page).to have_css("article", text: "Alpha")
    expect(page).to have_css("article dt", text: "Amount")
    expect(page).to have_link("View", href: "/things/1")
  end

  it "does not render a row action without row_action" do
    render_table
    expect(page).not_to have_link(href: %r{/actions/})
  end

  it "renders a row action link on table rows and mobile cards" do
    customer = Struct.new(:id).new(81_721_200)
    render_table(
      customer: customer,
      row_action: { action_key: "enroll", field: "course", label: "Enroll" }
    )

    href = Pages::ActionLink.path(customer_id: 81_721_200, action_key: "enroll", prefill: { "course" => 1 })
    expect(page).to have_link("Enroll", href: href)
    expect(page).to have_link("View", href: "/things/1")
    expect(page).to have_css("article a", text: "Enroll")
  end

  it "falls back to the default row action label" do
    customer = Struct.new(:id).new(81_721_200)
    render_table(
      customer: customer,
      row_action: { action_key: "enroll", field: "course" }
    )

    href = Pages::ActionLink.path(customer_id: 81_721_200, action_key: "enroll", prefill: { "course" => 1 })
    expect(page).to have_link(I18n.t("member.entity_surfaces.row_action_default"), href: href)
  end
end
