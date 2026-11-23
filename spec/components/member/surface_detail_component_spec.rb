# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceDetailComponent, type: :component do
  let_it_be(:customer) { create(:customer) }
  let(:record) do
    SurfaceDetailRow.new(id: 7, name: "Alpha", amount_cents: 4200, refunds: [{ at: "2026-01-01", amount: 100 }])
  end
  let(:surface) do
    Member::Surface.new(
      key: :widgets, label: "Widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets", scope: ->(_u) { [] },
        columns: [{ key: :name, label: "Name", value: ->(r) { r.name } }],
        empty_state: { headline: "x", body: "y", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title:    ->(r) { "Widget #{r.name}" },
        subtitle: ->(_r) { "Subtitle" },
        meta:     ->(_r) { { label: "active", tone: :success } },
        sections: [
          { key: :primary, rows: [
              { key: :amount, label: "Amount", value: ->(r) { r.amount_cents }, format: :money_large },
              { key: :name,   label: "Name",   value: ->(r) { r.name } }
          ]},
          { key:   :refunds,
            title: "Refunds",
            when:  ->(r) { r.refunds_any? },
            list:  ->(r) { r.refunds.map { |x| { left: x[:at], right: x[:amount], format: :money } } } }
        ]
      )
    )
  end

  SurfaceDetailRow = Struct.new(:id, :name, :amount_cents, :refunds, keyword_init: true) do
    def refunds_any?
      Array(refunds).any?
    end
  end

  def render_detail(rec = record)
    render_inline(described_class.new(surface: surface, record: rec, customer: customer))
  end

  it "renders the title, subtitle, and meta from the descriptor" do
    render_detail

    expect(page).to have_css("h1", text: "Widget Alpha")
    expect(page).to have_text("Subtitle")
    expect(page).to have_css("span.badge.badge-success", text: "active")
  end

  it "renders an eyebrow back-link to the index" do
    render_detail
    expect(page).to have_link("Back to Widgets", href: "/#{customer.id}/member/widgets")
  end

  it "renders grid sections" do
    render_detail
    expect(page).to have_css("dt", text: "Amount")
    expect(page).to have_css("span.text-3xl", text: "$42.00")
    expect(page).to have_css("dt", text: "Name")
    expect(page).to have_css("dd", text: "Alpha")
  end

  it "renders list sections with title + line items" do
    render_detail
    expect(page).to have_css("h2", text: "Refunds")
    expect(page).to have_text("2026-01-01")
    expect(page).to have_text("$1.00")
  end

  it "skips a list section when its when: predicate is false" do
    no_refunds = SurfaceDetailRow.new(id: 1, name: "X", amount_cents: 0, refunds: [])
    render_detail(no_refunds)
    expect(page).not_to have_css("h2", text: "Refunds")
  end

  it "renders list item right-hand values in a monospace site size" do
    render_detail
    right_spans = page.all("li span").select do |s|
      cls = s[:class].to_s
      cls.include?("font-mono") && cls.include?("text-site-sm")
    end
    expect(right_spans).not_to be_empty
  end
end
