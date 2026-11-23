# frozen_string_literal: true

require "rails_helper"

RSpec.describe LayoutHelper, type: :helper do
  describe "#container_width_class" do
    it "returns max-w-3xl for :narrow" do
      expect(helper.container_width_class(:narrow)).to eq("max-w-3xl mx-auto px-3 sm:px-4 lg:px-8")
    end

    it "returns max-w-7xl for :wide" do
      expect(helper.container_width_class(:wide)).to eq("max-w-7xl mx-auto px-3 sm:px-4 lg:px-8")
    end

    it "returns a full-width class for :full" do
      expect(helper.container_width_class(:full)).to eq("w-full px-3 sm:px-4 lg:px-8")
    end

    it "returns :wide for nil / unknown" do
      expect(helper.container_width_class(nil)).to eq(helper.container_width_class(:wide))
      expect(helper.container_width_class(:whatever)).to eq(helper.container_width_class(:wide))
    end

    it "accepts strings and symbols interchangeably" do
      expect(helper.container_width_class("narrow")).to eq(helper.container_width_class(:narrow))
    end
  end

  describe "#default_container_width_for" do
    it "returns :full for any /:cid/admin/... path" do
      expect(helper.default_container_width_for("/12345678/admin")).to eq(:full)
      expect(helper.default_container_width_for("/12345678/admin/maintenance/constants")).to eq(:full)
      expect(helper.default_container_width_for("/81721200/admin/maintenance/platform/customers")).to eq(:full)
    end

    it "returns :wide for non-admin paths" do
      expect(helper.default_container_width_for("/12345678/member/dashboard")).to eq(:wide)
      expect(helper.default_container_width_for("/some/public/page")).to eq(:wide)
      expect(helper.default_container_width_for("/")).to eq(:wide)
      expect(helper.default_container_width_for(nil)).to eq(:wide)
    end

    it "returns :full for tenant settings paths" do
      expect(helper.default_container_width_for("/12345678/admin/settings")).to eq(:full)
      expect(helper.default_container_width_for("/12345678/admin/settings/member")).to eq(:full)
    end

    it "does not match an /admin segment that isn't directly under the tenant" do
      expect(helper.default_container_width_for("/12345678/something/admin/x")).to eq(:wide)
    end
  end
end
