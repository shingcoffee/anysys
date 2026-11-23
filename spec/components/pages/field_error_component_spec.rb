# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::FieldErrorComponent, type: :component do
  it "lists each distinct message under the field" do
    render_inline(described_class.new(messages: ["can't be blank", "can't be blank", "is too short"]))

    expect(page).to have_css("ul[data-field-error].text-danger li", count: 2)
    expect(page.all("li").map { |item| item.text.strip }).to eq(["can't be blank", "is too short"])
    expect(page).to have_css("svg[aria-hidden='true']", count: 2)
  end

  it "renders nothing without messages" do
    render_inline(described_class.new(messages: [nil, ""]))

    expect(page).not_to have_css("[data-field-error]")
  end

  it "escapes messages" do
    render_inline(described_class.new(messages: ["<b>bold</b>"]))

    expect(page).to have_text("<b>bold</b>")
    expect(page).not_to have_css("b")
  end
end
