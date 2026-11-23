# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::EntryGroupComponent, type: :component do
  it "titles a fieldset and lays its content out in the two-column entry grid" do
    rendered = render_inline(described_class.new(label: "Identity")) { "<p id='cell'>x</p>".html_safe }

    expect(rendered.at_css("fieldset legend").text).to eq("Identity")
    expect(rendered.at_css("fieldset > div.grid.grid-cols-1.md\\:grid-cols-2 #cell")).to be_present
    expect(rendered.css("hr, fieldset > p")).to be_empty
  end

  it "sets a later group off with a rule and shows a description" do
    rendered = render_inline(described_class.new(label: "Notes", separated: true, description: "Staff only"))

    expect(rendered.at_css("hr + fieldset")).to be_present
    expect(rendered.at_css("fieldset > p").text.strip).to eq("Staff only")
  end

  it "falls back to the ungrouped title in both locales" do
    %i[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        expect(render_inline(described_class.new(label: nil)).at_css("legend").text)
          .to eq(I18n.t("admin_misc.entities.entry_detail.ungrouped"))
      end
    end
    expect(I18n.t("admin_misc.entities.entry_detail.ungrouped", locale: :"zh-CN"))
      .not_to eq(I18n.t("admin_misc.entities.entry_detail.ungrouped", locale: :en))
  end

  it "escapes an authored title" do
    rendered = render_inline(described_class.new(label: "<img src=x onerror=alert(1)>"))

    expect(rendered.css("img")).to be_empty
  end
end
