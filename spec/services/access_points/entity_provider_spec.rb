# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::EntityProvider do
  subject(:provider) { described_class.new }

  let(:customer)        { create(:customer) }
  let(:other_customer)  { create(:customer) }

  it "yields one descriptor per entity scoped to the customer" do
    e1 = create(:entity, customer: customer, name: "Patients")
    e2 = create(:entity, customer: customer, name: "Doctors")
    create(:entity, customer: other_customer, name: "Other")

    results = provider.call(customer_id: customer.id)
    ids = results.map(&:subject_id)
    expect(ids).to contain_exactly(e1.id, e2.id)
    expect(provider.group_label).to eq("Specific entities")
  end

  it "translates the instance-group label in zh-CN" do
    expect(I18n.with_locale(:"zh-CN") { provider.group_label }).to eq(
      I18n.t("admin_settings.access_points.groups.entities_instances", locale: :"zh-CN")
    )
  end

  it "all descriptors have subject_type == 'Entity' and matching actions" do
    create(:entity, customer: customer)
    d = provider.call(customer_id: customer.id).first
    expect(d.subject_type).to eq("Entity")
    expect(d.actions).to contain_exactly(:read, :update, :destroy)
  end

  it "returns empty when query is filtered to a non-matching customer" do
    create(:entity, customer: other_customer)
    expect(provider.call(customer_id: customer.id)).to be_empty
  end

  describe "#search" do
    it "filters by query string against name" do
      create(:entity, customer: customer, name: "Patients")
      create(:entity, customer: customer, name: "Doctors")
      results = provider.search(customer_id: customer.id, query: "patient")
      expect(results.map(&:label)).to contain_exactly("Patients")
    end
  end
end
