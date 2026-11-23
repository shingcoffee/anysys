# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::LandingPath do
  let(:customer) { create(:customer) }

  describe ".for" do
    it "sends an admin to the admin surface" do
      user = create(:user, :admin, customer: customer)
      expect(described_class.for(user)).to eq("/#{customer.id}/admin/assistant")
    end

    it "sends the platform owner to the admin surface" do
      user = find_or_create_platform_owner
      expect(described_class.for(user)).to eq("/#{user.customer_id}/admin/assistant")
    end

    it "sends a member to the member surface" do
      user = create(:user, :member, customer: customer)
      expect(described_class.for(user)).to eq("/#{customer.id}/member")
    end

    it "sends a member promoted to admin to the admin surface" do
      user = create(:user, :member, customer: customer)
      admin_role = customer.roles.system.find_by!(key: "admin")
      result = UserRoles::Operation::Assign.call(user: user, role_ids: [admin_role.id])

      expect(result.success?).to be(true)
      expect(user.reload.reserved_role_keys).to eq(["admin"])
      expect(described_class.for(user.reload)).to eq("/#{customer.id}/admin/assistant")
    end

    # A role-less user would only be denied again on the admin surface, which
    # is how the old copy-pasted versions produced a redirect loop.
    it "sends a user carrying no role row to the member surface" do
      user = create(:user, customer: customer)
      expect(described_class.for(user)).to eq("/#{customer.id}/member")
    end

    it "sends an anonymous caller to the sign-in form" do
      expect(described_class.for(nil)).to eq("/auth/sign_in")
    end

    it "falls back to the sign-in form when no tenant can be resolved" do
      user = build(:user, customer: nil)
      expect(described_class.for(user)).to eq("/auth/sign_in")
    end
  end

  describe "customer_id override" do
    # A platform owner acting inside another tenant stays on that tenant's
    # surface rather than being bounced back to 81721200.
    it "prefers the explicit tenant over the user's own" do
      owner = find_or_create_platform_owner

      expect(described_class.for(owner, customer_id: customer.id))
        .to eq("/#{customer.id}/admin/assistant")
    end

    it "falls back to the user's tenant when the override is blank" do
      user = create(:user, :admin, customer: customer)
      expect(described_class.for(user, customer_id: nil)).to eq("/#{customer.id}/admin/assistant")
    end
  end
end
