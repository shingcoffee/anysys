# frozen_string_literal: true

# Helpers for resolving the pinned platform-owner account in specs.
#
# The owner role is reserved for one user (email + customer 81_721_200);
# see AGENTS.md "Reserved Roles & Access Rules". The Authentication
# Provisioner auto-creates that user when the platform customer exists,
# so specs that need a "platform owner" should look up the canonical
# row rather than trying to create a duplicate.
module PlatformOwnerHelpers
  def ensure_platform_customer(name: "Platform")
    Customer.find_or_create_by!(id: ::Authentication::User::PLATFORM_CUSTOMER_ID) do |c|
      c.name = name
      c.industry = :technology
      c.tier = :basic
    end
  end

  def find_or_create_platform_owner(password: "password123")
    customer = ensure_platform_customer
    user = ::Authentication::User.find_by(
      customer: customer,
      email: ::Authentication::User::PLATFORM_OWNER_EMAIL
    )
    return user.tap { |u| u.update!(password: password) if password } if user

    create(:user, :platform_owner, password: password)
  end
end

RSpec.configure do |config|
  config.include PlatformOwnerHelpers
end
