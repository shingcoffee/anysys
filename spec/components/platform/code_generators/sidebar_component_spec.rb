# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::SidebarComponent, type: :component do
  let(:customer_id) { "81721200" }

  # -------------------------------------------------------------------------
  # Shared sidebar data fixtures
  # -------------------------------------------------------------------------
  let(:element_type_items) do
    [
      { kind: "element_type", key: "start",    label: "Start",    count: 3 },
      { kind: "element_type", key: "decision", label: "Decision", count: 2 },
      { kind: "element_type", key: "loop",     label: "Loop",     count: 1 },
      { kind: "element_type", key: "end",      label: "End",      count: 4 },
      { kind: "element_type", key: "subflow",  label: "Subflow",  count: 2 }
    ]
  end

  let(:step_action_items) do
    [
      { kind: "step_action", key: "validation",       label: "Validation",       count: 5 },
      { kind: "step_action", key: "model_operations", label: "Model Operations", count: 8 }
    ]
  end

  let(:sidebar_data) { element_type_items + step_action_items }

  # Render with the shared defaults (full sidebar_data); any keyword overrides.
  def render_sidebar(**opts)
    render_inline(described_class.new(**{
      sidebar_data: sidebar_data,
      customer_id:  customer_id
    }.merge(opts)))
  end

  # -------------------------------------------------------------------------
  # Base rendering
  # -------------------------------------------------------------------------
  describe "base rendering" do
    subject(:rendered) { render_sidebar(total_count: 20) }

    it "renders the nav element with data-controller=generator-search" do
      expect(rendered.css("nav[data-controller='generator-search']")).not_to be_empty
    end

    it "renders 'Code Generators' header text" do
      expect(rendered.text).to include("Code Generators")
    end

    it "displays the total count" do
      expect(rendered.text).to include("20 generators")
    end

    it "renders the search input" do
      expect(rendered.css("input[placeholder='Search generators...']")).not_to be_empty
    end

    it "renders the search results container (initially hidden)" do
      expect(rendered.css("[data-generator-search-target='searchResults']")).not_to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # Element type partitioning: primary vs secondary
  # -------------------------------------------------------------------------
  describe "primary element types" do
    subject(:rendered) { render_sidebar }

    it "renders Start (first primary) before the Process group" do
      expect(rendered.text).to include("Start")
    end

    it "renders Decision, Loop, End (remaining primaries)" do
      %w[Decision Loop End].each { |label| expect(rendered.text).to include(label) }
    end

    it "links Start to the element_type filter URL" do
      expected = "/#{customer_id}/admin/maintenance/platform/code_generators?element_type=start"
      expect(rendered.css("a[href='#{expected}']")).not_to be_empty
    end

    it "shows the count badge on each primary element type" do
      expect(rendered.text).to include("3")  # start count
    end
  end

  describe "secondary element types" do
    it "renders the 'More Elements' collapsible section when secondary items exist" do
      expect(render_sidebar.text).to include("More Elements")
    end

    it "shows the secondary count in the toggle" do
      # subflow is the only secondary item
      expect(render_sidebar.text).to include("1")
    end

    it "does not render 'More Elements' when there are no secondary element types" do
      primary_only = element_type_items.first(4) + step_action_items
      expect(render_sidebar(sidebar_data: primary_only).text).not_to include("More Elements")
    end

    it "renders secondary items as links with element_type filter" do
      expected = "/#{customer_id}/admin/maintenance/platform/code_generators?element_type=subflow"
      expect(render_sidebar.css("a[href='#{expected}']")).not_to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # Step action (Process) group
  # -------------------------------------------------------------------------
  describe "step action categories" do
    subject(:rendered) { render_sidebar }

    it "renders the Process group toggle button" do
      expect(rendered.text).to include("Process")
    end

    it "renders each step action category label" do
      expect(rendered.text).to include("Validation")
      expect(rendered.text).to include("Model Operations")
    end

    it "links each step action category with kind=step_action and category filter" do
      expected = "/#{customer_id}/admin/maintenance/platform/code_generators?category=validation&kind=step_action"
      expect(rendered.css("a[href='#{expected}']")).not_to be_empty
    end

    it "shows the step action total count in the Process toggle" do
      # 5 + 8 = 13
      expect(rendered.text).to include("13")
    end
  end

  # -------------------------------------------------------------------------
  # Active state
  # -------------------------------------------------------------------------
  describe "active category highlighting" do
    it "marks the Process group as active and expands it when active_category is set" do
      rendered = render_sidebar(active_category: "validation")
      # active button uses text-accent font-medium, and the content div loses 'hidden'
      active_toggle = rendered.css("button.font-medium")
      expect(active_toggle).not_to be_empty
    end

    it "highlights the active step action category link" do
      rendered = render_sidebar(active_category: "validation")
      # active links include text-accent font-medium
      expect(rendered.css("a.font-medium")).not_to be_empty
    end

    it "highlights the active element type link" do
      rendered = render_sidebar(active_element_type: "start")
      # active element type links contain text-indigo-700
      expect(rendered.css("a.text-indigo-700")).not_to be_empty
    end

    it "does not mark Process group as active when no category is active" do
      rendered = render_sidebar
      # Process group content div should be hidden
      group_content = rendered.css("[data-generator-nav-target='groupContent']").first
      expect(group_content["class"]).to include("hidden")
    end
  end

  # -------------------------------------------------------------------------
  # Secondary active state — expands More Elements
  # -------------------------------------------------------------------------
  describe "secondary_active? expansion" do
    it "expands More Elements when active_element_type is a secondary item" do
      rendered = render_sidebar(active_element_type: "subflow")
      # The secondary group content div should NOT have 'hidden'
      secondary_group_content = rendered.css("[data-generator-nav-target='groupContent']").last
      expect(secondary_group_content["class"]).not_to include("hidden")
    end
  end

  # -------------------------------------------------------------------------
  # Element type dot colors
  # -------------------------------------------------------------------------
  describe "element type dot colors" do
    subject(:rendered) { render_sidebar }

    it "uses bg-green-500 for start element type" do
      expect(rendered.css("span.bg-green-500")).not_to be_empty
    end

    it "uses bg-amber-500 for decision element type" do
      expect(rendered.css("span.bg-amber-500")).not_to be_empty
    end

    it "uses bg-red-500 for end element type" do
      expect(rendered.css("span.bg-red-500")).not_to be_empty
    end
  end

  # -------------------------------------------------------------------------
  # search_index_json
  # -------------------------------------------------------------------------
  describe "search index" do
    it "embeds the search index JSON in the data attribute" do
      index = [{ name: "check_presence", path: "validation/check_presence_generator" }]
      rendered = render_sidebar(search_index: index)
      expect(rendered.css("[data-generator-search-index-value]").first["data-generator-search-index-value"])
        .to include("check_presence")
    end

    it "defaults to an empty JSON array when search_index is not supplied" do
      rendered = render_sidebar
      val = rendered.css("[data-generator-search-index-value]").first["data-generator-search-index-value"]
      expect(val).to eq("[]")
    end
  end

  # -------------------------------------------------------------------------
  # Empty sidebar_data
  # -------------------------------------------------------------------------
  describe "with no sidebar data" do
    it "renders without error and shows 0 generators" do
      rendered = render_sidebar(sidebar_data: [], total_count: 0)
      expect(rendered.text).to include("0 generators")
    end
  end
end
