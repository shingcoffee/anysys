# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::HistoryFiltersComponent, type: :component do
  def render_filters(**options)
    render_inline described_class.new(action: "/81721200/admin/maintenance/platform/billing/invoices",
      filters: { q: "INV_%", status: "uncollectible", tenant_id: "12345678" },
      query_key: "comp_billing.history.invoice_query", statuses: Billing::Invoice::STATUSES,
      status_prefix: "comp_billing.invoice_table.statuses", tenant_filter: true, **options)
  end

  it "retains GET filters and locale while resetting the page on submission" do
    render_filters
    expect(page).to have_css('form[method="get"]')
    expect(page).to have_field("q", with: "INV_%")
    expect(page).to have_select("status", selected: "Uncollectible")
    expect(page).to have_field("tenant_id", with: "12345678")
    expect(page).to have_css('input[name="locale"][value="en"]', visible: :all)
    expect(page).not_to have_css('input[name="page"]', visible: :all)
    expect(page).to have_link("Reset", href: "/81721200/admin/maintenance/platform/billing/invoices")
  end

  it "localizes labels and escapes a literal query without adding a tenant filter" do
    I18n.with_locale(:"zh-CN") do
      render_filters(tenant_filter: false, filters: { "q" => "<script>query</script>" })
      expect(page).to have_field(I18n.t("comp_billing.history.invoice_query"), with: "<script>query</script>")
      expect(page).not_to have_field("tenant_id")
      expect(page).not_to have_css("script, .translation_missing")
    end
  end
end
