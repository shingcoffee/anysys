# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SortableHeaderComponent, type: :component do
  it "renders an inactive header with a hover-only hint" do
    render_inline(described_class.new(label: "Name", href: "/list?sort=name&dir=asc", frame_id: "list"))
    link = page.find_link(href: "/list?sort=name&dir=asc")
    expect(link.text.strip).to eq("Name")
    expect(link["title"]).to eq(I18n.t("chrome.admin_table.sort_by", label: "Name"))
    expect(link["data-turbo-frame"]).to eq("list")
    expect(link["data-turbo-action"]).to eq("advance")
    expect(link["class"].split).not_to include("text-text-primary")
    expect(page.find("svg", visible: :all)["class"]).to include("opacity-0")
  end

  it "highlights the active column with a direction arrow" do
    render_inline(described_class.new(label: "Name", href: "/list", direction: "desc", align: :right))
    link = page.find_link(href: "/list")
    expect(link["class"]).to include("text-text-primary", "justify-end")
    expect(link["data-turbo-frame"]).to be_nil
    expect(page.find("path", visible: :all)["d"]).to eq("M12 5v14m6-6l-6 6-6-6")
  end

  it "maps directions to aria-sort values" do
    expect(described_class.aria_sort("asc")).to eq("ascending")
    expect(described_class.aria_sort(:desc)).to eq("descending")
    expect(described_class.aria_sort(nil)).to be_nil
  end
end
