# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Authentication::Deprovisioner do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "deactivates all active users for the customer" do
      user1 = create(:user, customer: customer, status: :active)
      user2 = create(:user, customer: customer, status: :active)
      described_class.call(customer)
      aggregate_failures do
        expect(user1.reload.status).to eq("inactive")
        expect(user2.reload.status).to eq("inactive")
      end
    end

    it "does not affect already inactive users" do
      inactive_user = create(:user, customer: customer, status: :inactive)
      described_class.call(customer)
      expect(inactive_user.reload.status).to eq("inactive")
    end

    it "does not affect users from other customers" do
      other_customer = create(:customer)
      other_user = create(:user, customer: other_customer, status: :active)
      described_class.call(customer)
      expect(other_user.reload.status).to eq("active")
    end
  end
end
