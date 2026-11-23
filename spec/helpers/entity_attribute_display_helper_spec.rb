# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityAttributeDisplayHelper, type: :helper do
  describe "#normalize_attribute_visibility" do
    it "defaults to all-on for nil" do
      expect(helper.normalize_attribute_visibility(nil))
        .to eq(admin: true, member: true, public: true)
    end

    it "preserves false values from string keys" do
      expect(helper.normalize_attribute_visibility("admin" => false, "member" => true, "public" => false))
        .to eq(admin: false, member: true, public: false)
    end

    it "preserves false values from symbol keys" do
      expect(helper.normalize_attribute_visibility(admin: false, member: true, public: true))
        .to eq(admin: false, member: true, public: true)
    end

    it "treats missing keys as enabled" do
      expect(helper.normalize_attribute_visibility("admin" => false))
        .to eq(admin: false, member: true, public: true)
    end
  end

  describe "#render_attribute_visibility_badges" do
    it "renders three labels in order" do
      result = helper.render_attribute_visibility_badges(nil)
      expect(result).to match(/Admin.*Member.*Public/m)
    end

    it "applies the disabled class to unchecked audiences" do
      result = helper.render_attribute_visibility_badges("admin" => true, "member" => false, "public" => true)
      expect(result).to include("line-through")
    end

    it "does not strike through fully-enabled visibility" do
      result = helper.render_attribute_visibility_badges("admin" => true, "member" => true, "public" => true)
      expect(result).not_to include("line-through")
    end
  end
end
