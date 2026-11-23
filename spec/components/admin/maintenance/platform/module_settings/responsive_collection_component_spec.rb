# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::ModuleSettings::ResponsiveCollectionComponent, type: :component do
  it "renders a complete ARIA table relationship around one responsive content tree" do
    render_inline(described_class.new(label: "SMS templates", columns: %w[Template Status Actions])) do
      '<div role="row" data-responsive-collection-record="verify_code"><span role="cell">verify_code</span><span role="cell">Active</span><span role="cell">Edit Delete</span></div>'.html_safe
    end

    expect(page).to have_css("[data-responsive-collection='true'][role='table'][aria-label='SMS templates'][aria-colcount='3']")
    expect(page).to have_css("[role='rowgroup'] [role='row'] [role='columnheader']", count: 3, visible: :all)
    expect(page).to have_css("[data-responsive-collection-body][role='rowgroup'] [role='row'] [role='cell']", count: 3)
    expect(page).to have_css("[data-responsive-collection-mobile-label]")
    expect(page).to have_css("[data-responsive-collection-record='verify_code']", count: 1)
  end

  it "renders sortable column actions with active direction feedback" do
    columns = [
      { label: "Template", sort_path: "/templates?q=code&sort=key&dir=desc", sort_direction: :ascending },
      { label: "Status", sort_path: "/templates?q=code&sort=status&dir=asc" }
    ]
    render_inline(described_class.new(label: "SMS templates", columns: columns)) { "" }

    expect(page).to have_css("[role='columnheader'][aria-sort='ascending']", text: "Template", visible: :all)
    expect(page).to have_link("Template", href: "/templates?q=code&sort=key&dir=desc", visible: :all)
    expect(page).to have_css("[role='columnheader'][aria-sort='none']", text: "Status", visible: :all)
  end

  it "contains any tablet overflow locally instead of widening the document" do
    render_inline(described_class.new(label: "Webhook events", columns: %w[Provider Event Status Actions])) { "Records" }

    expect(page).to have_css("[data-responsive-collection-viewport].overflow-x-auto")
    expect(page).to have_css("[data-responsive-collection-body]", text: "Records")
  end
end
