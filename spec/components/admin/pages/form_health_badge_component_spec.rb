# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::FormHealthBadgeComponent, type: :component do
  def status(kind, problems: [], built: nil, current: nil, entity_name: nil)
    Pages::FormHealth::Status.new(kind: kind, problems: problems, built: built, current: current, entity_name: entity_name)
  end

  it "renders nothing for a form that needs no badge" do
    render_inline(described_class.new(status: nil))

    expect(page).not_to have_css(".badge")
  end

  it "flags a form that can't be submitted, with every problem in the tooltip" do
    render_inline(described_class.new(status: status(:cannot_submit, problems: ["Name is missing", "Process offline"])))
    hint = I18n.t("admin_misc.pages.cannot_submit_hint", problems: "Name is missing; Process offline")

    expect(page).to have_css(".badge.badge-danger", text: I18n.t("admin_misc.pages.cannot_submit"))
    expect(page.find(".badge")["data-tooltip"]).to eq(hint)
    expect(page).to have_css(".sr-only", text: hint)
  end

  it "flags an out-of-date form with both version numbers" do
    render_inline(described_class.new(status: status(:out_of_date, built: 1, current: 3, entity_name: "Student")))

    expect(page).to have_css(".badge.badge-warning", text: I18n.t("admin_misc.pages.out_of_date"))
    expect(page.find(".badge")["data-tooltip"]).to eq(
      I18n.t("admin_misc.pages.out_of_date_hint", built: 1, entity: "Student", current: 3)
    )
  end

  it "speaks zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(status: status(:out_of_date, built: 1, current: 2, entity_name: "学生")))
    end

    expect(page).to have_text("版本过旧")
    expect(page.find(".badge")["data-tooltip"]).to eq("基于第 1 版生成；学生当前为第 2 版。")
  end
end
