# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::SurfaceIndexComponent, type: :component do
  SurfaceIndexRow = Struct.new(:id, :name, keyword_init: true)

  let(:surface) do
    Member::Surface.new(
      key: :widgets, label: "Widgets", icon: :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Widgets",
        subtitle: "All widgets",
        scope: ->(_u) { [] },
        columns: [{ key: :name, label: "Name", value: ->(r) { r.name } }],
        empty_state: { headline: "Nothing here", body: "Yet.", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { r.name },
        sections: [{ key: :primary, rows: [{ key: :name, label: "Name", value: ->(r) { r.name } }] }]
      )
    )
  end

  let_it_be(:customer) { create(:customer) }

  def render_index(records:, page_meta:, **opts)
    render_inline(described_class.new(
      surface: surface, records: records, page_meta: page_meta, customer: customer, **opts
    ))
  end

  it "renders the empty state when records are empty" do
    render_index(records: [], page_meta: Pagy.new(count: 0, page: 1, limit: 20))

    expect(page).to have_css("h1", text: "Widgets")
    expect(page).to have_css("h2", text: "Nothing here")
    expect(page).not_to have_css("table")
  end

  it "renders the table when records exist" do
    rows = [SurfaceIndexRow.new(id: 1, name: "Alpha"), SurfaceIndexRow.new(id: 2, name: "Beta")]
    render_index(records: rows, page_meta: Pagy.new(count: 2, page: 1, limit: 20))

    expect(page).to have_css("table tbody tr", count: 2)
    expect(page).to have_link("View", href: "/#{customer.id}/member/widgets/1")
    expect(page).to have_link("View", href: "/#{customer.id}/member/widgets/2")
  end

  it "renders pagination when total exceeds per_page" do
    rows = (1..20).map { |i| SurfaceIndexRow.new(id: i, name: "R#{i}") }
    render_index(records: rows, page_meta: Pagy.new(count: 30, page: 1, limit: 20))

    expect(page).to have_link("Next")
  end

  it "does not render a row action button when none is configured" do
    rows = [SurfaceIndexRow.new(id: 1, name: "Alpha")]
    render_index(records: rows, page_meta: Pagy.new(count: 1, page: 1, limit: 20))

    expect(page).to have_link("View", href: "/#{customer.id}/member/widgets/1")
    expect(page).not_to have_link(href: %r{/actions/})
  end

  it "renders the row action with the overlay label and prefill path" do
    rows = [SurfaceIndexRow.new(id: 42, name: "Alpha")]
    render_index(
      records: rows,
      page_meta: Pagy.new(count: 1, page: 1, limit: 20),
      row_action: { action_key: "enroll", field: "course", label: "Enroll" }
    )

    href = Pages::ActionLink.path(
      customer_id: customer.id, action_key: "enroll", prefill: { "course" => 42 }
    )
    expect(page).to have_link("Enroll", href: href)
    expect(page).to have_link("View", href: "/#{customer.id}/member/widgets/42")
  end

  it "uses the default row action label when the overlay omits one" do
    rows = [SurfaceIndexRow.new(id: 7, name: "Alpha")]
    render_index(
      records: rows,
      page_meta: Pagy.new(count: 1, page: 1, limit: 20),
      row_action: { action_key: "enroll", field: "course" }
    )

    href = Pages::ActionLink.path(
      customer_id: customer.id, action_key: "enroll", prefill: { "course" => 7 }
    )
    expect(page).to have_link(I18n.t("member.entity_surfaces.row_action_default"), href: href)
  end

  it "does not infer a row action when the kwarg is omitted" do
    setting = Member::SurfaceSetting.new
    setting.write_overlay(row_action_key: "enroll", row_action_field: "course", row_action_label: "Open course")
    effective = Member::EffectiveSurface.new(
      descriptor: surface, settings: setting, source_key: :entities
    )
    rows = [SurfaceIndexRow.new(id: 9, name: "Alpha")]
    render_inline(described_class.new(
      surface: effective, records: rows, page_meta: Pagy.new(count: 1, page: 1, limit: 20), customer: customer
    ))

    expect(page).not_to have_link(href: %r{/actions/})
  end
end
