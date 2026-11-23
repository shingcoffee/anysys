# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::SeedReserved do
  let(:customer) { create(:customer) }

  it "creates owner, admin, member system roles for the customer" do
    described_class.call(customer: customer)
    keys = customer.roles.pluck(:key).sort
    expect(keys).to eq(%w[admin member owner])
    expect(customer.roles.where(system: true).count).to eq(3)
    expect(customer.roles.where(locked_grants: true).count).to eq(3)
  end

  it "is idempotent" do
    described_class.call(customer: customer)
    expect { described_class.call(customer: customer) }
      .not_to change { customer.reload.roles.count }
  end

  it "seeds admin grants on first call" do
    roles = described_class.call(customer: customer)
    admin_role = roles.find { |r| r.key == "admin" }
    expect(admin_role.role_permissions.count).to be > 0
  end

  it "does not re-seed admin grants when they already exist (idempotent grants)" do
    described_class.call(customer: customer)
    admin_role = customer.roles.find_by!(key: "admin")
    initial_count = admin_role.role_permissions.count

    described_class.call(customer: customer)
    expect(admin_role.role_permissions.reload.count).to eq(initial_count)
  end

  it "seeds exactly the catalog's non-platform grant tuples for the admin role" do
    roles = described_class.call(customer: customer)
    admin_role = roles.find { |r| r.key == "admin" }

    Current.access_points_catalog = nil
    catalog = AccessPoints::Catalog.for(customer_id: customer.id)
    expected = catalog.groups.flat_map do |group|
      next [] if group[:key] == "platform" || group[:key].start_with?("admin.maintenance.platform")

      group[:descriptors].flat_map do |d|
        d.actions.map { |action| [d.subject_type, d.subject_key, d.subject_id, action.to_s] }
      end
    end
    Current.access_points_catalog = nil

    actual = admin_role.role_permissions.pluck(:subject_type, :subject_key, :subject_id, :action)
    expect(actual.size).to eq(expected.size)
    expect(actual.sort_by(&:to_s)).to eq(expected.sort_by(&:to_s))
  end
end
