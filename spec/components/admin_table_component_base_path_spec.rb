# spec/components/admin_table_component_base_path_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminTableComponent, type: :component do
  it "prefixes sort/pagination links with base_path when given" do
    rows = [double(name: "X")]
    component = described_class.new(
      rows: rows,
      columns: [{ key: :name, label: "Name", sortable: true }],
      pagination: { page: 1, total_pages: 2 },
      params: { entity_id: "5" },
      base_path: "/1/admin/pages/group"
    )
    expect(component.page_link(2)).to start_with("/1/admin/pages/group?")
    expect(component.page_link(2)).to include("entity_id=5")
    link = component.sort_link_for({ key: :name, sortable: true })
    expect(link[:href]).to start_with("/1/admin/pages/group?")
  end

  it "keeps relative links when base_path is omitted" do
    component = described_class.new(
      rows: [], columns: [{ key: :name, label: "Name" }],
      pagination: {}, params: {}
    )
    expect(component.page_link(2)).to start_with("?")
  end

  # Render-depth coverage: prove the base_path actually reaches the DOM through
  # the template (search form action, sort links, and pagination links), not
  # just the helper methods in isolation.
  describe "rendered output", type: :component do
    let(:rendered) do
      render_inline(described_class.new(
        rows: [double(name: "Widget")],
        columns: [{ key: :name, label: "Name", sortable: true }],
        pagination: { page: 1, total_pages: 2 },
        params: { entity_id: "5" },
        search: { param: :q, placeholder: "Search" },
        base_path: "/1/admin/pages/group"
      ))
    end

    it "prefixes the search form action with base_path" do
      expect(rendered).to have_css("form[action='/1/admin/pages/group']")
    end

    it "prefixes the sortable column header link with base_path" do
      expect(rendered).to have_css("thead a[href^='/1/admin/pages/group?']")
    end

    it "prefixes the pagination Next link with base_path and carries params" do
      link = rendered.css("footer a").find { |a| a[:href]&.start_with?("/1/admin/pages/group?") }
      expect(link).not_to be_nil
      expect(link[:href]).to include("page=2")
      expect(link[:href]).to include("entity_id=5")
    end

    it "emits the bound target once in native search and retains it through sort and pagination" do
      target = "12345678"
      rendered = render_inline(described_class.new(
        rows: [double(name: "Widget")],
        columns: [{ key: :name, label: "Name", sortable: true }],
        pagination: { page: 2, total_pages: 3 },
        params: { "q" => "Widget", "sort" => "name", "dir" => "desc", "page" => "2", "target_customer_id" => target },
        search: { param: :q, placeholder: "Search" },
        base_path: "/81721200/admin/maintenance/platform/customers"
      ))

      form = rendered.at_css("form[method='get']")
      expect(form.css("input[name='target_customer_id']").map { |input| input["value"] }).to eq([target])
      expect(form.at_css("input[name='page']")).to be_nil
      expect(form.at_css("input[name='q']")["value"]).to eq("Widget")
      %w[sort dir].each { |key| expect(form.css("input[name='#{key}']").size).to eq(1) }
      links = rendered.css("thead a[href], footer a[href]")
      expect(links).not_to be_empty
      links.each do |link|
        expect(URI.parse(link["href"]).path).to eq(form["action"])
        expect(Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)).to include("q" => "Widget", "target_customer_id" => target)
      end
    end
  end
end
