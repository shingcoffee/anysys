# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Geolocation do
  let(:ctx) { { customer_id: 49, errors: [] } }

  it "computes Haversine distance" do
    result = described_class.lookup(
      ctx, source: { lat: 0, lng: 0 }, other: { lat: 0, lng: 1 }
    )
    expect(result[:km]).to be_within(1).of(111.19)
    expect(result[:miles]).to be > 60
  end

  it "reads latitude/longitude aliases" do
    result = described_class.lookup(
      ctx, source: { "latitude" => 0, "longitude" => 0 }, other: { "lat" => 0, "lon" => 1 }
    )
    expect(result[:km]).to be_within(1).of(111.19)
  end

  it "fails when a coordinate is missing" do
    expect(described_class.lookup(ctx, source: { lat: 0 }, other: { lat: 0, lng: 1 })).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.geolocation_lookup.invalid_coordinates"))
  end

  it "does not call HTTP vendors" do
    expect(OutboundHttp).not_to receive(:request)
    described_class.lookup(ctx, source: { lat: 0, lng: 0 }, other: { lat: 0, lng: 1 })
  end
end
