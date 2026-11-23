# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Sources::Builtin do
  let_it_be(:customer) { create(:customer) }

  describe "metadata" do
    it_behaves_like "member source metadata", key: :builtin, editable: false, position: 0

    it { expect(described_class.name).to eq("Built-in") }
    it { expect(described_class.description).to eq("Always-visible member pages.") }
  end

  describe "#surfaces" do
    subject(:surfaces) { described_class.new(customer: customer).surfaces }

    it "yields three surfaces in fixed order: home, profile, security" do
      expect(surfaces.map(&:key)).to eq([:builtin_home, :builtin_profile, :builtin_security])
    end

    it "labels them Home / Profile / Security" do
      expect(surfaces.map(&:label)).to eq(["Home", "Profile", "Security"])
    end

    it "assigns ascending default positions (0, 10, 20)" do
      expect(surfaces.map(&:default_position)).to eq([0, 10, 20])
    end

    it "exposes path_seg on each surface" do
      expect(surfaces.map(&:path_seg)).to eq(["", "profile", "security"])
    end

    it "responds true to enabled_for? for any user" do
      surface = surfaces.first
      expect(surface.enabled_for?(double("User"))).to be(true)
    end
  end
end
