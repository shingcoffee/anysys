# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntriesTableComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  let(:entity) do
    create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [
        { "name" => "first name", "name_slug" => "first_name", "display_label" => "First name", "html_type" => "text" },
        { "name" => "grade", "name_slug" => "grade", "display_label" => "Grade", "html_type" => "select",
          "config" => { "options" => [{ "label" => "A", "value" => "a" }, { "label" => "B", "value" => "b" }] } }
      ].to_json
    )
  end

  let(:alpha) do
    create(
      :entity_entry,
      :with_data,
      customer: customer,
      entity: entity,
      entry_data: { "first_name" => "Alice", "grade" => "a" }
    )
  end

  let(:beta) do
    create(
      :entity_entry,
      :with_data,
      customer: customer,
      entity: entity,
      entry_data: { "first_name" => "", "grade" => "b" }
    )
  end

  let(:rows) { [alpha, beta] }
  let(:pagination) { { page: 1, per_page: 10, total: 2, total_pages: 1 } }
  let(:base_path) { "/#{customer.id}/admin/entities/#{entity.id}" }
  let(:batch_path) { "/#{customer.id}/admin/entities/#{entity.id}/entries/batch" }

  let(:columns) do
    Admin::Entities::ColumnsBuilder.call(
      entity: entity,
      setting: EntityIndexSetting.new(entity: entity, customer: customer),
      customer_id: customer.id,
      display: Entities::EntryDisplay.new(
        entity: entity,
        entries: rows,
        customer_id: customer.id,
        audience: EntityAttributeAudience::ADMIN
      )
    )
  end

  def render_table(**overrides)
    args = {
      rows: rows,
      columns: columns,
      pagination: pagination,
      params: {},
      filters: [],
      search: { param: :q, placeholder: "Search entries…" },
      empty_state: { title: "No entries yet" },
      base_path: base_path,
      batch_path: batch_path,
      entry_path: ->(row) { "#{base_path}/entries/#{row.id}" },
      destroy_path: ->(row) { "#{base_path}/entries/#{row.id}" },
      density: "comfortable"
    }.merge(overrides)
    render_inline(described_class.new(**args))
  end

  it "adds a top-level edit link per row on desktop and mobile only when an edit path is given" do
    edit_label = I18n.t("common.actions.edit")
    expect(render_table.css("a[aria-label='#{edit_label}']")).to be_empty

    rendered = render_table(edit_path: ->(row) { "#{base_path}/entries/#{row.id}/edit" })
    links = rendered.css("a[aria-label='#{edit_label}']")
    expect(links.size).to eq(rows.size * 2)
    expect(links.map { |link| link["href"] }.uniq).to match_array(rows.map { |row| "#{base_path}/entries/#{row.id}/edit" })
    expect(links.map { |link| link["data-turbo-frame"] }.uniq).to eq(["_top"])
  end

  it "wraps the table in the entity-entries turbo-frame" do
    rendered = render_table
    frame = rendered.css("turbo-frame#entity-entries-table").first
    expect(frame).not_to be_nil
    expect(frame["data-turbo-action"]).to eq("advance")
  end

  it "mounts batch-select with the selected-count template value" do
    rendered = render_table
    section = rendered.css("section[data-controller~='batch-select']").first
    expect(section).not_to be_nil
    expect(section["data-batch-select-count-template-value"]).to eq(
      I18n.t("comp_admin.batch_select.selected")
    )
  end

  it "mounts the tooltip controller and overflow-gated tooltip triggers on truncated cells" do
    rendered = render_table
    expect(rendered.css("section[data-controller~='tooltip']")).not_to be_empty
    expect(rendered.css("[data-tooltip-overflow='true']")).not_to be_empty
  end

  it "sets data-tooltip with the full cell text on truncated cells" do
    rendered = render_table
    expect(rendered.css("[data-tooltip='Alice'][data-tooltip-overflow='true']")).not_to be_empty
  end

  describe "toolbar and bulk bar targets" do
    it "renders toolbar and bulk bar batch-select targets" do
      rendered = render_table
      expect(rendered.css("[data-batch-select-target='toolbar']")).not_to be_empty
      bulkbar = rendered.css("[data-batch-select-target='bulkbar']").first
      expect(bulkbar).not_to be_nil
      expect(bulkbar["class"]).to include("hidden")
    end

    it "renders a search form when search config is provided" do
      rendered = render_table
      expect(rendered.css("input[type='search'][name='q']")).not_to be_empty
      expect(rendered.css("input[placeholder='Search entries…']")).not_to be_empty
    end
  end

  describe "column order" do
    it "renders the checkbox column before the ID header" do
      rendered = render_table
      header_cells = rendered.css("thead th")
      expect(header_cells.first.css("input[type='checkbox'][data-batch-select-target='all']")).not_to be_empty
      expect(header_cells[1].text.strip).to include(I18n.t("admin_misc.entities.columns.id"))
    end

    it "renders row checkboxes named ids[]" do
      rendered = render_table
      boxes = rendered.css("tbody input[type='checkbox'][name='ids[]']")
      expect(boxes.length).to eq(2)
      expect(boxes.map { |b| b["value"] }).to contain_exactly(alpha.id.to_s, beta.id.to_s)
    end

    it "renders exactly one ids[] checkbox per row (no mobile duplicates)" do
      render_table
      expect(page.all("input[name='ids[]']").size).to eq(rows.size)
    end
  end

  describe "responsive layout" do
    it "renders a mobile card region" do
      rendered = render_table
      expect(rendered.css(".sm\\:hidden.divide-y")).not_to be_empty
    end
  end

  describe "cell rendering" do
    it "renders em-dash for blank attribute cells" do
      render_table
      expect(page.text).to include("—")
    end

    it "renders badge cells for select columns" do
      rendered = render_table
      expect(rendered.css(".badge")).not_to be_empty
      expect(rendered.text).to include("A", "B")
    end

    it "renders a select attribute's option label, not the stored value" do
      rendered = render_table
      badges = rendered.css(".badge").map { |node| node.text.strip }
      expect(badges).to include("A", "B")
      expect(badges).not_to include("a", "b")
    end

    it "renders boolean columns as Yes/No" do
      bool_columns = columns + [
        { key: :active, label: "Active", type: :boolean, cell: ->(_row) { true } },
        { key: :inactive, label: "Inactive", type: :boolean, cell: ->(_row) { false } }
      ]
      render_table(columns: bool_columns)
      expect(page.text).to include(
        I18n.t("common.labels.yes"),
        I18n.t("common.labels.no")
      )
    end

    it "links the primary column to the full entry detail page" do
      rendered = render_table
      link = rendered.css("a[data-row-link-primary][data-turbo-frame='_top']").first
      expect(link).not_to be_nil
      expect(link["href"]).to eq("#{base_path}/entries/#{alpha.id}")
    end

    it "centers every column and header, and renders the ID as a link" do
      rendered = render_table
      rendered.css("thead th, tbody td").each do |cell|
        expect(cell["class"]).to include("text-center")
      end

      id_link = rendered.css("tbody tr a.link").find { |link| link.text.strip == alpha.id.to_s }
      expect(id_link).not_to be_nil
      expect(id_link["href"]).to eq("#{base_path}/entries/#{alpha.id}")
      expect(id_link["class"]).to include("underline")
    end

    it "links a column with an href on desktop and mobile, and leaves it plain without one" do
      linked_columns = [columns.first,
                        { key: :owner, label: "Owner", cell: ->(row) { "Owner #{row.id}" },
                          href: ->(row) { "/users/#{row.id}" if row == alpha } },
                        *columns.drop(1)]
      rendered = render_table(columns: linked_columns)

      desktop = rendered.css("table a[href='/users/#{alpha.id}']")
      expect(desktop.map { |link| link.text.strip }).to eq(["Owner #{alpha.id}"])
      expect(desktop.first["data-turbo-frame"]).to eq("_top")
      expect(desktop.first["data-row-link-primary"]).to be_nil
      expect(rendered.css(".sm\\:hidden a[href='/users/#{alpha.id}']").size).to eq(0)
      expect(rendered.css("a[href='/users/#{beta.id}']")).to be_empty
      expect(rendered.css("table").text).to include("Owner #{beta.id}")
    end

    it "links a meta column with an href on mobile cards" do
      linked_columns = [*columns.first(2),
                        { key: :owner, label: "Owner", cell: ->(row) { "Owner #{row.id}" },
                          href: ->(row) { "/users/#{row.id}" } },
                        *columns.drop(2)]
      rendered = render_table(columns: linked_columns)

      expect(rendered.css(".sm\\:hidden dd a[href='/users/#{alpha.id}']").map { |link| link.text.strip })
        .to eq(["Owner #{alpha.id}"])
    end
  end

  describe "row actions" do
    it "renders a delete action with turbo confirm" do
      rendered = render_table
      delete_link = rendered.css("a[data-turbo-method='delete']").first
      expect(delete_link).not_to be_nil
      expect(delete_link["data-turbo-confirm"]).to eq(
        I18n.t("comp_admin.entries_table.delete_entry_confirm")
      )
    end
  end

  describe "batch delete form" do
    it "posts DELETE to batch_path with authenticity" do
      rendered = render_table
      form = rendered.css("form").find { |f| f["action"] == batch_path }
      expect(form).not_to be_nil
      expect(form["method"]).to eq("post")
      expect(form.css("input[name='_method'][value='delete']")).not_to be_empty
      expect(form.css("input[name='authenticity_token']")).not_to be_empty
    end

    it "renders bulk delete submit wired to batch-select" do
      rendered = render_table
      submit = rendered.css("[data-batch-select-target='submit']").first
      expect(submit).not_to be_nil
      expect(submit["disabled"]).to eq("disabled")
      expect(submit.text.strip).to eq(I18n.t("comp_admin.entries_table.delete_selected"))
    end
  end

  describe "empty states" do
    it "renders the provided empty state when there are no rows and no active search" do
      render_table(rows: [], pagination: { page: 1, per_page: 10, total: 0, total_pages: 0 })
      expect(page).to have_text("No entries yet")
    end

    it "renders the no-matches empty state with clear search when q is active" do
      render_table(
        rows: [],
        pagination: { page: 1, per_page: 10, total: 0, total_pages: 0 },
        params: { q: "missing" }
      )
      expect(page).to have_text(I18n.t("chrome.admin_table.no_matches_html", query: "missing"))
      expect(page).to have_link(I18n.t("comp_admin.entries_table.clear_search"))
    end
  end

  describe "footer" do
    it "renders shared Admin::PaginationComponent with numbered pages and rows-per-page" do
      render_table(pagination: { page: 1, per_page: 10, total: 25, total_pages: 3 }, params: { q: "a" })
      expect(page).to have_css("footer", text: "Showing 1–10 of 25")
      expect(page).to have_css("footer a[data-turbo-frame='entity-entries-table']")
      expect(page).to have_css("footer [aria-current='page']", text: "1")
      expect(page).to have_link("3", href: "#{base_path}?page=3&q=a")
      expect(page).to have_link("50", href: "#{base_path}?per_page=50&q=a", visible: :all)
    end

    it "keeps a count-only footer when there is one page" do
      render_table(pagination: { page: 1, per_page: 10, total: 2, total_pages: 1 })
      expect(page).to have_css("footer", text: "2 results")
      expect(page).not_to have_css("footer nav")
      expect(page).not_to have_css("footer [data-controller='dropdown']")
    end

    it "omits the footer when there are no rows" do
      render_table(rows: [], pagination: { page: 1, per_page: 10, total: 0, total_pages: 0 })
      expect(page).not_to have_css("footer")
    end
  end

  describe "row navigation" do
    it "opens the entry detail page from anywhere on a row via row-link" do
      rendered = render_table
      expect(rendered.css("tbody[data-controller='row-link'][data-action='click->row-link#open']")).not_to be_empty
      rows_with_links = rendered.css("tr[data-row-link-row]")
      expect(rows_with_links.size).to eq(2)
      rows_with_links.each do |tr|
        expect(tr.css("a[data-row-link-primary][data-turbo-frame='_top']").size).to eq(1)
      end
    end

    it "leads mobile cards with the first descriptive field and a muted entry number" do
      rendered = render_table
      card = rendered.css(".sm\\:hidden [data-row-link-row]").first
      expect(card.css("a[data-row-link-primary]").text.strip).to eq("Alice")
      expect(card.text).to include("##{alpha.id}")
    end
  end

  describe "toolbar" do
    it "renders toolbar_actions next to a density toggle that keeps the current query" do
      render_inline(described_class.new(
        rows: rows, columns: columns, pagination: pagination, params: { q: "ali" },
        search: { param: :q }, base_path: base_path, batch_path: batch_path,
        entry_path: ->(row) { "#{base_path}/entries/#{row.id}" },
        destroy_path: ->(row) { "#{base_path}/entries/#{row.id}" },
        density: "compact"
      )) { |table| table.with_toolbar_actions { "Columns slot" } }

      expect(page).to have_text("Columns slot")
      group = page.find("[role='group'][aria-label='#{I18n.t('chrome.admin_table.density')}']")
      expect(group).to have_css("a[aria-current='true'][href='#{base_path}?density=compact&q=ali']")
      expect(group).to have_link(href: "#{base_path}?density=comfortable&q=ali")
    end

    it "shows a Reset link only while narrowed" do
      render_table
      expect(page).not_to have_link(I18n.t("chrome.admin_table.reset"))
      render_table(params: { q: "ali", sort: "id", dir: "asc" })
      expect(page).to have_link(I18n.t("chrome.admin_table.reset"), href: "#{base_path}?dir=asc&sort=id")
    end
  end

  describe "sorting" do
    it "marks the sorted column with aria-sort and resets to the first page" do
      render_table(params: { sort: "id", dir: "desc", page: "2" })
      th = page.find("th[aria-sort='descending']")
      expect(th).to have_text(I18n.t("admin_misc.entities.columns.id"))
      expect(th).to have_link(href: "#{base_path}?dir=asc&sort=id")
    end
  end
end
