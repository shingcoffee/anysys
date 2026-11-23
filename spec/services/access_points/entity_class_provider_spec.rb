# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::EntityClassProvider do
  subject(:provider) { described_class.new }

  it "yields a single 'all entities' descriptor" do
    results = provider.call(customer_id: 12_345_678)
    expect(results.size).to eq(1)
    d = results.first
    expect(d.subject_type).to eq("EntityClass")
    expect(d.subject_key).to eq("Entity")
    expect(d.actions).to contain_exactly(:read, :create, :update, :destroy)
    expect(d.group_key).to eq("entities")
    expect(d.label).to eq("All entities")
    expect(d.description).to eq("Grant covers every Entity record for this customer.")
  end

  it "translates the all-entities copy in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      d = provider.call(customer_id: 12_345_678).first
      expect(d.label).to eq(I18n.t("admin_settings.access_points.entities_all"))
      expect(provider.group_label).to eq(I18n.t("admin_settings.access_points.groups.entities"))
    end
  end
end
