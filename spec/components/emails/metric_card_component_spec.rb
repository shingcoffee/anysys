# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::MetricCardComponent, type: :component do
  it "renders a metric with the supplied accent border" do
    render_inline(described_class.new(
      label: "Delivered",
      value: "1,024",
      border_class: "border-l-success"
    ))

    expect(page).to have_css(".card.border-l-4.border-l-success")
    expect(page).to have_css(".text-text-muted", text: "Delivered")
    expect(page).to have_css(".text-text-primary", text: "1,024")
  end

  it "resolves a named tone onto a border token" do
    render_inline(described_class.new(label: "Bounced", value: "3", tone: :danger))

    expect(page).to have_css(".card.border-l-4.border-l-danger")
    expect(page).to have_text("Bounced")
  end

  it "renders without an accent border override" do
    render_inline(described_class.new(label: "Sent", value: "0"))

    expect(page).to have_css(".card.border-l-4.border-l-accent")
    expect(page).to have_text("Sent")
    expect(page).to have_text("0")
  end
end
