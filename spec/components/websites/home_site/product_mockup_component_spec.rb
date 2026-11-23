# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::ProductMockupComponent, type: :component do
  it "exposes one localized image label and hides the illustrative interior from assistive technology" do
    %i[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        html = render_inline(described_class.new)
        root = html.at_css("[role='img']")
        expect(root["aria-label"]).to eq(I18n.t("website.home_site.mockup.label"))
        expect(root.element_children.map { |node| node["aria-hidden"] }).to all(eq("true"))
        expect(html.css("a, button, input, form, img")).to be_empty
        expect(html.css("svg").map { |node| node["focusable"] }).to all(eq("false"))
      end
    end
  end

  it "renders every localized nav item, stat, column and sample row" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new)
      mockup = ->(key) { I18n.t("website.home_site.mockup.#{key}") }
      expect(html).to have_text(mockup.call("url"))
      mockup.call("nav").each { |item| expect(html).to have_text(item) }
      mockup.call("stats").each { |stat| expect(html).to have_text(stat[:value]) }
      mockup.call("columns").each { |column| expect(html).to have_text(column) }
      mockup.call("rows").each { |row| expect(html).to have_text(row[:name]).and have_text(row[:status]) }
      expect(html).to have_text(mockup.call("assistant.message"))
      expect(html).to have_text(mockup.call("toasts.payment.title"))
    end
  end

  it "derives avatar initials from latin and CJK names" do
    component = described_class.new
    expect(component.initials("Emma Chen")).to eq("EC")
    expect(component.initials("陈思雨")).to eq("陈")
  end
end
