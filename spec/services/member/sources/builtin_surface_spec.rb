# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Sources::BuiltinSurface do
  subject(:surface) do
    described_class.new(
      key:              :profile,
      label:            "Profile",
      icon:             :user,
      path_seg:         "profile",
      default_position: 2
    )
  end

  it "exposes key, label, icon, path_seg" do
    expect(surface.key).to       eq(:profile)
    expect(surface.label).to     eq("Profile")
    expect(surface.icon).to      eq(:user)
    expect(surface.path_seg).to  eq("profile")
  end

  it "default_position_or_default returns the integer value of default_position" do
    expect(surface.default_position_or_default).to eq(2)
  end

  it "default_position_or_default returns 0 when default_position is nil" do
    s = described_class.new(key: :home, label: "Home", icon: :home, path_seg: "home", default_position: nil)
    expect(s.default_position_or_default).to eq(0)
  end

  it "default_enabled? is true unless default_enabled is false" do
    expect(surface.default_enabled?).to be(true)

    off = described_class.new(
      key: :page_1, label: "Enroll", icon: :link, path_seg: "pages/1", default_enabled: false
    )
    expect(off.default_enabled?).to be(false)
  end

  it "enabled_for? always returns true regardless of user" do
    expect(surface.enabled_for?(nil)).to be(true)
    expect(surface.enabled_for?(:any_user)).to be(true)
  end

  it "validate! returns true" do
    expect(surface.validate!).to be(true)
  end

  it "returns an empty Member::Surface::Index so settings show does not 500" do
    expect(surface.index).to be_a(Member::Surface::Index)
    expect(surface.index.columns).to eq([])
  end

  it "returns an empty Member::Surface::Detail so settings show does not 500" do
    expect(surface.detail).to be_a(Member::Surface::Detail)
    expect(surface.detail.sections).to eq([])
  end
end
