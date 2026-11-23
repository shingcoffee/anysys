require "rails_helper"

RSpec.describe PropertyEditor::EmptyStateComponent, type: :component do
  it "renders the message" do
    render_inline(described_class.new(message: "No items yet"))
    expect(page).to have_text("No items yet")
  end

  it "renders with dashed border styling" do
    render_inline(described_class.new(message: "No items yet"))
    expect(page).to have_css("div.border-dashed")
  end

  it "renders a custom icon when provided" do
    render_inline(described_class.new(message: "Empty", icon: "plus"))
    expect(page).to have_css("svg")
  end

  it "renders without icon by default" do
    render_inline(described_class.new(message: "Empty"))
    expect(page).not_to have_css("svg")
  end
end
