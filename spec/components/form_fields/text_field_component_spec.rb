# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::TextFieldComponent, type: :component do
  it "renders a password input without reflecting a supplied secret" do
    render_inline(described_class.new(field_name: "entity[password]", label: "Password", input_type: "password", value: "do-not-reflect"))
    expect(page).to have_css('input[type="password"][name="entity[password]"]')
    expect(rendered_content).not_to include("do-not-reflect")
  end

  it "renders a hidden input without a visible label or wrapper" do
    render_inline(described_class.new(field_name: "entity[reference]", label: "Internal reference", input_type: "hidden", value: "42"))
    expect(page).to have_css('input[type="hidden"][name="entity[reference]"][value="42"]', visible: :all)
    expect(page).not_to have_css("label", visible: :all)
    expect(page).not_to have_css("div", visible: :all)
  end

  it "falls back to text for unsupported types" do
    render_inline(described_class.new(field_name: "name", input_type: 'text" onfocus="alert(1)'))
    expect(page).to have_css('input[type="text"]')
    expect(page).not_to have_css("[onfocus]")
  end
end
