# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartVisibility do
  it "allows only the platform owner" do
    expect(described_class.allowed?(find_or_create_platform_owner)).to be(true)
  end

  it "denies a tenant admin" do
    admin = create(:user, :admin, customer: create(:customer))

    expect(described_class.allowed?(admin)).to be(false)
  end

  it "denies a missing user" do
    expect(described_class.allowed?(nil)).to be(false)
  end

  it "recognises flowchart maintenance controllers" do
    expect(described_class.controller?("admin/maintenance/flowcharts")).to be(true)
    expect(described_class.controller?("admin/maintenance/flowchart_traces")).to be(true)
    expect(described_class.controller?("admin/maintenance/pages")).to be(false)
  end

  it "recognises flowchart CanCan route subjects" do
    expect(described_class.route_subject?(:route_admin_maintenance_flowcharts)).to be(true)
    expect(described_class.route_subject?(:route_admin_maintenance_flowchart_copies)).to be(true)
    expect(described_class.route_subject?(:route_admin_dashboards)).to be(false)
  end
end
