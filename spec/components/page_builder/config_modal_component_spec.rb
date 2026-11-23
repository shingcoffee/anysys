# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::ConfigModalComponent, type: :component do
  def render_modal(**opts)
    defaults = { key: "rules", title: "Conditional Rules", subtitle: "Sub", accent: :indigo, icon: :rules, size: :md }
    render_inline(described_class.new(**defaults.merge(opts))) { "<p>BODY</p>".html_safe }
  end

  it "renders the title, subtitle and yielded body" do
    render_modal
    expect(page).to have_text("Conditional Rules")
    expect(page).to have_text("Sub")
    expect(page).to have_text("BODY")
  end

  it "carries the tab-panel hooks switchTab depends on, hidden by default" do
    render_modal
    el = page.find("[data-tab-panel='rules']", visible: :all)
    expect(el["data-page-builder-target"]).to include("tabPanel")
    expect(el[:class]).to include("hidden")
  end

  it "wires backdrop click to close and stops dialog clicks from closing" do
    render_modal
    expect(page).to have_css("[data-action='click->page-builder#onModalBackdropClick']")
    expect(page).to have_css("[data-action='click->page-builder#stopModalClose']")
  end

  it "maps size to a max-width class" do
    render_modal(size: :xl)
    expect(page.native.to_html).to include("max-w-5xl")
  end

  it "applies the accent in the header" do
    render_modal(accent: :purple)
    expect(page.native.to_html).to include("purple")
  end
end
