# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::FormPanelComponent, type: :component do
  it "cards the rendered page and follows it with the first + Add New dialog" do
    rendered = render_inline(described_class.new) { "<form action='/1/page/abc'></form>".html_safe }

    expect(rendered.at_css(".card > div > div.mx-auto.max-w-4xl form[action='/1/page/abc']")).to be_present
    expect(rendered.at_css(".card + dialog#entity-quick-add-dialog-0 turbo-frame#entity-quick-add-frame-0")).to be_present
  end

  it "shows the empty state, without the card or dialog, when no page rendered" do
    rendered = render_inline(described_class.new(empty_title: "No form", empty_description: "Launch one.")) { "\n" }

    expect(rendered.at_css("h3").text).to eq("No form")
    expect(rendered.text).to include("Launch one.")
    expect(rendered.css(".max-w-4xl, dialog")).to be_empty
  end
end
