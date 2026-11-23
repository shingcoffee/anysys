# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::WorkflowMapComponent, type: :component do
  let(:customer) { create(:customer) }
  include_context "booking journeys"

  before { Current.customer = customer }
  after { Current.reset }

  def render_map(journeys) = render_inline(described_class.new(journeys: journeys, customer_id: customer.id))
  def map = page.find("[data-role='journey-workflow-map']")

  it "draws one row per hand-off between the domain's journeys, linking each to its builder" do
    render_map([request_journey, review_journey, pay_journey])

    expect(map).to have_css("h4", text: I18n.t("journeys.admin.map.title"))
    rows = map.all("ol > li")
    expect(rows.map { |row| row["aria-label"] }).to contain_exactly(
      I18n.t("journeys.admin.map.connection", from: "Request a booking", to: "Review a booking"),
      I18n.t("journeys.admin.map.connection", from: "Review a booking", to: "Pay for a booking")
    )
    request_row = rows.find { |row| row["aria-label"].include?("Request a booking") }
    expect(request_row).to have_text(I18n.t("journeys.admin.map.picks_up", entity: "Booking", states: "Requested"))
    expect(request_row).to have_link(href: "/#{customer.id}/admin/maintenance/entities/journeys/#{request_journey.id}/edit")
    expect(request_row).to have_link(href: "/#{customer.id}/admin/maintenance/entities/journeys/#{review_journey.id}/edit")
    expect(request_row).to have_text(I18n.t("journeys.audiences.admin"))
  end

  it "says so when no journey picks up another's records" do
    render_map([request_journey, pay_journey])

    expect(map).to have_text(I18n.t("journeys.admin.map.empty"))
    expect(map).not_to have_css("ol")
  end

  it "renders nothing for fewer than two journeys" do
    render_map([request_journey])

    expect(page).not_to have_css("[data-role='journey-workflow-map']")
  end
end
