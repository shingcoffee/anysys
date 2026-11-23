# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Navigation::Item do
  let(:customer) { build_stubbed(:customer) }
  let(:user)     { build_stubbed(:user) }

  let(:item) do
    described_class.new(
      key:     :profile,
      label:   "My Profile",
      icon:    :user,
      path:    ->(c) { "/#{c.id}/member/profile" },
      visible: ->(u) { u.member? }
    )
  end

  it "exposes key, label, and icon" do
    expect(item.key).to   eq(:profile)
    expect(item.label).to eq("My Profile")
    expect(item.icon).to  eq(:user)
  end

  describe "#path_for" do
    it "calls the path proc with the given customer" do
      expect(item.path_for(customer)).to eq("/#{customer.id}/member/profile")
    end
  end

  describe "#visible_to?" do
    it "returns the result of calling the visible proc with the user" do
      allow(user).to receive(:member?).and_return(true)
      expect(item.visible_to?(user)).to be(true)
    end

    it "returns false when the visible proc returns false" do
      allow(user).to receive(:member?).and_return(false)
      expect(item.visible_to?(user)).to be(false)
    end
  end
end
