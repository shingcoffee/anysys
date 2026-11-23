# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::CatalogEditorHeaderComponent, type: :component do
  it "renders title, description, back link, and actions" do
    render_inline(described_class.new(
      title: "Presence",
      description: "Edit the starter",
      back_path: "/catalog"
    )) do |header|
      header.with_actions { "<button type='submit'>Save</button>".html_safe }
    end

    expect(page).to have_css("[data-catalog-editor-header='true']")
    expect(page).to have_css("h2", text: "Presence")
    expect(page).to have_text("Edit the starter")
    expect(page).to have_link(I18n.t("website.platform.catalog.back"), href: "/catalog")
    expect(page).to have_button("Save")
  end
end
