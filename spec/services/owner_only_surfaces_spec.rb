# frozen_string_literal: true

require "rails_helper"

RSpec.describe OwnerOnlySurfaces do
  it "covers flowchart and domain controllers only" do
    expect(described_class.controller?("admin/maintenance/flowcharts")).to be(true)
    expect(described_class.controller?("admin/maintenance/entity_domains")).to be(true)
    expect(described_class.controller?("admin/maintenance/entity_domain_memberships")).to be(true)
    expect(described_class.controller?("admin/maintenance/entities")).to be(false)
  end

  it "matches the CanCan route subjects of those controllers" do
    expect(described_class.route_subject?(:route_admin_maintenance_entity_domains)).to be(true)
    expect(described_class.route_subject?(:route_admin_maintenance_entity_domain_memberships)).to be(true)
    expect(described_class.route_subject?(:route_admin_maintenance_entities)).to be(false)
  end

  it "covers the journey builder but not the public journey start" do
    expect(described_class.controller?("admin/maintenance/journeys")).to be(true)
    expect(described_class.controller?("admin/maintenance/journey_launches")).to be(true)
    expect(described_class.controller?("journeys/starts")).to be(false)
    expect(described_class.route_subject?(:route_admin_maintenance_journeys)).to be(true)
    expect(Ability.new(create(:user, :admin, customer: create(:customer))).can?(:read, :route_admin_maintenance_journeys)).to be(false)
  end

  it "denies domain routes to tenant admins and allows them to the platform owner" do
    customer = create(:customer)
    admin_ability = Ability.new(create(:user, :admin, customer: customer))
    owner_ability = Ability.new(find_or_create_platform_owner)

    expect(admin_ability.can?(:read, :route_admin_maintenance_entity_domains)).to be(false)
    expect(admin_ability.can?(:read, :route_admin_maintenance_entities)).to be(true)
    expect(owner_ability.can?(:update, :route_admin_maintenance_entity_domain_memberships)).to be(true)
  end

  it "keeps domain routes out of the grantable access points" do
    descriptors = AccessPoints::RouteProvider.new.call(customer_id: create(:customer).id)
    expect(descriptors.map(&:subject_key)).not_to include(a_string_matching(/entity_domain/))
  end
end
