# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::IconComponent, type: :component do
  it "renders a decorative outline svg with the requested size" do
    render_inline described_class.new(name: :credit_card, class_name: "h-4 w-4")
    svg = page.find("svg", visible: :all)
    expect(svg[:class]).to eq("shrink-0 h-4 w-4")
    expect(svg["aria-hidden"]).to eq("true")
    expect(svg[:viewbox]).to eq("0 0 24 24")
    expect(page).to have_css("path[d='#{described_class::PATHS[:credit_card]}']", visible: :all)
  end

  it "rejects unknown icon names" do
    expect { described_class.new(name: :unknown) }.to raise_error(KeyError)
  end
end
