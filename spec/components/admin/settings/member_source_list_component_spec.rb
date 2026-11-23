require "rails_helper"

RSpec.describe Admin::Settings::MemberSourceListComponent, type: :component do
  let(:customer) { build_stubbed(:customer) }
  let(:source) { Member::Sources::Modules }

  it "labels immediate saves and mounts the existing searchable-list controller" do
    render_inline(described_class.new(rows: [], source: source, customer: customer))
    expect(page).to have_text("Visibility changes save immediately.")
    expect(page).to have_field("Search pages")
    expect(page).to have_css("input[data-list-filter-target='search'][data-action='input->list-filter#search']")
    expect(page).to have_text("No pages to display.")
  end

  it "explains why core pages are read-only" do
    render_inline(described_class.new(rows: [], source: Member::Sources::Builtin, customer: customer))
    expect(page).to have_text("These core pages cannot be hidden or reordered.")
    expect(page).not_to have_text("Visibility changes save immediately.")
    expect(page).to have_link("Core pages", href: "/#{customer.id}/admin/settings/member/sources/builtin")
    expect(page).to have_css("a[aria-current='page']", text: "Core pages", count: 1)
  end

  it "links the Pages source tab" do
    render_inline(described_class.new(rows: [], source: Member::Sources::Pages, customer: customer))
    expect(page).to have_css("a[aria-current='page'][href='/#{customer.id}/admin/settings/member/sources/pages']", text: "Pages")
  end
end
