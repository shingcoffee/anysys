# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::IndexToolbarComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(customer_id: customer_id, total_count: 42))
  end

  let(:customer_id) { "81721200" }


  it "renders the header element" do
    expect(rendered.css("header")).not_to be_empty
  end

  it "renders 'Code Generators' title" do
    expect(rendered.text).to include("Code Generators")
  end

  it "displays the total count badge" do
    expect(rendered.text).to include("42")
  end

  it "renders a back link to the maintenance page" do
    back_href = "/#{customer_id}/admin/maintenance"
    expect(rendered.css("a[href='#{back_href}']")).not_to be_empty
  end

  it "renders a 'New Generator' link" do
    expect(rendered.text).to include("New Generator")
  end

  it "links New Generator to the new generator path with kind=step_action" do
    new_href = "/#{customer_id}/admin/maintenance/platform/code_generators/new?kind=step_action"
    expect(rendered.css("a[href='#{new_href}']")).not_to be_empty
  end

  it "shows 0 when total_count is zero" do
    html = render_inline(described_class.new(customer_id: customer_id, total_count: 0))
    expect(html.text).to include("0")
  end
end
