# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::RowMenuComponent, type: :component do
  let(:live) { build_stubbed(:page, launched: true) }
  let(:draft) { build_stubbed(:page, launched: false) }

  def render_menu(page_record)
    render_inline(described_class.new(
      page: page_record, manage_path: "/1/admin/pages/9", preview_path: "/1/admin/maintenance/pages/9/preview",
      launch_path: "/1/admin/maintenance/pages/9/launch", publishing_frame: "page-publishing"
    ))
  end

  def items = page.all("[role='menu'] a", visible: :all)

  it "lists Manage access, Preview and Take offline with clean labels" do
    render_menu(live)
    expect(items.map { |a| a.text(:all) }).to eq([
      I18n.t("admin_misc.pages.manage_access"), I18n.t("maint_core.pages.preview"),
      I18n.t("admin_misc.pages.take_offline")
    ])
    expect(page).to have_css("[role='separator']", count: 2, visible: :all)
  end

  it "opens Manage access in the publishing frame and the preview in a new top-level tab" do
    render_menu(live)
    expect(items[0]["data-turbo-frame"]).to eq("page-publishing")
    expect(items[1]["href"]).to eq("/1/admin/maintenance/pages/9/preview")
    expect(items[1]["target"]).to eq("_blank")
    expect(items[1]["rel"].split).to contain_exactly("noopener", "noreferrer")
    expect(items[1]["data-turbo-frame"]).to eq("_top")
  end

  it "takes a live page offline with a danger-toned DELETE" do
    render_menu(live)
    offline = items.last
    expect(offline["data-turbo-method"]).to eq("delete")
    expect(offline["class"]).to include("text-danger")
  end

  it "launches a draft with POST" do
    render_menu(draft)
    expect(items.map { |a| a.text(:all) }).to eq([
      I18n.t("admin_misc.pages.manage_access"), I18n.t("maint_core.pages.preview"), I18n.t("admin_misc.pages.launch")
    ])
    expect(items.last["data-turbo-method"]).to eq("post")
    expect(items.last["class"]).not_to include("text-danger")
  end

  it "labels the trigger for assistive tech in both locales" do
    I18n.with_locale(:"zh-CN") { render_menu(live) }
    expect(page.find("summary")["aria-label"]).to eq(I18n.t("common.actions.more", locale: :"zh-CN"))
    expect(items.first.text(:all)).to eq("管理访问")
  end
end
