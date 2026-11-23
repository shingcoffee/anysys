# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::H5RedirectComponent, type: :component do
  let(:payment) { instance_double(Payments::Payment, prepay_payload: { "h5_url" => "https://psp.example/h5/abc" }) }

  it "renders the H5 redirect section with Stimulus wiring" do
    render_inline(described_class.new(payment: payment))

    section = page.find("section")
    expect(section["data-controller"]).to eq("payments--h5-redirect")
    expect(section["data-payments--h5-redirect-url-value"]).to eq("https://psp.example/h5/abc")
    expect(page).to have_link("Tap to continue", href: "https://psp.example/h5/abc")
    expect(page).to have_text("Redirecting to your payment app")
  end

  it "handles missing h5 url gracefully" do
    empty_payment = instance_double(Payments::Payment, prepay_payload: {})
    render_inline(described_class.new(payment: empty_payment))

    section = page.find("section")
    expect(section["data-payments--h5-redirect-url-value"]).to eq("")
  end
end
