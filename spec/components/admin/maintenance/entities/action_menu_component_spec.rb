# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Entities::ActionMenuComponent, type: :component do
  it "renders links, separators and a danger delete that escapes the frame" do
    render_inline(described_class.new(label: "Row actions", items: [
      { label: "Edit", path: "/edit" },
      :separator,
      { label: "Delete", path: "/thing", method: :delete, tone: :danger, data: { turbo_confirm: "Sure?" } }
    ]))

    expect(page).to have_css("summary[aria-label='Row actions']")
    expect(page).to have_css("[role=separator]", visible: :all)
    edit = page.find_link("Edit", visible: :all)
    expect(edit["data-turbo-frame"]).to eq("_top")
    expect(edit["data-turbo-method"]).to be_nil
    delete = page.find_link("Delete", visible: :all)
    expect(delete["data-turbo-method"]).to eq("delete")
    expect(delete["data-turbo-confirm"]).to eq("Sure?")
    expect(delete[:class]).to include("text-danger")
  end

  it "falls back to the generic label" do
    render_inline(described_class.new(items: [{ label: "Edit", path: "/edit" }]))

    expect(page).to have_css("summary[aria-label='#{I18n.t("common.actions.more")}']")
  end

  it "renders nothing without actionable items" do
    render_inline(described_class.new(items: [:separator, nil]))

    expect(page).to have_no_css("details")
  end
end
