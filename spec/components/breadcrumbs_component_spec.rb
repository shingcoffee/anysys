# frozen_string_literal: true

require "rails_helper"

RSpec.describe BreadcrumbsComponent, type: :component do
  it "renders each crumb separated by slash" do
    rendered = render_inline(described_class.new(crumbs: [
      { label: "Entity Entries", path: "/1/entity-entries" },
      { label: "Customer",       path: nil }
    ]))
    expect(rendered.text).to include("Entity Entries")
    expect(rendered.text).to include("Customer")
    expect(rendered.text).to include("/")
    expect(rendered.css("a[href='/1/entity-entries']")).not_to be_empty
  end
end
