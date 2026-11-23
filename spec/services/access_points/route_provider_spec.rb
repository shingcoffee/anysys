# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::RouteProvider do
  subject(:provider) { described_class.new }

  describe "#call" do
    let(:results) { provider.call(customer_id: 12_345_678) }
    let(:keys)    { results.map(&:subject_key) }

    it "yields a descriptor for each admin-area controller_path" do
      expect(keys).to include("admin/dashboards")
      expect(keys).to include("admin/maintenance/pages")
    end

    it "omits flowchart controllers so tenant grants never name them" do
      expect(keys).not_to include("admin/maintenance/flowcharts")
      expect(keys.grep(/flowchart/)).to be_empty
    end

    it "derives read/create/update/destroy actions from a resource's HTTP verbs" do
      pages = results.find { |d| d.subject_key == "admin/maintenance/pages" }
      expect(pages.actions).to include(:read, :create, :update, :destroy)
    end

    it "skips routes outside the admin area (payments, forms)" do
      expect(keys).not_to include(a_string_starting_with("payments"))
      expect(keys).not_to include(a_string_starting_with("forms"))
    end

    it "tags every descriptor with subject_type 'Route'" do
      results.each do |d|
        expect(d.subject_type).to eq("Route")
      end
    end
  end

  describe "#label_for_group" do
    it "translates static admin route groups instead of titleizing dotted keys" do
      expect(provider.label_for_group("admin.maintenance")).to eq(
        I18n.t("admin_settings.access_points.route_groups.maintenance")
      )
      expect(provider.label_for_group("admin.maintenance")).not_to eq("admin.maintenance".titleize)
    end

    it "uses the module display_name for admin.modules.<key> groups" do
      allow(FeatureModules::Module).to receive(:find_by).with(key: "emails").and_return(
        instance_double(FeatureModules::Module, display_name: "Email")
      )
      expect(provider.label_for_group("admin.modules.emails")).to eq("Email")
    end

    it "localizes settings-module groups" do
      I18n.with_locale(:"zh-CN") do
        expect(provider.label_for_group("admin.settings.modules.ghost")).to eq(
          I18n.t("admin_settings.access_points.route_groups.settings_module", name: "ghost")
        )
      end
    end
  end
end
