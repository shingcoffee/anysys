# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuickActionCardComponent, type: :component do
  it "renders a linked card with label and description" do
    rendered = render_inline(described_class.new(label: "Create Entity", description: "Set up a new data type", path: "/x"))
    expect(rendered.css("a[href='/x']")).not_to be_empty
    expect(rendered.text).to include("Create Entity")
    expect(rendered.text).to include("Set up a new data type")
  end

  it "renders a compact list row" do
    rendered = render_inline(
      described_class.new(label: "Invite user", description: "Add a teammate", path: "/users/new", compact: true)
    )
    expect(rendered.css("a[href='/users/new']")).not_to be_empty
    expect(rendered.text).to include("Invite user")
    expect(rendered).to have_css("a.px-4.py-3.no-underline")
    expect(rendered).to have_css("a.focus-visible\\:ring-2")
  end

  it "applies custom icon_classes in compact mode when provided" do
    rendered = render_inline(
      described_class.new(
        label: "Invite user",
        description: "Add a teammate",
        path: "/users/new",
        compact: true,
        icon_classes: "bg-success-subtle text-success"
      )
    )
    expect(rendered).to have_css("div.bg-success-subtle.text-success")
  end
end
