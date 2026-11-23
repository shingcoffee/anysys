# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminTableComponent, type: :component do
  let(:alpha) { OpenStruct.new(id: 1, name: "Alpha", status: "active",  updated_at: Time.utc(2026, 5, 14, 12, 0)) }
  let(:beta)  { OpenStruct.new(id: 2, name: "Beta",  status: "draft",   updated_at: Time.utc(2026, 5, 13, 12, 0)) }
  let(:rows)  { [alpha, beta] }
  let(:pagination) { { page: 1, per_page: 25, total: 2, total_pages: 1 } }
  let(:columns) do
    [
      { key: :name,       label: "Name",   sortable: true,  searchable: true },
      { key: :status,     label: "Status", type: :badge,
        badge: ->(r) { { variant: r.status == "active" ? :success : :default, label: r.status.titleize } } },
      { key: :updated_at, label: "Updated", type: :datetime, sortable: true }
    ]
  end

  def render_table(**overrides)
    args = {
      rows:        rows,
      columns:     columns,
      pagination:  pagination,
      params:      {},
      search:      { param: :q },
      filters:     [],
      row_path:    nil,
      row_actions: nil,
      empty_state: nil
    }.merge(overrides)
    render_inline(described_class.new(**args))
  end

  # Bare component (no toolbar defaults) for exercising helper methods directly.
  def build_component(**overrides)
    described_class.new(**{ rows: rows, columns: columns, pagination: pagination, params: {} }.merge(overrides))
  end

  it "wraps the table in a turbo-frame so search/sort/page swap only the table region" do
    rendered = render_table
    frame = rendered.css("turbo-frame").first
    expect(frame).not_to be_nil
    expect(frame["id"]).to eq("admin-table")
    expect(frame["data-turbo-action"]).to eq("advance")
  end

  it "scopes the search form to the table frame so the chrome is not re-rendered" do
    rendered = render_table(search: { param: :q })
    form = rendered.css("form").first
    expect(form["data-turbo-frame"]).to eq("admin-table")
    expect(form["data-turbo-action"]).to eq("advance")
  end

  it "lets the caller pick a unique frame id when more than one table is on a page" do
    rendered = render_inline(described_class.new(
      rows: rows, columns: columns, pagination: pagination,
      params: {}, frame_id: "left-table"
    ))
    expect(rendered.css("turbo-frame#left-table")).not_to be_empty
  end

  it "renders one header per column" do
    render_table
    expect(page).to have_text("Name")
    expect(page).to have_text("Status")
    expect(page).to have_text("Updated")
  end

  it "renders one row per record" do
    rendered = render_table
    expect(rendered.css("tbody tr").length).to eq(2)
  end

  it "renders cell values from the row" do
    expect(render_table.text).to include("Alpha", "Beta")
  end

  describe "toolbar" do
    it "renders a search input when search config is provided" do
      rendered = render_table(search: { param: :q, placeholder: "Find me" })
      expect(rendered.css("input[type='search'][name='q']")).not_to be_empty
      expect(rendered.css("input[placeholder='Find me']")).not_to be_empty
    end

    it "renders filter selects" do
      rendered = render_table(filters: [
        { key: :status, label: "Status", options: [["Active", "active"], ["Draft", "draft"]] }
      ])
      expect(rendered.css("select[name='status']")).not_to be_empty
      expect(rendered.css("select[name='status'] option[value='active']")).not_to be_empty
    end

    it "preserves the current search value" do
      rendered = render_table(search: { param: :q }, params: { q: "alpha" })
      expect(rendered.css("input[type='search'][value='alpha']")).not_to be_empty
    end
  end

  describe "sortable headers" do
    it "links sortable headers with sort/dir query params" do
      rendered = render_table(params: { sort: "name", dir: "asc" })
      header = rendered.css("th a").find { |a| a.text.include?("Name") }
      expect(header[:href]).to include("sort=name", "dir=desc")
    end

    it "renders an arrow next to the active sort column" do
      rendered = render_table(params: { sort: "name", dir: "asc" })
      header = rendered.css("th").find { |th| th.text.include?("Name") }
      expect(header.text).to include("↑")
    end

    it "does not link non-sortable columns" do
      cols = columns.map { |c| c[:key] == :status ? c.merge(sortable: false) : c }
      rendered = render_table(columns: cols)
      status_header = rendered.css("th").find { |th| th.text.include?("Status") }
      expect(status_header.css("a")).to be_empty
    end
  end

  describe "badges" do
    it "renders badge cells using the BadgeComponent" do
      rendered = render_table
      expect(rendered.css(".badge")).not_to be_empty
      expect(rendered.text).to include("Active", "Draft")
    end

    it "renders multiple badges when the badge lambda returns an array" do
      multi = [
        { key: :name, label: "Name", sortable: true, searchable: true },
        { key: :audiences, label: "Visibility", type: :badge,
          badge: ->(_r) { [
            { variant: :warning, label: "Admin" },
            { variant: :purple, label: "Member" }
          ] } }
      ]
      rendered = render_table(columns: multi)
      badges = rendered.css("td .badge").map(&:text).map(&:strip)
      expect(badges).to include("Admin", "Member")
    end
  end

  describe "row interactions" do
    it "wraps the first cell in a link when row_path is provided" do
      rendered = render_table(row_path: ->(r) { "/rows/#{r.id}" })
      expect(rendered.css("a[href='/rows/1']")).not_to be_empty
    end

    it "links only the columns flagged link: true" do
      cols = [
        { key: :id, label: "ID", link: true },
        { key: :name, label: "Name", link: true },
        { key: :status, label: "Status" }
      ]
      rendered = render_table(columns: cols, row_path: ->(r) { "/rows/#{r.id}" })
      expect(rendered.css("tbody a[href='/rows/1']").map { |anchor| anchor.text.strip }).to eq(["1", "Alpha"])
      expect(rendered.css("tbody tr").first.css("td").last.css("a")).to be_empty
    end

    it "shows a later column on the mobile card when mobile: true" do
      cols = [
        { key: :name, label: "Name" },
        { key: :status, label: "Status" },
        { key: :note, label: "Note" },
        { key: :created_at, label: "Created", type: :datetime, mobile: true }
      ]
      row = OpenStruct.new(id: 1, name: "Alpha", status: "active", note: "n", created_at: Time.utc(2026, 5, 14, 12, 0))
      rendered = render_table(rows: [row], columns: cols, search: nil)
      mobile = rendered.css("div").find { |node| node["class"].to_s.split.include?("sm:hidden") }
      expect(mobile.text).to include("Created")
      expect(mobile.css("time").first["datetime"]).to eq(Time.utc(2026, 5, 14, 12, 0).iso8601)
    end

    it "defaults the row_path link to turbo-frame _top" do
      rendered = render_table(row_path: ->(r) { "/rows/#{r.id}" })
      anchor = rendered.css("a[href='/rows/1']").first
      expect(anchor["data-turbo-frame"]).to eq("_top")
    end

    it "lets the caller pin the row_path link to a specific frame" do
      rendered = render_table(
        row_path: ->(r) { "/rows/#{r.id}" },
        row_path_data: { turbo_frame: "page-publishing" }
      )
      anchor = rendered.css("a[href='/rows/1']").first
      expect(anchor["data-turbo-frame"]).to eq("page-publishing")
    end

    it "passes target and rel through on row actions" do
      rendered = render_table(row_actions: ->(r) {
        [{ label: "Preview", path: "/p/#{r.id}", target: "_blank", rel: "noopener noreferrer" }]
      })
      anchor = rendered.css("a[href='/p/1']").first
      expect(anchor["target"]).to eq("_blank")
      expect(anchor["rel"]).to eq("noopener noreferrer")
    end

    it "renders row_actions in the last column" do
      rendered = render_table(row_actions: ->(r) {
        [{ label: "Edit", path: "/rows/#{r.id}/edit" }]
      })
      expect(rendered.css("a[href='/rows/1/edit']")).not_to be_empty
    end

    it "translates non-GET row_action methods into data-turbo-method attributes" do
      rendered = render_table(row_actions: ->(r) {
        [{ label: "Act As", path: "/act/#{r.id}", method: :patch }]
      })
      anchor = rendered.css("a[href='/act/1']").first
      expect(anchor).not_to be_nil
      expect(anchor["data-turbo-method"]).to eq("patch")
    end

    it "preserves data attributes the caller supplied" do
      rendered = render_table(row_actions: ->(r) {
        [{ label: "Restore", path: "/r/#{r.id}", method: :patch, data: { turbo_confirm: "Sure?" } }]
      })
      anchor = rendered.css("a[href='/r/1']").first
      expect(anchor["data-turbo-method"]).to eq("patch")
      expect(anchor["data-turbo-confirm"]).to eq("Sure?")
    end

    it "renders an Actions header above the actions cell" do
      rendered = render_table(row_actions: ->(_) { [{ label: "Edit", path: "/x" }] })
      expect(rendered.css("th").map(&:text).map(&:strip)).to include("Actions")
    end

    it "escapes the table turbo-frame on row actions" do
      rendered = render_table(row_actions: ->(r) { [{ label: "Edit", path: "/e/#{r.id}" }] })
      anchor = rendered.css("a[href='/e/1']").first
      expect(anchor["data-turbo-frame"]).to eq("_top")
    end

    it "lets the caller pin a row action to a specific frame" do
      rendered = render_table(row_actions: ->(r) { [
        { label: "Quick", path: "/q/#{r.id}", data: { turbo_frame: "modal" } }
      ] })
      anchor = rendered.css("a[href='/q/1']").first
      expect(anchor["data-turbo-frame"]).to eq("modal")
    end

    it "tones DELETE actions red and other actions muted" do
      rendered = render_table(row_actions: ->(r) { [
        { label: "Edit",   path: "/e/#{r.id}" },
        { label: "Delete", path: "/d/#{r.id}", method: :delete }
      ] })
      edit_link   = rendered.css("a[href='/e/1']").first
      delete_link = rendered.css("a[href='/d/1']").first
      expect(edit_link["class"]).to   include("text-text-secondary")
      expect(delete_link["class"]).to include("text-danger")
    end

    it "separates actions with a hairline vertical rule" do
      rendered = render_table(row_actions: ->(r) { [
        { label: "Edit", path: "/e/#{r.id}" },
        { label: "Copy", path: "/c/#{r.id}" }
      ] })
      dividers = rendered.css("td span[aria-hidden='true']")
      expect(dividers).not_to be_empty
      # one divider between two actions per row, two rows in fixture => two dividers
      expect(dividers.size).to eq(2)
      expect(dividers.first["class"]).to include("w-px", "bg-border-subtle/80")
    end
  end

  describe "symbolize_params — ActionController::Parameters path" do
    it "handles ActionController::Parameters (to_unsafe_h path)" do
      params = ActionController::Parameters.new(sort: "name", dir: "asc")
      rendered = render_inline(described_class.new(
        rows: rows, columns: columns, pagination: pagination,
        params: params, search: { param: :q }
      ))
      expect(rendered.css("turbo-frame")).not_to be_empty
    end
  end

  describe "cell_value / cell_text type branches" do
    let(:now) { Time.utc(2026, 6, 15, 8, 30) }
    let(:date_row) { OpenStruct.new(id: 3, created_on: Date.new(2026, 6, 15), flag: true, note: "hello world") }

    it "uses the cell lambda when provided" do
      cols = [{ key: :id, label: "ID", cell: ->(r) { "custom-#{r.id}" } }]
      rendered = render_table(rows: [alpha], columns: cols)
      expect(rendered.text).to include("custom-1")
    end

    it "formats :date cells with the locale long date" do
      cols = [{ key: :created_on, label: "Date", type: :date }]
      rendered = render_table(rows: [date_row], columns: cols)
      expect(rendered.text).to include(I18n.l(Date.new(2026, 6, 15), format: :long))
    end

    it "truncates :truncate cells" do
      cols = [{ key: :note, label: "Note", type: :truncate, truncate: 5 }]
      rendered = render_table(rows: [date_row], columns: cols)
      expect(rendered.text).to include("...")
    end

    it "renders :boolean true as 'Yes'" do
      cols = [{ key: :flag, label: "Active?", type: :boolean }]
      rendered = render_table(rows: [date_row], columns: cols)
      expect(rendered.text).to include("Yes")
    end

    it "renders :boolean false as 'No'" do
      falsy_row = OpenStruct.new(id: 4, flag: false)
      cols = [{ key: :flag, label: "Active?", type: :boolean }]
      rendered = render_table(rows: [falsy_row], columns: cols)
      expect(rendered.text).to include("No")
    end

    it "renders :number cells as plain text" do
      num_row = OpenStruct.new(id: 5, count: 42)
      cols = [{ key: :count, label: "Count", type: :number }]
      rendered = render_table(rows: [num_row], columns: cols)
      expect(rendered.text).to include("42")
    end

    it "renders nil datetime cells as —" do
      nil_row = OpenStruct.new(id: 6, updated_at: nil)
      cols = [{ key: :updated_at, label: "Updated", type: :datetime }]
      rendered = render_table(rows: [nil_row], columns: cols)
      expect(rendered.text).to include("—")
    end

    it "renders a non-strftime datetime value as its to_s" do
      str_row = OpenStruct.new(id: 7, updated_at: "not-a-time")
      cols = [{ key: :updated_at, label: "Updated", type: :datetime }]
      rendered = render_table(rows: [str_row], columns: cols)
      expect(rendered.text).to include("not-a-time")
    end

    it "renders nil date cells as —" do
      nil_row = OpenStruct.new(id: 8, created_on: nil)
      cols = [{ key: :created_on, label: "Date", type: :date }]
      rendered = render_table(rows: [nil_row], columns: cols)
      expect(rendered.text).to include("—")
    end

    it "renders a non-strftime date value as its to_s" do
      str_row = OpenStruct.new(id: 9, created_on: "not-a-date")
      cols = [{ key: :created_on, label: "Date", type: :date }]
      rendered = render_table(rows: [str_row], columns: cols)
      expect(rendered.text).to include("not-a-date")
    end
  end

  describe "alignment_class" do
    it "applies text-right for right-aligned columns" do
      cols = columns.map { |c| c[:key] == :name ? c.merge(align: :right) : c }
      rendered = render_table(columns: cols)
      expect(rendered.css("td.text-right")).not_to be_empty
    end

    it "applies text-center for center-aligned columns" do
      cols = columns.map { |c| c[:key] == :name ? c.merge(align: :center) : c }
      rendered = render_table(columns: cols)
      expect(rendered.css("td.text-center")).not_to be_empty
    end
  end

  describe "badge_for" do
    it "returns nil for a non-badge column" do
      component = described_class.new(rows: rows, columns: columns, pagination: pagination, params: {})
      non_badge_col = columns.first
      expect(component.badge_for(alpha, non_badge_col)).to be_nil
    end

    it "returns nil for a badge column with no callable badge" do
      no_callable_badge_col = { key: :status, label: "Status", type: :badge }
      component = described_class.new(rows: rows, columns: [no_callable_badge_col], pagination: pagination, params: {})
      expect(component.badge_for(alpha, no_callable_badge_col)).to be_nil
    end
  end

  describe "empty_after_search?" do
    it "returns false when rows are not empty" do
      component = described_class.new(rows: rows, columns: columns, pagination: pagination,
                                      params: { q: "alpha" }, search: { param: :q })
      expect(component.empty_after_search?).to be_falsy
    end

    it "returns false when search is nil and no filters are active" do
      component = described_class.new(rows: [], columns: columns, pagination: pagination,
                                      params: { q: "z" }, search: nil)
      expect(component.empty_after_search?).to be_falsy
    end

    it "returns falsy when search param value is blank" do
      component = described_class.new(rows: [], columns: columns, pagination: pagination,
                                      params: { q: "" }, search: { param: :q })
      expect(component.empty_after_search?).to be_falsy
    end

    it "returns true when rows are empty and a filter is active" do
      component = described_class.new(
        rows: [], columns: columns, pagination: pagination,
        params: { status: "active" }, search: { param: :q },
        filters: [{ key: :status, label: "Status", options: [["Active", "active"]] }]
      )
      expect(component.empty_after_search?).to be(true)
    end
  end

  describe "row_menu_actions" do
    it "renders an icon-only kebab menu labelled for assistive tech" do
      rendered = render_table(row_menu_actions: ->(r) {
        [{ label: "Preview", path: "/p/#{r.id}" }]
      })
      summary = rendered.css("details summary").first
      expect(summary["aria-label"]).to eq(I18n.t("common.actions.more"))
      expect(summary["role"]).to eq("button")
      # icon-only trigger: the label is not painted as visible text
      expect(summary.css("svg circle").size).to eq(3)
      expect(summary.text.strip).to be_empty
      expect(rendered.css("details a[href='/p/1']")).not_to be_empty
      expect(rendered.css("th").map(&:text).map(&:strip)).to include("Actions")
    end

    it "can combine inline row_actions with a More menu" do
      rendered = render_table(
        row_actions: ->(r) { [{ label: "Edit", path: "/e/#{r.id}" }] },
        row_menu_actions: ->(r) { [{ label: "Preview", path: "/p/#{r.id}" }] }
      )
      expect(rendered.css("a[href='/e/1']")).not_to be_empty
      expect(rendered.css("details a[href='/p/1']")).not_to be_empty
    end
  end

  describe "action_tone_class — danger via explicit tone" do
    it "marks tone: :danger actions as red regardless of method" do
      rendered = render_table(row_actions: ->(r) {
        [{ label: "Archive", path: "/a/#{r.id}", tone: :danger }]
      })
      anchor = rendered.css("a[href='/a/1']").first
      expect(anchor["class"]).to include("text-danger")
    end
  end

  describe "sort_link_for — desc arrow when active desc sort" do
    it "renders ↓ arrow when column is sorted descending" do
      rendered = render_table(params: { sort: "name", dir: "desc" })
      header = rendered.css("th").find { |th| th.text.include?("Name") }
      expect(header.text).to include("↓")
    end

    it "returns nil for non-sortable columns" do
      component = described_class.new(rows: rows, columns: columns, pagination: pagination, params: {})
      non_sortable = { key: :status, label: "Status", sortable: false }
      expect(component.sort_link_for(non_sortable)).to be_nil
    end
  end

  describe "pagination" do
    it "renders Page x of y when total_pages > 1" do
      rendered = render_table(pagination: { page: 1, per_page: 1, total: 2, total_pages: 2 })
      expect(rendered.text).to include("Page 1")
      expect(rendered.text).to include("of 2")
    end

    it "links Next using the next page" do
      rendered = render_table(pagination: { page: 1, per_page: 1, total: 2, total_pages: 2 })
      expect(rendered.css("a[href*='page=2']")).not_to be_empty
    end
  end

  describe "subtitle" do
    it "renders a muted subtitle under the primary cell on desktop and mobile" do
      cols = [
        { key: :name, label: "Name", subtitle: ->(r) { "Subject for #{r.name}" } },
        { key: :status, label: "Status" }
      ]
      rows_with = [OpenStruct.new(id: 1, name: "Alpha", status: "active")]
      render_inline(described_class.new(
        rows: rows_with, columns: cols, pagination: pagination, params: {},
        row_path: ->(r) { "/rows/#{r.id}" }
      ))
      expect(page).to have_css("a.link", text: "Alpha")
      expect(page).to have_css(".text-text-muted", text: "Subject for Alpha")
    end
  end

  describe "leading icon" do
    it "renders a tinted icon tile before the primary cell when a leading spec is given" do
      cols = [
        { key: :name, label: "Name", leading: ->(_) { { icon: :document, tone: :accent } } },
        { key: :status, label: "Status" }
      ]
      rows_with = [OpenStruct.new(id: 1, name: "Alpha", status: "active")]
      rendered = render_inline(described_class.new(
        rows: rows_with, columns: cols, pagination: pagination, params: {},
        row_path: ->(r) { "/rows/#{r.id}" }
      ))
      tile = rendered.css("span.rounded-lg svg path").first
      expect(tile).not_to be_nil
      expect(tile[:d]).to eq(described_class::LEADING_ICONS[:document])
      expect(rendered.css("span.bg-accent-subtle")).not_to be_empty
    end

    it "falls back to the default tone for an unknown tone key" do
      cols = [{ key: :name, label: "Name", leading: ->(_) { { icon: :code, tone: :nope } } }]
      rendered = render_table(columns: cols)
      expect(rendered.css("span.bg-surface-active")).not_to be_empty
    end

    it "renders no tile when the leading lambda returns blank or an unknown icon" do
      cols = [{ key: :name, label: "Name", leading: ->(_) { { icon: :missing } } }]
      rendered = render_table(columns: cols)
      expect(rendered.css("span.rounded-lg svg")).to be_empty
    end

    it "renders no tile when the column has no leading option" do
      rendered = render_table
      expect(rendered.css("td span.rounded-lg svg")).to be_empty
    end
  end

  describe "plain cell treatment" do
    it "applies mono, nowrap, and break classes only on columns that opt in" do
      cols = [
        { key: :name, label: "Name" },
        { key: :code, label: "Code", mono: true, nowrap: true, break: true }
      ]
      rendered = render_inline(described_class.new(
        rows: [OpenStruct.new(id: 1, name: "Alpha", code: "acme.example.com")],
        columns: cols,
        pagination: pagination,
        params: {}
      ))

      spans = rendered.css("span.font-mono")
      expect(spans.map { |span| span.text }).to all(eq("acme.example.com"))
      expect(spans).not_to be_empty
      spans.each do |span|
        expect(span[:class]).to include("whitespace-nowrap", "break-all", "tabular-nums", "text-text-primary")
      end
      name_cell = rendered.css("td").find { |cell| cell.text.strip == "Alpha" }
      expect(name_cell&.at_css("span.font-mono")).to be_nil
    end
  end

  describe "display: false" do
    it "omits non-display columns from headers and cells but keeps them in the columns list for callers" do
      cols = [
        { key: :name, label: "Name" },
        { key: :subject, label: "Subject", display: false, searchable: true },
        { key: :status, label: "Status" }
      ]
      render_table(columns: cols)
      expect(page).to have_text("Name")
      expect(page).to have_text("Status")
      expect(page).not_to have_css("th", text: "Subject")
    end
  end

  describe "result count summary" do
    it "renders a plain total when everything fits on one page" do
      rendered = render_table(pagination: { page: 1, per_page: 25, total: 2, total_pages: 1 })
      expect(rendered.text).to include(I18n.t("chrome.admin_table.result_count", count: 2))
    end

    it "renders a showing-range while paginated" do
      rendered = render_table(pagination: { page: 1, per_page: 25, total: 40, total_pages: 2 })
      expect(rendered.text).to include(
        I18n.t("chrome.admin_table.showing_range", from: 1, to: 2, total: 40)
      )
    end

    it "offsets the range by the current page" do
      component = build_component(pagination: { page: 3, per_page: 25, total: 100, total_pages: 4 })
      expect(component.showing_from).to eq(51)
      expect(component.showing_to).to eq(52)
    end

    it "renders no summary when the caller supplies no total" do
      component = build_component(pagination: { page: 1, per_page: 25, total_pages: 1 })
      expect(component.count_summary).to be_nil
    end

    it "still renders the toolbar for a count-only table with no search or filters" do
      rendered = render_inline(described_class.new(
        rows: rows, columns: columns, pagination: pagination, params: {}
      ))
      expect(rendered.css("header")).not_to be_empty
      expect(rendered.css("input[type='search']")).to be_empty
    end
  end

  describe "active filter chips" do
    let(:status_filter) do
      [{ key: :status, label: "Status", options: [["Active", "active"], ["Draft", "draft"]] }]
    end

    it "renders a chip per active filter that links to the same view without it" do
      rendered = render_table(filters: status_filter, params: { status: "active", q: "welcome" })
      chip = rendered.css("a[title='#{I18n.t('chrome.admin_table.remove_filter', label: 'Status')}']").first
      expect(chip).not_to be_nil
      expect(chip.text).to include("Status", "Active")
      # drops its own filter, keeps the sibling search term
      expect(chip[:href]).to include("q=welcome")
      expect(chip[:href]).not_to include("status=active")
    end

    it "shows the raw value when it matches no configured option" do
      rendered = render_table(filters: status_filter, params: { status: "mystery" })
      expect(rendered.text).to include("mystery")
    end

    it "renders a clear-all link that drops every filter but keeps the search" do
      rendered = render_table(filters: status_filter, params: { status: "active", q: "welcome" })
      clear = rendered.css("a").find { |a| a.text.strip == I18n.t("chrome.admin_table.clear_filters") }
      expect(clear).not_to be_nil
      expect(clear[:href]).to include("q=welcome")
      expect(clear[:href]).not_to include("status=")
    end

    it "renders no chips when no filter is active" do
      rendered = render_table(filters: status_filter, params: {})
      expect(rendered.css("a").map(&:text).join).not_to include(I18n.t("chrome.admin_table.clear_filters"))
    end

    it "omits a chip when the value is the filter default" do
      rendered = render_table(
        filters: [{ key: :role, label: "Role", default: "member", options: [["Member", "member"], ["Admin", "admin"]] }],
        params: { role: "member" }
      )
      expect(rendered.css("a").map(&:text).join).not_to include(I18n.t("chrome.admin_table.clear_filters"))
      expect(build_component(
        filters: [{ key: :role, label: "Role", default: "member" }],
        params: { role: "member" }
      ).active_filters?).to be(false)
    end

    it "chips a non-default value and can omit the blank option" do
      rendered = render_table(
        filters: [{
          key: :role, label: "Role", default: "member", include_blank: false,
          options: [["Member", "member"], ["Admin", "admin"]]
        }],
        params: { role: "admin" }
      )
      expect(rendered.text).to include("Role", "Admin")
      select = rendered.css("select[name='role']").first
      expect(select["aria-label"]).to eq("Role")
      expect(select.css("option[value='']")).to be_empty
    end
  end

  describe "temporal cells" do
    let(:stamped) { OpenStruct.new(id: 1, name: "Alpha", updated_at: Time.utc(2026, 5, 14, 12, 0)) }

    it "wraps a datetime in a <time> element carrying the exact timestamp" do
      cols = [{ key: :name, label: "Name" }, { key: :updated_at, label: "Updated", type: :datetime }]
      rendered = render_table(rows: [stamped], columns: cols)
      tag = rendered.css("td time").first
      expect(tag).not_to be_nil
      expect(tag["title"]).to eq(I18n.l(Time.utc(2026, 5, 14, 12, 0), format: :long))
      expect(tag["datetime"]).to eq(Time.utc(2026, 5, 14, 12, 0).iso8601)
      expect(tag.text.strip).to eq(I18n.l(Time.utc(2026, 5, 14, 12, 0), format: :long))
    end

    it "localizes datetime cells in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        cols = [{ key: :updated_at, label: "Updated", type: :datetime }]
        rendered = render_table(rows: [stamped], columns: cols)
        expect(rendered.css("td time").first.text.strip).to eq(
          I18n.l(Time.utc(2026, 5, 14, 12, 0), format: :long)
        )
      end
    end

    it "shows relative text but keeps the exact timestamp on hover when relative: true" do
      cols = [{ key: :name, label: "Name" },
              { key: :updated_at, label: "Updated", type: :datetime, relative: true }]
      row = OpenStruct.new(id: 1, name: "Alpha", updated_at: 2.days.ago)
      rendered = render_table(rows: [row], columns: cols)
      tag = rendered.css("td time").first
      expect(tag.text).to eq(I18n.t("chrome.admin_table.time_ago", time: "2 days"))
      expect(tag["title"]).to be_present
    end

    it "phrases future timestamps as upcoming rather than past" do
      cols = [{ key: :sends_at, label: "Sends", type: :datetime, relative: true }]
      row = OpenStruct.new(id: 1, sends_at: 3.days.from_now)
      rendered = render_table(rows: [row], columns: cols)
      expect(rendered.css("td time").first.text).to eq(
        I18n.t("chrome.admin_table.time_in", time: "3 days")
      )
    end

    it "leaves a :date column absolute and formatted" do
      cols = [{ key: :created_on, label: "Date", type: :date }]
      row = OpenStruct.new(id: 1, created_on: Date.new(2026, 6, 15))
      rendered = render_table(rows: [row], columns: cols)
      expect(rendered.css("td time").first.text.strip).to eq(I18n.l(Date.new(2026, 6, 15), format: :long))
    end

    it "falls back to plain text for an unformattable value" do
      cols = [{ key: :updated_at, label: "Updated", type: :datetime, relative: true }]
      row = OpenStruct.new(id: 1, updated_at: nil)
      rendered = render_table(rows: [row], columns: cols)
      expect(rendered.css("td time")).to be_empty
      expect(rendered.text).to include("—")
    end
  end

  describe "numeric typography" do
    it "applies tabular-nums to numeric and temporal cells only" do
      cols = [
        { key: :name,       label: "Name" },
        { key: :count,      label: "Count", type: :number },
        { key: :updated_at, label: "Updated", type: :datetime }
      ]
      row = OpenStruct.new(id: 1, name: "Alpha", count: 42, updated_at: Time.utc(2026, 5, 14, 12, 0))
      cells = render_table(rows: [row], columns: cols).css("tbody td")
      expect(cells[0]["class"]).not_to include("tabular-nums")
      expect(cells[1]["class"]).to include("tabular-nums")
      expect(cells[2]["class"]).to include("tabular-nums")
    end
  end

  describe "empty state" do
    it "renders 'no records yet' when rows are empty without a search" do
      rendered = render_inline(described_class.new(
        rows: [], columns: columns,
        pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 },
        params: {}, search: { param: :q },
        empty_state: { title: "No constants yet", description: "Create one to get started",
                       action_path: "/new", action_text: "New constant" }
      ))
      expect(rendered.text).to include("No constants yet")
      expect(rendered.css("a[href='/new']")).not_to be_empty
    end

    it "renders a search-specific empty state when q is present" do
      rendered = render_inline(described_class.new(
        rows: [], columns: columns,
        pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 },
        params: { q: "zzz" }, search: { param: :q },
        empty_state: { title: "No constants yet" }
      ))
      expect(rendered.text).to include("zzz")
    end

    it "renders a filter-specific empty state when filters are active and rows are empty" do
      rendered = render_inline(described_class.new(
        rows: [], columns: columns,
        pagination: { page: 1, per_page: 25, total: 0, total_pages: 0 },
        params: { status: "active" }, search: { param: :q },
        filters: [{ key: :status, label: "Status", options: [["Active", "active"]] }],
        empty_state: { title: "No constants yet" }
      ))
      expect(rendered.text).to include(I18n.t("chrome.admin_table.no_filter_matches"))
      expect(rendered.text).not_to include("No constants yet")
    end
  end
end
