# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Authorization do
  describe ".allowed?" do
    it "never grants a role from current_user_role metadata without a verified principal" do
      ctx = { current_user_role: "admin" }
      expect(described_class.allowed?(ctx, user: nil, type: "role_check", role: "admin")).to be(false)
      expect(described_class.allowed?(ctx, user: nil, type: "multi_role", roles: %w[admin member])).to be(false)
    end

    it "matches roles on a real user" do
      user = create(:user, :admin)
      expect(described_class.allowed?({}, user: user, type: "role_check", role: "admin")).to be(true)
    end

    it "requires every role in all_of mode" do
      user = create(:user, :admin)
      expect(described_class.role_allowed?({}, user: user, roles: %w[admin member], mode: "all_of")).to be(false)
      expect(described_class.role_allowed?({}, user: user, roles: %w[admin member], mode: "any_of")).to be(true)
    end

    it "does not let an admin authorize another tenant's record" do
      user = create(:user, :admin)
      foreign = create(:user)
      expect(described_class.ability_allowed?({}, user: user, action: "update", resource: foreign)).to be(false)
      expect(described_class.ability_allowed?({}, user: user, action: "update", resource: user)).to be(true)
    end

    it "allows a member only when user_id matches in the same tenant" do
      member = create(:user, :member)
      own = Struct.new(:customer_id, :user_id).new(member.customer_id, member.id)
      other = Struct.new(:customer_id, :user_id).new(member.customer_id, create(:user, :member).id)
      foreign = Struct.new(:customer_id, :user_id).new(create(:customer).id, member.id)
      expect(described_class.allowed?({}, user: member, type: "record_owner", resource: own)).to be(true)
      expect(described_class.allowed?({}, user: member, type: "record_owner", resource: other)).to be(false)
      expect(described_class.allowed?({}, user: member, type: "record_owner", resource: foreign)).to be(false)
    end

    it "raises Error for an unsafe ability action" do
      expect {
        described_class.ability_allowed?({}, user: create(:user, :admin), action: "read); system", resource: :x)
      }.to raise_error(described_class::Error, /invalid ability action/)
    end
  end
end
