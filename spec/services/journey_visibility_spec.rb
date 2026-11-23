# frozen_string_literal: true

require "rails_helper"

RSpec.describe JourneyVisibility do
  it "allows only the platform owner" do
    expect(described_class.allowed?(find_or_create_platform_owner)).to be(true)
    expect(described_class.allowed?(create(:user, :admin, customer: create(:customer)))).to be(false)
    expect(described_class.allowed?(nil)).to be(false)
  end

  it "recognises the journey builder controllers but not the public start" do
    expect(described_class.controller?("admin/maintenance/journeys")).to be(true)
    expect(described_class.controller?("admin/maintenance/journey_generations")).to be(true)
    expect(described_class.controller?("admin/maintenance/journey_launches")).to be(true)
    expect(described_class.controller?("journeys/starts")).to be(false)
    expect(described_class.controller?("admin/maintenance/pages")).to be(false)
    expect(described_class.controller?("admin/maintenance/entities")).to be(false)
  end

  it "recognises the journey builder route subjects" do
    expect(described_class.route_subject?(:route_admin_maintenance_journeys)).to be(true)
    expect(described_class.route_subject?(:route_admin_maintenance_journey_generations)).to be(true)
    expect(described_class.route_subject?(:route_admin_maintenance_entities)).to be(false)
    expect(described_class.route_subject?(:route_admin_domains)).to be(false)
    expect(described_class.route_subject?(:route_journeys_starts)).to be(false)
  end
end
