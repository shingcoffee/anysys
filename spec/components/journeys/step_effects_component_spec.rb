# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::StepEffectsComponent, type: :component do
  let(:customer) { create(:customer) }
  include_context "booking journeys"

  let(:catalog) { Journeys::BuilderCatalog.new(pages: [request_page, review_page], domain: booking_domain, customer_id: customer.id) }

  before { Current.customer = customer }
  after { Current.reset }

  def effect(key, **vars) = I18n.t("journeys.admin.effects.#{key}", **vars)
  def block = page.find("[data-step-effects]", visible: :all)
  def items(list) = block.all("[data-step-effects-#{list}] li", visible: :all).map(&:text)

  it "names the page's processing, links to it and lists what a new record's submit does and who picks it up" do
    render_inline(described_class.new(catalog: catalog, page: request_page))

    link = block.find("a[data-step-effects-link]")
    expect(link.text).to eq(effect(:processing, name: catalog.effects(request_page).flowchart.name))
    expect(link[:href]).to eq("/#{customer.id}/admin/maintenance/pages/#{request_page.id}")
    expect(block).to have_text(effect(:heading))
    expect(items("lines")).to eq([effect(:saves_only), effect(:starts_in, entity: "Booking", field: "Status", state: "Requested")])
    expect(items("next")).to eq([I18n.t("journeys.admin.handoffs.next", journey: "Review a booking", audiences: I18n.t("journeys.audiences.admin"),
                                                                       entity: "Booking", states: "Requested")])
  end

  it "drops what only a new record does on a row that edits one" do
    render_inline(described_class.new(catalog: catalog, page: request_page, updating: true))

    expect(items("lines")).to eq([effect(:saves_only)])
    expect(block).to have_css("[data-step-effects-next][hidden]", visible: :all)
  end

  it "publishes the same lines for the builder to swap in" do
    payload = described_class.payload(catalog, review_page, "/path")

    expect(payload).to include("title" => effect(:processing, name: catalog.effects(review_page).flowchart.name), "path" => "/path",
                               "creating" => [], "nextCreating" => [], "skips" => [])
    expect(payload["next"].sole).to include("Pay for a booking")
  end

  it "renders hidden and empty until the row has a page" do
    render_inline(described_class.new(catalog: catalog, page: nil))

    expect(page).to have_css("[data-step-effects][hidden]", visible: :all)
    expect(block).to have_css("a[data-step-effects-link][hidden][href='#']", visible: :all)
    expect(items("lines")).to eq([])
  end
end
