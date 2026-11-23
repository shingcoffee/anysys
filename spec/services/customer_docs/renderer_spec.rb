# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeveloperDocs::Renderer, "with the customer catalog" do
  def render(markdown, **options)
    described_class.call(
      markdown,
      link_resolver: ->(slug) { "/123/admin/help/docs/#{slug}" },
      labels: { "attention" => "Important", "note" => "Note" },
      anchor_label: "Link to this section",
      **options
    )
  end

  it "rewrites customer links while stripping developer, unknown, and traversal destinations" do
    result = render(<<~MD, catalog: CustomerDocs::Catalog)
      [Getting started](getting-started)
      [Users](./users.md#steps)
      [Developer guide](entity-builder)
      [Unknown guide](unknown)
      [Traversal](../overview.md)
      [Developer path](/81721200/admin/maintenance/platform/developer_docs/overview)
    MD

    anchors = Nokogiri::HTML.fragment(result.html).css("a").to_h { |anchor| [anchor.text, anchor["href"]] }
    expect(anchors).to eq(
      "Getting started" => "/123/admin/help/docs/getting-started",
      "Users" => "/123/admin/help/docs/users#steps",
      "Developer guide" => nil,
      "Unknown guide" => nil,
      "Traversal" => nil,
      "Developer path" => nil
    )
  end

  it "preserves safe external and section links and sanitizes executable content" do
    result = render(<<~MD, catalog: CustomerDocs::Catalog)
      ## Steps

      [Section](#steps)
      [External](https://example.com/help#setup)
      [Unsafe](javascript:alert(1))
      <script>alert(1)</script>
      <p onclick="alert(1)">Body</p>
    MD

    expect(result.html).to include('href="#steps"', 'href="https://example.com/help#setup"')
    expect(result.html).not_to include("javascript:", "<script", "onclick")
  end

  it "keeps the developer allow-list as the default" do
    result = render("[Developer](entity-builder)\n\n[Customer](getting-started)")
    anchors = Nokogiri::HTML.fragment(result.html).css("a").to_h { |anchor| [anchor.text, anchor["href"]] }

    expect(anchors).to eq("Developer" => "/123/admin/help/docs/entity-builder", "Customer" => nil)
  end
end
