# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ListToolbarComponent, type: :component do
  let(:filters) { [{ key: :status, label: "Status", options: [["Active", "active"], ["Archived", "archived"]] }] }

  def render_toolbar(params: {}, **overrides, &block)
    render_inline(described_class.new(
      base_path: "/1/admin/things", frame_id: "things-table", params: params,
      search: { param: :q, placeholder: "Search things…" }, filters: filters, **overrides
    ), &block)
  end

  it "submits a debounced GET search into the list frame" do
    render_toolbar
    form = page.find("form[role='search']")
    expect(form["method"]).to eq("get")
    expect(form["action"]).to eq("/1/admin/things")
    expect(form["data-turbo-frame"]).to eq("things-table")
    expect(form["data-controller"]).to eq("admin-table")
    input = form.find("input[type='search'][name='q']")
    expect(input["placeholder"]).to eq("Search things…")
    expect(input["data-admin-table-target"]).to eq("searchInput")
    expect(input["data-action"]).to eq("input->admin-table#debounceSubmit")
  end

  it "renders filters that submit on change and highlight when active" do
    render_toolbar(params: { status: "archived" })
    select = page.find("select[name='status']")
    expect(select["data-action"]).to eq("change->admin-table#submit")
    expect(select["class"]).to include("bg-accent-subtle")
    expect(select.find("option[selected]").text).to eq("Archived")
  end

  it "uses a dashed outline for an unset filter" do
    render_toolbar
    expect(page.find("select[name='status']")["class"]).to include("border-dashed")
  end

  it "carries other query params as hidden fields but not search, filters or page" do
    render_toolbar(params: { q: "x", status: "active", page: "3", sort: "name", dir: "asc", per_page: "25" })
    hidden = page.all("input[type='hidden']", visible: :all).to_h { |i| [i["name"], i["value"]] }
    expect(hidden).to eq("sort" => "name", "dir" => "asc", "per_page" => "25")
  end

  it "shows Reset only while narrowed and keeps sort params" do
    render_toolbar(params: { sort: "name" })
    expect(page).not_to have_link(I18n.t("chrome.admin_table.reset"))

    render_toolbar(params: { status: "active", sort: "name", page: "2" })
    reset = page.find_link(I18n.t("chrome.admin_table.reset"))
    expect(reset["href"]).to eq("/1/admin/things?sort=name")
    expect(reset["data-turbo-frame"]).to eq("things-table")
  end

  it "resets to the bare path when nothing else is set" do
    render_toolbar(params: { q: "x" })
    expect(page).to have_link(I18n.t("chrome.admin_table.reset"), href: "/1/admin/things")
  end

  it "renders the actions slot and passes data attributes to the header" do
    render_toolbar(data: { batch_select_target: "toolbar" }) { |t| t.with_actions { "Columns" } }
    expect(page).to have_css("header[data-batch-select-target='toolbar']", text: "Columns")
  end

  it "omits search and actions when not configured" do
    render_toolbar(search: nil, filters: [])
    expect(page).not_to have_css("input[type='search']")
    expect(page).to have_css("form[role='search']")
  end

  it "translates Reset in Chinese" do
    I18n.with_locale(:"zh-CN") { render_toolbar(params: { q: "x" }) }
    expect(page).to have_link("重置")
  end
end
